//
//  MAXQuickLook.m
//

#import "MAXQuickLook.h"

@implementation MAXQuickLook {
    NSURL *_file;
}

+ (BOOL)canShowFileAtPath:(NSString *)path {
    if (path.length == 0) return NO;
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) return NO;

    return [QLPreviewController canPreviewItem:[NSURL fileURLWithPath:path]];
}

+ (BOOL)showFileAtPath:(NSString *)path from:(UIViewController *)host {
    BOOL can = [self canShowFileAtPath:path];

    // Что за файл и взялась ли за него система — в журнал: когда просмотр не
    // складывается, сама она говорит только «не удалось открыть».
    NSDictionary *about = [[NSFileManager defaultManager] attributesOfItemAtPath:path
                                                                          error:NULL];
    NSLog(@"[Max/Просмотр] %@ (%@ Б): %@", [path lastPathComponent],
          about[NSFileSize] ?: @"?", can ? @"берётся" : @"не берётся");

    if (host == nil || !can) return NO;

    MAXQuickLook *preview = [[MAXQuickLook alloc] init];
    preview->_file = [NSURL fileURLWithPath:path];
    preview.dataSource = preview;

    // Показывается поверх всего: у просмотрщика свои полоски сверху и снизу
    // с кнопкой «Готово», и внутрь чужой навигации он не просится.
    [host presentViewController:preview animated:YES completion:nil];
    return YES;
}

#pragma mark - Что показывать

- (NSInteger)numberOfPreviewItemsInPreviewController:(QLPreviewController *)controller {
    return _file != nil ? 1 : 0;
}

- (id<QLPreviewItem>)previewController:(QLPreviewController *)controller
                    previewItemAtIndex:(NSInteger)index {
    return _file;
}

@end
