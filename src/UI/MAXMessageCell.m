//
//  MAXMessageCell.m
//

#import "MAXMessageCell.h"
#import "MAXMessage.h"
#import "MAXAttachment.h"
#import "MAXChatsModule.h"
#import "MAXContact.h"
#import "MAXAvatarView.h"
#import "MAXTheme.h"
#import "MAXIcons.h"
#import "MAXImageLoader.h"
#import "MAXRichText.h"
#import "MAXWaveView.h"
#import "MAXLottie.h"
#import "MAXVoicePlayer.h"
#import "MAXTranscripts.h"
#import <QuartzCore/QuartzCore.h>

static const CGFloat MAXBubblePaddingX = 10.0;
static const CGFloat MAXBubblePaddingY = 7.0;
static const CGFloat MAXBubbleMargin = 8.0;
static const CGFloat MAXBubbleMaxWidthRatio = 0.72;
static const CGFloat MAXSenderLabelHeight = 16.0;
static const CGFloat MAXForwardLabelHeight = 15.0;
static const CGFloat MAXAvatarSize = 30.0;
static const CGFloat MAXAvatarGap = 6.0;
static const CGFloat MAXReplyHeight = 34.0;
static const CGFloat MAXReactionsHeight = 18.0;
static const CGFloat MAXTimeLabelHeight = 13.0;
static const CGFloat MAXFileRowHeight = 44.0;

/// Строка голосового: кнопка, график громкости и длительность.
static const CGFloat MAXVoiceRowHeight = 40.0;

/// Кнопка «Т» в строке голосового и шрифт расшифровки под ним.
static const CGFloat MAXTranscribeWidth = 26.0;
static const CGFloat MAXTranscriptFontSize = 13.0;
static const CGFloat MAXVoiceButtonSize = 30.0;
static const CGFloat MAXFileIconSize = 30.0;
static const CGFloat MAXMediaGap = 6.0;
static const CGFloat MAXPhotoTileGap = 2.0;

/// Высота полоски с датой над первым сообщением дня.
static const CGFloat MAXDateHeight = 26.0;

/// Раскладка картинок в пузыре: одна — во всю ширину со своими пропорциями,
/// несколько — квадратными плитками по две в ряд, нечётная последняя занимает
/// ряд целиком.
///
/// Komet показывает не больше четырёх и рисует «+N» поверх последней; здесь
/// показываются все. Спрятать лишние было бы нечестно: галереи в порте нет,
/// и открыть скрытое оказалось бы нечем.
/// Сторона стикера в переписке. Больше делать нечего: стикер и так самый
/// заметный на экране, а на телефонах тех лет ширина всего 320 точек.
static const CGFloat MAXStickerSide = 140.0;

/// Сторона кружка. Он крупнее стикера: в нём лицо, и мелким оно не читается.
static const CGFloat MAXNoteSide = 180.0;

/// Кружок-видеосообщение: показывается кругом и без пузыря, как и стикер.
static BOOL MAXIsBareNote(MAXMessage *message) {
    if (message.text.length > 0) return NO;
    if (message.fileAttachment != nil || message.voiceAttachment != nil) return NO;
    if (message.replyPayload != nil) return NO;
    if (message.reactionsSummary.length > 0) return NO;

    NSArray *photos = message.photoAttachments;
    if (photos.count != 1) return NO;

    return ((MAXAttachment *)photos[0]).isVideoNote;
}

/// Сообщение, у которого всё содержимое — один стикер.
///
/// Такое рисуется без пузыря: у стикера свои поля и прозрачные углы, и
/// облачко вокруг него выглядит наклейкой на наклейке. Так же его показывают
/// и MAX, и Komet. Подпись под стикером сервер прислать может — тогда пузырь
/// нужен, и сообщение остаётся обычным.
static BOOL MAXIsBareSticker(MAXMessage *message) {
    if (message.text.length > 0) return NO;
    if (message.fileAttachment != nil) return NO;
    if (message.replyPayload != nil) return NO;
    if (message.reactionsSummary.length > 0) return NO;

    NSArray *photos = message.photoAttachments;
    if (photos.count != 1) return NO;

    return ((MAXAttachment *)photos[0]).type == MAXAttachmentTypeSticker;
}

static CGFloat MAXPhotoLayoutHeight(NSArray *photos, CGFloat mediaWidth) {
    NSUInteger count = photos.count;
    if (count == 0) return 0;
    if (count == 1) return [(MAXAttachment *)photos[0] displayHeightForWidth:mediaWidth];

    CGFloat tile = (mediaWidth - MAXPhotoTileGap) / 2.0;
    NSUInteger rows = (count + 1) / 2;
    return rows * tile + (rows - 1) * MAXPhotoTileGap;
}

static CGRect MAXPhotoTileFrame(NSUInteger index,
                                NSUInteger count,
                                CGFloat mediaWidth,
                                CGFloat singleHeight) {
    if (count == 1) return CGRectMake(0, 0, mediaWidth, singleHeight);

    CGFloat tile = (mediaWidth - MAXPhotoTileGap) / 2.0;
    CGFloat y = (index / 2) * (tile + MAXPhotoTileGap);

    // Нечётная последняя растягивается на весь ряд — дырка справа выглядела бы
    // поломкой раскладки.
    if (index == count - 1 && count % 2 == 1) return CGRectMake(0, y, mediaWidth, tile);

    return CGRectMake((index % 2) * (tile + MAXPhotoTileGap), y, tile, tile);
}

#pragma mark - Диагностика вложений

/// Короткая сводка по `attaches`: имена полей и укороченные значения.
///
/// Целиком payload в журнал писать нельзя — там и текст переписки, и превью
/// на сотни килобайт, — поэтому строки режутся, а двоичное показывается одной
/// длиной. Нужно это ровно затем, чтобы увидеть, чем отличаются сообщения
/// с фотографиями, которые не показываются.
static NSString *MAXShortFieldValue(id value) {
    if ([value isKindOfClass:[NSString class]]) {
        NSString *text = value;
        if (text.length <= 60) return text;
        return [[text substringToIndex:60] stringByAppendingString:@"…"];
    }
    if ([value isKindOfClass:[NSData class]]) {
        return [NSString stringWithFormat:@"<%lu Б>", (unsigned long)[value length]];
    }
    if ([value isKindOfClass:[NSDictionary class]]) {
        return [NSString stringWithFormat:@"{%@}",
                [[value allKeys] componentsJoinedByString:@","]];
    }
    if ([value isKindOfClass:[NSArray class]]) {
        return [NSString stringWithFormat:@"[%lu]", (unsigned long)[value count]];
    }
    return [value description];
}

static NSString *MAXAttachesSummary(id attaches) {
    if (attaches == nil || attaches == [NSNull null]) return @"поля attaches нет";
    if (![attaches isKindOfClass:[NSArray class]]) {
        return [NSString stringWithFormat:@"attaches не массив, а %@", [attaches class]];
    }
    if ([attaches count] == 0) return @"attaches пуст";

    NSMutableArray *parts = [NSMutableArray array];
    for (id attach in attaches) {
        if (![attach isKindOfClass:[NSDictionary class]]) {
            [parts addObject:[NSString stringWithFormat:@"<%@>", [attach class]]];
            continue;
        }
        NSMutableArray *fields = [NSMutableArray array];
        for (id key in (NSDictionary *)attach) {
            [fields addObject:[NSString stringWithFormat:@"%@=%@",
                               key, MAXShortFieldValue(((NSDictionary *)attach)[key])]];
        }
        [parts addObject:[NSString stringWithFormat:@"{%@}",
                          [fields componentsJoinedByString:@" "]]];
    }
    return [parts componentsJoinedByString:@" "];
}

/// Ячейки настраиваются заново на каждой прокрутке — без этого одно и то же
/// сообщение забило бы журнал десятками одинаковых строк.
static BOOL MAXShouldLogMessageOnce(NSString *messageId) {
    static NSMutableSet *seen = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ seen = [[NSMutableSet alloc] init]; });

    if (messageId.length == 0) return YES;
    if ([seen containsObject:messageId]) return NO;
    [seen addObject:messageId];
    return YES;
}

/// Имя источника пересылки, либо nil, если разрешить его нечем.
///
/// Порядок тот же, что у `_forwardedSourceName` в Komet: имя канала из `link`,
/// затем контакт по автору исходного сообщения (у Komet это `ContactCache`,
/// здесь — кэш контактов в `MAXChatsModule`).
static NSString *MAXForwardedSourceName(MAXMessage *message) {
    if (message.forwardedFrom.length > 0) return message.forwardedFrom;

    MAXContact *contact = [[MAXChatsModule shared] contactWithId:message.forwardedSenderId];
    if (contact.name.length > 0) return contact.name;

    if (message.forwardedIsChannel) return @"канала";
    return nil;
}

/// Поля словаря с укороченными значениями, на один уровень вглубь. Нужна,
/// чтобы разобрать `link` пересылки, когда автор не опознался.
static NSString *MAXFieldsSummary(id map) {
    if (![map isKindOfClass:[NSDictionary class]]) return @"—";

    NSMutableArray *fields = [NSMutableArray array];
    for (id key in (NSDictionary *)map) {
        id value = ((NSDictionary *)map)[key];

        // Текст пересланного сообщения для разбора не нужен, а в журнал,
        // который потом кому-то показывают, попадать ему незачем.
        if ([[key description] isEqualToString:@"text"]) {
            [fields addObject:[NSString stringWithFormat:@"text=<%lu симв.>",
                               (unsigned long)[[value description] length]]];
            continue;
        }

        if ([value isKindOfClass:[NSDictionary class]]) {
            [fields addObject:[NSString stringWithFormat:@"%@={%@}",
                               key, MAXFieldsSummary(value)]];
            continue;
        }
        [fields addObject:[NSString stringWithFormat:@"%@=%@", key, MAXShortFieldValue(value)]];
    }
    return [fields componentsJoinedByString:@" "];
}

#pragma mark - Плитка с картинкой

/// Одна картинка в пузыре: своя крутилка и своя подпись на случай, когда
/// показать нечего. Сообщение может нести несколько снимков, и каждый живёт
/// сам по себе — общий на всех крутилки не хватало.
@interface MAXPhotoTile : UIImageView
@property (nonatomic, strong) MAXAttachment *attachment;
- (void)prepareForImage;
- (void)showSpinner;
- (void)showHint;
/// Движущийся стикер: завести, остановить, идёт ли.
- (void)startLottieIfNeeded;
- (void)stopLottie;
- (BOOL)lottieGoing;
@end

@implementation MAXPhotoTile {
    UIActivityIndicatorView *_spinner;
    UILabel *_hint;
    UIView *_playBadge;

    MAXLottie *_lottie;         // движущийся стикер, если это он
    NSTimer *_lottieTimer;
    NSDate *_lottieStarted;
    NSString *_lottieUrl;       // чей стикер сейчас открыт или открывается
}

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.contentMode = UIViewContentModeScaleAspectFill;
        self.clipsToBounds = YES;
        self.layer.cornerRadius = 10.0;
        self.backgroundColor = [MAXTheme placeholderTileColor];
        self.userInteractionEnabled = YES;

        _spinner = [[UIActivityIndicatorView alloc]
                    initWithActivityIndicatorStyle:[MAXTheme activityIndicatorStyle]];
        _spinner.hidesWhenStopped = YES;
        [self addSubview:_spinner];

        _hint = [[UILabel alloc] initWithFrame:CGRectZero];
        _hint.text = @"Нажмите, чтобы открыть";
        _hint.font = [UIFont systemFontOfSize:13.0];
        _hint.textColor = [MAXTheme secondaryTextColor];
        _hint.textAlignment = NSTextAlignmentCenter;
        _hint.backgroundColor = [UIColor clearColor];
        _hint.hidden = YES;
        [self addSubview:_hint];

        // Значок «играть» поверх кадра: без него ролик неотличим от снимка,
        // а открываются они по-разному.
        _playBadge = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 44.0, 44.0)];
        _playBadge.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.45];
        _playBadge.layer.cornerRadius = 22.0;
        _playBadge.userInteractionEnabled = NO;
        _playBadge.hidden = YES;

        // Значок нарисованный, а не знак из шрифта: «▶» на разных прошивках
        // то мелкий, то вовсе цветной эмодзи, не слушающийся ни цвета, ни
        // размера. Сдвиг на точку вправо — потому что треугольник, стоящий
        // ровно по середине, кажется сдвинутым влево: глаз считает середину
        // по весу фигуры, а вес у неё у широкой стороны.
        UIImageView *triangle =
            [[UIImageView alloc] initWithFrame:CGRectMake(1.0, 0, 44.0, 44.0)];
        triangle.image = [MAXIcons imageNamed:@"play" size:16.0
                                        color:[UIColor whiteColor]];
        triangle.contentMode = UIViewContentModeCenter;
        [_playBadge addSubview:triangle];
        [self addSubview:_playBadge];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGSize size = self.bounds.size;
    _spinner.center = CGPointMake(size.width / 2.0, size.height / 2.0);
    _hint.frame = CGRectMake(0, (size.height - 18.0) / 2.0, size.width, 18.0);
    _playBadge.center = CGPointMake(size.width / 2.0, size.height / 2.0);
}

- (void)setAttachment:(MAXAttachment *)attachment {
    // Плитку переиспользуют: то, что двигалось в прошлой строке, должно
    // остановиться до того, как в неё положат новое.
    if (![attachment.lottieUrl isEqualToString:_lottieUrl]) [self stopLottie];

    _attachment = attachment;
    _playBadge.hidden = (attachment.type != MAXAttachmentTypeVideo);
    [self bringSubviewToFront:_playBadge];

    // У стикера прозрачные углы и свои поля: серая подложка со скруглением
    // превратила бы его в наклейку на плашке.
    BOOL sticker = (attachment.type == MAXAttachmentTypeSticker);
    self.contentMode = sticker ? UIViewContentModeScaleAspectFit
                               : UIViewContentModeScaleAspectFill;
    self.backgroundColor = sticker ? [UIColor clearColor] : [MAXTheme placeholderTileColor];

    // Кружок круглый — на iOS это одно скругление в половину стороны. На
    // Windows Phone ради того же круга пришлось складывать шестнадцать
    // повёрнутых обрезок: тамошняя разметка обрезает только прямоугольником.
    if (attachment.isVideoNote) {
        self.layer.cornerRadius = self.bounds.size.width / 2.0;
    } else {
        self.layer.cornerRadius = sticker ? 0.0 : 10.0;
    }
}

/// Скругление считается от стороны, а она известна только после раскладки.
- (void)setFrame:(CGRect)frame {
    [super setFrame:frame];
    if (self.attachment.isVideoNote) self.layer.cornerRadius = frame.size.width / 2.0;
}

- (void)prepareForImage {
    self.image = nil;
    _hint.hidden = YES;
    [_spinner stopAnimating];
}

- (void)showSpinner {
    _hint.hidden = YES;
    [_spinner startAnimating];
}

#pragma mark - Движущийся стикер

/// Завести движение, если стикер движущийся.
///
/// Описание скачивается и разбирается один раз на плитку; пока это идёт,
/// на месте стикера остаётся его неподвижная картинка — та самая, что
/// показывается и у обычных.
- (void)startLottieIfNeeded {
    NSString *url = _attachment.lottieUrl;
    if (url.length == 0) return;
    if ([url isEqualToString:_lottieUrl]) return;     // уже это и открываем

    [self stopLottie];
    _lottieUrl = [url copy];

    NSString *wanted = [url copy];
    __weak MAXPhotoTile *weakSelf = self;

    // Сторона — та, в которой стикер и будет показан: рисовать мельче
    // значит получить мыло, крупнее — тратить время впустую.
    //
    // Меньшая из двух, а не большая: плитка под одиночным вложением —
    // во всю ширину пузыря, а стикер вписывается в неё по высоте и выходит
    // квадратом по меньшей стороне. С большей выходило 200 там, где место
    // 140, — вчетверо лишней работы на каждый кадр.
    CGSize place = self.bounds.size;
    CGFloat side = MIN(place.width, place.height);
    if (side < 1.0) side = MAXStickerSide;

    [MAXLottie openURL:url
                   key:(_attachment.token ?: url)
                  side:side
            completion:^(MAXLottie *animation) {
        MAXPhotoTile *strongSelf = weakSelf;
        if (strongSelf == nil || animation == nil) return;

        // Пока качалось, плитку могли отдать другому сообщению.
        if (![strongSelf->_lottieUrl isEqualToString:wanted]) return;

        strongSelf->_lottie = animation;
        strongSelf->_lottieStarted = [NSDate date];

        // Не чаще тридцати раз в секунду, даже если стикер снят на
        // шестидесяти. Замедлить его этим нельзя: нужный кадр считается от
        // времени, а не от числа тиков, — стикер просто пойдёт через кадр.
        // А вот успеть нарисовать вдвое меньше кадров старое устройство
        // вполне может, и тогда не встанет всё остальное.
        NSTimeInterval step = MAX(animation.frameDuration, 1.0 / 30.0);

        strongSelf->_lottieTimer =
            [NSTimer scheduledTimerWithTimeInterval:step
                                             target:strongSelf
                                           selector:@selector(lottieTick)
                                           userInfo:nil
                                            repeats:YES];
    }];
}

/// Остановить движение и отпустить сцену.
///
/// Зовётся и при переиспользовании плитки, и когда строка уходит с экрана:
/// невидимое рисовать незачем — движения всё равно никто не увидит, а время
/// и батарею оно тратит.
- (void)stopLottie {
    [_lottieTimer invalidate];
    _lottieTimer = nil;
    _lottie = nil;
    _lottieStarted = nil;
    _lottieUrl = nil;
}

- (BOOL)lottieGoing { return _lottieTimer != nil; }

/// Какой кадр показывать сейчас — считается от времени, а не от числа тиков:
/// пропущенный кадр не должен замедлять стикер.
- (void)lottieTick {
    if (_lottie == nil || _lottie.busy) return;

    NSInteger frames = _lottie.frames;
    if (frames <= 0) {
        [self stopLottie];
        return;
    }

    NSTimeInterval passed = -[_lottieStarted timeIntervalSinceNow];
    NSInteger frame = (NSInteger)(passed / _lottie.frameDuration) % frames;

    __weak MAXPhotoTile *weakSelf = self;
    [_lottie renderFrame:frame completion:^(UIImage *image) {
        MAXPhotoTile *strongSelf = weakSelf;
        if (strongSelf == nil || image == nil) return;

        [strongSelf->_spinner stopAnimating];
        strongSelf->_hint.hidden = YES;
        strongSelf.image = image;
    }];
}

- (void)showHint {
    [_spinner stopAnimating];
    // У ролика уже есть значок «играть» — вторая подсказка поверх кадра
    // только загромождает пузырь.
    _hint.hidden = (_attachment.type == MAXAttachmentTypeVideo);
}

@end

#pragma mark - Пузырь

@interface MAXMessageCell () <UIGestureRecognizerDelegate>
@end

@implementation MAXMessageCell {
    UIView *_bubble;
    UILabel *_dateLabel;
    MAXAvatarView *_avatarView;
    UILabel *_senderLabel;
    UILabel *_forwardLabel;
    UILabel *_textLabel_;
    UILabel *_timeLabel;
    UILabel *_reactionsLabel;

    UIView *_replyBlock;
    UIView *_replyBar;
    UILabel *_replyAuthor;
    UILabel *_replyText;

    NSMutableArray *_photoTiles;

    UIView *_fileRow;
    UIImageView *_fileIcon;
    UILabel *_fileName;
    UILabel *_fileSize;

    UIView *_voiceRow;
    UIView *_voiceButton;
    UIImageView *_voiceIcon;
    MAXWaveView *_voiceWave;
    UILabel *_voiceTime;
    UIImageView *_transcribeIcon;   // кнопка «Т»
    UILabel *_transcriptLabel;      // расшифровка под строкой голосового
}

+ (UIFont *)messageFont {
    return [UIFont systemFontOfSize:15.0];
}

+ (CGFloat)maxBubbleWidthForWidth:(CGFloat)width {
    return width * MAXBubbleMaxWidthRatio;
}

+ (CGSize)textSizeForText:(NSString *)text width:(CGFloat)width {
    CGFloat maxWidth = [self maxBubbleWidthForWidth:width] - MAXBubblePaddingX * 2;
    if (maxWidth < 40) maxWidth = 40;

    return [text sizeWithFont:[self messageFont]
            constrainedToSize:CGSizeMake(maxWidth, 10000)
                lineBreakMode:NSLineBreakByWordWrapping];
}

/// Размеченный текст пузыря либо nil, если размечать нечего.
+ (NSAttributedString *)markedTextFor:(MAXMessage *)message
                                shown:(NSString *)shown
                                color:(UIColor *)color {
    if (message.markupRanges.count == 0) return nil;
    if (![shown isEqualToString:message.text]) return nil;   // подпись вложения не размечена

    return [MAXRichText attributedText:shown
                                ranges:message.markupRanges
                                  font:[self messageFont]
                                 color:color
                             linkColor:[MAXTheme accentColor]];
}

/// Высота размеченного текста.
///
/// Считать по обычной строке нельзя: моноширинное шире системного, и строки
/// переносятся не там же — хвост оказывался бы срезан. При этом обычная
/// мерка остаётся нижней границей: она надёжнее, а лишний пиксель пустоты
/// незаметнее обрезанной строки.
+ (CGSize)textSizeForMessage:(MAXMessage *)message
                       shown:(NSString *)shown
                       width:(CGFloat)width {
    CGSize plain = [self textSizeForText:shown width:width];

    NSAttributedString *marked = [self markedTextFor:message
                                               shown:shown
                                               color:[MAXTheme textColor]];
    if (marked == nil) return plain;

    CGFloat maxWidth = [self maxBubbleWidthForWidth:width] - MAXBubblePaddingX * 2;
    if (maxWidth < 40) maxWidth = 40;

    CGRect box = [marked boundingRectWithSize:CGSizeMake(maxWidth, 10000)
                                      options:(NSStringDrawingUsesLineFragmentOrigin |
                                               NSStringDrawingUsesFontLeading)
                                      context:nil];

    return CGSizeMake(MAX(plain.width, ceilf(box.size.width)),
                      MAX(plain.height, ceilf(box.size.height)));
}

/// Ширина картинки в пузыре — вся доступная ширина за вычетом отступов.
+ (CGFloat)mediaWidthForWidth:(CGFloat)width {
    return [self maxBubbleWidthForWidth:width] - MAXBubblePaddingX * 2;
}

/// То же, но у стикера и кружка своя мера: они не растягиваются на весь
/// пузырь.
+ (CGFloat)mediaWidthForMessage:(MAXMessage *)message width:(CGFloat)width {
    if (MAXIsBareSticker(message)) return MAXStickerSide;
    if (MAXIsBareNote(message)) return MAXNoteSide;
    return [self mediaWidthForWidth:width];
}

/// Текст расшифровки, который сейчас показывается под сообщением, либо nil.
/// Его показывают и пока сервер считает: «Расшифровываю…» на том же месте
/// понятнее, чем кружок где-то сбоку.
+ (NSString *)transcriptTextForMessage:(MAXMessage *)message {
    if (message.voiceAttachment == nil) return nil;

    MAXTranscript *transcript =
        [[MAXTranscripts shared] transcriptForMessageId:message.messageId];
    if (transcript == nil || !transcript.shown) return nil;

    return transcript.text;
}

/// Сколько места занимает расшифровка вместе с отступом под ней. Считается
/// и при раскладке, и при замере высоты строки — числа должны совпадать,
/// поэтому ширину обе стороны передают одну и ту же.
+ (CGFloat)transcriptHeightForText:(NSString *)text mediaWidth:(CGFloat)mediaWidth {
    if (text.length == 0 || mediaWidth < 20) return 0;

    CGSize size = [text sizeWithFont:[UIFont systemFontOfSize:MAXTranscriptFontSize]
                   constrainedToSize:CGSizeMake(mediaWidth, 10000)
                       lineBreakMode:NSLineBreakByWordWrapping];

    return ceilf(size.height) + MAXMediaGap;
}

+ (CGFloat)heightForMessage:(MAXMessage *)message
                 showSender:(BOOL)showSender
                   dateText:(NSString *)dateText
                      width:(CGFloat)width {
    NSArray *photos = message.photoAttachments;
    MAXAttachment *photo = [photos lastObject];
    MAXAttachment *file = message.fileAttachment;

    CGFloat height = MAXBubblePaddingY * 2 + MAXTimeLabelHeight;
    if (showSender) height += MAXSenderLabelHeight;
    if (message.forwardedPayload != nil) height += MAXForwardLabelHeight;
    if (message.replyPayload != nil) height += MAXReplyHeight + MAXMediaGap;
    if (message.reactionsSummary.length > 0) height += MAXReactionsHeight;

    if (photo != nil) {
        height += MAXPhotoLayoutHeight(photos, [self mediaWidthForMessage:message width:width])
                + MAXMediaGap;
    }
    if (file != nil) {
        height += MAXFileRowHeight + MAXMediaGap;
    }
    if (message.voiceAttachment != nil) {
        height += MAXVoiceRowHeight + MAXMediaGap;
        height += [self transcriptHeightForText:[self transcriptTextForMessage:message]
                                     mediaWidth:[self mediaWidthForMessage:message
                                                                     width:width]];
    }

    // У сообщения с вложением текст часто пустой — тогда строка не нужна.
    NSString *text = message.text;
    if (text.length > 0 || (photo == nil && file == nil && message.voiceAttachment == nil)) {
        NSString *shown = text.length > 0 ? text : message.displayText;
        if (shown.length == 0) shown = @" ";
        height += [self textSizeForMessage:message shown:shown width:width].height;
    }

    if (dateText.length > 0) height += MAXDateHeight;

    return height + MAXBubbleMargin * 2;
}

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        self.backgroundColor = [UIColor clearColor];
        self.contentView.backgroundColor = [UIColor clearColor];

        _avatarView = [[MAXAvatarView alloc] initWithFrame:
                       CGRectMake(0, 0, MAXAvatarSize, MAXAvatarSize)];
        _avatarView.hidden = YES;
        _avatarView.userInteractionEnabled = YES;
        [self.contentView addSubview:_avatarView];

        UITapGestureRecognizer *avatarTap =
            [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(senderTapped)];
        [_avatarView addGestureRecognizer:avatarTap];

        // Скругление и всё остальное задаёт MAXTheme при перекладке: оно
        // разное у скевоморфной и современной темы.
        _dateLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _dateLabel.font = [UIFont boldSystemFontOfSize:12.0];
        _dateLabel.textAlignment = NSTextAlignmentCenter;
        _dateLabel.textColor = [MAXTheme secondaryTextColor];
        _dateLabel.backgroundColor = [UIColor clearColor];
        _dateLabel.hidden = YES;
        [self.contentView addSubview:_dateLabel];

        _bubble = [[UIView alloc] initWithFrame:CGRectZero];
        [self.contentView addSubview:_bubble];

        // Цитата: полоска слева, имя автора и одна строка исходного текста.
        // Нажатие ведёт к самому сообщению, поэтому у блока свой распознаватель.
        _replyBlock = [[UIView alloc] initWithFrame:CGRectZero];
        _replyBlock.backgroundColor = [UIColor clearColor];
        _replyBlock.userInteractionEnabled = YES;
        _replyBlock.hidden = YES;
        [_bubble addSubview:_replyBlock];

        UITapGestureRecognizer *replyTap =
            [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(replyTapped)];
        [_replyBlock addGestureRecognizer:replyTap];

        _replyBar = [[UIView alloc] initWithFrame:CGRectZero];
        _replyBar.backgroundColor = [MAXTheme accentColor];
        [_replyBlock addSubview:_replyBar];

        _replyAuthor = [[UILabel alloc] initWithFrame:CGRectZero];
        _replyAuthor.font = [UIFont boldSystemFontOfSize:12.0];
        _replyAuthor.textColor = [MAXTheme accentColor];
        _replyAuthor.backgroundColor = [UIColor clearColor];
        [_replyBlock addSubview:_replyAuthor];

        _replyText = [[UILabel alloc] initWithFrame:CGRectZero];
        _replyText.font = [UIFont systemFontOfSize:12.0];
        _replyText.textColor = [MAXTheme secondaryTextColor];
        _replyText.backgroundColor = [UIColor clearColor];
        [_replyBlock addSubview:_replyText];

        _senderLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _senderLabel.font = [UIFont boldSystemFontOfSize:12.0];
        _senderLabel.textColor = [MAXTheme accentColor];
        _senderLabel.backgroundColor = [UIColor clearColor];
        _senderLabel.userInteractionEnabled = YES;
        [_bubble addSubview:_senderLabel];

        UITapGestureRecognizer *senderTap =
            [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(senderTapped)];
        [_senderLabel addGestureRecognizer:senderTap];

        // Строка ведёт к источнику, поэтому она цветом ссылки и со своим
        // распознавателем: нажатие по ней не должно открывать вложение.
        _forwardLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _forwardLabel.font = [UIFont italicSystemFontOfSize:12.0];
        _forwardLabel.textColor = [MAXTheme accentColor];
        _forwardLabel.backgroundColor = [UIColor clearColor];
        _forwardLabel.userInteractionEnabled = YES;
        _forwardLabel.hidden = YES;
        [_bubble addSubview:_forwardLabel];

        UITapGestureRecognizer *forwardTap =
            [[UITapGestureRecognizer alloc] initWithTarget:self
                                                    action:@selector(forwardedSourceTapped)];
        [_forwardLabel addGestureRecognizer:forwardTap];

        _photoTiles = [NSMutableArray array];

        _fileRow = [[UIView alloc] initWithFrame:CGRectZero];
        _fileRow.hidden = YES;
        [_bubble addSubview:_fileRow];

        _fileIcon = [[UIImageView alloc] initWithFrame:
                     CGRectMake(0, (MAXFileRowHeight - MAXFileIconSize) / 2.0,
                                MAXFileIconSize, MAXFileIconSize)];
        _fileIcon.image = [MAXTheme iconNamed:@"file"
                                          size:MAXFileIconSize
                                         color:[MAXTheme accentColor]];
        [_fileRow addSubview:_fileIcon];

        _fileName = [[UILabel alloc] initWithFrame:CGRectZero];
        _fileName.font = [UIFont systemFontOfSize:14.0];
        _fileName.textColor = [MAXTheme textColor];
        _fileName.backgroundColor = [UIColor clearColor];
        [_fileRow addSubview:_fileName];

        _fileSize = [[UILabel alloc] initWithFrame:CGRectZero];
        _fileSize.font = [UIFont systemFontOfSize:11.0];
        _fileSize.textColor = [MAXTheme secondaryTextColor];
        _fileSize.backgroundColor = [UIColor clearColor];
        [_fileRow addSubview:_fileSize];

        // Голосовое: круглая кнопка, график громкости и длительность. Своя
        // строка, а не общая с файлами: у записи нет ни имени, ни размера,
        // зато есть то, чего нет у файла, — рисунок речи.
        _voiceRow = [[UIView alloc] initWithFrame:CGRectZero];
        _voiceRow.hidden = YES;
        [_bubble addSubview:_voiceRow];

        _voiceButton = [[UIView alloc] initWithFrame:
                        CGRectMake(0, (MAXVoiceRowHeight - MAXVoiceButtonSize) / 2.0,
                                   MAXVoiceButtonSize, MAXVoiceButtonSize)];
        _voiceButton.backgroundColor = [MAXTheme accentColor];
        _voiceButton.layer.cornerRadius = MAXVoiceButtonSize / 2.0;
        _voiceButton.clipsToBounds = YES;
        _voiceIcon = [[UIImageView alloc] initWithFrame:_voiceButton.bounds];
        _voiceIcon.contentMode = UIViewContentModeCenter;
        [_voiceButton addSubview:_voiceIcon];
        [_voiceRow addSubview:_voiceButton];

        _voiceWave = [[MAXWaveView alloc] initWithFrame:CGRectZero];
        [_voiceRow addSubview:_voiceWave];

        // Кнопка «Т»: своей кнопкой не сделана нарочно — нажатия во всём
        // пузыре ловит один распознаватель, и он же различает, куда попали
        // (см. attachmentTapped:). Так проще, чем спорить двум обработчикам.
        _transcribeIcon = [[UIImageView alloc] initWithFrame:CGRectZero];
        _transcribeIcon.contentMode = UIViewContentModeCenter;
        _transcribeIcon.hidden = YES;
        [_voiceRow addSubview:_transcribeIcon];

        _voiceTime = [[UILabel alloc] initWithFrame:CGRectZero];
        _voiceTime.font = [UIFont systemFontOfSize:11.0];
        _voiceTime.textColor = [MAXTheme secondaryTextColor];
        _voiceTime.backgroundColor = [UIColor clearColor];
        [_voiceRow addSubview:_voiceTime];

        // Расшифровка живёт не в строке голосового, а прямо в пузыре: она
        // бывает в несколько строк, и строка голосового ради неё тянуться
        // не должна.
        _transcriptLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _transcriptLabel.font = [UIFont systemFontOfSize:MAXTranscriptFontSize];
        _transcriptLabel.backgroundColor = [UIColor clearColor];
        _transcriptLabel.numberOfLines = 0;
        _transcriptLabel.hidden = YES;
        [_bubble addSubview:_transcriptLabel];

        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(voiceChanged:)
                                                     name:MAXVoicePlayerDidChangeNotification
                                                   object:nil];

        _textLabel_ = [[UILabel alloc] initWithFrame:CGRectZero];
        _textLabel_.font = [MAXMessageCell messageFont];
        _textLabel_.numberOfLines = 0;
        _textLabel_.backgroundColor = [UIColor clearColor];
        _textLabel_.userInteractionEnabled = YES;
        [_bubble addSubview:_textLabel_];

        UITapGestureRecognizer *textTap =
            [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(textTapped)];
        [_textLabel_ addGestureRecognizer:textTap];

        _timeLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _timeLabel.font = [UIFont systemFontOfSize:10.0];
        _timeLabel.textColor = [MAXTheme secondaryTextColor];
        _timeLabel.backgroundColor = [UIColor clearColor];
        _timeLabel.textAlignment = NSTextAlignmentRight;
        [_bubble addSubview:_timeLabel];

        _reactionsLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _reactionsLabel.font = [UIFont systemFontOfSize:13.0];
        _reactionsLabel.textColor = [MAXTheme textColor];
        _reactionsLabel.backgroundColor = [UIColor clearColor];
        _reactionsLabel.hidden = YES;
        [_bubble addSubview:_reactionsLabel];

        UITapGestureRecognizer *tap =
            [[UITapGestureRecognizer alloc] initWithTarget:self
                                                    action:@selector(attachmentTapped:)];
        tap.delegate = self;
        [_bubble addGestureRecognizer:tap];

        // Долгое нажатие — меню действий. Висит на всём пузыре, включая
        // картинки: там оно тоже уместно, а короткое нажатие остаётся за ними.
        UILongPressGestureRecognizer *longPress =
            [[UILongPressGestureRecognizer alloc] initWithTarget:self
                                                          action:@selector(bubbleLongPressed:)];
        [_bubble addGestureRecognizer:longPress];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];

    // Часы движущегося стикера держат плитку за собой, а плитка — разобранную
    // сцену. Не остановив их здесь, мы оставили бы рисовать невидимое навсегда:
    // ячейки не стало, а часы идут.
    [self stopAnimations];
}

/// Распознаватель пузыря отвечает теперь только за строку файла: у картинок
/// свои плитки со своими нажатиями, иначе по одному касанию нельзя было бы
/// понять, какую из четырёх открывать.
- (void)attachmentTapped:(UITapGestureRecognizer *)tap {
    MAXAttachment *voice = _message.voiceAttachment;
    if (voice != nil) {
        // Попали в «Т» — это не «играть», а «расшифровать».
        if (!_transcribeIcon.hidden) {
            CGPoint where = [tap locationInView:_voiceRow];
            if (CGRectContainsPoint(_transcribeIcon.frame, where)) {
                [self.delegate messageCellDidTapTranscribe:self];
                return;
            }
        }

        [self.delegate messageCell:self didTapAttachment:voice];
        return;
    }

    MAXAttachment *file = _message.fileAttachment;
    if (file == nil) return;
    [self.delegate messageCell:self didTapAttachment:file];
}

- (void)photoTileTapped:(UITapGestureRecognizer *)recognizer {
    MAXPhotoTile *tile = (MAXPhotoTile *)recognizer.view;
    if (tile.attachment == nil) return;
    [self.delegate messageCell:self didTapAttachment:tile.attachment];
}

- (void)forwardedSourceTapped {
    if (_message.forwardedPayload == nil) return;
    [self.delegate messageCellDidTapForwardedSource:self];
}

- (void)replyTapped {
    if (_message.replyPayload == nil) return;
    [self.delegate messageCellDidTapReply:self];
}

- (void)senderTapped {
    if (_message.senderId == 0) return;
    [self.delegate messageCellDidTapSender:self];
}

/// Кнопка и полоска на строке голосового.
///
/// Кнопка эта не UIButton: нажатие ловится общим распознавателем пузыря, а
/// значок в ней меняется по состоянию проигрывателя — «играть», «стоп» или
/// многоточие, пока запись качается и раскодируется.
- (void)refreshVoiceState {
    if (_voiceRow.hidden) return;

    MAXVoicePlayer *player = [MAXVoicePlayer shared];
    BOOL mine = (_message.messageId.length > 0
                 && [player.messageId isEqualToString:_message.messageId]);

    if (!mine) {
        [self showVoiceIcon:@"play"];
        _voiceWave.progress = 0;
        return;
    }

    if (player.preparing) {
        [self showVoiceIcon:@"waiting"];
        _voiceWave.progress = 0;
        return;
    }

    [self showVoiceIcon:@"stop"];
    _voiceWave.progress = player.progress;
}

/// Значок на круглой кнопке голосового: «играть», «стоп» или три точки,
/// пока запись качается. Треугольник сдвинут на точку вправо — по той же
/// причине, что и на кадре ролика.
- (void)showVoiceIcon:(NSString *)name {
    _voiceIcon.image = [MAXIcons imageNamed:name size:12.0
                                      color:[UIColor whiteColor]];

    CGFloat shift = [name isEqualToString:@"play"] ? 1.0 : 0.0;
    _voiceIcon.frame = CGRectOffset(_voiceButton.bounds, shift, 0);
}

- (void)voiceChanged:(NSNotification *)note {
    [self refreshVoiceState];
}

/// Остановить движение во всех плитках строки. Зовётся, когда строка ушла
/// с экрана: невидимое рисовать незачем.
- (void)stopAnimations {
    for (MAXPhotoTile *tile in _photoTiles) [tile stopLottie];
}

- (CGRect)videoNoteFrame {
    for (MAXPhotoTile *tile in _photoTiles) {
        if (tile.hidden || !tile.attachment.isVideoNote) continue;
        return [self convertRect:tile.frame fromView:tile.superview];
    }
    return CGRectZero;
}

- (void)textTapped {
    if (_message.markupRanges.count == 0) return;
    [self.delegate messageCellDidTapLinks:self];
}

- (void)bubbleLongPressed:(UILongPressGestureRecognizer *)recognizer {
    // Только начало жеста: иначе меню открылось бы ещё раз на отпускании.
    if (recognizer.state != UIGestureRecognizerStateBegan) return;
    if (_message.isControl) return;
    [self.delegate messageCellDidLongPress:self];
}

/// Распознаватель висит на всём пузыре и получает касания по всему, что внутри,
/// — включая строку «Переслано» и плитки картинок, у которых свои нажатия.
/// Иначе одно касание срабатывало бы дважды.
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)recognizer
       shouldReceiveTouch:(UITouch *)touch {
    if (!_forwardLabel.hidden &&
        [_forwardLabel pointInside:[touch locationInView:_forwardLabel] withEvent:nil]) {
        return NO;
    }

    if (!_replyBlock.hidden &&
        [_replyBlock pointInside:[touch locationInView:_replyBlock] withEvent:nil]) {
        return NO;
    }

    if (!_senderLabel.hidden &&
        [_senderLabel pointInside:[touch locationInView:_senderLabel] withEvent:nil]) {
        return NO;
    }

    for (MAXPhotoTile *tile in _photoTiles) {
        if (tile.hidden) continue;
        if ([tile pointInside:[touch locationInView:tile] withEvent:nil]) return NO;
    }
    return YES;
}

/// Плитки создаются по мере надобности и живут вместе с ячейкой: сообщений
/// с четырьмя снимками мало, а переиспользуется ячейка постоянно.
- (MAXPhotoTile *)tileAtIndex:(NSUInteger)index {
    while (_photoTiles.count <= index) {
        MAXPhotoTile *tile = [[MAXPhotoTile alloc] initWithFrame:CGRectZero];
        tile.hidden = YES;

        UITapGestureRecognizer *tap =
            [[UITapGestureRecognizer alloc] initWithTarget:self
                                                    action:@selector(photoTileTapped:)];
        [tile addGestureRecognizer:tap];

        [_bubble addSubview:tile];
        [_photoTiles addObject:tile];
    }
    return _photoTiles[index];
}

- (void)configureWithMessage:(MAXMessage *)message
                    outgoing:(BOOL)outgoing
                  senderName:(NSString *)senderName
             senderAvatarURL:(NSString *)senderAvatarURL
                  showSender:(BOOL)showSender
                     inGroup:(BOOL)inGroup
                    dateText:(NSString *)dateText
                       width:(CGFloat)width {
    _message = message;

    _dateLabel.text = dateText;
    _dateLabel.hidden = (dateText.length == 0);
    _dateLabel.textColor = [MAXTheme secondaryTextColor];

    if (width <= 0) width = [UIScreen mainScreen].bounds.size.width;

    NSArray *photos = message.photoAttachments;
    MAXAttachment *photo = [photos lastObject];
    MAXAttachment *file = message.fileAttachment;
    MAXAttachment *voice = message.voiceAttachment;

    NSString *text = message.text;

    // Пузырь без текста и без разобранного вложения — то самое «пустое
    // облачко»: показывать нечего, потому что в сообщении ничего не нашлось.
    // Так вскрылась пересылка (всё содержимое в link.message); строка
    // оставлена на случай, если найдётся ещё одна форма сообщения, о которой
    // порт не знает, — она сразу назовёт себя по именам полей.
    if (photo == nil && file == nil && voice == nil && text.length == 0 &&
        MAXShouldLogMessageOnce(message.messageId)) {
        NSLog(@"[Max/Вложение] пустой пузырь id=%@ поля=%@ | своё: %@ | внутри link: %@",
              message.messageId,
              [message.payload.allKeys componentsJoinedByString:@","],
              MAXAttachesSummary(message.payload[@"attaches"]),
              message.forwardedPayload != nil
                  ? MAXAttachesSummary(message.forwardedPayload[@"attaches"])
                  : @"—");
    }

    BOOL showText = text.length > 0 || (photo == nil && file == nil && voice == nil);
    NSString *shown = text.length > 0 ? text : message.displayText;
    if (shown.length == 0) shown = @" ";

    CGSize textSize = showText
        ? [MAXMessageCell textSizeForMessage:message shown:shown width:width]
        : CGSizeZero;
    CGFloat mediaWidth = [MAXMessageCell mediaWidthForMessage:message width:width];

    CGFloat contentWidth = textSize.width;
    if (photo != nil || file != nil || voice != nil) contentWidth = MAX(contentWidth, mediaWidth);

    CGFloat bubbleWidth = MAX(contentWidth + MAXBubblePaddingX * 2, 70.0);

    CGFloat bubbleHeight = MAXBubblePaddingY * 2 + MAXTimeLabelHeight;
    if (showSender) bubbleHeight += MAXSenderLabelHeight;
    if (message.forwardedPayload != nil) bubbleHeight += MAXForwardLabelHeight;
    if (message.replyPayload != nil) bubbleHeight += MAXReplyHeight + MAXMediaGap;

    NSString *reactions = message.reactionsSummary;
    if (reactions.length > 0) bubbleHeight += MAXReactionsHeight;
    CGFloat photosHeight = MAXPhotoLayoutHeight(photos, mediaWidth);
    if (photo != nil) bubbleHeight += photosHeight + MAXMediaGap;
    if (file != nil) bubbleHeight += MAXFileRowHeight + MAXMediaGap;
    if (voice != nil) {
        bubbleHeight += MAXVoiceRowHeight + MAXMediaGap;

        // Пузырь считается здесь, а высота строки — в heightForMessage:.
        // Расшифровку надо прибавить в обоих местах, иначе текст либо
        // вылезет за пузырь, либо обрежется вместе с ним.
        bubbleHeight += [MAXMessageCell transcriptHeightForText:
                            [MAXMessageCell transcriptTextForMessage:message]
                                                     mediaWidth:mediaWidth];
    }
    if (showText) bubbleHeight += textSize.height;

    // В группе входящие сдвигаются вправо, освобождая колонку под аватарку.
    // Сдвигаются все, а не только подписанные именем: иначе пузыри одной серии
    // стояли бы уступом. Ширина пузыря при этом не меняется — колонка берётся
    // из поля, которое и так пустовало.
    CGFloat avatarColumn = (inGroup && !outgoing) ? MAXAvatarSize + MAXAvatarGap : 0;

    CGFloat x = outgoing
        ? (width - bubbleWidth - MAXBubbleMargin)
        : MAXBubbleMargin + avatarColumn;

    // Дата занимает верх ячейки, и всё остальное съезжает под неё. Полоска
    // принадлежит первому сообщению дня, а не отдельной строке таблицы.
    CGFloat top = MAXBubbleMargin;
    if (!_dateLabel.hidden) {
        _dateLabel.frame = CGRectMake(0, MAXBubbleMargin, width, MAXDateHeight - 8.0);
        top += MAXDateHeight;
    }

    _bubble.frame = CGRectMake(x, top, bubbleWidth, bubbleHeight);

    // Заливка, а в скевоморфной теме ещё градиент, рамка и тень. Строго после
    // frame: градиентный слой за видом сам не тянется.
    //
    // У стикера пузыря нет вовсе: у него свои поля и прозрачные углы, и
    // облачко вокруг выглядит наклейкой на наклейке.
    if (MAXIsBareSticker(message) || MAXIsBareNote(message)) {
        [MAXTheme clearBubbleStyleOf:_bubble];
    } else {
        [MAXTheme applyBubbleStyleTo:_bubble outgoing:outgoing];
    }

    if (avatarColumn > 0 && showSender) {
        _avatarView.hidden = NO;
        _avatarView.frame = CGRectMake(MAXBubbleMargin, top,
                                       MAXAvatarSize, MAXAvatarSize);
        [_avatarView setTitle:senderName
                    avatarURL:senderAvatarURL
                   identifier:message.senderId];
    } else {
        _avatarView.hidden = YES;
    }

    CGFloat cursorY = MAXBubblePaddingY;

    if (showSender) {
        _senderLabel.hidden = NO;
        _senderLabel.text = senderName;
        _senderLabel.frame = CGRectMake(MAXBubblePaddingX, cursorY,
                                        bubbleWidth - MAXBubblePaddingX * 2,
                                        MAXSenderLabelHeight);
        cursorY += MAXSenderLabelHeight;
    } else {
        _senderLabel.hidden = YES;
    }

    if (message.forwardedPayload != nil) {
        NSString *source = MAXForwardedSourceName(message);

        if (source == nil) {
            // Автор не из наших диалогов — карточки в кэше нет. Просим её
            // отдельно: список чатов такого человека не обходит, а имя
            // появится при следующей перерисовке.
            [[MAXChatsModule shared] ensureContactWithId:message.forwardedSenderId];

            if (MAXShouldLogMessageOnce(message.messageId)) {
                NSLog(@"[Max/Пересылка] id=%@ автор=%lld чат=%lld канал=%d | link: %@",
                      message.messageId, message.forwardedSenderId,
                      message.forwardedChatId, message.forwardedIsChannel ? 1 : 0,
                      MAXFieldsSummary(message.payload[@"link"]));
            }

            if (message.forwardedSenderId != 0) {
                source = [NSString stringWithFormat:@"ID %lld", message.forwardedSenderId];
            }
        }

        _forwardLabel.hidden = NO;
        _forwardLabel.text = source.length > 0
            ? [NSString stringWithFormat:@"Переслано от %@", source]
            : @"Переслано";
        _forwardLabel.frame = CGRectMake(MAXBubblePaddingX, cursorY,
                                         bubbleWidth - MAXBubblePaddingX * 2,
                                         MAXForwardLabelHeight);
        cursorY += MAXForwardLabelHeight;
    } else {
        _forwardLabel.hidden = YES;
    }

    if (message.replyPayload != nil) {
        _replyBlock.hidden = NO;
        _replyBlock.frame = CGRectMake(MAXBubblePaddingX, cursorY,
                                       bubbleWidth - MAXBubblePaddingX * 2, MAXReplyHeight);

        CGFloat textLeft = 8.0;
        CGFloat textWidth = _replyBlock.bounds.size.width - textLeft;

        _replyBar.frame = CGRectMake(0, 0, 2.0, MAXReplyHeight);
        _replyAuthor.frame = CGRectMake(textLeft, 0, textWidth, 15.0);
        _replyText.frame = CGRectMake(textLeft, 16.0, textWidth, 15.0);

        MAXContact *author = [[MAXChatsModule shared] contactWithId:message.replySenderId];
        if (author == nil) [[MAXChatsModule shared] ensureContactWithId:message.replySenderId];

        _replyAuthor.text = author.name.length > 0
            ? author.name
            : [NSString stringWithFormat:@"ID %lld", message.replySenderId];
        _replyText.text = message.replyPreview;

        cursorY += MAXReplyHeight + MAXMediaGap;
    } else {
        _replyBlock.hidden = YES;
    }

    NSUInteger photoCount = photos.count;
    CGFloat singleHeight = photoCount == 1 ? photosHeight : 0;

    for (NSUInteger i = 0; i < photoCount; i++) {
        MAXPhotoTile *tile = [self tileAtIndex:i];
        CGRect frame = MAXPhotoTileFrame(i, photoCount, mediaWidth, singleHeight);
        frame.origin.x += MAXBubblePaddingX;
        frame.origin.y += cursorY;

        tile.hidden = NO;
        tile.frame = frame;
        [self loadPhoto:photos[i] intoTile:tile];
    }

    // Лишние плитки остаются от прошлого сообщения — ячейку переиспользуют.
    for (NSUInteger i = photoCount; i < _photoTiles.count; i++) {
        MAXPhotoTile *tile = _photoTiles[i];
        tile.hidden = YES;
        tile.attachment = nil;
        [tile prepareForImage];
    }

    if (photoCount > 0) cursorY += photosHeight + MAXMediaGap;

    if (file != nil) {
        _fileRow.hidden = NO;
        _fileRow.frame = CGRectMake(MAXBubblePaddingX, cursorY, mediaWidth, MAXFileRowHeight);

        CGFloat textLeft = MAXFileIconSize + 8.0;
        _fileName.text = file.name.length > 0 ? file.name : @"Файл";
        _fileName.frame = CGRectMake(textLeft, 6.0, mediaWidth - textLeft, 18.0);

        // «Открыть», а не «скачать»: скачивание теперь только первый шаг,
        // дальше документ показывается просмотрщиком системы.
        NSString *sizeText = [file humanReadableSize];
        _fileSize.text = sizeText.length > 0
            ? [NSString stringWithFormat:@"%@ · нажмите, чтобы открыть", sizeText]
            : @"Нажмите, чтобы открыть";
        _fileSize.frame = CGRectMake(textLeft, 24.0, mediaWidth - textLeft, 14.0);

        cursorY += MAXFileRowHeight + MAXMediaGap;
    } else {
        _fileRow.hidden = YES;
    }

    if (voice != nil) {
        _voiceRow.hidden = NO;
        _voiceRow.frame = CGRectMake(MAXBubblePaddingX, cursorY, mediaWidth, MAXVoiceRowHeight);

        CGFloat left = MAXVoiceButtonSize + 8.0;
        CGFloat timeWidth = 34.0;

        // «Т» показывается не у всех записей: расшифровать сервер может
        // только ту, у которой есть свой номер.
        BOOL canTranscribe = (voice.fileId != 0 && _message.messageId.length > 0);
        CGFloat transcribeWidth = canTranscribe ? MAXTranscribeWidth : 0;

        _voiceWave.frame = CGRectMake(left, 6.0,
                                      mediaWidth - left - timeWidth - transcribeWidth - 4.0,
                                      MAXVoiceRowHeight - 12.0);
        _voiceWave.playedColor = [MAXTheme accentColor];
        _voiceWave.restColor = [MAXTheme secondaryTextColor];
        _voiceWave.bars = [voice waveBarsCount:
                           (NSUInteger)(_voiceWave.bounds.size.width / 3.0)];

        _voiceTime.frame = CGRectMake(mediaWidth - timeWidth, 12.0,
                                      timeWidth, 16.0);
        _voiceTime.text = voice.duration > 0
            ? [voice humanReadableDuration]
            : @"";

        NSString *transcript = [MAXMessageCell transcriptTextForMessage:message];

        _transcribeIcon.hidden = !canTranscribe;
        if (canTranscribe) {
            // Во всю высоту строки — не ради вида (буква рисуется по
            // середине), а ради пальца: в 13 точек буквы не попасть.
            _transcribeIcon.frame = CGRectMake(mediaWidth - timeWidth - transcribeWidth, 0,
                                               transcribeWidth, MAXVoiceRowHeight);

            // Раскрытая расшифровка отмечается цветом: иначе непонятно, что
            // тем же нажатием её можно и убрать.
            UIColor *tint = transcript.length > 0
                ? [MAXTheme accentColor]
                : [MAXTheme secondaryTextColor];
            _transcribeIcon.image = [MAXIcons imageNamed:@"text" size:13.0 color:tint];
        }

        [self refreshVoiceState];
        cursorY += MAXVoiceRowHeight + MAXMediaGap;

        if (transcript.length > 0) {
            CGFloat whole = [MAXMessageCell transcriptHeightForText:transcript
                                                         mediaWidth:mediaWidth];

            _transcriptLabel.hidden = NO;
            _transcriptLabel.text = transcript;
            _transcriptLabel.textColor = [MAXTheme secondaryTextColor];
            _transcriptLabel.frame = CGRectMake(MAXBubblePaddingX, cursorY,
                                                mediaWidth, whole - MAXMediaGap);
            cursorY += whole;
        } else {
            _transcriptLabel.hidden = YES;
        }
    } else {
        _voiceRow.hidden = YES;
        _transcriptLabel.hidden = YES;
    }

    if (showText) {
        UIColor *textColor = message.isControl
            ? [MAXTheme secondaryTextColor]
            : [MAXTheme textColor];

        _textLabel_.hidden = NO;
        _textLabel_.textColor = textColor;

        // Разметку сервер шлёт отдельным списком отрезков, а не тегами внутри
        // текста, — собрать её можно только строкой с признаками.
        NSAttributedString *marked = [MAXMessageCell markedTextFor:message
                                                             shown:shown
                                                             color:textColor];
        if (marked != nil) {
            _textLabel_.attributedText = marked;
        } else {
            _textLabel_.text = shown;
        }

        _textLabel_.frame = CGRectMake(MAXBubblePaddingX, cursorY, textSize.width, textSize.height);
        cursorY += textSize.height;
    } else {
        _textLabel_.hidden = YES;
    }

    if (reactions.length > 0) {
        _reactionsLabel.hidden = NO;
        _reactionsLabel.text = reactions;
        _reactionsLabel.frame = CGRectMake(MAXBubblePaddingX, cursorY,
                                           bubbleWidth - MAXBubblePaddingX * 2,
                                           MAXReactionsHeight);
        cursorY += MAXReactionsHeight;
    } else {
        _reactionsLabel.hidden = YES;
    }

    NSString *time = [MAXTheme shortTimeFromMilliseconds:message.time];
    _timeLabel.text = message.isPending ? [NSString stringWithFormat:@"%@ ·", time] : time;
    _timeLabel.frame = CGRectMake(MAXBubblePaddingX, cursorY,
                                  bubbleWidth - MAXBubblePaddingX * 2, MAXTimeLabelHeight);
}

/// Картинка грузится, только если сервер дал прямую ссылку. Когда её нет,
/// нужен отдельный запрос FILE_DOWNLOAD — он делается по нажатию, чтобы
/// прокрутка списка не порождала по запросу на каждое фото.
- (void)loadPhoto:(MAXAttachment *)photo intoTile:(MAXPhotoTile *)tile {
    tile.attachment = photo;
    [tile prepareForImage];

    // У ролика кадр лежит не там, где у фотографии: `previewUrl` у него не
    // бывает, зато есть `thumbnail`. Перепутать нельзя — по `previewUrl`
    // у видео либо пусто, либо сам ролик.
    NSString *url = (photo.type == MAXAttachmentTypeVideo)
        ? photo.thumbnailUrl
        : photo.previewUrl;

    // Вложенный в сообщение кадр показывается сразу, не дожидаясь сети:
    // размытый, зато мгновенно. Приехавший по адресу заменит его собой.
    if (photo.previewBytes.length > 0) {
        UIImage *quick = [UIImage imageWithData:photo.previewBytes];
        if (quick != nil) tile.image = quick;
    }

    if (url.length == 0) {
        // Единственная ветка, которая раньше молчала в журнал: адреса нет,
        // и запроса не будет вовсе. Раз так — печатаем сам attach.
        if (MAXShouldLogMessageOnce(_message.messageId)) {
            NSLog(@"[Max/Фото] без адреса id=%@ | %@",
                  _message.messageId, MAXAttachesSummary(_message.payload[@"attaches"]));
        }
        if (tile.image == nil) [tile showHint];
        [tile startLottieIfNeeded];
        return;
    }

    UIImage *cached = [[MAXImageLoader shared] cachedImageForURL:url size:0];
    if (cached != nil) {
        tile.image = cached;
        [tile startLottieIfNeeded];
        return;
    }

    [tile showSpinner];

    NSString *requested = [url copy];
    [[MAXImageLoader shared] loadOriginalImageForURL:url completion:^(UIImage *image) {
        // Плитку могли переиспользовать, пока картинка ехала: сверяем не саму
        // ячейку, а вложение, которое в плитке лежит сейчас.
        if (tile.attachment != photo) return;

        if (image != nil) {
            [tile prepareForImage];
            tile.image = image;
            [tile startLottieIfNeeded];
            return;
        }

        // Прямая ссылка не сработала: у только что отправленного фото сервер
        // часто даёт лишь baseUrl с токеном, а настоящий адрес выдаёт по
        // FILE_DOWNLOAD. Тянуть его за каждую ячейку на прокрутке — лишние
        // запросы, поэтому здесь просто приглашение нажать: по нажатию
        // MAXChatViewController адрес и запросит.
        //
        // Вложенный кадр, если он был показан, при этом остаётся: он хуже
        // приехавшего, но лучше пустоты.
        NSLog(@"[Max/Фото] %@ не загрузилось напрямую", requested);
        if (tile.image == nil) [tile showHint];
    }];
}

@end
