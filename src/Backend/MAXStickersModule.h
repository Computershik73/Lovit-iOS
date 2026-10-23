//
//  MAXStickersModule.h
//  Max — наборы стикеров.
//
//  Устроено в два шага, и иначе нельзя: сначала сервер называет только номера
//  наборов, потом по этим номерам приходят сами наборы, и лишь в них — номера
//  стикеров, за которыми нужен третий запрос. Поэтому всё складывается в
//  память: перелистывая наборы, человек возвращается к одним и тем же, и
//  спрашивать их заново было бы расточительно.
//
//  Порт Lovit/Backend/StickersModule.cs.
//

#import <Foundation/Foundation.h>

@class MAXStickerSet, MAXSticker;

@interface MAXStickersModule : NSObject

+ (instancetype)shared;

/// Недавно отправленные — они идут первой вкладкой (MAXSticker).
@property (nonatomic, readonly) NSArray *recent;

/// Свои наборы в том порядке, в каком их держит сервер (MAXStickerSet).
@property (nonatomic, readonly) NSArray *sets;

/// Загрузить свои наборы и недавние. Второй раз ничего не спрашивает: панель
/// выбора открывают часто.
- (void)loadWithCompletion:(void (^)(NSError *error))completion;

/// Стикеры набора. Те, что уже в памяти, повторно не спрашиваются — а лежит
/// там обычно почти всё: наборы перелистывают туда-обратно.
- (void)stickersOfSet:(MAXStickerSet *)set
           completion:(void (^)(NSArray *stickers))completion;

/// Набор, из которого взят стикер. Сам стикер при этом тоже оказывается в
/// памяти: номер набора лежит в нём, а не в сообщении. Ноль — не нашлось.
- (void)setIdForSticker:(long long)stickerId
             completion:(void (^)(long long setId))completion;

/// Набор по номеру — с именем, значком и составом. Уже известный отдаётся
/// сразу, без запроса.
- (void)setWithId:(long long)setId
       completion:(void (^)(MAXStickerSet *set))completion;

/// Загрузить список своих наборов (тех, что «добавлены к себе»). Нужен
/// отдельно от общей загрузки: предпросмотр набора открывают и до того, как
/// человек хоть раз заглянул в панель выбора.
- (void)loadFavoritesWithCompletion:(void (^)(NSError *error))completion;

/// Есть ли набор среди своих. Осмысленно после loadFavorites.
- (BOOL)isFavorite:(long long)setId;

/// Добавить набор к себе или убрать. `ok` говорит, согласился ли сервер;
/// при согласии список своих правится здесь же.
- (void)favoriteSet:(long long)setId completion:(void (^)(BOOL ok))completion;
- (void)unfavoriteSet:(long long)setId completion:(void (^)(BOOL ok))completion;

/// Запомнить отправленный: он встаёт первым среди недавних. Сервер свой
/// список недавних ведёт сам, но узнаём мы о нём только при следующей
/// загрузке — до тех пор порядок держится здесь.
- (void)noteSent:(long long)stickerId;

/// Сбрасывает всё при смене аккаунта.
- (void)reset;

@end
