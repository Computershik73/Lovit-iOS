//
//  MAXChatViewController.m
//

#import "MAXChatViewController.h"
#import "MAXMessageCell.h"
#import "MAXTheme.h"
#import "MAXWallpaper.h"
#import "MAXTextField.h"
#import "MAXApi.h"
#import "MAXChatsModule.h"
#import "MAXMessagesModule.h"
#import "MAXSettings.h"
#import "MAXChat.h"
#import "MAXContact.h"
#import "MAXMessage.h"
#import "MAXAttachment.h"
#import "MAXIcons.h"
#import "MAXUploader.h"
#import "MAXFilePickerViewController.h"
#import "MAXPhotoViewController.h"
#import "MAXContactViewController.h"
#import "MAXChatInfoViewController.h"
#import "MAXHttp.h"
#import "MAXVideoViewController.h"
#import "MAXMp4Facts.h"
#import "MAXStreamServer.h"
#import "MAXQuickLook.h"
#import "MAXRichText.h"
#import "MAXSticker.h"
#import "MAXStickerSetViewController.h"
#import "MAXVoicePlayer.h"
#import "MAXTranscripts.h"
#import "MAXVideoNotePlayer.h"
#import "MAXVideoNoteView.h"
#import "MAXVoiceRecorder.h"
#import "MAXVideoNoteRecorder.h"
#import "MAXWaveView.h"

static const CGFloat MAXComposerHeight = 46.0;
static const CGFloat MAXComposerBannerHeight = 28.0;
static const CGFloat MAXPinnedBarHeight = 32.0;

/// Сторона круглой кнопки «вниз» со счётчиком непрочитанного.
static const CGFloat MAXJumpButtonSize = 40.0;

/// Больше этого ролик не открываем: он читается в память целиком, а телефону
/// тех лет и сорока мегабайт хватает, чтобы быть снятым за расход памяти.
static const unsigned long long MAXVideoLargest = 40ULL * 1024 * 1024;

@implementation MAXChatViewController {
    MAXChat *_chat;
    NSMutableArray *_messages;
    UITableView *_tableView;
    UIView *_composer;
    MAXTextField *_inputField;
    UIButton *_sendButton;
    UIButton *_attachButton;
    UIActivityIndicatorView *_spinner;
    UIPopoverController *_photoPopover;   // только на планшете, см. pickPhoto
    CGFloat _keyboardHeight;
    BOOL _loading;
    BOOL _uploading;

    UILabel *_headerTitle;
    UILabel *_headerSubtitle;
    NSString *_presenceText;
    UIButton *_muteButton;

    BOOL _subscribing;             // идёт подписка на канал

    UIView *_pinnedBar;            // полоска закрепа под панелью навигации
    UILabel *_pinnedLabel;

    UIView *_composerBanner;
    UILabel *_composerBannerLabel;
    MAXMessage *_replyToMessage;
    MAXMessage *_editingMessage;
    MAXMessage *_actionMessage;
    NSArray *_actionTitles;
    NSArray *_reactionTitles;
    NSArray *_linkTitles;          // ссылки сообщения, из которых выбирают
    NSArray *_markupTitles;        // виды разметки, из которых выбирают
    NSMutableArray *_markup;       // наложенное руками на набранное
    NSRange _markupRange;          // что было выделено, когда открыли список

    NSTimer *_typingTimer;         // сколько ещё держать «печатает…»

    UIButton *_micButton;          // удержание — запись, касание — чем писать
    BOOL _noteMode;                // удержанием запишется кружок, а не голосовое
    UIView *_noteWindow;           // круглое окошко предпросмотра поверх переписки
    MAXVideoNoteView *_noteView;   // играющий кружок на своём месте в переписке
    BOOL _noteCornered;            // ушёл за край и отставлен в угол
    CAShapeLayer *_noteRing;       // кольцо: сколько осталось от минуты
    BOOL _recordStarted;           // удержание уже признано записью
    UIView *_recordBar;            // полоса поверх строки ввода во время записи
    UIView *_recordDot;
    UILabel *_recordTime;
    UILabel *_recordHint;
    MAXWaveView *_recordWave;
    UIButton *_recordCancel;
    UIButton *_recordSend;
    NSTimer *_recordTimer;
    NSMutableArray *_recordLevels;
    CGPoint _recordStart;          // где палец лёг на кнопку
    BOOL _recordCancelling;        // увели влево — отпустят на отмену
    BOOL _recordLocked;            // увели вверх — писать можно без пальца

    UIButton *_jumpButton;         // «вниз» со счётчиком непрочитанного
    NSUInteger _unseenCount;       // сколько пришло, пока читали выше
}

- (id)initWithChat:(MAXChat *)chat {
    self = [super init];
    if (self) {
        _chat = chat;
        _messages = [NSMutableArray array];

        // Панель вкладок на экране переписки не нужна, и дело не только
        // в виде: она полупрозрачная, вид контроллера продолжается под ней,
        // и строка ввода, прижатая к низу, оказывалась за панелью — то есть
        // невидимой и ненажимаемой.
        self.hidesBottomBarWhenPushed = YES;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    [self setupTitleView];
    self.view.backgroundColor = [MAXWallpaper backgroundColor];

    // Отсюда открываются профиль и сведения о чате; их заголовкам ни к чему
    // кнопка возврата с названием чата во всю ширину.
    self.navigationItem.backBarButtonItem = [MAXTheme backBarButtonItem];

    // Раскладка здесь во фреймах, поэтому вид не должен продолжаться под
    // полупрозрачными панелями: иначе его границы больше видимой области,
    // и всё, что прижато к низу, уезжает под панель.
    if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)]) {
        self.edgesForExtendedLayout = UIRectEdgeNone;
    }

    CGRect bounds = self.view.bounds;

    _tableView = [[UITableView alloc] initWithFrame:
                  CGRectMake(0, 0, bounds.size.width, bounds.size.height - MAXComposerHeight)
                                              style:UITableViewStylePlain];
    _tableView.dataSource = self;
    _tableView.delegate = self;
    _tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    [MAXTheme applyToTableView:_tableView];
    [self.view addSubview:_tableView];
    [self applyWallpaper];

    _composer = [[UIView alloc] initWithFrame:
                 CGRectMake(0, bounds.size.height - MAXComposerHeight,
                            bounds.size.width, MAXComposerHeight)];
    _composer.backgroundColor = [MAXTheme barBackgroundColor];
    [self.view addSubview:_composer];

    // Полоска «Ответ: …» / «Изменение: …» живёт над строкой ввода и появляется
    // только по делу, поэтому высоту переписки приходится пересчитывать.
    _composerBanner = [[UIView alloc] initWithFrame:
                       CGRectMake(0, 0, bounds.size.width, MAXComposerBannerHeight)];
    _composerBanner.backgroundColor = [MAXTheme fieldBackgroundColor];
    _composerBanner.hidden = YES;
    [self.view addSubview:_composerBanner];

    _composerBannerLabel = [[UILabel alloc] initWithFrame:
                            CGRectMake(12, 0, bounds.size.width - 52, MAXComposerBannerHeight)];
    _composerBannerLabel.font = [UIFont systemFontOfSize:13.0];
    _composerBannerLabel.textColor = [MAXTheme secondaryTextColor];
    _composerBannerLabel.backgroundColor = [UIColor clearColor];
    _composerBannerLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [_composerBanner addSubview:_composerBannerLabel];

    UIButton *bannerClose = [MAXTheme plainButtonWithTitle:@""];
    bannerClose.frame = CGRectMake(bounds.size.width - 44, 0, 40, MAXComposerBannerHeight);
    bannerClose.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    [bannerClose setTitle:@"×" forState:UIControlStateNormal];
    bannerClose.titleLabel.font = [UIFont systemFontOfSize:22.0];
    [bannerClose addTarget:self action:@selector(cancelComposerMode)
          forControlEvents:UIControlEventTouchUpInside];
    [_composerBanner addSubview:bannerClose];

    _attachButton = [UIButton buttonWithType:UIButtonTypeCustom];
    _attachButton.frame = CGRectMake(bounds.size.width - 102, 6, 34, MAXComposerHeight - 12);
    _attachButton.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    [_attachButton setImage:[MAXTheme iconNamed:@"attach"
                                            size:24
                                           color:[MAXTheme accentColor]]
                   forState:UIControlStateNormal];
    [_attachButton addTarget:self action:@selector(showAttachmentOptions)
            forControlEvents:UIControlEventTouchUpInside];
    [_composer addSubview:_attachButton];

    _inputField = [[MAXTextField alloc] initWithFrame:
                   CGRectMake(8, 6, bounds.size.width - 116, MAXComposerHeight - 12)];
    _inputField.placeholder = @"Сообщение";
    _inputField.delegate = self;
    _inputField.returnKeyType = UIReturnKeySend;
    _inputField.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [MAXTheme styleTextField:_inputField];
    _inputField.backgroundColor = [MAXTheme fieldBackgroundColor];
    [_composer addSubview:_inputField];

    // «Отправить», а не стрелка: подпись понятнее значка, и она же — то,
    // что стояло на этом месте и в iOS 6, и в iOS 7.
    _sendButton = [MAXTheme composerSendButton];
    _sendButton.frame = CGRectMake(bounds.size.width - 62, 6, 54, MAXComposerHeight - 12);
    _sendButton.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    [_sendButton addTarget:self action:@selector(sendMessage)
          forControlEvents:UIControlEventTouchUpInside];
    [_composer addSubview:_sendButton];

    // Кнопка записи стоит там же, где отправка, и подменяет её: пока не
    // набрано ни слова, отправлять нечего, а как набрано — запись уже не
    // нужна. Так это устроено и в клиенте под Windows Phone.
    //
    // Касание и удержание на ней делают разное: удержание записывает,
    // касание переключает, что именно запишется, — голосовое или кружок.
    // Отдельной кнопки под этот выбор в строке ввода нет места.
    _micButton = [UIButton buttonWithType:UIButtonTypeCustom];
    _micButton.frame = _sendButton.frame;
    _micButton.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    _micButton.backgroundColor = [MAXTheme accentColor];
    _micButton.layer.cornerRadius = 6.0;
    [_micButton addTarget:self
                   action:@selector(micTapped)
         forControlEvents:UIControlEventTouchUpInside];
    [_composer addSubview:_micButton];

    UILongPressGestureRecognizer *hold =
        [[UILongPressGestureRecognizer alloc] initWithTarget:self
                                                      action:@selector(micHeld:)];
    // Столько же, сколько на Windows Phone: короче — и запись начиналась бы
    // от случайного касания, длиннее — и удержание ощущается тугим.
    hold.minimumPressDuration = 0.25;
    // Палец во время записи ездит: без этого распознаватель считает движение
    // отменой жеста и запись обрывается на полуслове.
    hold.allowableMovement = 10000.0;
    [_micButton addGestureRecognizer:hold];

    [self refreshRecordGlyph];

    // В канале, который мы не ведём, писать нельзя — вместо строки ввода
    // кнопка уведомлений, как в composer_input.dart у Komet.
    _muteButton = [MAXTheme plainButtonWithTitle:@""];
    _muteButton.frame = CGRectMake(0, 0, bounds.size.width, MAXComposerHeight);

    // Стрелка «вниз» — над правым нижним углом переписки, чуть выше строки
    // ввода: под самой строкой её закрывала бы клавиатура.
    _jumpButton.frame = CGRectMake(bounds.size.width - MAXJumpButtonSize - 12.0,
                                   CGRectGetMaxY(_tableView.frame) - MAXJumpButtonSize - 12.0,
                                   MAXJumpButtonSize, MAXJumpButtonSize);
    _muteButton.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    _muteButton.titleLabel.font = [UIFont systemFontOfSize:16.0];
    _muteButton.hidden = YES;
    [_muteButton addTarget:self action:@selector(toggleMute)
          forControlEvents:UIControlEventTouchUpInside];
    [_composer addSubview:_muteButton];

    // Закреп — полоска поверх переписки, а не строка в ней: сообщение может
    // быть далеко в истории, и держать его на виду умеет только она.
    _pinnedBar = [[UIView alloc] initWithFrame:
                  CGRectMake(0, 0, bounds.size.width, MAXPinnedBarHeight)];
    _pinnedBar.backgroundColor = [MAXTheme barBackgroundColor];
    _pinnedBar.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    _pinnedBar.hidden = YES;
    [self.view addSubview:_pinnedBar];

    UIView *pinnedStripe = [[UIView alloc] initWithFrame:CGRectMake(10, 6, 2.0,
                                                                    MAXPinnedBarHeight - 12)];
    pinnedStripe.backgroundColor = [MAXTheme accentColor];
    [_pinnedBar addSubview:pinnedStripe];

    _pinnedLabel = [[UILabel alloc] initWithFrame:
                    CGRectMake(20, 0, bounds.size.width - 30, MAXPinnedBarHeight)];
    _pinnedLabel.font = [UIFont systemFontOfSize:13.0];
    _pinnedLabel.textColor = [MAXTheme textColor];
    _pinnedLabel.backgroundColor = [UIColor clearColor];
    _pinnedLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [_pinnedBar addSubview:_pinnedLabel];

    UIView *pinnedSeparator = [[UIView alloc] initWithFrame:
                               CGRectMake(0, MAXPinnedBarHeight - 0.5,
                                          bounds.size.width, 0.5)];
    pinnedSeparator.backgroundColor = [MAXTheme separatorColor];
    pinnedSeparator.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [_pinnedBar addSubview:pinnedSeparator];

    [_pinnedBar addGestureRecognizer:
        [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(openPinned)]];

    _spinner = [[UIActivityIndicatorView alloc]
                initWithActivityIndicatorStyle:[MAXTheme activityIndicatorStyle]];
    _spinner.center = CGPointMake(bounds.size.width / 2, 40);
    [self.view addSubview:_spinner];

    // Полоса записи. Лежит поверх строки ввода и показывается только на
    // время записи: своего места в раскладке ей не нужно.
    _recordBar = [[UIView alloc] initWithFrame:CGRectZero];
    _recordBar.backgroundColor = [MAXTheme barBackgroundColor];
    _recordBar.hidden = YES;
    [_composer addSubview:_recordBar];

    _recordDot = [[UIView alloc] initWithFrame:CGRectMake(10, 0, 10, 10)];
    _recordDot.backgroundColor = [UIColor colorWithRed:0.85 green:0.22 blue:0.22 alpha:1.0];
    _recordDot.layer.cornerRadius = 5.0;
    [_recordBar addSubview:_recordDot];

    _recordTime = [[UILabel alloc] initWithFrame:CGRectZero];
    _recordTime.font = [UIFont systemFontOfSize:13.0];
    _recordTime.textColor = [MAXTheme textColor];
    _recordTime.backgroundColor = [UIColor clearColor];
    [_recordBar addSubview:_recordTime];

    _recordWave = [[MAXWaveView alloc] initWithFrame:CGRectZero];
    _recordWave.playedColor = [MAXTheme accentColor];
    _recordWave.restColor = [MAXTheme accentColor];
    _recordWave.progress = 1.0;
    [_recordBar addSubview:_recordWave];

    _recordHint = [[UILabel alloc] initWithFrame:CGRectZero];
    _recordHint.font = [UIFont systemFontOfSize:12.0];
    _recordHint.textColor = [MAXTheme secondaryTextColor];
    _recordHint.textAlignment = NSTextAlignmentRight;
    _recordHint.backgroundColor = [UIColor clearColor];
    [_recordBar addSubview:_recordHint];

    _recordCancel = [MAXTheme plainButtonWithTitle:@""];
    [_recordCancel setTitle:@"Отмена" forState:UIControlStateNormal];
    [_recordCancel addTarget:self
                      action:@selector(cancelRecording)
            forControlEvents:UIControlEventTouchUpInside];
    _recordCancel.hidden = YES;
    [_recordBar addSubview:_recordCancel];

    _recordSend = [MAXTheme plainButtonWithTitle:@""];
    [_recordSend setTitle:@"Отправить" forState:UIControlStateNormal];
    [_recordSend addTarget:self
                    action:@selector(finishRecording)
          forControlEvents:UIControlEventTouchUpInside];
    _recordSend.hidden = YES;
    [_recordBar addSubview:_recordSend];

    // Стрелка «вниз» со счётчиком: появляется, когда сообщения приходят,
    // пока читают выше. Место ей считает layoutComposerAndTable.
    _jumpButton = [UIButton buttonWithType:UIButtonTypeCustom];
    _jumpButton.titleLabel.font = [UIFont boldSystemFontOfSize:13.0];
    _jumpButton.backgroundColor = [MAXTheme accentColor];
    [_jumpButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    _jumpButton.layer.cornerRadius = MAXJumpButtonSize / 2.0;
    _jumpButton.hidden = YES;
    [_jumpButton addTarget:self
                    action:@selector(jumpToBottom)
          forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:_jumpButton];

    [self refreshPinnedBar];

    [self updateComposerAvailability];

    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center addObserver:self selector:@selector(messageReceived:)
                   name:MAXChatDidReceiveMessageNotification object:nil];
    [center addObserver:self selector:@selector(messagesDeleted:)
                   name:MAXChatMessagesDeletedNotification object:nil];
    [center addObserver:self selector:@selector(reactionsChanged:)
                   name:MAXChatReactionsChangedNotification object:nil];
    [center addObserver:self selector:@selector(someoneTyping:)
                   name:MAXChatTypingNotification object:nil];
    [center addObserver:self selector:@selector(noteStateChanged:)
                   name:MAXVideoNotePlayerDidChangeNotification object:nil];
    [center addObserver:self selector:@selector(transcriptChanged:)
                   name:MAXTranscriptsDidChangeNotification object:nil];
    // Имена в пузырях берутся из кэша контактов, а он пополняется на ходу —
    // и у отправителей в группе, и у авторов пересылок. Без перерисовки имя
    // осталось бы номером до следующего открытия чата.
    [center addObserver:self selector:@selector(contactsChanged:)
                   name:MAXChatsDidChangeNotification object:nil];
    [center addObserver:self selector:@selector(wallpaperChanged:)
                   name:MAXWallpaperDidChangeNotification object:nil];
    [center addObserver:self selector:@selector(keyboardWillShow:)
                   name:UIKeyboardWillShowNotification object:nil];
    [center addObserver:self selector:@selector(keyboardWillHide:)
                   name:UIKeyboardWillHideNotification object:nil];

    [[MAXChatsModule shared] subscribeToChat:_chat.chatId subscribe:YES];
    [self refreshPresence];
    [self refreshChatInfo];
    [self loadHistory];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    if (self.isMovingFromParentViewController) {
        [[MAXChatsModule shared] subscribeToChat:_chat.chatId subscribe:NO];

        // Таймер держит экран за собой, пока не сработает: NSTimer владеет
        // своей целью. Без этого закрытая переписка жила бы ещё шесть секунд.
        [_typingTimer invalidate];
        _typingTimer = nil;

        // Запись без своего экрана бессмысленна: отправлять её будет некуда,
        // а микрофон и камера остались бы занятыми.
        if ([MAXVoiceRecorder shared].recording
                || [MAXVideoNoteRecorder shared].recording) {
            [self cancelRecording];
        }
        [_recordTimer invalidate];
        _recordTimer = nil;

        // Голосовое и кружок, играющие в закрытом чате, остановить нечем:
        // ни строки с кнопкой, ни самого кружка на экране больше нет.
        if ([MAXVoicePlayer shared].messageId != nil) [[MAXVoicePlayer shared] stop];
        if ([MAXVideoNotePlayer shared].messageId != nil) [[MAXVideoNotePlayer shared] stop];
    }
}

#pragma mark - Строка ввода

/// Читателю канала писать нечего: сервер такую отправку всё равно отвергнет,
/// а поле ввода обещало бы обратное. Вместо него — переключатель уведомлений,
/// ровно как в Komet.
/// Подписан ли на канал.
///
/// Отдельного признака у чата нет, и спрашивать сервер незачем: подписка —
/// это и есть присутствие канала в своём списке чатов. Канал, открытый из
/// поиска, там не значится.
- (BOOL)isSubscribedChannel {
    if (![_chat.type isEqualToString:@"CHANNEL"]) return YES;
    return [[MAXChatsModule shared] chatWithId:_chat.chatId] != nil;
}

- (void)updateComposerAvailability {
    BOOL subscribed = [self isSubscribedChannel];
    BOOL canWrite = subscribed
        && [_chat canWriteAsUser:[MAXChatsModule shared].currentUserId];

    _inputField.hidden = !canWrite;
    _attachButton.hidden = !canWrite;
    _muteButton.hidden = canWrite;

    // Кто из двух — отправка или запись — решается отдельно: место у них одно.
    [self updateSendButton];

    if (canWrite) return;

    [_inputField resignFirstResponder];

    // Одна и та же кнопка на два случая: пока не подписан — подписка,
    // после — переключение уведомлений. Место у строки ввода одно.
    if (!subscribed) {
        [_muteButton setTitle:(_subscribing ? @"Подписываемся…" : @"Подписаться")
                     forState:UIControlStateNormal];
        return;
    }

    [_muteButton setTitle:(_chat.isMuted ? @"Включить уведомления"
                                         : @"Отключить уведомления")
                 forState:UIControlStateNormal];
}

- (void)subscribeToChannel {
    if (_subscribing) return;
    _subscribing = YES;
    [self updateComposerAvailability];

    __weak MAXChatViewController *weakSelf = self;
    [[MAXChatsModule shared] subscribeToChannel:_chat.chatId
                                     completion:^(MAXChat *chat, NSError *error) {
        MAXChatViewController *strongSelf = weakSelf;
        if (strongSelf == nil) return;

        strongSelf->_subscribing = NO;

        if (error != nil) {
            [strongSelf updateComposerAvailability];
            [strongSelf showAlert:@"Не удалось подписаться" message:error.localizedDescription];
            return;
        }

        // Теперь канал в списке — и заготовка, с которой открывали, больше
        // не нужна: у настоящего чата есть и права, и число подписчиков.
        if (chat != nil) strongSelf->_chat = chat;

        [strongSelf updateComposerAvailability];
        [strongSelf updateHeader];
        [strongSelf loadHistory];
    }];
}

- (void)toggleMute {
    if (![self isSubscribedChannel]) {
        [self subscribeToChannel];
        return;
    }

    long long until = _chat.isMuted ? 0 : -1;

    __weak MAXChatViewController *weakSelf = self;
    [[MAXChatsModule shared] setMuteUntil:until
                                  forChat:_chat.chatId
                               completion:^(NSError *error) {
        MAXChatViewController *strongSelf = weakSelf;
        if (strongSelf == nil) return;

        if (error != nil) {
            [strongSelf showAlert:@"Не вышло" message:error.localizedDescription];
            return;
        }
        [strongSelf updateComposerAvailability];
    }];
}

#pragma mark - Шапка

/// Две строки вместо обычного заголовка: название и то, что Komet пишет под
/// ним — сколько участников или подписчиков. Нажатие открывает сведения о чате,
/// как `onOpenInfo` в chat_screen.dart.
- (void)setupTitleView {
    // Ширина заголовка — по остатку от кнопок панели. Панель не ужимает
    // titleView сама: с широкой кнопкой «‹ Профиль» слева фиксированные 220 pt
    // не помещались по центру, и заголовок уезжал вправо.
    CGFloat available = self.view.bounds.size.width - 160.0;
    if (available < 120.0) available = 120.0;

    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, available, 40)];
    header.backgroundColor = [UIColor clearColor];

    _headerTitle = [[UILabel alloc] initWithFrame:CGRectMake(0, 2, available, 20)];
    _headerTitle.font = [UIFont boldSystemFontOfSize:16.0];
    _headerTitle.textAlignment = NSTextAlignmentCenter;
    // Цвет именно панели, а не экрана: заголовок лежит на ней, и в тёмной
    // теме чёрный по умолчанию сливался с её фоном.
    _headerTitle.textColor = [MAXTheme barTextColor];
    _headerTitle.backgroundColor = [UIColor clearColor];
    _headerTitle.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [header addSubview:_headerTitle];

    _headerSubtitle = [[UILabel alloc] initWithFrame:CGRectMake(0, 22, available, 14)];
    _headerSubtitle.font = [UIFont systemFontOfSize:11.0];
    _headerSubtitle.textAlignment = NSTextAlignmentCenter;
    _headerSubtitle.textColor = [MAXTheme secondaryTextColor];
    _headerSubtitle.backgroundColor = [UIColor clearColor];
    _headerSubtitle.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [header addSubview:_headerSubtitle];

    UITapGestureRecognizer *tap =
        [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(openChatInfo)];
    [header addGestureRecognizer:tap];
    header.userInteractionEnabled = YES;

    self.navigationItem.titleView = header;

    // Разметка накладывается на выделенное в поле ввода. Отдельной кнопкой,
    // а не значками вокруг строки: места там нет, а выделять текст всё равно
    // приходится пальцем. Так же она устроена и на Windows Phone.
    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithTitle:@"Аа"
                                         style:[MAXTheme barButtonStyle]
                                        target:self
                                        action:@selector(chooseMarkup)];
    [self updateHeader];
}

/// Возвращает шапку к обычному виду. Сюда же сходятся временные состояния
/// («Отправка…», «Скачивание…»): заголовок один, и место у них общее.
- (void)updateHeader {
    MAXChatsModule *module = [MAXChatsModule shared];
    _headerTitle.text = [module displayTitleForChat:_chat];
    _headerSubtitle.text = _presenceText.length > 0
        ? _presenceText
        : [module subtitleForChat:_chat];
}

/// У диалога вторая строка — присутствие собеседника, как в Komet. Пока оно
/// не приехало (или его нет вовсе), там остаётся номер.
- (void)refreshPresence {
    if (!_chat.isDialog) return;

    MAXChatsModule *module = [MAXChatsModule shared];
    long long otherId = [_chat otherParticipantIdForCurrentUser:module.currentUserId];
    if (otherId == 0 || otherId == module.currentUserId) return;

    __weak MAXChatViewController *weakSelf = self;
    [module fetchPresenceForIds:@[@(otherId)]
                     completion:^(NSDictionary *presence, NSError *error) {
        MAXChatViewController *strongSelf = weakSelf;
        if (strongSelf == nil || error != nil) return;

        strongSelf->_presenceText = MAXPresenceText(presence[@(otherId)]);
        if (!strongSelf->_uploading) [strongSelf updateHeader];
    }];
}

#pragma mark - Разметка набранного

/// Что именно выделено в поле ввода. Длина ноль — не выделено ничего.
- (NSRange)selectionInInput {
    UITextRange *chosen = _inputField.selectedTextRange;
    if (chosen == nil) return NSMakeRange(0, 0);

    NSInteger start = [_inputField offsetFromPosition:_inputField.beginningOfDocument
                                            toPosition:chosen.start];
    NSInteger length = [_inputField offsetFromPosition:chosen.start
                                            toPosition:chosen.end];

    if (start < 0 || length <= 0) return NSMakeRange(0, 0);
    return NSMakeRange((NSUInteger)start, (NSUInteger)length);
}

- (void)chooseMarkup {
    NSRange chosen = [self selectionInInput];

    if (chosen.length == 0) {
        [self showAlert:@"Разметка"
                message:@"Выделите в сообщении то, что нужно разметить."];
        return;
    }

    _markupRange = chosen;
    NSMutableArray *titles = [NSMutableArray arrayWithArray:
        @[@"жирным", @"наклонным", @"подчёркнутым", @"моноширинным", @"зачёркнутым"]];

    if (_markup.count > 0) [titles addObject:@"снять всю разметку"];
    _markupTitles = titles;

    UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:@"Разметка"
                                                       delegate:self
                                              cancelButtonTitle:nil
                                         destructiveButtonTitle:nil
                                              otherButtonTitles:nil];
    for (NSString *title in titles) [sheet addButtonWithTitle:title];
    sheet.cancelButtonIndex = [sheet addButtonWithTitle:@"Отмена"];

    [sheet showInView:self.view];
}

/// Запомнить наложенное вместе с куском, который оно покрывает.
///
/// Живого пересчёта при правке нет нарочно: слежение за границами на каждое
/// нажатие клавиши — это отдельный редактор, а ошибётся оно так, что жирным
/// окажется не то слово. Перед отправкой кусок ищется в тексте заново.
- (void)markSelectionAs:(NSString *)type {
    NSString *text = _inputField.text;
    if (_markupRange.location + _markupRange.length > text.length) return;

    MAXAppliedMarkup *mark = [[MAXAppliedMarkup alloc] init];
    mark.type = type;
    mark.start = (NSInteger)_markupRange.location;
    mark.covered = [text substringWithRange:_markupRange];

    if (_markup == nil) _markup = [NSMutableArray array];
    [_markup addObject:mark];

    [self setHeaderStatus:[NSString stringWithFormat:@"разметка: %@", mark.covered]];
    [NSObject cancelPreviousPerformRequestsWithTarget:self
                                             selector:@selector(updateHeader)
                                               object:nil];
    [self performSelector:@selector(updateHeader) withObject:nil afterDelay:2.0];
}

#pragma mark - Действия над сообщением

/// Меню по долгому нажатию. Набор пунктов зависит от того, чьё сообщение
/// и что в нём: править и удалять у всех можно только своё, копировать —
/// только когда есть что.
- (void)messageCellDidLongPress:(MAXMessageCell *)cell {
    _actionMessage = cell.message;
    BOOL mine = _actionMessage.senderId == [MAXChatsModule shared].currentUserId;

    NSMutableArray *titles = [NSMutableArray array];
    if ([_chat canWriteAsUser:[MAXChatsModule shared].currentUserId]) {
        [titles addObject:@"Ответить"];
    }

    // Своя реакция снимается тем же пунктом, каким ставилась: отдельная
    // кнопка «убрать» в списке из пяти эмодзи выглядела бы лишней.
    [titles addObject:(_actionMessage.myReaction.length > 0 ? @"Убрать реакцию" : @"Реакция")];
    [titles addObject:@"Переслать"];
    if (_actionMessage.text.length > 0) [titles addObject:@"Копировать"];
    if (mine && _actionMessage.text.length > 0) [titles addObject:@"Изменить"];

    // Закреплять может тот, кто управляет чатом; в диалоге — любой из двоих.
    MAXChat *cached = [[MAXChatsModule shared] chatWithId:_chat.chatId] ?: _chat;
    BOOL canPin = _chat.isDialog
        || [_chat isAdmin:[MAXChatsModule shared].currentUserId];
    if (canPin) {
        long long messageId = [_actionMessage.messageId longLongValue];
        [titles addObject:(cached.pinnedMessageId == messageId && messageId != 0
                           ? @"Открепить" : @"Закрепить")];
    }

    [titles addObject:@"Удалить"];

    _actionTitles = titles;

    UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:nil
                                                       delegate:self
                                              cancelButtonTitle:nil
                                         destructiveButtonTitle:nil
                                              otherButtonTitles:nil];
    for (NSString *title in titles) [sheet addButtonWithTitle:title];
    sheet.destructiveButtonIndex = (NSInteger)titles.count - 1;
    sheet.cancelButtonIndex = [sheet addButtonWithTitle:@"Отмена"];

    [sheet showInView:self.view];
}

/// Набор эмодзи вторым листом. Панели с полным набором в порте нет: на iOS 6
/// её пришлось бы рисовать самому, а пять ходовых закрывают почти всё.
/// Лица, которых сервер не принял. Помним до перезапуска: кнопка, которая
/// всякий раз отвечает отказом, хуже отсутствующей.
+ (NSMutableSet *)refusedReactions {
    static NSMutableSet *refused = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ refused = [[NSMutableSet alloc] init]; });
    return refused;
}

- (void)chooseReactionFor:(MAXMessage *)message {
    _actionMessage = message;

    // Набор тот же, что на Windows Phone: он там подбирался по тому, что
    // сервер согласен принять.
    NSArray *faces = @[@"👍", @"❤️", @"🔥", @"🤣", @"😭", @"😍"];

    NSMutableArray *offered = [NSMutableArray array];
    for (NSString *emoji in faces) {
        if ([[MAXChatViewController refusedReactions] containsObject:emoji]) continue;
        [offered addObject:emoji];
    }

    if (offered.count == 0) {
        [self showAlert:@"Реакции" message:@"Реакции здесь не принимаются"];
        return;
    }

    _reactionTitles = offered;

    UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:@"Реакция"
                                                       delegate:self
                                              cancelButtonTitle:nil
                                         destructiveButtonTitle:nil
                                              otherButtonTitles:nil];
    for (NSString *emoji in _reactionTitles) [sheet addButtonWithTitle:emoji];
    sheet.cancelButtonIndex = [sheet addButtonWithTitle:@"Отмена"];

    [sheet showInView:self.view];
}

- (void)setReaction:(NSString *)emoji forMessage:(MAXMessage *)message {
    NSString *previous = message.myReaction;
    message.myReaction = emoji.length > 0 ? emoji : nil;
    [message applyMyReaction:emoji instead:previous];
    [self reloadRowForMessage:message];

    __weak MAXChatViewController *weakSelf = self;
    [[MAXMessagesModule shared] setReaction:emoji
                                 forMessage:message.messageId
                                     inChat:_chat.chatId
                                 completion:^(NSError *error) {
        MAXChatViewController *strongSelf = weakSelf;
        if (strongSelf == nil) return;

        if (error != nil) {
            message.myReaction = previous;
            [message applyMyReaction:previous instead:emoji];
            [strongSelf reloadRowForMessage:message];

            // Отказ сервера на само лицо — значит его здесь не принимают.
            // Второй раз предлагать его незачем.
            if (emoji.length > 0) {
                [[MAXChatViewController refusedReactions] addObject:emoji];
            }

            [strongSelf showAlert:@"Реакция не поставилась" message:error.localizedDescription];
            return;
        }

        // Точные счётчики приедут пушем NOTIF_MSG_YOU_REACTED и поправят
        // наш подсчёт. Перечитывать ради этого всю историю не надо: вместе с
        // ней уезжала и прокрутка — а реакцию часто ставят не на последнее
        // сообщение, а на давнее.
    }];
}

- (void)reloadRowForMessage:(MAXMessage *)message {
    NSUInteger index = [_messages indexOfObject:message];
    if (index == NSNotFound) return;
    [self reloadRowAtIndex:index];
}

/// Перерисовать одну строку. Целиком строку, а не одну её часть: от реакций
/// меняется её высота.
- (void)reloadRowAtIndex:(NSUInteger)index {
    if ([_tableView numberOfRowsInSection:0] != (NSInteger)_messages.count) {
        [_tableView reloadData];
        return;
    }

    [_tableView reloadRowsAtIndexPaths:
        @[[NSIndexPath indexPathForRow:(NSInteger)index inSection:0]]
                      withRowAnimation:UITableViewRowAnimationNone];
}

- (void)actionSheet:(UIActionSheet *)actionSheet clickedButtonAtIndex:(NSInteger)buttonIndex {
    // Лист разметки — свой набор кнопок и свой разбор.
    if (_markupTitles != nil) {
        NSArray *titles = _markupTitles;
        _markupTitles = nil;

        if (buttonIndex < 0 || buttonIndex >= (NSInteger)titles.count) return;
        NSString *chosen = titles[(NSUInteger)buttonIndex];

        if ([chosen isEqualToString:@"жирным"]) [self markSelectionAs:@"STRONG"];
        else if ([chosen isEqualToString:@"наклонным"]) [self markSelectionAs:@"EMPHASIZED"];
        else if ([chosen isEqualToString:@"подчёркнутым"]) [self markSelectionAs:@"UNDERLINE"];
        else if ([chosen isEqualToString:@"моноширинным"]) [self markSelectionAs:@"MONOSPACED"];
        else if ([chosen isEqualToString:@"зачёркнутым"]) [self markSelectionAs:@"STRIKETHROUGH"];
        else if ([chosen isEqualToString:@"снять всю разметку"]) [_markup removeAllObjects];
        return;
    }

    // Лист со ссылками — свой набор кнопок и свой разбор.
    if (_linkTitles != nil) {
        NSArray *links = _linkTitles;
        _linkTitles = nil;

        if (buttonIndex >= 0 && buttonIndex < (NSInteger)links.count) {
            [self openLink:links[(NSUInteger)buttonIndex]];
        }
        return;
    }

    // Лист с эмодзи — второй по счёту, у него свой набор кнопок.
    if (_reactionTitles != nil) {
        NSArray *emoji = _reactionTitles;
        _reactionTitles = nil;

        if (buttonIndex >= 0 && buttonIndex < (NSInteger)emoji.count) {
            [self setReaction:emoji[(NSUInteger)buttonIndex] forMessage:_actionMessage];
        }
        return;
    }

    // Лист вложений — свой, у него другой набор кнопок и своя обработка.
    if (_actionTitles == nil) {
        [self attachmentSheet:actionSheet clickedButtonAtIndex:buttonIndex];
        return;
    }

    NSArray *titles = _actionTitles;
    MAXMessage *message = _actionMessage;
    _actionTitles = nil;

    if (buttonIndex < 0 || buttonIndex >= (NSInteger)titles.count) return;
    NSString *action = titles[(NSUInteger)buttonIndex];

    if ([action isEqualToString:@"Ответить"]) {
        [self startReplyTo:message];
    } else if ([action isEqualToString:@"Реакция"]) {
        [self chooseReactionFor:message];
    } else if ([action isEqualToString:@"Убрать реакцию"]) {
        [self setReaction:@"" forMessage:message];
    } else if ([action isEqualToString:@"Переслать"]) {
        [self startForwardOf:message];
    } else if ([action isEqualToString:@"Закрепить"]) {
        [self setPinned:[message.messageId longLongValue]];
    } else if ([action isEqualToString:@"Открепить"]) {
        [self setPinned:0];
    } else if ([action isEqualToString:@"Копировать"]) {
        [UIPasteboard generalPasteboard].string = message.text;
    } else if ([action isEqualToString:@"Изменить"]) {
        [self startEditOf:message];
    } else if ([action isEqualToString:@"Удалить"]) {
        [self confirmDeleteOf:message];
    }
}

- (void)startReplyTo:(MAXMessage *)message {
    _replyToMessage = message;
    _editingMessage = nil;
    [self updateComposerBanner];
    [_inputField becomeFirstResponder];
}

- (void)startEditOf:(MAXMessage *)message {
    _editingMessage = message;
    _replyToMessage = nil;
    _inputField.text = message.text;
    [self updateSendButton];
    [self updateComposerBanner];
    [_inputField becomeFirstResponder];
}

- (void)cancelComposerMode {
    _replyToMessage = nil;
    _editingMessage = nil;
    _inputField.text = @"";
    [_markup removeAllObjects];
    [self updateSendButton];
    [self updateComposerBanner];
}

/// Полоска над строкой ввода: на что отвечаем или что правим. Она же съедает
/// часть высоты у таблицы, поэтому та каждый раз пересчитывается.
- (void)updateComposerBanner {
    MAXMessage *shown = _replyToMessage ?: _editingMessage;

    if (shown == nil) {
        _composerBanner.hidden = YES;
        [self layoutComposerAndTable];
        return;
    }

    NSString *prefix = _editingMessage != nil ? @"Изменение" : @"Ответ";
    NSString *body = shown.displayText;
    if (body.length > 60) body = [[body substringToIndex:60] stringByAppendingString:@"…"];

    _composerBannerLabel.text = [NSString stringWithFormat:@"%@: %@", prefix, body];
    _composerBanner.hidden = NO;
    [self layoutComposerAndTable];
}

- (void)confirmDeleteOf:(MAXMessage *)message {
    _actionMessage = message;
    BOOL mine = message.senderId == [MAXChatsModule shared].currentUserId;

    id alert = [MAXTheme alertWithTitle:@"Удалить сообщение?"
                              message:(mine ? @"Можно удалить у всех или только у себя"
                                              : @"Удалится только у вас")
                             delegate:self
                    cancelButtonTitle:@"Отмена"
                     otherButtonTitle:@"У себя"];
    if (mine) [alert addButtonWithTitle:@"У всех"];
    [alert show];
}

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex {
    if (buttonIndex == alertView.cancelButtonIndex || _actionMessage == nil) return;

    BOOL forEveryone = buttonIndex == 2;
    NSString *messageId = _actionMessage.messageId;

    __weak MAXChatViewController *weakSelf = self;
    [[MAXMessagesModule shared] deleteMessages:@[messageId]
                                        inChat:_chat.chatId
                                   forEveryone:forEveryone
                                    completion:^(NSError *error) {
        MAXChatViewController *strongSelf = weakSelf;
        if (strongSelf == nil) return;

        if (error != nil) {
            [strongSelf showAlert:@"Не удалилось" message:error.localizedDescription];
            return;
        }

        for (NSUInteger i = 0; i < strongSelf->_messages.count; i++) {
            if (![[strongSelf->_messages[i] messageId] isEqualToString:messageId]) continue;
            [strongSelf->_messages removeObjectAtIndex:i];
            break;
        }
        [strongSelf->_tableView reloadData];
    }];
}

/// Пересылка: выбираем чат, отправляем и уходим в него — так понятнее, что
/// сообщение действительно ушло.
- (void)startForwardOf:(MAXMessage *)message {
    MAXChatPickerViewController *picker = [[MAXChatPickerViewController alloc] init];
    picker.delegate = self;
    _actionMessage = message;

    UINavigationController *stack =
        [[UINavigationController alloc] initWithRootViewController:picker];
    [MAXTheme applyToNavigationBar:stack.navigationBar];
    [self presentViewController:stack animated:YES completion:nil];
}

- (void)chatPicker:(MAXChatPickerViewController *)picker didPickChat:(MAXChat *)chat {
    [self dismissViewControllerAnimated:YES completion:nil];
    if (chat == nil || _actionMessage == nil) return;

    MAXMessage *message = _actionMessage;
    __weak MAXChatViewController *weakSelf = self;
    [[MAXMessagesModule shared] forwardMessage:message.messageId
                                      fromChat:_chat.chatId
                                        toChat:chat.chatId
                                    completion:^(NSString *messageId, NSError *error) {
        MAXChatViewController *strongSelf = weakSelf;
        if (strongSelf == nil) return;

        if (error != nil) {
            [strongSelf showAlert:@"Не переслалось" message:error.localizedDescription];
            return;
        }

        MAXChatViewController *screen = [[MAXChatViewController alloc] initWithChat:chat];
        [strongSelf.navigationController pushViewController:screen animated:YES];
    }];
}

- (void)setHeaderStatus:(NSString *)status {
    if (status.length == 0) {
        [self updateHeader];
        return;
    }
    _headerSubtitle.text = status;
}

/// У диалога сведения о чате — это карточка собеседника, как в Komet:
/// отдельного экрана с одним участником там тоже нет.
- (void)openChatInfo {
    if (_chat.isDialog) {
        long long otherId =
            [_chat otherParticipantIdForCurrentUser:[MAXChatsModule shared].currentUserId];
        if (otherId == 0) return;

        MAXContactViewController *card =
            [[MAXContactViewController alloc] initWithContactId:otherId];
        [self.navigationController pushViewController:card animated:YES];
        return;
    }

    MAXChatInfoViewController *info = [[MAXChatInfoViewController alloc] initWithChat:_chat];
    [self.navigationController pushViewController:info animated:YES];
}

#pragma mark - История

- (void)loadHistory {
    if (_loading) return;
    _loading = YES;
    [_spinner startAnimating];

    // Обычно берётся хвост истории; при переходе к найденному сообщению или
    // к источнику пересылки — окно вокруг него. Плюс миллисекунда, чтобы само
    // сообщение в окно попало: сервер отдаёт то, что строго раньше `from`.
    //
    // Половина окна берётся вперёд, и это не запас на будущее: без неё история
    // обрывается ровно на искомом сообщении, и прокрутить чат вниз оказывается
    // некуда — всё, что пришло позже, просто не запрошено.
    BOOL aroundMessage = (_initialMessageTime > 0);
    long long from = aroundMessage ? _initialMessageTime + 1 : 0;

    [[MAXMessagesModule shared] fetchHistoryForChat:_chat.chatId
                                           fromTime:from
                                            forward:(aroundMessage ? 25 : 0)
                                           backward:(aroundMessage ? 25 : 50)
                                         completion:^(NSArray *messages, NSError *error) {
        self->_loading = NO;
        [self->_spinner stopAnimating];

        if (error != nil) {
            [self setHeaderStatus:@"не загрузилось"];
            return;
        }

        [self->_messages setArray:messages];
        [self resolveMessageAuthors];
        [self->_tableView reloadData];

        // История перечитана целиком — считать нечего.
        self->_unseenCount = 0;
        [self refreshJumpButton];

        // Окно из глубины истории — не повод ни отмечать прочитанным, ни
        // обновлять строку в списке чатов: последнее сообщение в таком окне
        // старое, и то и другое откатило бы состояние чата назад.
        if (self->_initialMessageId.length > 0) {
            [self scrollToInitialMessage];
            return;
        }

        [self scrollToBottomAnimated:NO];
        [self markRead];

        // Список чатов знает только то, что приехало при входе; здесь мы
        // видим свежую историю и подтягиваем его сами, не дожидаясь пуша.
        [[MAXChatsModule shared] noteMessage:[self->_messages lastObject]
                                      inChat:self->_chat.chatId];
    }];
}

/// Просит карточки всех, кто написал что-то в этом чате, и авторов цитат.
///
/// В группе отправитель — почти всегда человек не из наших диалогов, а обход
/// при входе идёт по чатам: без этого запроса вместо имён и аватарок в шапках
/// пузырей оставались номера. Запрос один на всю историю; уже известные
/// и уже запрошенные отсеиваются в модуле.
- (void)resolveMessageAuthors {
    NSMutableArray *ids = [NSMutableArray array];

    for (MAXMessage *message in _messages) {
        if (message.senderId != 0) [ids addObject:@(message.senderId)];
        if (message.replySenderId != 0) [ids addObject:@(message.replySenderId)];
        if (message.forwardedSenderId != 0) [ids addObject:@(message.forwardedSenderId)];
    }

    [[MAXChatsModule shared] ensureContactsWithIds:ids];
}

/// Ставит на видное место сообщение, ради которого чат и открыли. Обычно оно
/// последнее в окне, но искать всё равно надо по id: сервер мог отдать и то,
/// что пришло позже, а промахнуться экраном тут заметнее всего.
- (void)scrollToInitialMessage {
    NSUInteger target = NSNotFound;
    for (NSUInteger i = 0; i < _messages.count; i++) {
        MAXMessage *message = _messages[i];
        if ([message.messageId isEqualToString:_initialMessageId]) {
            target = i;
            break;
        }
    }

    if (target == NSNotFound) {
        [self scrollToBottomAnimated:NO];
        return;
    }

    [_tableView scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:(NSInteger)target inSection:0]
                      atScrollPosition:UITableViewScrollPositionMiddle
                              animated:NO];
}

- (void)markRead {
    MAXMessage *last = [_messages lastObject];
    if (last == nil) return;
    [[MAXChatsModule shared] markChatRead:_chat.chatId
                                messageId:last.messageId
                                     time:last.time];
}

#pragma mark - Отправка

- (void)sendMessage {
    NSString *text = [_inputField.text stringByTrimmingCharactersInSet:
                      [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (text.length == 0) return;

    // Разметку забираем до того, как поле очистится: очистка её и сбрасывает.
    NSArray *markup = [_markup copy];

    // Правка идёт другим опкодом и нового пузыря не создаёт — только меняет
    // текст в уже существующем.
    if (_editingMessage != nil) {
        MAXMessage *edited = _editingMessage;
        NSString *previous = edited.text;
        edited.text = text;

        [self cancelComposerMode];
        [_tableView reloadData];

        __weak MAXChatViewController *weakSelf = self;
        [[MAXMessagesModule shared] editMessage:edited.messageId
                                         inChat:_chat.chatId
                                           text:text
                                         markup:markup
                                     completion:^(NSError *error) {
            MAXChatViewController *strongSelf = weakSelf;
            if (strongSelf == nil || error == nil) return;

            edited.text = previous;
            [strongSelf->_tableView reloadData];
            [strongSelf showAlert:@"Не изменилось" message:error.localizedDescription];
        }];
        return;
    }

    long long replyTo = [_replyToMessage.messageId longLongValue];
    _inputField.text = @"";
    [self cancelComposerMode];

    // Локальный пузырь до подтверждения сервером.
    MAXMessage *pending = [[MAXMessage alloc] init];
    pending.messageId = [NSString stringWithFormat:@"local-%f", [[NSDate date] timeIntervalSince1970]];
    pending.chatId = _chat.chatId;
    pending.senderId = [MAXChatsModule shared].currentUserId;
    pending.text = text;
    pending.time = (long long)([[NSDate date] timeIntervalSince1970] * 1000.0);
    pending.isPending = YES;

    [_messages addObject:pending];
    [_tableView reloadData];
    [self scrollToBottomAnimated:YES];

    [[MAXMessagesModule shared] sendText:text
                                  toChat:_chat.chatId
                        replyToMessageId:replyTo
                                  markup:markup
                              completion:^(NSString *messageId, NSError *error) {
        if (error != nil) {
            pending.text = [NSString stringWithFormat:@"%@ (не отправлено)", text];
            [self->_tableView reloadData];
            return;
        }
        pending.isPending = NO;
        if (messageId.length > 0) pending.messageId = messageId;
        [self->_tableView reloadData];
        [[MAXChatsModule shared] noteMessage:pending inChat:self->_chat.chatId];
    }];
}

#pragma mark - Голосовое и кружок: запись

/// Насколько увести палец, чтобы отменить запись или закрепить её. Числа те
/// же, что на Windows Phone: меньше — и запись срывалась бы от дрожи руки.
static const CGFloat MAXCancelSlide = 90.0;
static const CGFloat MAXLockSlide = 80.0;

/// Одна кнопка на два дела: пока не набрано ни слова, отправлять нечего — и
/// на её месте стоит запись. Как только появился текст, запись уступает:
/// писать и говорить разом всё равно не выйдет.
- (void)updateSendButton {
    BOOL canWrite = [self isSubscribedChannel]
        && [_chat canWriteAsUser:[MAXChatsModule shared].currentUserId];

    BOOL typed = [[_inputField.text stringByTrimmingCharactersInSet:
                   [NSCharacterSet whitespaceAndNewlineCharacterSet]] length] > 0;

    // Во время правки запись не показываем даже на пустом поле: записать
    // голосовое взамен написанного нельзя, а стёртый текст означает лишь,
    // что правку ещё не набрали.
    BOOL editing = (_editingMessage != nil);

    _sendButton.hidden = !(canWrite && typed);
    _micButton.hidden = !(canWrite && !typed && !editing);
}

/// Значок на кнопке записи — микрофон или камера. Меняется на ней же: иначе
/// о выбранном не догадаться до первой записи.
- (void)refreshRecordGlyph {
    // Камера уже нарисована в наборе значков, а микрофона там нет — его
    // MAXTheme рисует сам.
    UIImage *glyph = _noteMode
        ? [MAXTheme iconNamed:@"camera" size:24 color:[UIColor whiteColor]]
        : [MAXTheme microphoneIconOfSize:24 color:[UIColor whiteColor]];

    [_micButton setImage:glyph forState:UIControlStateNormal];
}

/// Касание, не переросшее в удержание, — это не запись, а выбор, что
/// записывать: отдельной кнопки под него в строке ввода нет.
- (void)micTapped {
    if ([MAXVoiceRecorder shared].recording) return;
    if ([MAXVideoNoteRecorder shared].recording) return;

    _noteMode = !_noteMode;
    [self refreshRecordGlyph];

    [self setHeaderStatus:(_noteMode
                           ? @"кружок: удерживайте, чтобы снять"
                           : @"голосовое: удерживайте, чтобы записать")];
    [NSObject cancelPreviousPerformRequestsWithTarget:self
                                             selector:@selector(updateHeader)
                                               object:nil];
    [self performSelector:@selector(updateHeader) withObject:nil afterDelay:2.0];
}

/// Удержание: началось — пишем, ведут пальцем — смотрим куда, отпустили —
/// отправляем либо отменяем.
///
/// Порог по вертикали проверяется первым: увести палец ровно вверх мало кому
/// удаётся, движение почти всегда идёт с примесью вбок, и отмена
/// перехватывала бы закрепление.
- (void)micHeld:(UILongPressGestureRecognizer *)hold {
    CGPoint at = [hold locationInView:_composer];

    switch (hold.state) {
        case UIGestureRecognizerStateBegan:
            _recordStart = at;
            _recordCancelling = NO;
            _recordLocked = NO;
            _recordStarted = YES;
            [self beginRecording];
            return;

        case UIGestureRecognizerStateChanged: {
            if (!_recordStarted || _recordLocked) return;

            CGFloat up = _recordStart.y - at.y;
            CGFloat left = _recordStart.x - at.x;

            if (up > MAXLockSlide) {
                _recordLocked = YES;
                _recordCancelling = NO;
                [self refreshRecordBar];
                [self.view setNeedsLayout];
                return;
            }

            BOOL cancelling = (left > MAXCancelSlide);
            if (cancelling != _recordCancelling) {
                _recordCancelling = cancelling;
                [self refreshRecordBar];
            }
            return;
        }

        case UIGestureRecognizerStateEnded:
            _recordStarted = NO;
            if (_recordLocked) return;          // писать продолжаем без пальца
            if (_recordCancelling) [self cancelRecording];
            else [self finishRecording];
            return;

        // Нажатие отобрали не пальцем, а самой системой — звонком,
        // блокировкой, её же вопросом о разрешении. Начатую запись
        // заканчиваем как обычно: бросать снятое из-за этого незачем.
        case UIGestureRecognizerStateCancelled:
        case UIGestureRecognizerStateFailed:
            _recordStarted = NO;
            if (!_recordLocked) [self finishRecording];
            return;

        default:
            return;
    }
}

/// Разрешение система спрашивает в тот миг, когда оборудование впервые
/// открывают, — и, спрашивая, отбирает у кнопки нажатие. Для приложения это
/// выглядит как отпущенный палец: запись кончалась бы, не начавшись. Поэтому
/// первый раз мы только спрашиваем, а пишем со следующего удержания.
///
/// Возвращает YES, если вопрос задан и записывать сейчас не надо.
- (BOOL)askedForPermission {
    __weak MAXChatViewController *weakSelf = self;

    if (_noteMode && ![MAXVideoNoteRecorder permissionSettled]) {
        [MAXVideoNoteRecorder askPermission:^(BOOL granted) {
            MAXChatViewController *strongSelf = weakSelf;
            if (strongSelf == nil) return;

            [strongSelf showAlert:(granted ? @"Камера разрешена" : @"Камера запрещена")
                          message:(granted
                                   ? @"Удерживайте кнопку ещё раз, чтобы снять кружок."
                                   : @"Разрешить её можно в настройках телефона.")];
        }];
        return YES;
    }

    if (![MAXVoiceRecorder permissionSettled]) {
        [MAXVoiceRecorder askPermission:^(BOOL granted) {
            MAXChatViewController *strongSelf = weakSelf;
            if (strongSelf == nil) return;

            [strongSelf showAlert:(granted ? @"Микрофон разрешён" : @"Микрофон запрещён")
                          message:(granted
                                   ? @"Удерживайте кнопку ещё раз, чтобы записать."
                                   : @"Разрешить его можно в настройках телефона.")];
        }];
        return YES;
    }

    return NO;
}

- (void)beginRecording {
    if ([MAXVoiceRecorder shared].recording) return;
    if ([MAXVideoNoteRecorder shared].recording) return;

    if ([self askedForPermission]) return;

    [self.view endEditing:YES];

    // Играющее голосовое и микрофон делят звук: одно другому мешает, и
    // слушать своё же эхо во время записи незачем.
    if ([MAXVoicePlayer shared].messageId != nil) [[MAXVoicePlayer shared] stop];

    if (_noteMode) {
        [self beginNote];
        return;
    }

    NSString *problem = nil;
    if (![[MAXVoiceRecorder shared] startWithProblem:&problem]) {
        [self showAlert:@"Запись не пошла" message:problem ?: @"Микрофон недоступен"];
        return;
    }

    [self showRecordBar];
}

/// Общее начало для голосового и кружка: полоса поверх строки ввода и часы.
- (void)showRecordBar {
    _recordLevels = [NSMutableArray array];
    _recordBar.hidden = NO;
    [_composer bringSubviewToFront:_recordBar];

    [self refreshRecordBar];
    [self.view setNeedsLayout];

    [_recordTimer invalidate];
    _recordTimer = [NSTimer scheduledTimerWithTimeInterval:0.1
                                                    target:self
                                                  selector:@selector(recordTick)
                                                  userInfo:nil
                                                   repeats:YES];
}

#pragma mark - Кружок

/// Круглое окошко предпросмотра поверх переписки.
///
/// Здесь это просто скруглённый угол в половину стороны — обрезать по кругу
/// слой iOS умеет сам. На Windows Phone ради того же круга пришлось
/// складывать шестнадцать повёрнутых обрезок: тамошняя разметка обрезать
/// умеет только прямоугольником.
- (void)beginNote {
    MAXVideoNoteRecorder *note = [MAXVideoNoteRecorder shared];

    // Полосу показываем сразу, не дожидаясь камеры: включается она до
    // секунды, и всё это время экран иначе не отвечал бы ничем.
    [self showRecordBar];

    __weak MAXChatViewController *weakSelf = self;
    [note startWithCompletion:^(BOOL ready, NSString *problem) {
        MAXChatViewController *strongSelf = weakSelf;
        if (strongSelf == nil) return;

        if (!ready) {
            if (problem != nil) {
                [strongSelf showAlert:@"Съёмка не пошла" message:problem];
            }
            [strongSelf hideNoteWindow];
            [strongSelf stopRecordUi];
            return;
        }

        // Палец могли убрать, пока включалась камера, — тогда снимать уже
        // нечего и не для кого.
        if (!strongSelf->_recordStarted && !strongSelf->_recordLocked) {
            [note cancel];
            [strongSelf stopRecordUi];
            return;
        }

        [strongSelf showNoteWindow:note.previewLayer];
    }];
}

- (void)showNoteWindow:(CALayer *)preview {
    CGFloat side = 240.0;

    if (_noteWindow == nil) {
        _noteWindow = [[UIView alloc] initWithFrame:CGRectZero];
        _noteWindow.backgroundColor = [UIColor blackColor];
        _noteWindow.layer.cornerRadius = side / 2.0;
        _noteWindow.layer.masksToBounds = YES;
        // Слой не ловит касаний: палец в это время лежит на кнопке записи, и
        // перехватить его здесь значило бы оборвать съёмку в тот же миг.
        _noteWindow.userInteractionEnabled = NO;
        [self.view addSubview:_noteWindow];

        _noteRing = [CAShapeLayer layer];
        _noteRing.fillColor = NULL;
        _noteRing.strokeColor = [[UIColor colorWithRed:0.88 green:0.25 blue:0.25 alpha:1.0] CGColor];
        _noteRing.lineWidth = 5.0;
        _noteRing.lineCap = kCALineCapRound;
    }

    CGRect bounds = self.view.bounds;
    _noteWindow.frame = CGRectMake((bounds.size.width - side) / 2.0,
                                   (bounds.size.height - side) / 2.0 - 40.0,
                                   side, side);

    preview.frame = _noteWindow.bounds;
    [_noteWindow.layer insertSublayer:preview atIndex:0];

    // Кольцо рисуется поверх окошка, а не внутри: внутри его срезала бы та же
    // обрезка, что делает окошко круглым.
    _noteRing.frame = _noteWindow.frame;
    [self.view.layer addSublayer:_noteRing];

    _noteWindow.hidden = NO;
    _noteRing.hidden = NO;
    [self.view bringSubviewToFront:_noteWindow];
    [self updateNoteRing:0];
}

- (void)updateNoteRing:(CGFloat)part {
    if (_noteRing == nil) return;

    CGFloat side = _noteRing.bounds.size.width;
    CGFloat radius = side / 2.0 - 2.5;

    UIBezierPath *path =
        [UIBezierPath bezierPathWithArcCenter:CGPointMake(side / 2.0, side / 2.0)
                                       radius:radius
                                   startAngle:-M_PI_2
                                     endAngle:-M_PI_2 + 2.0 * M_PI * part
                                    clockwise:YES];
    _noteRing.path = [path CGPath];
}

- (void)hideNoteWindow {
    _noteWindow.hidden = YES;
    _noteRing.hidden = YES;

    // Слой предпросмотра принадлежит съёмке и уходит вместе с ней.
    for (CALayer *layer in [_noteWindow.layer.sublayers copy]) {
        if ([layer isKindOfClass:[AVCaptureVideoPreviewLayer class]]) {
            [layer removeFromSuperlayer];
        }
    }
}

- (void)recordTick {
    MAXVoiceRecorder *recorder = [MAXVoiceRecorder shared];
    MAXVideoNoteRecorder *note = [MAXVideoNoteRecorder shared];

    NSTimeInterval elapsed = note.recording ? note.elapsed
                           : (recorder.recording ? recorder.elapsed : -1);
    if (elapsed < 0) return;

    NSInteger seconds = (NSInteger)elapsed;
    _recordTime.text = [NSString stringWithFormat:@"%ld:%02ld",
                        (long)(seconds / 60), (long)(seconds % 60)];

    if (note.recording) {
        // Минута — предел; кольцо по краю окошка показывает, сколько от неё
        // осталось, а на исходе съёмка заканчивается сама.
        CGFloat part = elapsed / [MAXVideoNoteRecorder longest];
        [self updateNoteRing:(part > 1.0 ? 1.0 : part)];

        if (elapsed >= [MAXVideoNoteRecorder longest]) [self finishRecording];
        return;
    }

    // Живой график едет справа налево: столбиков ровно столько, сколько
    // помещается, лишнее слева уходит.
    [_recordLevels addObject:@(recorder.level)];

    NSUInteger fits = (NSUInteger)(_recordWave.bounds.size.width / 3.0);
    if (fits > 0 && _recordLevels.count > fits) {
        [_recordLevels removeObjectsInRange:NSMakeRange(0, _recordLevels.count - fits)];
    }
    _recordWave.bars = [_recordLevels copy];
}

- (void)refreshRecordBar {
    _recordCancel.hidden = !_recordLocked;
    _recordSend.hidden = !_recordLocked;
    _recordHint.hidden = _recordLocked;

    _recordHint.text = _recordCancelling
        ? @"Отпустите — отмена"
        : @"\u2190 отмена, \u2191 закрепить";
    _recordHint.textColor = _recordCancelling
        ? [MAXTheme destructiveColor]
        : [MAXTheme secondaryTextColor];
}

- (void)stopRecordUi {
    [_recordTimer invalidate];
    _recordTimer = nil;

    _recordBar.hidden = YES;
    _recordLocked = NO;
    _recordCancelling = NO;
    _recordLevels = nil;
    _recordWave.bars = @[];
    _recordTime.text = @"";
}

- (void)cancelRecording {
    [[MAXVoiceRecorder shared] cancel];
    [[MAXVideoNoteRecorder shared] cancel];
    [self hideNoteWindow];
    [self stopRecordUi];
}

/// Слишком короткая запись — это промах по кнопке, а не сообщение.
- (void)tooShort {
    [self stopRecordUi];
    [self setHeaderStatus:@"слишком коротко"];
    [NSObject cancelPreviousPerformRequestsWithTarget:self
                                             selector:@selector(updateHeader)
                                               object:nil];
    [self performSelector:@selector(updateHeader) withObject:nil afterDelay:1.5];
}

- (void)finishRecording {
    if ([MAXVideoNoteRecorder shared].recording) {
        [self finishNote];
        return;
    }

    MAXVoiceRecorder *recorder = [MAXVoiceRecorder shared];
    if (!recorder.recording) {
        [self stopRecordUi];
        return;
    }

    if (recorder.elapsed < 0.6) {
        [recorder cancel];
        [self tooShort];
        return;
    }

    [self stopRecordUi];
    [self setUploading:YES status:@"Обработка записи…"];

    __weak MAXChatViewController *weakSelf = self;
    [recorder stopWithCompletion:^(MAXVoiceTake *take) {
        MAXChatViewController *strongSelf = weakSelf;
        if (strongSelf == nil) return;

        if (take.data.length == 0) {
            [strongSelf setUploading:NO status:nil];
            [strongSelf showAlert:@"Голосовое"
                          message:take.error ?: @"Записать не получилось"];
            return;
        }
        [strongSelf uploadVoice:take];
    }];
}

- (void)finishNote {
    MAXVideoNoteRecorder *note = [MAXVideoNoteRecorder shared];

    if (note.elapsed < 0.6) {
        [note cancel];
        [self hideNoteWindow];
        [self tooShort];
        return;
    }

    [self hideNoteWindow];
    [self stopRecordUi];
    [self setUploading:YES status:@"Обработка кружка…"];

    __weak MAXChatViewController *weakSelf = self;
    [note stopWithCompletion:^(MAXNoteTake *take) {
        MAXChatViewController *strongSelf = weakSelf;
        if (strongSelf == nil) return;

        if (take.data.length == 0) {
            [strongSelf setUploading:NO status:nil];
            [strongSelf showAlert:@"Кружок"
                          message:take.error ?: @"Снять не получилось"];
            return;
        }
        [strongSelf uploadNote:take];
    }];
}

/// Заливка и отправка кружка. Вид записи для CDN — 1; у голосового он 2.
- (void)uploadNote:(MAXNoteTake *)take {
    [self setUploading:YES status:@"Отправка кружка…"];

    long long replyTo = [_replyToMessage.messageId longLongValue];
    [self cancelComposerMode];

    NSData *data = take.data;
    NSInteger duration = take.durationMs;

    __weak MAXChatViewController *weakSelf = self;
    [[MAXUploader shared] uploadMedia:data
                                 kind:1
                           completion:^(NSString *token, long long fileId, NSError *error) {
        MAXChatViewController *strongSelf = weakSelf;
        if (strongSelf == nil) return;

        if (error != nil) {
            [strongSelf setUploading:NO status:nil];
            [strongSelf showAlert:@"Кружок не ушёл" message:error.localizedDescription];
            return;
        }

        [[MAXMessagesModule shared] sendVideoNoteToken:token
                                                toChat:strongSelf->_chat.chatId
                                            durationMs:duration
                                      replyToMessageId:replyTo
                                            completion:^(NSString *messageId,
                                                         NSError *sendError) {
            MAXChatViewController *inner = weakSelf;
            if (inner == nil) return;

            [inner setUploading:NO status:nil];

            if (sendError != nil) {
                [inner showAlert:@"Кружок не ушёл" message:sendError.localizedDescription];
                return;
            }
            [inner loadHistory];
        }];
    }];
}

/// Заливка и отправка голосового. Вид записи для CDN — 2; у кружка он 1.
- (void)uploadVoice:(MAXVoiceTake *)take {
    [self setUploading:YES status:@"Отправка голосового…"];

    long long replyTo = [_replyToMessage.messageId longLongValue];
    [self cancelComposerMode];

    __weak MAXChatViewController *weakSelf = self;
    [[MAXUploader shared] uploadMedia:take.data
                                 kind:2
                           completion:^(NSString *token, long long fileId, NSError *error) {
        MAXChatViewController *strongSelf = weakSelf;
        if (strongSelf == nil) return;

        if (error != nil) {
            [strongSelf setUploading:NO status:nil];
            [strongSelf showAlert:@"Голосовое не ушло" message:error.localizedDescription];
            return;
        }

        [[MAXMessagesModule shared] sendVoiceToken:token
                                            toChat:strongSelf->_chat.chatId
                                        durationMs:take.durationMs
                                              wave:take.wave
                                  replyToMessageId:replyTo
                                        completion:^(NSString *messageId, NSError *sendError) {
            MAXChatViewController *inner = weakSelf;
            if (inner == nil) return;

            [inner setUploading:NO status:nil];

            if (sendError != nil) {
                [inner showAlert:@"Голосовое не ушло" message:sendError.localizedDescription];
                return;
            }
            [inner loadHistory];
        }];
    }];
}

#pragma mark - Вложения: отправка

- (void)showAttachmentOptions {
    [self.view endEditing:YES];

    if (_uploading) {
        [self showAlert:@"Подождите" message:@"Предыдущее вложение ещё отправляется"];
        return;
    }

    // Какой камерой снимать кружок — здесь же, а не на самой кнопке записи:
    // снимают удержанием, и мгновения на выбор там нет. Выбирают заранее и
    // надолго, поэтому место ему в списке, а не на виду.
    NSString *camera = [MAXVideoNoteRecorder shared].front
        ? @"Кружок: основной камерой"
        : @"Кружок: передней камерой";

    UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:nil
                                                       delegate:self
                                              cancelButtonTitle:@"Отмена"
                                         destructiveButtonTitle:nil
                                              otherButtonTitles:@"Фото из галереи",
                                                                @"Файл из Documents",
                                                                @"Стикер",
                                                                camera, nil];
    [sheet showInView:self.view];
}

- (void)attachmentSheet:(UIActionSheet *)actionSheet clickedButtonAtIndex:(NSInteger)buttonIndex {
    if (buttonIndex == actionSheet.cancelButtonIndex) return;

    if (buttonIndex == 0) {
        [self pickPhoto];
    } else if (buttonIndex == 1) {
        [self pickFile];
    } else if (buttonIndex == 2) {
        [self pickSticker];
    } else if (buttonIndex == 3) {
        MAXVideoNoteRecorder *note = [MAXVideoNoteRecorder shared];
        note.front = !note.front;

        [self setHeaderStatus:(note.front
                               ? @"кружок: передней камерой"
                               : @"кружок: основной камерой")];
        [NSObject cancelPreviousPerformRequestsWithTarget:self
                                                 selector:@selector(updateHeader)
                                                   object:nil];
        [self performSelector:@selector(updateHeader) withObject:nil afterDelay:2.0];
    }
}

- (void)pickSticker {
    MAXStickerPickerViewController *picker =
        [[MAXStickerPickerViewController alloc] init];
    picker.delegate = self;

    UINavigationController *stack =
        [[UINavigationController alloc] initWithRootViewController:picker];
    [MAXTheme applyToNavigationBar:stack.navigationBar];
    [self presentViewController:stack animated:YES completion:nil];
}

- (void)stickerPicker:(MAXStickerPickerViewController *)picker
       didPickSticker:(MAXSticker *)sticker {
    [picker dismissViewControllerAnimated:YES completion:nil];
    if (sticker.stickerId == 0) return;

    // Ответ стикером сервер понимает так же, как ответ текстом, — поэтому
    // полоска ответа снимается здесь же, а не остаётся висеть.
    long long replyTo = [_replyToMessage.messageId longLongValue];
    [self cancelComposerMode];

    __weak MAXChatViewController *weakSelf = self;
    [[MAXMessagesModule shared] sendSticker:sticker.stickerId
                                     toChat:_chat.chatId
                           replyToMessageId:replyTo
                                 completion:^(NSString *messageId, NSError *error) {
        MAXChatViewController *strongSelf = weakSelf;
        if (strongSelf == nil) return;

        if (error != nil) {
            [strongSelf showAlert:@"Стикер не отправился" message:error.localizedDescription];
            return;
        }
        [strongSelf loadHistory];
    }];
}

- (void)pickPhoto {
    if (![UIImagePickerController isSourceTypeAvailable:
          UIImagePickerControllerSourceTypePhotoLibrary]) {
        [self showAlert:@"Галерея недоступна" message:nil];
        return;
    }

    UIImagePickerController *picker = [[UIImagePickerController alloc] init];
    picker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
    picker.delegate = self;

    // На планшете галерею нельзя показывать модально: UIKit бросает
    // исключение «UIImagePickerController must be presented via
    // UIPopoverController» — и приложение снимается прямо в момент, когда
    // пользователь только что разрешил доступ к фотографиям.
    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
        _photoPopover = [[UIPopoverController alloc] initWithContentViewController:picker];
        [_photoPopover presentPopoverFromRect:_attachButton.frame
                                       inView:_composer
                     permittedArrowDirections:UIPopoverArrowDirectionAny
                                     animated:YES];
        return;
    }

    [self presentViewController:picker animated:YES completion:nil];
}

/// Галерея закрывается по-разному: модальный экран — сам, попап — только
/// через свой контроллер, `dismissViewControllerAnimated:` его не заметит.
- (void)dismissPhotoPicker {
    if (_photoPopover != nil) {
        [_photoPopover dismissPopoverAnimated:YES];
        _photoPopover = nil;
        return;
    }
    [self dismissViewControllerAnimated:YES completion:nil];
}

/// Своего выбора файлов на iOS 6 нет — UIDocumentPicker появился только в iOS 8.
/// Зато включён UIFileSharingEnabled, поэтому в Documents можно положить что
/// угодно через iTunes, и мы показываем именно эту папку.
- (void)pickFile {
    MAXFilePickerViewController *picker = [[MAXFilePickerViewController alloc] init];

    __weak MAXChatViewController *weakSelf = self;
    picker.completion = ^(NSString *path) {
        MAXChatViewController *strongSelf = weakSelf;
        if (strongSelf == nil || path == nil) return;
        [strongSelf uploadFileAtPath:path];
    };

    UINavigationController *stack =
        [[UINavigationController alloc] initWithRootViewController:picker];
    [MAXTheme applyToNavigationBar:stack.navigationBar];
    [self presentViewController:stack animated:YES completion:nil];
}

- (void)imagePickerController:(UIImagePickerController *)picker
        didFinishPickingMediaWithInfo:(NSDictionary *)info {
    UIImage *image = info[UIImagePickerControllerOriginalImage];
    [self dismissPhotoPicker];
    if (image == nil) return;

    // 0.8 — компромисс: на iPhone 4S снимок в оригинале это 2–3 МБ, а канал
    // у таких устройств обычно небыстрый.
    NSData *data = UIImageJPEGRepresentation(image, 0.8);
    [self setUploading:YES status:@"Отправка фото…"];

    __weak MAXChatViewController *weakSelf = self;
    [[MAXUploader shared] uploadPhoto:data
                             fileName:@"photo.jpg"
                           completion:^(NSString *token, long long fileId, NSError *error) {
        MAXChatViewController *strongSelf = weakSelf;
        if (strongSelf == nil) return;

        if (error != nil) {
            [strongSelf setUploading:NO status:nil];
            [strongSelf showAlert:@"Фото не отправилось" message:error.localizedDescription];
            return;
        }

        [[MAXMessagesModule shared] sendPhotoToken:token
                                            toChat:strongSelf->_chat.chatId
                                           caption:nil
                                        completion:^(NSString *messageId, NSError *sendError) {
            [strongSelf setUploading:NO status:nil];
            if (sendError != nil) {
                [strongSelf showAlert:@"Фото не отправилось"
                              message:sendError.localizedDescription];
                return;
            }
            [strongSelf loadHistory];
        }];
    }];
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker {
    [self dismissPhotoPicker];
}

- (void)uploadFileAtPath:(NSString *)path {
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (data.length == 0) {
        [self showAlert:@"Файл пуст или не читается" message:nil];
        return;
    }

    NSString *name = [path lastPathComponent];
    [self setUploading:YES status:[NSString stringWithFormat:@"Отправка %@…", name]];

    __weak MAXChatViewController *weakSelf = self;
    [[MAXUploader shared] uploadFile:data
                            fileName:name
                          completion:^(NSString *token, long long fileId, NSError *error) {
        MAXChatViewController *strongSelf = weakSelf;
        if (strongSelf == nil) return;

        if (error != nil) {
            [strongSelf setUploading:NO status:nil];
            [strongSelf showAlert:@"Файл не отправился" message:error.localizedDescription];
            return;
        }

        [[MAXMessagesModule shared] sendFileToken:token
                                           fileId:fileId
                                             name:name
                                           toChat:strongSelf->_chat.chatId
                                       completion:^(NSString *messageId, NSError *sendError) {
            [strongSelf setUploading:NO status:nil];
            if (sendError != nil) {
                [strongSelf showAlert:@"Файл не отправился"
                              message:sendError.localizedDescription];
                return;
            }
            [strongSelf loadHistory];
        }];
    }];
}

- (void)setUploading:(BOOL)uploading status:(NSString *)status {
    _uploading = uploading;
    _attachButton.enabled = !uploading;
    // Пока предыдущее вложение уезжает, второе начинать нечем: заливка тут
    // одна на экран, и вторая запись перебила бы её строку состояния.
    _micButton.enabled = !uploading;

    if (uploading) {
        [_spinner startAnimating];
        [self setHeaderStatus:(status ?: @"Отправка…")];
    } else {
        [_spinner stopAnimating];
        [self updateHeader];
    }
}

#pragma mark - Вложения: приём

- (void)messageCell:(MAXMessageCell *)cell didTapAttachment:(MAXAttachment *)attachment {
    if (attachment == nil) return;

    if (attachment.type == MAXAttachmentTypeVideo) {
        if (attachment.isVideoNote) [self playVideoNote:attachment inMessage:cell.message];
        else [self playVideo:attachment inMessage:cell.message];
        return;
    }
    if (attachment.type == MAXAttachmentTypeAudio) {
        [self playVoice:attachment inMessage:cell.message];
        return;
    }
    if (attachment.type == MAXAttachmentTypeSticker) {
        [self openStickerSet:attachment inMessage:cell.message];
        return;
    }
    if (attachment.type == MAXAttachmentTypePhoto) {
        [self openPhoto:attachment inMessage:cell.message];
        return;
    }
    [self downloadFile:attachment inMessage:cell.message];
}

/// Голосовое из переписки.
///
/// Играет оно не так, как ролик: Opus системный проигрыватель не открывает
/// вовсе, поэтому запись скачивается, раскодируется своей библиотекой и
/// играется уже обычным WAV. Всё это делает MAXVoicePlayer — здесь остаётся
/// добыть адрес.
- (void)playVoice:(MAXAttachment *)voice inMessage:(MAXMessage *)message {
    MAXVoicePlayer *player = [MAXVoicePlayer shared];

    // Нажали по тому, что играет, — остановить. Адрес для этого не нужен.
    if ([player.messageId isEqualToString:message.messageId]) {
        [player stop];
        return;
    }

    NSString *direct = voice.previewUrl.length > 0 ? voice.previewUrl : voice.baseUrl;
    if (direct.length > 0) {
        [player toggleMessage:message.messageId url:direct];
        return;
    }

    if (voice.fileId == 0) {
        [self showAlert:@"Голосовое" message:@"Сервер не дал ссылки на запись"];
        return;
    }

    [self setUploading:YES status:@"Получение ссылки…"];

    __weak MAXChatViewController *weakSelf = self;
    [[MAXMessagesModule shared] resolveFileURLForFileId:voice.fileId
                                                 chatId:_chat.chatId
                                              messageId:message.messageId
                                             completion:^(NSString *url, NSError *error) {
        MAXChatViewController *strongSelf = weakSelf;
        if (strongSelf == nil) return;
        [strongSelf setUploading:NO status:nil];

        if (error != nil || url.length == 0) {
            [strongSelf showAlert:@"Голосовое"
                          message:error.localizedDescription ?: @"Сервер не дал ссылки"];
            return;
        }
        [[MAXVoicePlayer shared] toggleMessage:message.messageId url:url];
    }];
}

#pragma mark - Кружок: показ на своём месте

/// Кружок играет не во весь экран, а там, где лежит, — кругом и с белой
/// полоской по краю.
///
/// Системным проигрывателем это не сделать вовсе, а на iOS 6 он вдобавок
/// падал: исключение брошено внутри AVFoundation, а позвала её MediaPlayer со
/// своей очереди, — поймать его снаружи нечем. Поэтому AVPlayer заводится
/// своими руками (MAXVideoNotePlayer), а кадр отдаётся слоем.
- (void)playVideoNote:(MAXAttachment *)note inMessage:(MAXMessage *)message {
    MAXVideoNotePlayer *player = [MAXVideoNotePlayer shared];

    // Нажали по тому, что играет, — остановить. Адрес для этого не нужен.
    if ([player.messageId isEqualToString:message.messageId]) {
        [player stop];
        return;
    }

    // Голос и кружок делят звук: слушать оба разом незачем.
    if ([MAXVoicePlayer shared].messageId != nil) [[MAXVoicePlayer shared] stop];

    [self setUploading:YES status:@"Получение ссылки…"];

    __weak MAXChatViewController *weakSelf = self;
    [[MAXMessagesModule shared] resolveVideoURLForVideoId:note.fileId
                                                    token:note.token
                                                   chatId:_chat.chatId
                                                messageId:message.messageId
                                               completion:^(NSString *url, NSError *error) {
        MAXChatViewController *strongSelf = weakSelf;
        if (strongSelf == nil) return;
        [strongSelf setUploading:NO status:nil];

        if (error != nil || url.length == 0) {
            [strongSelf showAlert:@"Кружок"
                          message:error.localizedDescription ?: @"Сервер не дал ссылки"];
            return;
        }
        [[MAXVideoNotePlayer shared] toggleMessage:message.messageId url:url];
    }];
}

- (void)noteStateChanged:(NSNotification *)note {
    MAXVideoNotePlayer *player = [MAXVideoNotePlayer shared];

    if (player.messageId == nil) {
        [_noteView removeFromSuperview];
        _noteView = nil;
        _noteCornered = NO;
        return;
    }

    if (_noteView == nil) {
        _noteView = [[MAXVideoNoteView alloc] initWithFrame:CGRectZero];

        UITapGestureRecognizer *tap =
            [[UITapGestureRecognizer alloc] initWithTarget:self
                                                    action:@selector(noteTapped)];
        [_noteView addGestureRecognizer:tap];
    }

    _noteView.preparing = player.preparing;
    _noteView.playerLayer = player.playerLayer;
    _noteView.progress = player.progress;

    [self layoutNoteView];
}

/// Нажатие по кружку: на своём месте — остановить, в углу — вернуться к его
/// сообщению.
- (void)noteTapped {
    if (!_noteCornered) {
        [[MAXVideoNotePlayer shared] stop];
        return;
    }

    NSUInteger index = [self indexOfMessageId:[MAXVideoNotePlayer shared].messageId];
    if (index == NSNotFound) return;

    [_tableView scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:(NSInteger)index inSection:0]
                     atScrollPosition:UITableViewScrollPositionMiddle
                             animated:YES];
}

- (NSUInteger)indexOfMessageId:(NSString *)messageId {
    if (messageId.length == 0) return NSNotFound;

    for (NSUInteger i = 0; i < _messages.count; i++) {
        if ([[_messages[i] messageId] isEqualToString:messageId]) return i;
    }
    return NSNotFound;
}

/// Положить кружок на место — или в угол, если место уехало за край.
///
/// Он живёт подвидом списка, а не ячейки: подвид списка лежит в его же
/// координатах содержимого и едет вместе с ним сам, ни на кадр не отставая, —
/// а из ячейки его унесло бы первое же переиспользование. Отставать он и не
/// может: это та самая беда, из-за которой на Windows Phone от круга
/// оставалась линза.
- (void)layoutNoteView {
    if (_noteView == nil) return;

    NSUInteger index = [self indexOfMessageId:[MAXVideoNotePlayer shared].messageId];
    if (index == NSNotFound) {
        [self cornerNoteView];
        return;
    }

    NSIndexPath *path = [NSIndexPath indexPathForRow:(NSInteger)index inSection:0];
    MAXMessageCell *cell = (MAXMessageCell *)[_tableView cellForRowAtIndexPath:path];

    CGRect place = cell != nil ? [cell videoNoteFrame] : CGRectZero;
    if (cell == nil || CGRectIsEmpty(place)) {
        [self cornerNoteView];
        return;
    }

    CGRect inTable = [_tableView convertRect:place fromView:cell];
    CGRect shown = CGRectMake(_tableView.contentOffset.x, _tableView.contentOffset.y,
                              _tableView.bounds.size.width, _tableView.bounds.size.height);

    // Наполовину вылезший кружок отставляем в угол целиком: половина круга
    // у края смотрится поломкой, а не решением.
    if (!CGRectContainsRect(shown, inTable)) {
        [self cornerNoteView];
        return;
    }

    _noteCornered = NO;

    if (_noteView.superview != _tableView) {
        [_noteView removeFromSuperview];
        [_tableView addSubview:_noteView];
    }
    _noteView.frame = inTable;
    [_tableView bringSubviewToFront:_noteView];
}

/// Сторона отставленного в угол кружка. Столько же, сколько на Windows Phone:
/// меньше — и лица не разобрать.
static const CGFloat MAXCorneredNoteSide = 128.0;

- (void)cornerNoteView {
    _noteCornered = YES;

    if (_noteView.superview != self.view) {
        [_noteView removeFromSuperview];
        [self.view addSubview:_noteView];
    }

    CGRect table = _tableView.frame;
    _noteView.frame = CGRectMake(CGRectGetMaxX(table) - MAXCorneredNoteSide - 10.0,
                                 table.origin.y + 10.0,
                                 MAXCorneredNoteSide, MAXCorneredNoteSide);
    [self.view bringSubviewToFront:_noteView];
}

/// Ролик из переписки.
///
/// Скачиванием файла его не взять: номер видео живёт в своём счёте, и
/// FILE_DOWNLOAD на него отвечает «файл не найден». Адрес спрашивается
/// отдельной командой.
///
/// Играется **скачанный файл**, а не поток, и проигрывателем своим, а не
/// системным. Системный на iOS 6 падал: исключение брошено внутри
/// AVFoundation, а позвала её MediaPlayer со своей очереди, — снаружи такое
/// ни поймать, ни поправить. А скачиваем сами потому, что своим корням верим
/// только мы: AVFoundation на iOS 6 проверяет цепочку системным хранилищем,
/// где корней этого CDN нет вовсе.
- (void)playVideo:(MAXAttachment *)video inMessage:(MAXMessage *)message {
    [self setUploading:YES status:@"Получение ссылки…"];

    __weak MAXChatViewController *weakSelf = self;
    [[MAXMessagesModule shared] resolveVideoURLForVideoId:video.fileId
                                                    token:video.token
                                                   chatId:_chat.chatId
                                                messageId:message.messageId
                                               completion:^(NSString *url, NSError *error) {
        MAXChatViewController *strongSelf = weakSelf;
        if (strongSelf == nil) return;

        if (error != nil || url.length == 0) {
            [strongSelf setUploading:NO status:nil];
            [strongSelf showAlert:@"Видео"
                          message:error.localizedDescription ?: @"Сервер не дал ссылки"];
            return;
        }
        [strongSelf setUploading:NO status:nil];
        [strongSelf play:url named:(video.name ?: @"Видео") size:video.size];
    }];
}

/// Ролик играется потоком: проигрывателю отдаётся местный адрес, а наружу
/// за ним ходит наш посредник (MAXStreamServer) — кусками и по мере
/// надобности. Начинается всё сразу, ждать скачивания целиком не нужно, и
/// предел на размер тоже больше не нужен: в памяти ролик не лежит.
///
/// Посредник может и не подняться — сокет на петле всё-таки. Тогда остаётся
/// прежний путь: скачать целиком и открыть файлом. Там предел есть.
- (void)play:(NSString *)url named:(NSString *)name size:(long long)size {
    NSURL *local = [MAXStreamServer localURLForRemoteURL:url name:name];

    if (local != nil) {
        MAXVideoViewController *screen =
            [[MAXVideoViewController alloc] initWithURL:local title:name];
        [self presentViewController:screen animated:YES completion:nil];
        return;
    }

    NSLog(@"[Max/Видео] поток не завёлся — качаем целиком");

    if (size > MAXVideoLargest) {
        [self showAlert:@"Видео"
                message:@"Ролик слишком велик, чтобы скачать его целиком, "
                        @"а играть потоком не вышло."];
        return;
    }
    [self downloadAndPlay:url named:name];
}

- (void)downloadAndPlay:(NSString *)url named:(NSString *)name {
    [self setUploading:YES status:@"Загрузка видео…"];

    __weak MAXChatViewController *weakSelf = self;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSData *video = [MAXHttp dataWithContentsOfURLString:url];

        NSString *path = nil;
        NSString *facts = [MAXMp4Facts describe:video];

        // Что именно приехало — в журнал. «Не удалось открыть видео» говорит
        // сама система, и почему — не объясняет; разбирать приходится самим.
        // Тут видно всё, что для этого нужно: части файла (есть ли `moov`,
        // нет ли `moof` — рваный файл старая прошивка не открывает вовсе),
        // марку и профиль H.264.
        NSLog(@"[Max/Видео] скачано %lu Б; %@", (unsigned long)video.length, facts);

        if (video.length > 0 && video.length <= MAXVideoLargest) {
            NSArray *dirs = NSSearchPathForDirectoriesInDomains(NSCachesDirectory,
                                                                 NSUserDomainMask, YES);
            NSString *folder = [dirs[0] stringByAppendingPathComponent:@"videos"];

            // Папка чистится перед каждым роликом: имя у файла своё на
            // каждый адрес, и старые копии иначе копились бы в кэше.
            [[NSFileManager defaultManager] removeItemAtPath:folder error:NULL];
            [[NSFileManager defaultManager] createDirectoryAtPath:folder
                                     withIntermediateDirectories:YES
                                                      attributes:nil
                                                           error:NULL];

            // Имя своё на каждый ролик, а не одно на все: AVFoundation
            // помнит разобранное по адресу файла, и второй ролик под тем же
            // именем она может принять за первый.
            NSString *fileName = [NSString stringWithFormat:@"video-%08lx.mp4",
                                  (unsigned long)[url hash]];

            path = [folder stringByAppendingPathComponent:fileName];
            if (![video writeToFile:path atomically:YES]) path = nil;
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            MAXChatViewController *strongSelf = weakSelf;
            if (strongSelf == nil) return;

            [strongSelf setUploading:NO status:nil];

            if (path == nil) {
                [strongSelf showAlert:@"Видео" message:@"Не удалось загрузить ролик"];
                return;
            }

            // Файл скачался, но роликом не оказался — так бывает, когда по
            // ссылке приезжает страница с ошибкой. Системе такое показывать
            // незачем: она ответит невнятным «не удалось открыть».
            if ([facts hasSuffix:@"части не разбираются"] || [facts isEqualToString:@"пусто"]) {
                [strongSelf showAlert:@"Видео"
                              message:@"По ссылке приехал не ролик. Попробуйте ещё раз."];
                return;
            }

            MAXVideoViewController *screen =
                [[MAXVideoViewController alloc] initWithFilePath:path title:name];
            [strongSelf presentViewController:screen animated:YES completion:nil];
        });
    });
}

/// Нажатие по строке «Переслано от …».
///
/// Порт `_openForwardedSource` из chat_screen.dart, с одной вынужденной
/// заменой. У Komet развилка такая: канал — открыть его на исходном сообщении,
/// человек — открыть карточку профиля. Экрана профиля в порте нет, поэтому для
/// человека открывается диалог с ним, как это делает вкладка «Контакты».
/// К самому сообщению это не ведёт — у Komet тоже не ведёт.
- (void)messageCellDidTapForwardedSource:(MAXMessageCell *)cell {
    MAXMessage *message = cell.message;
    if (message.forwardedPayload == nil) return;

    if (message.forwardedIsChannel) {
        [self openForwardedChannelForMessage:message];
        return;
    }

    long long senderId = message.forwardedSenderId;
    if (senderId == 0 || senderId == [MAXChatsModule shared].currentUserId) return;

    MAXContactViewController *card =
        [[MAXContactViewController alloc] initWithContactId:senderId];
    [self.navigationController pushViewController:card animated:YES];
}

/// Нажатие по цитате — к самому цитируемому сообщению.
///
/// Обычно оно уже в загруженном окне: отвечают, как правило, на недавнее, —
/// тогда просто отматываем список. Если нет, история перезагружается окном,
/// заканчивающимся этим сообщением, тем же путём, что и переход к источнику
/// пересылки.
- (void)messageCellDidTapReply:(MAXMessageCell *)cell {
    NSString *targetId = cell.message.replyMessageId;
    if (targetId.length == 0) {
        [self showAlert:@"Ответ" message:@"Сервер не сказал, на какое сообщение"];
        return;
    }

    for (NSUInteger i = 0; i < _messages.count; i++) {
        MAXMessage *candidate = _messages[i];
        if (![candidate.messageId isEqualToString:targetId]) continue;

        [_tableView scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:(NSInteger)i inSection:0]
                          atScrollPosition:UITableViewScrollPositionMiddle
                                  animated:YES];
        return;
    }

    self.initialMessageId = targetId;
    self.initialMessageTime = cell.message.replyTime;
    [self loadHistory];
}

/// Нажатие по размеченному тексту.
///
/// Обрезать нажатие ровно по ссылке разметка не даёт: подпись знает про свои
/// строки, а не про то, где какое слово лежит, а разбирать это самому значило
/// бы считать раскладку букв руками. Поэтому одна ссылка открывается сразу, а
/// когда их несколько — предлагается выбрать.
- (void)messageCellDidTapLinks:(MAXMessageCell *)cell {
    MAXMessage *message = cell.message;
    NSArray *links = [MAXRichText linksInText:message.text ranges:message.markupRanges];
    if (links.count == 0) return;

    if (links.count == 1) {
        [self openLink:links[0]];
        return;
    }

    _linkTitles = links;

    UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:@"Ссылки"
                                                       delegate:self
                                              cancelButtonTitle:nil
                                         destructiveButtonTitle:nil
                                              otherButtonTitles:nil];
    for (NSString *link in links) [sheet addButtonWithTitle:link];
    sheet.cancelButtonIndex = [sheet addButtonWithTitle:@"Отмена"];
    [sheet showInView:self.view];
}

- (void)openLink:(NSString *)address {
    NSURL *url = [MAXRichText absoluteURLFromString:address];
    if (url == nil) {
        [self showAlert:@"Ссылка" message:@"Адрес не разобрать"];
        return;
    }
    if (![[UIApplication sharedApplication] openURL:url]) {
        [self showAlert:@"Ссылка" message:@"Открыть это приложением не вышло"];
    }
}

/// Профиль отправителя — по аватарке или имени над пузырём. У Komet то же
/// действие висит на аватарке (`onAvatarTap`).
/// Нажали «Т» на голосовом.
///
/// Чат знает то, чего не знает ячейка: свой номер. Сам же вопрос серверу и
/// ожидание ответа — в MAXTranscripts, сюда возвращается только уведомление
/// о том, что показывать стало что-то новое.
- (void)messageCellDidTapTranscribe:(MAXMessageCell *)cell {
    MAXMessage *message = cell.message;
    MAXAttachment *voice = message.voiceAttachment;

    if (voice == nil || voice.fileId == 0 || message.messageId.length == 0) return;

    [[MAXTranscripts shared] toggleForMessageId:message.messageId
                                         chatId:_chat.chatId
                                        mediaId:voice.fileId];
}

/// Расшифровка появилась, сменилась или свернулась — строка перерисовывается
/// целиком: от текста под голосовым меняется её высота.
- (void)transcriptChanged:(NSNotification *)note {
    NSString *messageId = note.userInfo[@"messageId"];
    if (messageId.length == 0) return;

    for (NSUInteger i = 0; i < _messages.count; i++) {
        MAXMessage *message = _messages[i];
        if ([message.messageId isEqualToString:messageId]) {
            [self reloadRowAtIndex:i];
            return;
        }
    }
}

- (void)messageCellDidTapSender:(MAXMessageCell *)cell {
    long long senderId = cell.message.senderId;
    if (senderId == 0) return;

    MAXContactViewController *card =
        [[MAXContactViewController alloc] initWithContactId:senderId];
    [self.navigationController pushViewController:card animated:YES];
}

- (void)openForwardedChannelForMessage:(MAXMessage *)message {
    long long sourceChatId = message.forwardedChatId;
    if (sourceChatId == 0) {
        [self showAlert:@"Источник" message:@"Сервер не сказал, откуда переслано"];
        return;
    }

    // Пересылка внутри того же чата: никуда не уходим, просто отматываем
    // историю к исходному сообщению.
    if (sourceChatId == _chat.chatId) {
        if (message.forwardedMessageId.length == 0) return;
        self.initialMessageId = message.forwardedMessageId;
        self.initialMessageTime = message.forwardedTime;
        [self loadHistory];
        return;
    }

    MAXChat *source = [[MAXChatsModule shared] chatWithId:sourceChatId];
    if (source == nil) {
        // Komet в этом месте зовёт ensureChatCached (CHAT_INFO); здесь такого
        // ещё нет, поэтому открыть можно только то, что уже в списке.
        [self showAlert:@"Источник" message:@"Канала нет в списке чатов"];
        return;
    }

    MAXChatViewController *screen = [[MAXChatViewController alloc] initWithChat:source];
    screen.initialMessageId = message.forwardedMessageId;
    screen.initialMessageTime = message.forwardedTime;
    [self.navigationController pushViewController:screen animated:YES];
}

/// Нажали на стикер — показываем набор, из которого он взят, а не сам
/// стикер покрупнее: крупнее он ничего не объясняет, а из набора видно, что
/// там ещё есть, и его можно взять себе.
///
/// Номер набора в сообщении не лежит — только номер стикера, поэтому набор
/// ищется по нему уже на самом экране. Если и номера стикера нет (старое
/// сообщение или незнакомый вид вложения), открывается как раньше, картинкой.
- (void)openStickerSet:(MAXAttachment *)sticker inMessage:(MAXMessage *)message {
    if (sticker.stickerId == 0) {
        [self openPhoto:sticker inMessage:message];
        return;
    }

    MAXStickerSetViewController *screen =
        [[MAXStickerSetViewController alloc] initWithStickerId:sticker.stickerId];

    UINavigationController *stack =
        [[UINavigationController alloc] initWithRootViewController:screen];
    [MAXTheme applyToNavigationBar:stack.navigationBar];
    [self presentViewController:stack animated:YES completion:nil];
}

- (void)openPhoto:(MAXAttachment *)photo inMessage:(MAXMessage *)message {
    if (photo.previewUrl.length > 0) {
        // Снимки одного сообщения открываются группой, чтобы их можно было
        // листать. Те, у кого прямой ссылки нет, в неё не попадают: страница
        // с пустотой посреди листания хуже, чем группа на одну короче.
        NSMutableArray *urls = [NSMutableArray array];
        NSUInteger start = 0;

        for (MAXAttachment *item in message.photoAttachments) {
            if (item.previewUrl.length == 0) continue;
            // Ролики в листание не берём: там просмотрщик картинок, и кадр
            // из видео посреди снимков открыть было бы нечем.
            if (item.type == MAXAttachmentTypeVideo) continue;
            if (item == photo) start = urls.count;
            [urls addObject:item.previewUrl];
        }

        if (urls.count == 0) [urls addObject:photo.previewUrl];

        [self presentPhotoViewerWithURLs:urls startIndex:start];
        return;
    }

    // Прямой ссылки нет — просим её у сервера тем же запросом, что и для файлов.
    [self setUploading:YES status:@"Загрузка фото…"];

    __weak MAXChatViewController *weakSelf = self;
    [[MAXMessagesModule shared] resolveDownloadURLForBaseURL:photo.baseUrl
                                                       token:photo.token
                                                  completion:^(NSString *url, NSError *error) {
        MAXChatViewController *strongSelf = weakSelf;
        if (strongSelf == nil) return;
        [strongSelf setUploading:NO status:nil];

        if (error != nil) {
            [strongSelf showAlert:@"Не удалось открыть фото" message:error.localizedDescription];
            return;
        }
        [strongSelf presentPhotoViewerWithURL:url];
    }];
}

- (void)presentPhotoViewerWithURL:(NSString *)url {
    [self presentPhotoViewerWithURLs:(url.length > 0 ? @[url] : @[]) startIndex:0];
}

- (void)presentPhotoViewerWithURLs:(NSArray *)urls startIndex:(NSUInteger)startIndex {
    MAXPhotoViewController *viewer = [[MAXPhotoViewController alloc] initWithImageURLs:urls
                                                                           startIndex:startIndex];
    UINavigationController *stack =
        [[UINavigationController alloc] initWithRootViewController:viewer];
    [MAXTheme applyToNavigationBar:stack.navigationBar];
    [self presentViewController:stack animated:YES completion:nil];
}

/// Ссылка на файл добывается так же, как в Komet (`getFileUrl`): по `fileId`
/// вместе с чатом и сообщением. Прежний путь — baseUrl с токеном — остался
/// запасным: у части вложений идентификатора нет, зато есть адрес.
- (void)downloadFile:(MAXAttachment *)file inMessage:(MAXMessage *)message {
    [self setUploading:YES status:@"Получение ссылки…"];

    __weak MAXChatViewController *weakSelf = self;
    void (^finish)(NSString *, NSError *) = ^(NSString *url, NSError *error) {
        MAXChatViewController *strongSelf = weakSelf;
        if (strongSelf == nil) return;

        if (error != nil) {
            [strongSelf setUploading:NO status:nil];
            [strongSelf showAlert:@"Не удалось скачать" message:error.localizedDescription];
            return;
        }
        [strongSelf saveFileFromURL:url named:file.name];
    };

    if (file.fileId != 0) {
        [[MAXMessagesModule shared] resolveFileURLForFileId:file.fileId
                                                     chatId:_chat.chatId
                                                  messageId:message.messageId
                                                 completion:^(NSString *url, NSError *error) {
            if (error == nil) {
                finish(url, nil);
                return;
            }
            // Не вышло по идентификатору — пробуем по адресу с токеном.
            [[MAXMessagesModule shared]
                resolveDownloadURLForBaseURL:(file.baseUrl ?: file.previewUrl)
                                       token:file.token
                                  completion:finish];
        }];
        return;
    }

    [[MAXMessagesModule shared] resolveDownloadURLForBaseURL:(file.baseUrl ?: file.previewUrl)
                                                       token:file.token
                                                  completion:finish];
}

/// Файл кладётся в Documents: оттуда его видно в iTunes и в других
/// приложениях — своего «Файлы» на iOS 6 ещё нет. А сразу после — открывается
/// просмотрщиком системы, если она такой вид понимает: держать документ в
/// папке, которую нечем открыть, было полдела.
- (void)saveFileFromURL:(NSString *)url named:(NSString *)name {
    [self setHeaderStatus:@"Скачивание…"];

    NSString *fileName = name.length > 0 ? name : [url lastPathComponent];
    if (fileName.length == 0) fileName = @"file.bin";

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSData *data = [MAXHttp dataWithContentsOfURLString:url];

        NSString *documents = [NSSearchPathForDirectoriesInDomains(
            NSDocumentDirectory, NSUserDomainMask, YES) objectAtIndex:0];
        NSString *path = [documents stringByAppendingPathComponent:fileName];
        BOOL saved = data.length > 0 && [data writeToFile:path atomically:YES];

        dispatch_async(dispatch_get_main_queue(), ^{
            [self setUploading:NO status:nil];
            if (!saved) {
                [self showAlert:@"Не удалось скачать" message:@"Сервер не отдал файл"];
                return;
            }

            if ([MAXQuickLook showFileAtPath:path from:self]) return;

            // Такой вид система показывать не умеет — тогда хотя бы сказать,
            // куда файл лёг.
            [self showAlert:@"Сохранено"
                    message:[NSString stringWithFormat:@"%@ — в папке Documents", fileName]];
        });
    });
}

- (void)showAlert:(NSString *)title message:(NSString *)message {
    id alert = [MAXTheme alertWithTitle:title
                              message:message
                             delegate:nil
                    cancelButtonTitle:@"OK"
                     otherButtonTitle:nil];
    [alert show];
}

/// Кэш контактов пополнился — перерисовываем видимые пузыри. Прокрутку не
/// трогаем: имя может доехать в любой момент, и дёргать список под пальцем
/// было бы хуже, чем показать номер лишнюю секунду.
- (void)contactsChanged:(NSNotification *)note {
    // Шапка тоже держится на контактах: у диалога и название, и номер под ним
    // берутся из карточки собеседника, а она приезжает позже самого чата.
    // Сюда же приходит присутствие из пуша NOTIF_PRESENCE.
    if (_chat.isDialog) {
        long long otherId =
            [_chat otherParticipantIdForCurrentUser:[MAXChatsModule shared].currentUserId];
        NSDictionary *presence = [[MAXChatsModule shared] presenceForContact:otherId];
        if (presence != nil) _presenceText = MAXPresenceText(presence);
    }

    if (!_uploading) [self updateHeader];
    [self refreshPinnedBar];
    [_tableView reloadData];
}

/// Пришло новое сообщение.
///
/// Список при этом больше не собирается заново: строка дописывается в конец,
/// а всё, что выше, не трогается вовсе — иначе переписка на миг пустела,
/// прокрутка сваливалась в начало, и её приходилось возвращать числом.
/// Отсюда были и мигание, и съезд на пару сообщений.
///
/// И вниз оно уводит, только если конец переписки и так на экране. Читаете
/// выше — список стоит на месте, а внизу справа появляется стрелка со
/// счётчиком: сколько пришло, пока вы читали. Пришедшее при этом не
/// отмечается прочитанным — его же ещё не видели.
- (void)messageReceived:(NSNotification *)note {
    NSNumber *chatId = note.userInfo[@"chatId"];
    if ([chatId longLongValue] != _chat.chatId) return;

    NSDictionary *map = note.userInfo[@"message"];
    MAXMessage *message = [MAXMessage messageFromServerMap:map chatId:_chat.chatId];
    if (message == nil) return;

    for (MAXMessage *existing in _messages) {
        if ([existing.messageId isEqualToString:message.messageId]) return;
    }

    BOOL atBottom = [self isNearBottom];

    [_messages addObject:message];
    [self resolveMessageAuthors];

    // Дописываем строку, а не собираем список заново, — иначе переписка на
    // миг пустеет и прокрутка сваливается в начало. Но только если таблица и
    // впрямь знает ровно на одну строку меньше: если она ещё ни разу не
    // спрашивала их число, вставка развалится несоответствием.
    NSInteger known = [_tableView numberOfRowsInSection:0];
    if (known == (NSInteger)_messages.count - 1) {
        NSIndexPath *last = [NSIndexPath indexPathForRow:known inSection:0];
        [_tableView insertRowsAtIndexPaths:@[last]
                          withRowAnimation:UITableViewRowAnimationNone];
    } else {
        [_tableView reloadData];
    }

    if (atBottom) {
        [self scrollToBottomAnimated:YES];
        [self markRead];
        return;
    }

    _unseenCount++;
    [self refreshJumpButton];
}

/// Собеседник набирает сообщение.
///
/// Сервер шлёт эту отметку раз в несколько секунд, пока набирают, и ничего
/// не шлёт, когда бросили. Поэтому надпись снимается сама: пришло — держим
/// шесть секунд, пришло снова — держим ещё столько же.
- (void)someoneTyping:(NSNotification *)note {
    if ([note.userInfo[@"chatId"] longLongValue] != _chat.chatId) return;
    if (_uploading) return;

    NSString *name = note.userInfo[@"name"];
    [self setHeaderStatus:_chat.isDialog
        ? @"печатает…"
        : [NSString stringWithFormat:@"%@ печатает…", name]];

    [_typingTimer invalidate];
    _typingTimer = [NSTimer scheduledTimerWithTimeInterval:6.0
                                                    target:self
                                                  selector:@selector(typingEnded)
                                                  userInfo:nil
                                                   repeats:NO];
}

- (void)typingEnded {
    _typingTimer = nil;
    if (!_uploading) [self updateHeader];
}

/// Сообщения удалили — у себя или у всех. Раньше удалённое оставалось на
/// экране до перезахода в чат: этот пуш не разбирался вовсе.
- (void)messagesDeleted:(NSNotification *)note {
    if ([note.userInfo[@"chatId"] longLongValue] != _chat.chatId) return;

    NSArray *ids = note.userInfo[@"messageIds"];
    if (ids.count == 0) return;

    NSMutableArray *left = [NSMutableArray array];
    for (MAXMessage *message in _messages) {
        if ([ids containsObject:message.messageId]) continue;
        [left addObject:message];
    }
    if (left.count == _messages.count) return;

    [_messages setArray:left];
    [_tableView reloadData];
}

/// Реакции на сообщение изменились — у собеседника или у нас с другого
/// устройства. Счётчики приходят готовыми, считать нечего.
- (void)reactionsChanged:(NSNotification *)note {
    if ([note.userInfo[@"chatId"] longLongValue] != _chat.chatId) return;

    NSString *messageId = note.userInfo[@"messageId"];
    if (messageId.length == 0) return;

    for (NSUInteger i = 0; i < _messages.count; i++) {
        MAXMessage *message = _messages[i];
        if (![message.messageId isEqualToString:messageId]) continue;

        [message applyReactionCounters:note.userInfo[@"counters"]];
        [self reloadRowAtIndex:i];
        return;
    }
}

/// Виден ли конец переписки. Запас в высоту пузыря: строго по краю кнопка
/// мигала бы на каждом касании списка.
- (BOOL)isNearBottom {
    if (_messages.count == 0) return YES;

    CGFloat bottom = _tableView.contentOffset.y + _tableView.bounds.size.height;
    return bottom >= _tableView.contentSize.height - 60.0;
}

- (void)refreshJumpButton {
    BOOL show = (_unseenCount > 0);
    _jumpButton.hidden = !show;
    if (!show) return;

    NSString *title = _unseenCount > 99
        ? @"↓ 99+"
        : [NSString stringWithFormat:@"↓ %lu", (unsigned long)_unseenCount];
    [_jumpButton setTitle:title forState:UIControlStateNormal];
    [self.view bringSubviewToFront:_jumpButton];
}

/// Долистали до конца — считаем прочитанным и убираем стрелку. Зовётся и по
/// нажатию на неё, и когда до конца добрались пальцем.
- (void)noteReachedBottom {
    if (_unseenCount == 0) return;
    _unseenCount = 0;
    [self refreshJumpButton];
    [self markRead];
}

- (void)jumpToBottom {
    [self scrollToBottomAnimated:YES];
    [self noteReachedBottom];
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    if (scrollView != _tableView) return;
    if (_unseenCount > 0 && [self isNearBottom]) [self noteReachedBottom];

    // Кружок едет вместе с содержимым сам, но за край он может уйти — тогда
    // место ему в углу.
    [self layoutNoteView];
}

- (void)scrollToBottomAnimated:(BOOL)animated {
    if (_messages.count == 0) return;
    NSIndexPath *last = [NSIndexPath indexPathForRow:(NSInteger)_messages.count - 1 inSection:0];
    [_tableView scrollToRowAtIndexPath:last
                      atScrollPosition:UITableViewScrollPositionBottom
                              animated:animated];
}

#pragma mark - Поворот

/// Высота пузыря считается от ширины таблицы, поэтому после поворота её надо
/// пересчитать заново — иначе сообщения обрезаются или висят с пустотой.
- (void)didRotateFromInterfaceOrientation:(UIInterfaceOrientation)fromInterfaceOrientation {
    [super didRotateFromInterfaceOrientation:fromInterfaceOrientation];

    // Сначала фреймы, потом содержимое: высота строки считается от ширины
    // таблицы, а она меняется здесь же. В обратном порядке первый же
    // пересчёт шёл бы по старой ширине.
    [self layoutComposerAndTable];
    [_tableView reloadData];
    [self scrollToBottomAnimated:NO];
}

- (BOOL)shouldAutorotate {
    return YES;
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return UIInterfaceOrientationMaskAllButUpsideDown;
}

/// Закрепление и снятие — один и тот же вызов, разница только в номере
/// сообщения: ноль означает «убрать».
- (void)setPinned:(long long)messageId {
    __weak MAXChatViewController *weakSelf = self;
    [[MAXChatsModule shared] setPinnedMessage:messageId
                                       inChat:_chat.chatId
                                       notify:YES
                                   completion:^(NSError *error) {
        MAXChatViewController *strongSelf = weakSelf;
        if (strongSelf == nil) return;

        if (error != nil) {
            [strongSelf showAlert:@"Не удалось" message:error.localizedDescription];
            return;
        }
        [strongSelf refreshPinnedBar];
    }];
}

/// Число подписчиков и участников приходит не в списке чатов, а в CHAT_INFO:
/// в списке `participantsCount` у каналов пуст, и под заголовком не было
/// ничего. Заодно оттуда же приезжает название канала, открытого из поиска.
- (void)refreshChatInfo {
    if (_chat.isDialog) return;

    __weak MAXChatViewController *weakSelf = self;
    [[MAXChatsModule shared] fetchInfoForChat:_chat.chatId
                                   completion:^(NSDictionary *info, NSError *error) {
        MAXChatViewController *strongSelf = weakSelf;
        if (strongSelf == nil || info == nil) return;

        id count = info[@"participantsCount"];
        if ([count isKindOfClass:[NSNumber class]]) {
            strongSelf->_chat.participantsCount = [count integerValue];
        }

        id title = info[@"title"];
        if (strongSelf->_chat.title.length == 0 && [title isKindOfClass:[NSString class]]) {
            strongSelf->_chat.title = title;
        }

        [strongSelf updateHeader];
    }];
}

#pragma mark - Фон переписки

/// Картинка перекрывает оттенок: она кладётся подложкой таблицы, а сама
/// таблица становится прозрачной. Оттенок при этом остаётся под ней — на
/// случай, если картинка не покрывает экран целиком.
- (void)applyWallpaper {
    _tableView.backgroundColor = [MAXWallpaper backgroundColor];
    self.view.backgroundColor = [MAXWallpaper backgroundColor];

    UIImage *image = [MAXWallpaper image];
    if (image == nil) {
        _tableView.backgroundView = nil;
        return;
    }

    UIImageView *wallpaper = [[UIImageView alloc] initWithImage:image];
    wallpaper.contentMode = UIViewContentModeScaleAspectFill;
    wallpaper.clipsToBounds = YES;
    _tableView.backgroundView = wallpaper;
    _tableView.backgroundColor = [UIColor clearColor];
}

- (void)wallpaperChanged:(NSNotification *)note {
    [self applyWallpaper];
}

#pragma mark - Закреплённое сообщение

/// Полоска показывается, только если чат знает о закрепе. Своего запроса для
/// этого нет — сведения приезжают вместе с чатом.
- (void)refreshPinnedBar {
    MAXChat *chat = [[MAXChatsModule shared] chatWithId:_chat.chatId] ?: _chat;
    BOOL hasPin = (chat.pinnedMessageId != 0);

    _pinnedBar.hidden = !hasPin;
    if (hasPin) {
        NSString *text = chat.pinnedMessageText.length > 0
            ? chat.pinnedMessageText : @"Сообщение";
        _pinnedLabel.text = [NSString stringWithFormat:@"Закреплено: %@", text];
    }

    [self.view setNeedsLayout];
}

- (void)openPinned {
    MAXChat *chat = [[MAXChatsModule shared] chatWithId:_chat.chatId] ?: _chat;
    if (chat.pinnedMessageId == 0) return;

    // Открывается тем же путём, что и найденное сообщение: окно истории
    // вокруг него и прокрутка к нужной строке.
    MAXChatViewController *screen = [[MAXChatViewController alloc] initWithChat:chat];
    screen.initialMessageId = [NSString stringWithFormat:@"%lld", chat.pinnedMessageId];
    screen.initialMessageTime = chat.pinnedMessageTime;
    [self.navigationController pushViewController:screen animated:YES];
}

#pragma mark - Клавиатура

- (void)keyboardWillShow:(NSNotification *)note {
    CGRect frame = [note.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
    CGRect converted = [self.view convertRect:frame fromView:nil];
    _keyboardHeight = self.view.bounds.size.height - converted.origin.y;
    [self layoutForKeyboardWithDuration:
     [note.userInfo[UIKeyboardAnimationDurationUserInfoKey] doubleValue]];
}

- (void)keyboardWillHide:(NSNotification *)note {
    _keyboardHeight = 0;
    [self layoutForKeyboardWithDuration:
     [note.userInfo[UIKeyboardAnimationDurationUserInfoKey] doubleValue]];
}

- (void)layoutForKeyboardWithDuration:(NSTimeInterval)duration {
    [UIView animateWithDuration:duration animations:^{
        [self layoutComposerAndTable];
    } completion:^(BOOL finished) {
        [self scrollToBottomAnimated:NO];
    }];
}

/// Единственное место, где считаются размеры строки ввода и списка.
///
/// Раньше они считались один раз в viewDidLoad и дальше держались на
/// autoresizingMask. Этого мало: границы вида на тот момент ещё не
/// окончательные — их правят и панель вкладок, и панель навигации, — так что
/// строка ввода оказывалась ниже видимой области. Пересчёт от текущих границ
/// заодно решает поворот и клавиатуру.
- (void)layoutComposerAndTable {
    CGRect bounds = self.view.bounds;
    CGFloat composerY = bounds.size.height - MAXComposerHeight - _keyboardHeight;

    // Полоска ответа стоит над строкой ввода и отнимает высоту у переписки.
    CGFloat bannerHeight = _composerBanner.hidden ? 0 : MAXComposerBannerHeight;
    _composerBanner.frame = CGRectMake(0, composerY - bannerHeight,
                                       bounds.size.width, MAXComposerBannerHeight);

    _composer.frame = CGRectMake(0, composerY, bounds.size.width, MAXComposerHeight);

    CGFloat pinnedHeight = _pinnedBar.hidden ? 0 : MAXPinnedBarHeight;
    _pinnedBar.frame = CGRectMake(0, 0, bounds.size.width, MAXPinnedBarHeight);
    _tableView.frame = CGRectMake(0, pinnedHeight, bounds.size.width,
                                  composerY - bannerHeight - pinnedHeight);
    _muteButton.frame = CGRectMake(0, 0, bounds.size.width, MAXComposerHeight);

    // Ширина кнопки — по её подписи: «Отправить» в капсулу под стрелку
    // не помещалось, а на планшете полоса в 54 pt смотрелась огрызком.
    CGFloat sendWidth = [_sendButton sizeThatFits:CGSizeZero].width + 16.0;
    if (sendWidth < 54.0) sendWidth = 54.0;

    _sendButton.frame = CGRectMake(bounds.size.width - sendWidth - 8.0, 6.0,
                                   sendWidth, MAXComposerHeight - 12.0);
    // Порядок тот же, что на Windows Phone: поле ввода, за ним скрепка, за
    // ней отправка (или запись на её месте). Слева скрепка стояла зря —
    // палец тянется к правому краю, где и кончается набор.
    CGFloat attachWidth = 34.0;
    CGFloat attachX = bounds.size.width - sendWidth - 8.0 - 6.0 - attachWidth;

    _attachButton.frame = CGRectMake(attachX, 6.0, attachWidth, MAXComposerHeight - 12.0);
    _micButton.frame = _sendButton.frame;

    _recordBar.frame = CGRectMake(0, 0, bounds.size.width, MAXComposerHeight);
    _recordDot.center = CGPointMake(18.0, MAXComposerHeight / 2.0);
    _recordTime.frame = CGRectMake(30.0, 0, 44.0, MAXComposerHeight);

    if (_recordLocked) {
        CGFloat buttons = 160.0;
        _recordWave.frame = CGRectMake(78.0, 12.0,
                                       MAX(bounds.size.width - buttons - 82.0, 20.0),
                                       MAXComposerHeight - 24.0);
        _recordHint.frame = CGRectZero;
        _recordCancel.frame = CGRectMake(bounds.size.width - buttons, 6.0,
                                         72.0, MAXComposerHeight - 12.0);
        _recordSend.frame = CGRectMake(bounds.size.width - 84.0, 6.0,
                                       76.0, MAXComposerHeight - 12.0);
    } else {
        CGFloat hint = 150.0;
        _recordWave.frame = CGRectMake(78.0, 12.0,
                                       MAX(bounds.size.width - hint - 86.0, 20.0),
                                       MAXComposerHeight - 24.0);
        _recordHint.frame = CGRectMake(bounds.size.width - hint - 8.0, 0,
                                       hint, MAXComposerHeight);
    }

    _inputField.frame = CGRectMake(8.0, 6.0,
                                   MAX(attachX - 14.0, 40.0),
                                   MAXComposerHeight - 12.0);
    _spinner.center = CGPointMake(bounds.size.width / 2.0, 40.0);
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self layoutComposerAndTable];
    [self layoutNoteView];
}

#pragma mark - UITableView

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)_messages.count;
}

- (BOOL)showSenderForMessageAtIndex:(NSUInteger)index {
    if (_chat.isDialog) return NO;

    MAXMessage *message = _messages[index];
    if (message.senderId == [MAXChatsModule shared].currentUserId) return NO;
    if (index == 0) return YES;

    MAXMessage *previous = _messages[index - 1];
    return previous.senderId != message.senderId;
}

/// Дата над сообщением — только у первого за этот день.
///
/// Считается по соседу сверху: история идёт по возрастанию времени, значит
/// «первое за день» — это то, у которого предыдущее сообщение из другого дня.
/// У самого верхнего дата есть всегда: что было до него, мы ещё не загрузили.
- (NSString *)dateTextForIndex:(NSUInteger)index {
    MAXMessage *message = _messages[index];
    if (message.time <= 0) return nil;

    if (index > 0) {
        MAXMessage *previous = _messages[index - 1];
        if ([MAXTheme isSameDayMilliseconds:previous.time and:message.time]) return nil;
    }

    return [MAXTheme daySeparatorFromMilliseconds:message.time];
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSUInteger index = (NSUInteger)indexPath.row;
    MAXMessage *message = _messages[index];

    return [MAXMessageCell heightForMessage:message
                                 showSender:[self showSenderForMessageAtIndex:index]
                                   dateText:[self dateTextForIndex:index]
                                      width:tableView.bounds.size.width];
}

- (UITableViewCell *)tableView:(UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *identifier = @"MAXMessageCell";

    MAXMessageCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    if (cell == nil) {
        cell = [[MAXMessageCell alloc] initWithStyle:UITableViewCellStyleDefault
                                     reuseIdentifier:identifier];
    }

    cell.delegate = self;

    NSUInteger index = (NSUInteger)indexPath.row;
    MAXMessage *message = _messages[index];
    BOOL outgoing = message.senderId == [MAXChatsModule shared].currentUserId;

    MAXContact *sender = [[MAXChatsModule shared] contactWithId:message.senderId];
    NSString *senderName = sender.name.length > 0
        ? sender.name
        : [NSString stringWithFormat:@"ID %lld", message.senderId];

    [cell configureWithMessage:message
                      outgoing:outgoing
                    senderName:senderName
               senderAvatarURL:sender.avatarUrl
                    showSender:[self showSenderForMessageAtIndex:index]
                       inGroup:!_chat.isDialog
                      dateText:[self dateTextForIndex:index]
                         width:tableView.bounds.size.width];
    return cell;
}

#pragma mark - Ввод

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [self sendMessage];
    return NO;
}

- (BOOL)textField:(UITextField *)textField
shouldChangeCharactersInRange:(NSRange)range
replacementString:(NSString *)string {
    // Кнопка меняется по набранному, а текст поля на этот миг ещё прежний:
    // считаем по тому, что получится.
    NSString *after = [textField.text stringByReplacingCharactersInRange:range
                                                              withString:string];
    NSString *trimmed = [after stringByTrimmingCharactersInSet:
                         [NSCharacterSet whitespaceAndNewlineCharacterSet]];

    BOOL typed = trimmed.length > 0;
    BOOL canWrite = [self isSubscribedChannel]
        && [_chat canWriteAsUser:[MAXChatsModule shared].currentUserId];

    _sendButton.hidden = !(canWrite && typed);
    _micButton.hidden = !(canWrite && !typed && _editingMessage == nil);

    if (typed) [[MAXMessagesModule shared] sendTypingToChat:_chat.chatId];
    return YES;
}

/// Строка уехала с экрана — движущимся стикерам в ней двигаться незачем.
/// Вернётся — заведутся заново: описание к тому времени уже скачано.
- (void)tableView:(UITableView *)tableView
  didEndDisplayingCell:(UITableViewCell *)cell
     forRowAtIndexPath:(NSIndexPath *)indexPath {
    if ([cell isKindOfClass:[MAXMessageCell class]]) {
        [(MAXMessageCell *)cell stopAnimations];
    }
}

#pragma mark - Оформление секций

- (void)tableView:(UITableView *)tableView
  willDisplayHeaderView:(UIView *)view
         forSection:(NSInteger)section {
    [MAXTheme applyToHeaderFooterView:view];
}

- (void)tableView:(UITableView *)tableView
  willDisplayFooterView:(UIView *)view
         forSection:(NSInteger)section {
    [MAXTheme applyToHeaderFooterView:view];
}

@end
