//
//  MAXStickerPickerViewController.h
//  Max — выбор стикера.
//
//  Отдельным экраном, а не панелью снизу: панель под строкой ввода отняла бы
//  у переписки половину экрана, а на телефонах тех лет её и так немного.
//  Сверху — вкладки наборов (первая «Недавние»), ниже — сетка.
//

#import <UIKit/UIKit.h>

@class MAXStickerPickerViewController, MAXSticker;

@protocol MAXStickerPickerDelegate <NSObject>
- (void)stickerPicker:(MAXStickerPickerViewController *)picker
         didPickSticker:(MAXSticker *)sticker;
@end

@interface MAXStickerPickerViewController : UIViewController <UIScrollViewDelegate>

@property (nonatomic, weak) id<MAXStickerPickerDelegate> delegate;

@end
