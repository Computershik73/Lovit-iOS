//
//  MAXPacket.m
//

#import "MAXPacket.h"
#import "MAXMessagePack.h"
#import "MAXLZ4.h"

const NSUInteger MAXPacketHeaderSize = 10;
const NSUInteger MAXPacketMaxDecompressedSize = 32 * 1024 * 1024;
NSString *const MAXPacketErrorDomain = @"ru.max.packet";

/// Payload меньше этого размера отправляется без сжатия (как в оригинале).
static const NSUInteger MAXCompressionThreshold = 32;

/// Komet шлёт исходящие пакеты сжатыми; здесь по умолчанию выключено —
/// протокол разрешает флаг 0 (без сжатия) на любом размере, и это исключает
/// расхождения с серверным распаковщиком. Включается через
/// +[MAXPacket setCompressOutgoing:].
static BOOL MAXCompressOutgoing = NO;

/// Распаковать, пропустив сколько-то байт впереди. nil означает «не вышло» —
/// разбирать такое дальше незачем.
static NSData *MAXInflateBody(NSData *body, NSUInteger skip) {
    if (skip >= body.length) return nil;

    NSData *slice = skip > 0
        ? [body subdataWithRange:NSMakeRange(skip, body.length - skip)]
        : body;

    return [MAXLZ4 decompress:slice maxSize:MAXPacketMaxDecompressedSize error:NULL];
}

/// Попытка разобрать. `ok` говорит, удалась ли она, — а не сам ответ: пустое
/// содержимое сервер тоже присылает, и путать его с неудачей нельзя. Первая
/// по счёту беда запоминается для журнала.
static id MAXTryUnpackBody(NSData *raw, NSString *how, NSString **first, BOOL *ok) {
    *ok = NO;
    if (raw.length == 0) return nil;

    NSError *problem = nil;
    id made = [MAXMessagePack unpack:raw error:&problem];

    if (made == nil && problem != nil) {
        if (*first == nil) {
            *first = [NSString stringWithFormat:@"%@: %@", how, problem.localizedDescription];
        }
        return nil;
    }

    *ok = YES;

    // О необычном способе говорим вслух — и один раз: строка в журнале ценна
    // тем, что называет способ, а не тем, что повторяется на каждый пакет.
    static NSMutableSet *told = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ told = [[NSMutableSet alloc] init]; });

    if (![how isEqualToString:@"сжатое"] && ![how isEqualToString:@"как есть"]
            && ![told containsObject:how]) {
        [told addObject:how];
        NSLog(@"[Max/Пакет] содержимое разобрано как %@", how);
    }

    return made;
}

/// Разобрать содержимое, пробуя способы по очереди.
///
/// Байт сжатия в заголовке — подсказка, а не описание способа: в нём лежит
/// множитель, во сколько раз данные распухнут, и о самом виде упаковки он
/// говорит только «ноль — как есть, иначе сжато». Что именно значит «сжато»,
/// зависит от того, чем упаковывал сервер, а он не один и не всегда одинаков.
///
/// Отсюда и порядок: сперва самое вероятное, дальше — соседние толкования тех
/// же байтов. Годным считается только то, что разобралось целиком.
///
/// Так у людей и не входило в аккаунт: ответ на вход приходил сжатым — а
/// сжимает сервер только крупные, оттого и «у некоторых», — первое же
/// толкование не подходило, и пакет отбрасывался целиком. Клиент продолжал
/// ждать ответа, которого больше не будет, и через полминуты объявлял
/// «сервер не ответил». Той же бедой оборачивался и пустой список контактов.
static id MAXReadPacketBody(NSData *body, NSUInteger ratio, BOOL *ok, NSError **error) {
    NSString *first = nil;
    id made = nil;

    if (ratio != 0) {
        made = MAXTryUnpackBody(MAXInflateBody(body, 0), @"сжатое", &first, ok);
        if (*ok) return made;

        // Тот же блок, но с длиной впереди: некоторые упаковщики пишут перед
        // сжатым его будущий размер четырьмя байтами.
        if (body.length > 4) {
            made = MAXTryUnpackBody(MAXInflateBody(body, 4),
                                    @"сжатое с длиной впереди", &first, ok);
            if (*ok) return made;
        }

        // А бывает, что множитель проставлен, но сжатия нет.
        made = MAXTryUnpackBody(body, @"несжатое, хоть и помечено", &first, ok);
        if (*ok) return made;
    } else {
        made = MAXTryUnpackBody(body, @"как есть", &first, ok);
        if (*ok) return made;

        made = MAXTryUnpackBody(MAXInflateBody(body, 0), @"сжатое без пометки", &first, ok);
        if (*ok) return made;
    }

    if (error != NULL) {
        *error = [NSError errorWithDomain:MAXPacketErrorDomain
                                     code:3
                                 userInfo:@{NSLocalizedDescriptionKey:
                    [NSString stringWithFormat:
                     @"Содержимое не разобралось ни одним способом; первая беда — %@",
                     first ?: @"нет"]}];
    }
    return nil;
}

@implementation MAXPacket

// Ивар у cmd переименован не для красоты: автоматическое имя совпало бы
// со скрытым вторым параметром каждого метода (селектором), и компилятор
// ругается -Wshadow-ivar в каждой строке, где к нему обращаются. Публичное
// имя свойства при этом остаётся прежним — packet.cmd.
@synthesize cmd = _cmdType;

+ (void)setCompressOutgoing:(BOOL)enabled {
    MAXCompressOutgoing = enabled;
}

+ (BOOL)compressOutgoing {
    return MAXCompressOutgoing;
}

+ (instancetype)packetWithCmd:(NSUInteger)cmd
                          seq:(NSUInteger)seq
                       opcode:(NSUInteger)opcode
                      payload:(id)payload {
    MAXPacket *packet = [[MAXPacket alloc] init];
    packet.api = 10;
    packet.cmd = cmd;
    packet.seq = seq;
    packet.opcode = opcode;
    packet.payload = payload;
    return packet;
}

- (id)init {
    self = [super init];
    if (self) {
        _api = 10;
        _cmdType = MAXCmdTypeRequest;
    }
    return self;
}

- (BOOL)isOk { return _cmdType == MAXCmdTypeOk; }
- (BOOL)isError { return _cmdType == MAXCmdTypeError; }
- (BOOL)isPush { return _cmdType == MAXCmdTypePush; }

- (NSDictionary *)payloadMap {
    return [_payload isKindOfClass:[NSDictionary class]] ? _payload : nil;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"Packet(ver=%lu cmd=%lu seq=%lu opcode=%lu)",
            (unsigned long)_api, (unsigned long)_cmdType, (unsigned long)_seq, (unsigned long)_opcode];
}

+ (NSData *)packOpcode:(NSUInteger)opcode payload:(NSDictionary *)payload seq:(NSUInteger)seq {
    NSData *raw = [MAXMessagePack pack:(payload ?: @{})];

    NSData *body = raw;
    NSUInteger flag = 0;
    if (MAXCompressOutgoing && raw.length >= MAXCompressionThreshold) {
        NSData *compressed = [MAXLZ4 blockCompress:raw];
        if (compressed.length > 0 && compressed.length < raw.length) {
            body = compressed;
            flag = (raw.length / compressed.length) + 1;
            if (flag > 0xFF) flag = 0xFF;
        }
    }

    NSMutableData *out = [NSMutableData dataWithCapacity:MAXPacketHeaderSize + body.length];
    uint8_t header[10];
    header[0] = 10;
    header[1] = (uint8_t)MAXCmdTypeRequest;
    header[2] = (uint8_t)((seq >> 8) & 0xFF);
    header[3] = (uint8_t)(seq & 0xFF);
    header[4] = (uint8_t)((opcode >> 8) & 0xFF);
    header[5] = (uint8_t)(opcode & 0xFF);
    header[6] = (uint8_t)(flag & 0xFF);
    header[7] = (uint8_t)((body.length >> 16) & 0xFF);
    header[8] = (uint8_t)((body.length >> 8) & 0xFF);
    header[9] = (uint8_t)(body.length & 0xFF);
    [out appendBytes:header length:MAXPacketHeaderSize];
    [out appendData:body];
    return out;
}

+ (MAXPacket *)unpack:(NSData *)data error:(NSError **)error {
    if (data.length < MAXPacketHeaderSize) {
        if (error) {
            *error = [NSError errorWithDomain:MAXPacketErrorDomain
                                         code:1
                                     userInfo:@{NSLocalizedDescriptionKey: @"Пакет короче заголовка"}];
        }
        return nil;
    }

    const uint8_t *bytes = (const uint8_t *)data.bytes;
    MAXPacket *packet = [[MAXPacket alloc] init];
    packet.api = bytes[0];
    packet.cmd = bytes[1];
    packet.seq = ((NSUInteger)bytes[2] << 8) | bytes[3];
    packet.opcode = ((NSUInteger)bytes[4] << 8) | bytes[5];

    NSUInteger compressionFlag = bytes[6];
    NSUInteger payloadLength = ((NSUInteger)bytes[7] << 16) | ((NSUInteger)bytes[8] << 8) | bytes[9];

    if (payloadLength == 0) return packet;

    if (MAXPacketHeaderSize + payloadLength > data.length) {
        if (error) {
            *error = [NSError errorWithDomain:MAXPacketErrorDomain
                                         code:2
                                     userInfo:@{NSLocalizedDescriptionKey: @"Длина payload больше буфера"}];
        }
        return nil;
    }

    NSData *slice = [data subdataWithRange:NSMakeRange(MAXPacketHeaderSize, payloadLength)];
    if (slice.length == 0) return packet;

    NSError *bodyError = nil;
    BOOL ok = NO;
    id payload = MAXReadPacketBody(slice, compressionFlag, &ok, &bodyError);

    if (!ok) {
        if (error) *error = bodyError;
        return nil;
    }

    packet.payload = payload;
    return packet;
}

@end

static BOOL MAXIsRawServerTemplate(NSString *text) {
    return [text hasPrefix:@"Key: "] || [text hasPrefix:@"key: "];
}

NSString *MAXMessageFromErrorPayload(id payload) {
    if ([payload isKindOfClass:[NSDictionary class]]) {
        NSDictionary *map = payload;
        id message = map[@"message"];
        if ([message isEqual:@"FAIL_WRONG_PASSWORD"] || [message isEqual:@"FAIL_LOGIN_TOKEN"]) {
            return @"Ваш токен был отклонён сервером. Попробуйте войти ещё раз.";
        }
        NSArray *keys = @[@"localizedMessage", @"title", @"message"];
        for (NSString *key in keys) {
            id value = map[key];
            if (![value isKindOfClass:[NSString class]]) continue;
            NSString *text = [value stringByTrimmingCharactersInSet:
                              [NSCharacterSet whitespaceAndNewlineCharacterSet]];
            if (text.length == 0 || MAXIsRawServerTemplate(text)) continue;
            return text;
        }
        return @"Неизвестная ошибка";
    }
    if (payload == nil || payload == [NSNull null]) return @"Неизвестная ошибка";
    NSString *text = [payload description];
    return text.length > 0 ? text : @"Неизвестная ошибка";
}

BOOL MAXIsSessionExpiredPayload(id payload) {
    if (![payload isKindOfClass:[NSDictionary class]]) return NO;
    id message = ((NSDictionary *)payload)[@"message"];
    return [message isEqual:@"FAIL_LOGIN_TOKEN"] || [message isEqual:@"FAIL_WRONG_PASSWORD"];
}
