//
//  MAXProfile.h
//  Max — профиль своего аккаунта из ответов AUTH / LOGIN / AUTH_CONFIRM.
//

#import <Foundation/Foundation.h>

@interface MAXProfile : NSObject

@property (nonatomic, assign) long long profileId;
@property (nonatomic, copy) NSString *firstName;
@property (nonatomic, copy) NSString *lastName;
@property (nonatomic, copy) NSString *avatarUrl;
@property (nonatomic, assign) long long phone;

@property (nonatomic, readonly) NSString *displayName;

/// Из `profile` серверного ответа (внутри лежит `contact`).
+ (instancetype)profileFromServerProfile:(NSDictionary *)map;

/// Из плоской карточки контакта.
+ (instancetype)profileFromContactMap:(NSDictionary *)map;

@end
