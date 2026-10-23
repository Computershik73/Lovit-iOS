//
//  MAXOpus.m
//

#import "MAXOpus.h"
#import <opus/opus.h>

/// Частота готового WAV — см. +playbackRate.
static const int MAXOpusPlaybackRate = 24000;

/// Частота записи и поток. Числа не наши: с такими пишет настоящий клиент.
static const int MAXOpusRecordRate = 48000;
static const int MAXOpusBitrate = 24000;

/// Двадцать миллисекунд при частоте записи — обычный кадр Opus.
static const int MAXOpusFrameSamples = 960;

/// Сколько отсчётов кодек проглатывает на разгон. Число тоже не наше: его
/// пишет в заголовок настоящий клиент, и заголовок должен совпадать.
static const int MAXOpusPreSkip = 312;

/// Больше этого один кадр не занимает никогда.
static const int MAXOpusMostPacket = 4000;

/// Наибольший кадр на выходе декодера — 120 мс при 48 кГц.
static const int MAXOpusMostFrame = 5760;

/// Столько кусков помещается в одну страницу Ogg, и не больше.
static const NSUInteger MAXOggMostSegments = 255;
static const NSUInteger MAXOggHeaderSize = 27;

/// Чей это поток. Число произвольное, важна лишь его одинаковость.
static const uint32_t MAXOggSerial = 0x4C6F7669;

static NSString *const MAXOggVendor = @"libopus unknown";

#pragma mark - Мелочи разбора

static void MAXPutLittle(uint8_t *target, NSUInteger at, uint64_t value, int bytes) {
    for (int i = 0; i < bytes; i++) target[at + i] = (uint8_t)((value >> (i * 8)) & 0xFF);
}

static void MAXPutAscii(uint8_t *target, NSUInteger at, NSString *text) {
    for (NSUInteger i = 0; i < text.length; i++) {
        target[at + i] = (uint8_t)[text characterAtIndex:i];
    }
}

/// Контрольная сумма Ogg.
///
/// Тот же многочлен, что у обычной CRC-32, но без обращения битов и без
/// начального заполнения — своя, и обычной её не заменить.
static uint32_t MAXOggCrc32(const uint8_t *data, NSUInteger length) {
    static uint32_t table[256];
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        for (uint32_t at = 0; at < 256; at++) {
            uint32_t value = at << 24;
            for (int bit = 0; bit < 8; bit++) {
                value = (value & 0x80000000u) ? ((value << 1) ^ 0x04C11DB7u) : (value << 1);
            }
            table[at] = value;
        }
    });

    uint32_t crc = 0;
    for (NSUInteger at = 0; at < length; at++) {
        crc = (crc << 8) ^ table[((crc >> 24) ^ data[at]) & 0xFF];
    }
    return crc;
}

/// Разбор Ogg на пакеты.
///
/// Страница несёт таблицу отрезков; отрезок в 255 байт означает, что пакет
/// продолжается следующим, всё прочее его завершает. Пакет может тянуться и
/// через границу страниц — поэтому склейка ведётся поверх всего потока, а не
/// внутри страницы.
static NSArray *MAXOggPackets(NSData *source, uint64_t *lastGranule) {
    const uint8_t *data = source.bytes;
    NSUInteger length = source.length;

    NSMutableArray *packets = [NSMutableArray array];
    NSMutableData *current = [NSMutableData data];
    if (lastGranule != NULL) *lastGranule = 0;

    NSUInteger at = 0;
    while (at + MAXOggHeaderSize <= length) {
        if (data[at] != 'O' || data[at + 1] != 'g'
                || data[at + 2] != 'g' || data[at + 3] != 'S') {
            break;
        }

        if (lastGranule != NULL) {
            uint64_t granule = 0;
            for (int i = 0; i < 8; i++) granule |= ((uint64_t)data[at + 6 + i]) << (i * 8);
            // Незаполненная гранула помечена всеми единицами — это «ещё не
            // известно», а не «очень много».
            if (granule != UINT64_MAX) *lastGranule = granule;
        }

        NSUInteger segments = data[at + 26];
        NSUInteger table = at + MAXOggHeaderSize;
        if (table + segments > length) break;

        NSUInteger body = table + segments;

        for (NSUInteger i = 0; i < segments; i++) {
            NSUInteger piece = data[table + i];
            if (body + piece > length) return packets.count > 0 ? packets : nil;

            [current appendBytes:(data + body) length:piece];
            body += piece;

            // Отрезок короче 255 закрывает пакет.
            if (piece != 255) {
                [packets addObject:[current copy]];
                current = [NSMutableData data];
            }
        }

        at = body;
    }

    return packets.count > 0 ? packets : nil;
}

/// Первый пакет — OpusHead: сколько каналов и сколько отсчётов в начале
/// приходится на разгон.
static BOOL MAXOpusReadHead(NSData *packet, int *channels, int *preSkip) {
    if (packet.length < 19) return NO;

    const uint8_t *bytes = packet.bytes;
    if (memcmp(bytes, "OpusHead", 8) != 0) return NO;

    int found = bytes[9];
    if (found < 1 || found > 2) return NO;

    *channels = found;
    *preSkip = bytes[10] | (bytes[11] << 8);
    return YES;
}

@implementation MAXOpus

+ (int)playbackRate { return MAXOpusPlaybackRate; }

+ (NSInteger)durationMsOfOggOpus:(NSData *)ogg {
    if (ogg.length < MAXOggHeaderSize) return 0;

    uint64_t granule = 0;
    NSArray *packets = MAXOggPackets(ogg, &granule);
    if (packets == nil) return 0;

    int channels = 1;
    int preSkip = 0;
    if (!MAXOpusReadHead(packets[0], &channels, &preSkip)) return 0;

    if (granule <= (uint64_t)preSkip) return 0;

    // Гранулы Ogg Opus всегда считаются по 48 кГц, какой бы ни была частота
    // самой записи.
    return (NSInteger)((granule - preSkip) * 1000 / 48000);
}

/// Заголовок WAV поверх готовых отсчётов. Вид простейший — целые шестнадцать
/// разрядов без сжатия: его система играет всегда.
+ (NSData *)wrapPcm:(NSData *)sound channels:(int)channels {
    NSUInteger length = sound.length;
    int byteRate = MAXOpusPlaybackRate * channels * 2;

    NSMutableData *wav = [NSMutableData dataWithLength:44 + length];
    uint8_t *bytes = wav.mutableBytes;

    MAXPutAscii(bytes, 0, @"RIFF");
    MAXPutLittle(bytes, 4, 36 + length, 4);
    MAXPutAscii(bytes, 8, @"WAVE");

    MAXPutAscii(bytes, 12, @"fmt ");
    MAXPutLittle(bytes, 16, 16, 4);              // длина этого куска
    MAXPutLittle(bytes, 20, 1, 2);               // без сжатия
    MAXPutLittle(bytes, 22, (uint64_t)channels, 2);
    MAXPutLittle(bytes, 24, MAXOpusPlaybackRate, 4);
    MAXPutLittle(bytes, 28, (uint64_t)byteRate, 4);
    MAXPutLittle(bytes, 32, (uint64_t)(channels * 2), 2);  // байт на кадр
    MAXPutLittle(bytes, 34, 16, 2);              // разрядов на отсчёт

    MAXPutAscii(bytes, 36, @"data");
    MAXPutLittle(bytes, 40, length, 4);

    memcpy(bytes + 44, sound.bytes, length);
    return wav;
}

+ (NSData *)wavFromOggOpus:(NSData *)ogg {
    if (ogg.length == 0) return nil;

    NSArray *packets = MAXOggPackets(ogg, NULL);
    if (packets.count < 2) return nil;

    int channels = 1;
    int preSkip = 0;
    if (!MAXOpusReadHead(packets[0], &channels, &preSkip)) return nil;

    int problem = 0;
    OpusDecoder *decoder = opus_decoder_create(MAXOpusPlaybackRate, channels, &problem);
    if (decoder == NULL || problem != OPUS_OK) {
        NSLog(@"[Max/Голос] декодер Opus не завёлся: %d", problem);
        if (decoder != NULL) opus_decoder_destroy(decoder);
        return nil;
    }

    // Кадр меряется по частоте выхода, а не по 48 кГц: декодер сам приводит
    // частоту, и отсчётов на выходе меньше ровно во столько же раз.
    int mostFrame = MAXOpusMostFrame * MAXOpusPlaybackRate / 48000;
    int16_t *pcm = malloc(sizeof(int16_t) * mostFrame * channels);
    if (pcm == NULL) {
        opus_decoder_destroy(decoder);
        return nil;
    }

    NSMutableData *sound = [NSMutableData dataWithCapacity:ogg.length * 12];

    // Первые отсчёты — разгон кодировщика, их выбрасывают. Счёт в заголовке
    // идёт по 48 кГц, у нас частота своя.
    int skip = preSkip * MAXOpusPlaybackRate / 48000;

    // Первые два пакета — заголовок и подписи, звука в них нет.
    for (NSUInteger i = 2; i < packets.count; i++) {
        NSData *packet = packets[i];
        int got = opus_decode(decoder, packet.bytes, (opus_int32)packet.length,
                              pcm, mostFrame, 0);
        if (got <= 0) continue;

        int from = 0;
        if (skip > 0) {
            from = MIN(skip, got);
            skip -= from;
        }
        if (from >= got) continue;

        [sound appendBytes:(pcm + from * channels)
                    length:(NSUInteger)(got - from) * channels * sizeof(int16_t)];
    }

    free(pcm);
    opus_decoder_destroy(decoder);

    if (sound.length == 0) return nil;
    return [self wrapPcm:sound channels:channels];
}

@end

#pragma mark - Запись

@implementation MAXOpusEncoder {
    OpusEncoder *_encoder;
    NSMutableArray *_packets;
    uint8_t _packet[MAXOpusMostPacket];

    /// Недобранный до целого кадра остаток предыдущей порции.
    int16_t _tail[MAXOpusFrameSamples];
    NSUInteger _tailLength;

    long long _samples;
}

+ (int)recordingRate { return MAXOpusRecordRate; }

- (id)init {
    self = [super init];
    if (self) {
        _packets = [NSMutableArray array];

        int problem = 0;
        _encoder = opus_encoder_create(MAXOpusRecordRate, 1, OPUS_APPLICATION_VOIP, &problem);
        if (_encoder == NULL || problem != OPUS_OK) {
            NSLog(@"[Max/Голос] кодер Opus не завёлся: %d", problem);
            if (_encoder != NULL) {
                opus_encoder_destroy(_encoder);
                _encoder = NULL;
            }
            return self;
        }

        opus_encoder_ctl(_encoder, OPUS_SET_BITRATE(MAXOpusBitrate));
    }
    return self;
}

- (void)dealloc {
    if (_encoder != NULL) opus_encoder_destroy(_encoder);
}

- (BOOL)ready { return _encoder != NULL; }
- (long long)samples { return _samples; }

- (void)encodeFrame:(const int16_t *)frame {
    opus_int32 written = opus_encode(_encoder, frame, MAXOpusFrameSamples,
                                     _packet, MAXOpusMostPacket);
    if (written <= 0) return;

    [_packets addObject:[NSData dataWithBytes:_packet length:(NSUInteger)written]];
    _samples += MAXOpusFrameSamples;
}

- (void)feed:(const int16_t *)pcm count:(NSUInteger)count {
    if (_encoder == NULL || pcm == NULL || count == 0) return;

    NSUInteger at = 0;
    while (at < count) {
        NSUInteger need = MAXOpusFrameSamples - _tailLength;
        NSUInteger take = MIN(need, count - at);

        memcpy(_tail + _tailLength, pcm + at, take * sizeof(int16_t));
        _tailLength += take;
        at += take;

        if (_tailLength < MAXOpusFrameSamples) break;

        [self encodeFrame:_tail];
        _tailLength = 0;
    }
}

- (NSData *)finish {
    if (_encoder == NULL) return nil;

    if (_tailLength > 0) {
        memset(_tail + _tailLength, 0,
               (MAXOpusFrameSamples - _tailLength) * sizeof(int16_t));
        [self encodeFrame:_tail];
        _tailLength = 0;
    }

    if (_packets.count == 0) return nil;

    return [MAXOpusEncoder buildOgg:_packets samples:_samples];
}

#pragma mark - Контейнер Ogg

+ (NSData *)buildOgg:(NSArray *)packets samples:(long long)samples {
    NSMutableData *target = [NSMutableData data];
    uint32_t sequence = 0;

    // Первые две страницы служебные: чем это записано и чем играть. Каждая
    // обязана лежать в своей странице — так велит формат.
    [self writePage:target kind:0x02 granule:0 sequence:sequence++
            packets:@[[self headPacket]]];
    [self writePage:target kind:0x00 granule:0 sequence:sequence++
            packets:@[[self tagsPacket]]];

    NSMutableArray *page = [NSMutableArray array];
    NSUInteger segments = 0;
    long long counted = 0;

    for (NSData *packet in packets) {
        NSUInteger need = packet.length / 255 + 1;

        if (page.count > 0 && segments + need > MAXOggMostSegments) {
            [self writePage:target
                       kind:0x00
                    granule:(uint64_t)(counted + MAXOpusPreSkip)
                   sequence:sequence++
                    packets:page];

            page = [NSMutableArray array];
            segments = 0;
        }

        [page addObject:packet];
        segments += need;
        counted += MAXOpusFrameSamples;
    }

    // Последняя страница помечается концом потока, и время в ней — настоящая
    // длина записи, а не сумма кадров: хвост дописан тишиной, и играть её
    // незачем.
    [self writePage:target
               kind:0x04
            granule:(uint64_t)(samples + MAXOpusPreSkip)
           sequence:sequence++
            packets:page];

    return target;
}

+ (void)writePage:(NSMutableData *)target
             kind:(uint8_t)kind
          granule:(uint64_t)granule
         sequence:(uint32_t)sequence
          packets:(NSArray *)packets {
    NSUInteger segments = 0;
    NSUInteger body = 0;

    for (NSData *packet in packets) {
        segments += packet.length / 255 + 1;
        body += packet.length;
    }

    NSMutableData *page = [NSMutableData dataWithLength:MAXOggHeaderSize + segments + body];
    uint8_t *bytes = page.mutableBytes;

    MAXPutAscii(bytes, 0, @"OggS");
    bytes[4] = 0;
    bytes[5] = kind;

    MAXPutLittle(bytes, 6, granule, 8);
    MAXPutLittle(bytes, 14, MAXOggSerial, 4);
    MAXPutLittle(bytes, 18, sequence, 4);
    MAXPutLittle(bytes, 22, 0, 4);

    bytes[26] = (uint8_t)segments;

    NSUInteger table = MAXOggHeaderSize;
    for (NSData *packet in packets) {
        NSUInteger left = packet.length;
        while (left >= 255) {
            bytes[table++] = 255;
            left -= 255;
        }
        bytes[table++] = (uint8_t)left;
    }

    NSUInteger cursor = table;
    for (NSData *packet in packets) {
        memcpy(bytes + cursor, packet.bytes, packet.length);
        cursor += packet.length;
    }

    MAXPutLittle(bytes, 22, MAXOggCrc32(bytes, page.length), 4);

    [target appendData:page];
}

/// Чем записано: частота, каналы и разгон кодека.
+ (NSData *)headPacket {
    NSMutableData *head = [NSMutableData dataWithLength:19];
    uint8_t *bytes = head.mutableBytes;

    MAXPutAscii(bytes, 0, @"OpusHead");
    bytes[8] = 1;   // версия
    bytes[9] = 1;   // каналов

    MAXPutLittle(bytes, 10, MAXOpusPreSkip, 2);
    MAXPutLittle(bytes, 12, MAXOpusRecordRate, 4);
    MAXPutLittle(bytes, 16, 0, 2);   // поправка громкости

    bytes[18] = 0;  // раскладка каналов — простейшая
    return head;
}

/// Подписи. Своих нет, но и пустыми страницу пропустить нельзя.
+ (NSData *)tagsPacket {
    NSUInteger vendor = MAXOggVendor.length;
    NSMutableData *made = [NSMutableData dataWithLength:8 + 4 + vendor + 4];
    uint8_t *bytes = made.mutableBytes;

    MAXPutAscii(bytes, 0, @"OpusTags");
    MAXPutLittle(bytes, 8, vendor, 4);
    MAXPutAscii(bytes, 12, MAXOggVendor);
    MAXPutLittle(bytes, 12 + vendor, 0, 4);

    return made;
}

@end
