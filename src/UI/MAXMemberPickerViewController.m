//
//  MAXMemberPickerViewController.m
//

#import "MAXMemberPickerViewController.h"
#import "MAXAvatarView.h"
#import "MAXTheme.h"
#import "MAXChatsModule.h"
#import "MAXContact.h"

static const CGFloat MAXPickerRowHeight = 52.0;

@implementation MAXMemberPickerViewController {
    NSArray *_contacts;
    NSMutableSet *_selected;
    NSSet *_excluded;
}

- (id)initWithExcludedIds:(NSSet *)excludedIds {
    self = [super initWithStyle:UITableViewStylePlain];
    if (self) {
        _excluded = [excludedIds copy] ?: [NSSet set];
        _selected = [NSMutableSet set];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = @"Кого добавить";
    self.tableView.rowHeight = MAXPickerRowHeight;
    [MAXTheme applyToTableView:self.tableView];

    self.navigationItem.leftBarButtonItem =
        [[UIBarButtonItem alloc] initWithTitle:@"Отмена"
                                         style:[MAXTheme barButtonStyle]
                                        target:self
                                        action:@selector(cancel)];
    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithTitle:@"Добавить"
                                         style:UIBarButtonItemStyleDone
                                        target:self
                                        action:@selector(done)];
    self.navigationItem.rightBarButtonItem.enabled = NO;

    NSMutableArray *contacts = [NSMutableArray array];
    for (MAXContact *contact in [MAXChatsModule shared].contacts) {
        if ([_excluded containsObject:@(contact.contactId)]) continue;
        if (contact.contactId == [MAXChatsModule shared].currentUserId) continue;
        [contacts addObject:contact];
    }
    _contacts = contacts;
}

- (void)cancel {
    [self.delegate memberPicker:self didPickIds:@[]];
}

- (void)done {
    [self.delegate memberPicker:self didPickIds:[_selected allObjects]];
}

#pragma mark - UITableView

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)_contacts.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *identifier = @"MAXPickerCell";

    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    MAXAvatarView *avatar = nil;

    if (cell == nil) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
                                      reuseIdentifier:identifier];
        avatar = [[MAXAvatarView alloc] initWithFrame:CGRectMake(12, 8, 36, 36)];
        avatar.tag = 100;
        [cell.contentView addSubview:avatar];
        cell.indentationLevel = 4;
        cell.indentationWidth = 10.0;
    } else {
        avatar = (MAXAvatarView *)[cell.contentView viewWithTag:100];
    }

    [MAXTheme applyToCell:cell];
    MAXContact *contact = _contacts[(NSUInteger)indexPath.row];
    NSString *name = contact.name.length > 0
        ? contact.name
        : [NSString stringWithFormat:@"ID %lld", contact.contactId];

    cell.textLabel.text = name;
    cell.textLabel.font = [UIFont systemFontOfSize:16.0];
    [MAXTheme setCheckmark:[_selected containsObject:@(contact.contactId)] onCell:cell];

    [avatar setTitle:name avatarURL:contact.avatarUrl identifier:contact.contactId];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    MAXContact *contact = _contacts[(NSUInteger)indexPath.row];
    NSNumber *contactId = @(contact.contactId);

    if ([_selected containsObject:contactId]) {
        [_selected removeObject:contactId];
    } else {
        [_selected addObject:contactId];
    }

    self.navigationItem.rightBarButtonItem.enabled = _selected.count > 0;
    [tableView reloadRowsAtIndexPaths:@[indexPath]
                     withRowAnimation:UITableViewRowAnimationNone];
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
