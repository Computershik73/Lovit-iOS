//
//  MAXFilePickerViewController.m
//

#import "MAXFilePickerViewController.h"
#import "MAXTheme.h"
#import "MAXIcons.h"

@implementation MAXFilePickerViewController {
    NSArray *_files;          // словари: name, path, size
    UILabel *_emptyLabel;
}

- (id)init {
    return [super initWithStyle:UITableViewStylePlain];
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = @"Файлы";
    [MAXTheme applyToTableView:self.tableView];
    self.tableView.rowHeight = 56.0;
    self.navigationItem.leftBarButtonItem =
        [[UIBarButtonItem alloc] initWithTitle:@"Отмена"
                                         style:[MAXTheme barButtonStyle]
                                        target:self
                                        action:@selector(cancel)];

    _emptyLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _emptyLabel.text = @"В Documents пусто.\nПоложите файлы через iTunes.";
    _emptyLabel.numberOfLines = 2;
    _emptyLabel.textAlignment = NSTextAlignmentCenter;
    _emptyLabel.textColor = [MAXTheme secondaryTextColor];
    _emptyLabel.font = [UIFont systemFontOfSize:15.0];
    _emptyLabel.backgroundColor = [UIColor clearColor];
    [self.view addSubview:_emptyLabel];

    [self reload];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    _emptyLabel.frame = CGRectMake(20, 40, self.view.bounds.size.width - 40, 50);
}

- (void)cancel {
    if (self.completion != nil) self.completion(nil);
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)reload {
    NSString *documents = [NSSearchPathForDirectoriesInDomains(
        NSDocumentDirectory, NSUserDomainMask, YES) objectAtIndex:0];

    NSFileManager *manager = [NSFileManager defaultManager];
    NSArray *names = [manager contentsOfDirectoryAtPath:documents error:NULL];

    NSMutableArray *collected = [NSMutableArray array];
    for (NSString *name in names) {
        if ([name hasPrefix:@"."]) continue;

        NSString *path = [documents stringByAppendingPathComponent:name];

        BOOL directory = NO;
        if (![manager fileExistsAtPath:path isDirectory:&directory] || directory) continue;

        NSDictionary *attributes = [manager attributesOfItemAtPath:path error:NULL];
        [collected addObject:@{@"name": name,
                               @"path": path,
                               @"size": @([attributes fileSize])}];
    }

    _files = [collected sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a,
                                                                       NSDictionary *b) {
        return [a[@"name"] localizedCaseInsensitiveCompare:b[@"name"]];
    }];

    _emptyLabel.hidden = _files.count > 0;
    [self.tableView reloadData];
}

- (NSString *)describeSize:(long long)size {
    if (size < 1024) return [NSString stringWithFormat:@"%lld Б", size];
    if (size < 1024 * 1024) return [NSString stringWithFormat:@"%.0f КБ", size / 1024.0];
    return [NSString stringWithFormat:@"%.1f МБ", size / (1024.0 * 1024.0)];
}

#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)_files.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *identifier = @"MAXFileCell";

    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    if (cell == nil) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
                                      reuseIdentifier:identifier];
        cell.detailTextLabel.font = [UIFont systemFontOfSize:12.0];
        cell.detailTextLabel.textColor = [MAXTheme secondaryTextColor];
        cell.imageView.image = [MAXTheme iconNamed:@"file"
                                               size:28
                                              color:[MAXTheme accentColor]];
    }

    [MAXTheme applyToCell:cell];
    NSDictionary *file = _files[(NSUInteger)indexPath.row];
    cell.textLabel.text = file[@"name"];
    cell.detailTextLabel.text = [self describeSize:[file[@"size"] longLongValue]];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    NSDictionary *file = _files[(NSUInteger)indexPath.row];
    void (^completion)(NSString *) = self.completion;

    [self dismissViewControllerAnimated:YES completion:^{
        if (completion != nil) completion(file[@"path"]);
    }];
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
