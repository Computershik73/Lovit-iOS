//
//  MAXChatMediaViewController.m
//

#import "MAXChatMediaViewController.h"
#import "MAXPhotoViewController.h"
#import "MAXTheme.h"
#import "MAXQuickLook.h"
#import "MAXChatsModule.h"
#import "MAXMessagesModule.h"
#import "MAXImageLoader.h"
#import "MAXHttp.h"
#import "MAXChat.h"
#import "MAXMessage.h"
#import "MAXAttachment.h"

static const CGFloat MAXMediaRowHeight = 60.0;
static const CGFloat MAXMediaThumbSize = 44.0;

@implementation MAXChatMediaViewController {
    MAXChat *_chat;
    UISegmentedControl *_tabs;
    UITableView *_tableView;
    UIActivityIndicatorView *_spinner;
    UILabel *_emptyLabel;

    NSArray *_items;          // MAXAttachment
    NSArray *_owners;         // MAXMessage под тем же индексом
    NSInteger _loadedTab;     // какая вкладка сейчас в _items
}

- (id)initWithChat:(MAXChat *)chat {
    self = [super init];
    if (self) {
        _chat = chat;
        _loadedTab = -1;
        self.hidesBottomBarWhenPushed = YES;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = @"Вложения";
    self.view.backgroundColor = [MAXTheme backgroundColor];

    if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)]) {
        self.edgesForExtendedLayout = UIRectEdgeNone;
    }

    CGRect bounds = self.view.bounds;

    _tabs = [[UISegmentedControl alloc] initWithItems:@[@"Медиа", @"Файлы", @"Ссылки"]];
    _tabs.frame = CGRectMake(10, 8, bounds.size.width - 20, 30);
    _tabs.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    _tabs.selectedSegmentIndex = 0;
    // На iOS 6 переключатель по умолчанию выпуклый и глянцевый; Bar — самый
    // спокойный из тамошних стилей, и в современной теме он к месту, а в
    // скевоморфной как раз уместна выпуклость.
    if ([_tabs respondsToSelector:@selector(setSegmentedControlStyle:)]) {
        _tabs.segmentedControlStyle = [MAXTheme isSkeuomorphic]
            ? UISegmentedControlStyleBordered
            : UISegmentedControlStyleBar;
    }
    _tabs.tintColor = [MAXTheme isSkeuomorphic] ? nil : [MAXTheme accentColor];
    [_tabs addTarget:self action:@selector(tabChanged) forControlEvents:UIControlEventValueChanged];
    [self.view addSubview:_tabs];

    _tableView = [[UITableView alloc] initWithFrame:
                  CGRectMake(0, 46, bounds.size.width, bounds.size.height - 46)
                                              style:UITableViewStylePlain];
    _tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth
                                | UIViewAutoresizingFlexibleHeight;
    _tableView.dataSource = self;
    _tableView.delegate = self;
    _tableView.rowHeight = MAXMediaRowHeight;
    [MAXTheme applyToTableView:_tableView];
    [self.view addSubview:_tableView];

    _emptyLabel = [[UILabel alloc] initWithFrame:_tableView.frame];
    _emptyLabel.textAlignment = NSTextAlignmentCenter;
    _emptyLabel.font = [UIFont systemFontOfSize:15.0];
    _emptyLabel.textColor = [MAXTheme secondaryTextColor];
    _emptyLabel.backgroundColor = [UIColor clearColor];
    _emptyLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth
                                 | UIViewAutoresizingFlexibleHeight;
    _emptyLabel.hidden = YES;
    [self.view addSubview:_emptyLabel];

    _spinner = [[UIActivityIndicatorView alloc]
                initWithActivityIndicatorStyle:[MAXTheme activityIndicatorStyle]];
    _spinner.center = CGPointMake(CGRectGetMidX(bounds), CGRectGetMidY(bounds));
    _spinner.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin
                              | UIViewAutoresizingFlexibleRightMargin
                              | UIViewAutoresizingFlexibleTopMargin
                              | UIViewAutoresizingFlexibleBottomMargin;
    [self.view addSubview:_spinner];

    [self reload];
}

- (void)tabChanged {
    [self reload];
}

/// Типы вложений для запроса и тип, который отбираем из ответа: сервер отдаёт
/// сообщения целиком, а в сообщении с картинкой может ехать ещё и текст.
- (NSArray *)requestedTypes {
    switch (_tabs.selectedSegmentIndex) {
        case 1: return @[@"FILE"];
        case 2: return @[@"SHARE"];
        default: return @[@"PHOTO", @"VIDEO"];
    }
}

- (BOOL)matchesTab:(MAXAttachment *)attachment {
    switch (_tabs.selectedSegmentIndex) {
        case 1: return attachment.type == MAXAttachmentTypeFile;
        case 2: return attachment.type == MAXAttachmentTypeOther;
        default: return attachment.type == MAXAttachmentTypePhoto
                     || attachment.type == MAXAttachmentTypeVideo;
    }
}

- (void)reload {
    NSInteger tab = _tabs.selectedSegmentIndex;
    if (tab == _loadedTab) return;

    _items = nil;
    _owners = nil;
    _emptyLabel.hidden = YES;
    [_tableView reloadData];
    [_spinner startAnimating];

    __weak MAXChatMediaViewController *weakSelf = self;
    [[MAXMessagesModule shared] fetchMediaForChat:_chat.chatId
                                  anchorMessageId:@"0"
                                      attachTypes:[self requestedTypes]
                                       completion:^(NSArray *messages, NSError *error) {
        MAXChatMediaViewController *strongSelf = weakSelf;
        if (strongSelf == nil) return;
        if (strongSelf->_tabs.selectedSegmentIndex != tab) return;

        [strongSelf->_spinner stopAnimating];
        strongSelf->_loadedTab = tab;

        if (error != nil) {
            strongSelf->_emptyLabel.text = error.localizedDescription;
            strongSelf->_emptyLabel.hidden = NO;
            return;
        }

        NSMutableArray *items = [NSMutableArray array];
        NSMutableArray *owners = [NSMutableArray array];

        for (MAXMessage *message in messages) {
            for (MAXAttachment *attachment in message.attachments) {
                if (![strongSelf matchesTab:attachment]) continue;
                [items addObject:attachment];
                [owners addObject:message];
            }
        }

        strongSelf->_items = items;
        strongSelf->_owners = owners;
        [strongSelf->_tableView reloadData];

        if (items.count == 0) {
            strongSelf->_emptyLabel.text = @"Пусто";
            strongSelf->_emptyLabel.hidden = NO;
        }
    }];
}

#pragma mark - UITableView

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)_items.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *identifier = @"MAXMediaCell";

    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    UIImageView *thumb = nil;

    if (cell == nil) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
                                      reuseIdentifier:identifier];
        thumb = [[UIImageView alloc] initWithFrame:
                 CGRectMake(12, (MAXMediaRowHeight - MAXMediaThumbSize) / 2.0,
                            MAXMediaThumbSize, MAXMediaThumbSize)];
        thumb.contentMode = UIViewContentModeScaleAspectFill;
        thumb.clipsToBounds = YES;
        thumb.layer.cornerRadius = 6.0;
        thumb.backgroundColor = [MAXTheme placeholderTileColor];
        thumb.tag = 200;
        [cell.contentView addSubview:thumb];
        cell.indentationLevel = 5;
        cell.indentationWidth = 10.0;
    } else {
        thumb = (UIImageView *)[cell.contentView viewWithTag:200];
    }

    [MAXTheme applyToCell:cell];
    MAXAttachment *attachment = _items[(NSUInteger)indexPath.row];
    MAXMessage *owner = _owners[(NSUInteger)indexPath.row];

    cell.textLabel.font = [UIFont systemFontOfSize:15.0];
    cell.detailTextLabel.font = [UIFont systemFontOfSize:12.0];
    cell.detailTextLabel.textColor = [MAXTheme secondaryTextColor];
    [MAXTheme setDisclosureOnCell:cell];

    NSString *when = [MAXTheme relativeDateFromMilliseconds:owner.time];

    if (attachment.type == MAXAttachmentTypeFile) {
        cell.textLabel.text = attachment.name.length > 0 ? attachment.name : @"Файл";
        NSString *size = [attachment humanReadableSize];
        cell.detailTextLabel.text = size.length > 0
            ? [NSString stringWithFormat:@"%@ · %@", size, when] : when;
    } else if (attachment.type == MAXAttachmentTypePhoto
               || attachment.type == MAXAttachmentTypeVideo) {
        cell.textLabel.text = attachment.type == MAXAttachmentTypeVideo ? @"Видео" : @"Фото";
        cell.detailTextLabel.text = when;
    } else {
        cell.textLabel.text = owner.text.length > 0 ? owner.text : @"Ссылка";
        cell.detailTextLabel.text = when;
    }

    thumb.image = nil;
    NSString *url = attachment.previewUrl;
    if (url.length > 0) {
        UIImage *cached = [[MAXImageLoader shared] cachedImageForURL:url size:0];
        if (cached != nil) {
            thumb.image = cached;
        } else {
            [[MAXImageLoader shared] loadOriginalImageForURL:url completion:^(UIImage *image) {
                // Ячейку могли переиспользовать, пока картинка ехала: если она
                // уже ушла под другую строку, картинка тут лишняя.
                if ([tableView cellForRowAtIndexPath:indexPath] != cell) return;
                thumb.image = image;
            }];
        }
    }

    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    MAXAttachment *attachment = _items[(NSUInteger)indexPath.row];

    if (attachment.type == MAXAttachmentTypePhoto && attachment.previewUrl.length > 0) {
        MAXPhotoViewController *viewer =
            [[MAXPhotoViewController alloc] initWithImageURL:attachment.previewUrl];
        UINavigationController *stack =
            [[UINavigationController alloc] initWithRootViewController:viewer];
        [MAXTheme applyToNavigationBar:stack.navigationBar];
        [self presentViewController:stack animated:YES completion:nil];
        return;
    }

    // Всё остальное — файлы, видео и ссылки — качается тем же путём, что
    // и вложение в переписке; отдельного проигрывателя в порте нет.
    MAXMessage *owner = _owners[(NSUInteger)indexPath.row];
    [self downloadAttachment:attachment fromMessage:owner];
}

- (void)downloadAttachment:(MAXAttachment *)attachment fromMessage:(MAXMessage *)message {
    self.title = @"Получение ссылки…";

    __weak MAXChatMediaViewController *weakSelf = self;
    void (^finish)(NSString *, NSError *) = ^(NSString *url, NSError *error) {
        MAXChatMediaViewController *strongSelf = weakSelf;
        if (strongSelf == nil) return;

        strongSelf.title = @"Вложения";
        if (error != nil || url.length == 0) {
            [strongSelf showAlert:@"Не удалось скачать"
                          message:error.localizedDescription ?: @"Сервер не дал ссылку"];
            return;
        }
        [strongSelf saveFileFromURL:url named:attachment.name];
    };

    if (attachment.fileId != 0) {
        [[MAXMessagesModule shared] resolveFileURLForFileId:attachment.fileId
                                                     chatId:_chat.chatId
                                                  messageId:message.messageId
                                                 completion:finish];
        return;
    }

    [[MAXMessagesModule shared]
        resolveDownloadURLForBaseURL:(attachment.baseUrl ?: attachment.previewUrl)
                               token:attachment.token
                          completion:finish];
}

- (void)saveFileFromURL:(NSString *)url named:(NSString *)name {
    self.title = @"Скачивание…";

    NSString *fileName = name.length > 0 ? name : [url lastPathComponent];
    if (fileName.length == 0) fileName = @"file.bin";

    __weak MAXChatMediaViewController *weakSelf = self;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSData *data = [MAXHttp dataWithContentsOfURLString:url];

        NSString *documents = [NSSearchPathForDirectoriesInDomains(
            NSDocumentDirectory, NSUserDomainMask, YES) objectAtIndex:0];
        NSString *path = [documents stringByAppendingPathComponent:fileName];
        BOOL saved = data.length > 0 && [data writeToFile:path atomically:YES];

        dispatch_async(dispatch_get_main_queue(), ^{
            MAXChatMediaViewController *strongSelf = weakSelf;
            if (strongSelf == nil) return;

            strongSelf.title = @"Вложения";
            if (!saved) {
                [strongSelf showAlert:@"Не удалось скачать" message:@"Сервер не отдал файл"];
                return;
            }

            // Скачанное сразу и показывается — тем же просмотрщиком системы,
            // что и в переписке.
            if ([MAXQuickLook showFileAtPath:path from:strongSelf]) return;

            [strongSelf showAlert:@"Сохранено"
                          message:[NSString stringWithFormat:@"%@ — в папке Documents",
                                   fileName]];
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
