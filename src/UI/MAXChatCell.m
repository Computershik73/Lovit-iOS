//
//  MAXChatCell.m
//

#import "MAXChatCell.h"
#import "MAXAvatarView.h"
#import "MAXTheme.h"
#import "MAXChat.h"
#import <QuartzCore/QuartzCore.h>

static const CGFloat MAXChatCellHeight = 72.0;
static const CGFloat MAXAvatarSize = 52.0;
static const CGFloat MAXSideMargin = 12.0;
static const CGFloat MAXTextGap = 12.0;

@implementation MAXChatCell {
    MAXAvatarView *_avatar;
    UILabel *_titleLabel;
    UIImageView *_verifiedBadge;
    UILabel *_previewLabel;
    UILabel *_timeLabel;
    UILabel *_unreadLabel;
}

+ (CGFloat)rowHeight {
    return MAXChatCellHeight;
}

/// Синяя галочка рисуется кодом: в связке нет графики, а фигура простая —
/// круг и две линии галочки.
+ (UIImage *)verifiedBadgeImage {
    // Кэш держится на теме, а не на dispatch_once: синий у светлой и тёмной
    // разный, и однажды нарисованная галочка осталась бы от прежней темы.
    static UIImage *badge = nil;
    static BOOL badgeIsDark = NO;

    if (badge == nil || badgeIsDark != [MAXTheme isDark]) {
        badgeIsDark = [MAXTheme isDark];

        CGFloat size = 16.0;
        UIGraphicsBeginImageContextWithOptions(CGSizeMake(size, size), NO,
                                               [UIScreen mainScreen].scale);
        CGContextRef context = UIGraphicsGetCurrentContext();

        CGContextSetFillColorWithColor(context, [[MAXTheme badgeColor] CGColor]);
        CGContextFillEllipseInRect(context, CGRectMake(0, 0, size, size));

        CGContextSetStrokeColorWithColor(context, [[UIColor whiteColor] CGColor]);
        CGContextSetLineWidth(context, 1.8);
        CGContextSetLineCap(context, kCGLineCapRound);
        CGContextSetLineJoin(context, kCGLineJoinRound);
        CGContextMoveToPoint(context, size * 0.28, size * 0.52);
        CGContextAddLineToPoint(context, size * 0.44, size * 0.68);
        CGContextAddLineToPoint(context, size * 0.74, size * 0.34);
        CGContextStrokePath(context);

        badge = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
    }
    return badge;
}

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.selectionStyle = UITableViewCellSelectionStyleDefault;

        _avatar = [[MAXAvatarView alloc] initWithFrame:
                   CGRectMake(MAXSideMargin, (MAXChatCellHeight - MAXAvatarSize) / 2.0,
                              MAXAvatarSize, MAXAvatarSize)];
        [self.contentView addSubview:_avatar];

        _titleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _titleLabel.font = [UIFont boldSystemFontOfSize:16.0];
        _titleLabel.textColor = [MAXTheme textColor];
        _titleLabel.backgroundColor = [UIColor clearColor];
        [self.contentView addSubview:_titleLabel];

        _verifiedBadge = [[UIImageView alloc] initWithImage:[MAXChatCell verifiedBadgeImage]];
        _verifiedBadge.hidden = YES;
        [self.contentView addSubview:_verifiedBadge];

        _previewLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _previewLabel.font = [UIFont systemFontOfSize:14.0];
        _previewLabel.textColor = [MAXTheme secondaryTextColor];
        _previewLabel.backgroundColor = [UIColor clearColor];
        [self.contentView addSubview:_previewLabel];

        _timeLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _timeLabel.font = [UIFont systemFontOfSize:12.0];
        _timeLabel.textColor = [MAXTheme secondaryTextColor];
        _timeLabel.textAlignment = NSTextAlignmentRight;
        _timeLabel.backgroundColor = [UIColor clearColor];
        [self.contentView addSubview:_timeLabel];

        _unreadLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _unreadLabel.font = [UIFont boldSystemFontOfSize:12.0];
        _unreadLabel.textColor = [UIColor whiteColor];
        _unreadLabel.textAlignment = NSTextAlignmentCenter;
        _unreadLabel.backgroundColor = [MAXTheme badgeColor];
        _unreadLabel.layer.cornerRadius = 10.0;
        _unreadLabel.clipsToBounds = YES;
        _unreadLabel.hidden = YES;
        [self.contentView addSubview:_unreadLabel];
    }
    return self;
}

- (void)configureWithChat:(MAXChat *)chat
                    title:(NSString *)title
                avatarURL:(NSString *)avatarURL {
    [_avatar setTitle:title avatarURL:avatarURL identifier:chat.chatId];

    _titleLabel.text = title;
    _previewLabel.text = chat.lastMessagePreview;
    _timeLabel.text = [MAXTheme relativeDateFromMilliseconds:chat.lastMessageTime];

    _verifiedBadge.hidden = !chat.isOfficial;

    if (chat.unreadCount > 0) {
        _unreadLabel.hidden = NO;
        _unreadLabel.text = chat.unreadCount > 99
            ? @"99+"
            : [NSString stringWithFormat:@"%ld", (long)chat.unreadCount];
    } else {
        _unreadLabel.hidden = YES;
    }

    [self setNeedsLayout];
}

- (void)layoutSubviews {
    [super layoutSubviews];

    CGFloat width = self.contentView.bounds.size.width;
    CGFloat textLeft = MAXSideMargin + MAXAvatarSize + MAXTextGap;

    // Время и счётчик забирают правый край, остальное достаётся тексту.
    CGSize timeSize = [_timeLabel.text sizeWithFont:_timeLabel.font];
    CGFloat timeWidth = MIN(timeSize.width + 2.0, 64.0);
    _timeLabel.frame = CGRectMake(width - MAXSideMargin - timeWidth, 16.0, timeWidth, 14.0);

    if (!_unreadLabel.hidden) {
        CGSize badgeSize = [_unreadLabel.text sizeWithFont:_unreadLabel.font];
        CGFloat badgeWidth = MAX(20.0, badgeSize.width + 12.0);
        _unreadLabel.frame = CGRectMake(width - MAXSideMargin - badgeWidth, 40.0,
                                        badgeWidth, 20.0);
    }

    CGFloat titleRight = width - MAXSideMargin - timeWidth - 8.0;
    CGFloat titleWidth = titleRight - textLeft;

    CGSize titleSize = [_titleLabel.text sizeWithFont:_titleLabel.font];
    CGFloat drawnTitle = MIN(titleSize.width, titleWidth);
    _titleLabel.frame = CGRectMake(textLeft, 15.0, drawnTitle, 19.0);

    if (!_verifiedBadge.hidden) {
        // Галочка идёт сразу за именем и не вылезает за отведённое поле.
        CGFloat badgeX = MIN(textLeft + drawnTitle + 5.0, titleRight - 16.0);
        _verifiedBadge.frame = CGRectMake(badgeX, 17.0, 16.0, 16.0);
    }

    CGFloat previewRight = _unreadLabel.hidden
        ? width - MAXSideMargin
        : CGRectGetMinX(_unreadLabel.frame) - 8.0;
    _previewLabel.frame = CGRectMake(textLeft, 39.0, previewRight - textLeft, 18.0);
}

@end
