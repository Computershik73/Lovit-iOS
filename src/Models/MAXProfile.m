//
//  MAXProfile.m
//

#import "MAXProfile.h"

@implementation MAXProfile

+ (instancetype)profileFromServerProfile:(NSDictionary *)map {
    if (![map isKindOfClass:[NSDictionary class]]) return nil;
    id contact = map[@"contact"];
    if (![contact isKindOfClass:[NSDictionary class]]) return nil;
    return [self profileFromContactMap:contact];
}

+ (instancetype)profileFromContactMap:(NSDictionary *)map {
    if (![map isKindOfClass:[NSDictionary class]]) return nil;
    id profileId = map[@"id"];
    if (![profileId isKindOfClass:[NSNumber class]]) return nil;

    MAXProfile *profile = [[MAXProfile alloc] init];
    profile.profileId = [profileId longLongValue];

    id names = map[@"names"];
    if ([names isKindOfClass:[NSArray class]] && [names count] > 0) {
        NSDictionary *chosen = nil;
        for (id entry in names) {
            if (![entry isKindOfClass:[NSDictionary class]]) continue;
            if (chosen == nil) chosen = entry;
            if ([((NSDictionary *)entry)[@"type"] isEqual:@"ONEME"]) {
                chosen = entry;
                break;
            }
        }
        id firstName = chosen[@"firstName"];
        id lastName = chosen[@"lastName"];
        profile.firstName = [firstName isKindOfClass:[NSString class]] ? firstName : @"";
        profile.lastName = [lastName isKindOfClass:[NSString class]] ? lastName : nil;
    } else {
        profile.firstName = @"";
    }

    id phone = map[@"phone"];
    profile.phone = [phone isKindOfClass:[NSNumber class]] ? [phone longLongValue] : 0;

    id avatar = map[@"baseUrl"];
    profile.avatarUrl = [avatar isKindOfClass:[NSString class]] ? avatar : nil;

    return profile;
}

- (NSString *)displayName {
    if (_lastName.length > 0) {
        return [NSString stringWithFormat:@"%@ %@", _firstName ?: @"", _lastName];
    }
    return _firstName.length > 0 ? _firstName : @"Профиль";
}

@end
