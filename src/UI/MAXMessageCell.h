//
//  MAXMessageCell.h
//  Max — пузырь сообщения.
//

#import <UIKit/UIKit.h>

@class MAXMessage, MAXMessageCell, MAXAttachment;

@protocol MAXMessageCellDelegate <NSObject>
/// Нажатие по картинке или по строке файла — открыть или скачать. Вложение
/// передаётся явно: картинок в сообщении бывает несколько, и по самой ячейке
/// уже не понять, какую из них выбрали.
- (void)messageCell:(MAXMessageCell *)cell didTapAttachment:(MAXAttachment *)attachment;
/// Нажатие по строке «Переслано от …» — открыть источник пересылки.
- (void)messageCellDidTapForwardedSource:(MAXMessageCell *)cell;
/// Нажатие по цитате — перейти к сообщению, на которое отвечают.
- (void)messageCellDidTapReply:(MAXMessageCell *)cell;
/// Нажатие по аватарке или имени отправителя — открыть его профиль.
- (void)messageCellDidTapSender:(MAXMessageCell *)cell;
/// Нажатие по тексту сообщения, в котором есть ссылки.
///
/// Обрезать нажатие по самой ссылке разметка не даёт: подпись знает про свои
/// строки, а не про то, где какое слово лежит. Поэтому спрашивается весь
/// текст, а какую из ссылок открыть — решает экран переписки.
- (void)messageCellDidTapLinks:(MAXMessageCell *)cell;

/// Нажали «Т» на голосовом — расшифровать его в текст или свернуть уже
/// расшифрованное.
- (void)messageCellDidTapTranscribe:(MAXMessageCell *)cell;
/// Долгое нажатие по пузырю — меню действий над сообщением.
- (void)messageCellDidLongPress:(MAXMessageCell *)cell;
@end

@interface MAXMessageCell : UITableViewCell

@property (nonatomic, weak) id<MAXMessageCellDelegate> delegate;
@property (nonatomic, strong, readonly) MAXMessage *message;

/// `showSender` — первое сообщение подряд идущих от одного человека: только
/// у него подписывается имя и рисуется аватарка. `inGroup` — групповой чат:
/// входящие пузыри сдвигаются, освобождая колонку под аватарку, и сдвигаются
/// все, иначе пузыри одной серии стояли бы уступом.
/// `width` — ширина таблицы, а не ячейки. Спрашивать её у самой ячейки нельзя:
/// у только что выданной из очереди она ещё прошлая (на iPad это 320 вместо
/// 1024), а высоту строки таблица считает по своей ширине. Раскладка и высота
/// расходились, и пузыри налезали друг на друга.
/// `dateText` — надпись с датой над пузырём: «Сегодня», «Вчера», «17 августа».
/// Ставится только у самого раннего сообщения дня, у остальных nil. Отдельной
/// строкой в таблице она не сделана намеренно: в переписке всё держится на
/// индексах сообщений, и лишняя строка сбила бы и прокрутку, и вставку новых.
- (void)configureWithMessage:(MAXMessage *)message
                    outgoing:(BOOL)outgoing
                  senderName:(NSString *)senderName
             senderAvatarURL:(NSString *)senderAvatarURL
                  showSender:(BOOL)showSender
                     inGroup:(BOOL)inGroup
                    dateText:(NSString *)dateText
                       width:(CGFloat)width;

/// Место кружка внутри ячейки, в её собственных координатах. CGRectZero,
/// если кружка в сообщении нет.
///
/// Нужно затем, чтобы играющий кружок лёг ровно на своё место в переписке:
/// сам он живёт не в ячейке, а в списке — иначе переиспользование ячеек
/// уносило бы его вместе с ними.
- (CGRect)videoNoteFrame;

/// Остановить движущиеся стикеры в этой строке — она ушла с экрана.
- (void)stopAnimations;

+ (CGFloat)heightForMessage:(MAXMessage *)message
                  showSender:(BOOL)showSender
                    dateText:(NSString *)dateText
                       width:(CGFloat)width;

@end
