//
//  MAXPhotoViewController.h
//  Max — просмотр картинки во весь экран с масштабированием и сохранением.
//
//  Снимки одного сообщения листаются свайпом: каждая страница — своя область
//  прокрутки со своим масштабом, снаружи — общая с постраничным режимом.
//

#import <UIKit/UIKit.h>

@interface MAXPhotoViewController : UIViewController <UIScrollViewDelegate>

/// Одна картинка — когда листать нечего (например, адрес добыт по FILE_DOWNLOAD).
- (id)initWithImageURL:(NSString *)imageURL;

/// Группа снимков одного сообщения, открытая на выбранном.
- (id)initWithImageURLs:(NSArray *)imageURLs startIndex:(NSUInteger)startIndex;

@end
