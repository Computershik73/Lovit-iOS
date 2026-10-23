//
//  MAXSticker.h
//  Max — стикер и набор стикеров.
//
//  Порт Lovit/Models/MaxSticker.cs, который сам порт StickerItem/StickerSet
//  из Komet.
//

#import <Foundation/Foundation.h>

@interface MAXSticker : NSObject

@property (nonatomic, assign) long long stickerId;
@property (nonatomic, copy) NSString *url;
@property (nonatomic, assign) long long setId;
@property (nonatomic, assign) CGFloat width;
@property (nonatomic, assign) CGFloat height;

/// Значки, по которым стикер ищут: «улыбка», «кот» и прочее.
@property (nonatomic, strong) NSArray *tags;

/// Движущийся стикер. Рисовать такое порт не умеет — Lottie это набор
/// указаний для отрисовки, а не картинка, — но неподвижная у него есть,
/// ею и обходимся.
@property (nonatomic, assign) BOOL isAnimated;

+ (instancetype)stickerFromMap:(NSDictionary *)map;

@end

@interface MAXStickerSet : NSObject

@property (nonatomic, assign) long long setId;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *iconUrl;

/// Номера стикеров. Сами стикеры приходят отдельным запросом: набор хранит
/// только состав.
@property (nonatomic, strong) NSArray *stickerIds;

+ (instancetype)setFromMap:(NSDictionary *)map;

@end
