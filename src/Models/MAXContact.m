//
//  MAXContact.m
//

#import "MAXContact.h"

@implementation MAXContact

+ (NSString *)nameFromServerMap:(NSDictionary *)map {
    id names = map[@"names"];
    if (![names isKindOfClass:[NSArray class]] || [names count] == 0) return nil;

    NSDictionary *chosen = nil;
    for (id entry in names) {
        if (![entry isKindOfClass:[NSDictionary class]]) continue;
        if (chosen == nil) chosen = entry;
        if ([((NSDictionary *)entry)[@"type"] isEqual:@"ONEME"]) {
            chosen = entry;
            break;
        }
    }

    id name = chosen[@"name"];
    return [name isKindOfClass:[NSString class]] ? name : nil;
}

+ (instancetype)contactFromServerMap:(NSDictionary *)map {
    if (![map isKindOfClass:[NSDictionary class]]) return nil;
    id contactId = map[@"id"];
    if (![contactId isKindOfClass:[NSNumber class]]) return nil;

    MAXContact *contact = [[MAXContact alloc] init];
    contact.contactId = [contactId longLongValue];
    contact.name = [self nameFromServerMap:map];

    id names = map[@"names"];
    if ([names isKindOfClass:[NSArray class]]) {
        for (id entry in names) {
            if (![entry isKindOfClass:[NSDictionary class]]) continue;
            if (![((NSDictionary *)entry)[@"type"] isEqual:@"CUSTOM"]) continue;
            contact.isSavedContact = YES;
            break;
        }
    }

    id avatar = map[@"baseUrl"];
    contact.avatarUrl = [avatar isKindOfClass:[NSString class]] ? avatar : nil;

    id about = map[@"description"];
    if (![about isKindOfClass:[NSString class]]) about = map[@"about"];
    contact.about = [about isKindOfClass:[NSString class]] ? about : nil;

    id phone = map[@"phone"];
    contact.phone = [phone isKindOfClass:[NSNumber class]] ? [phone longLongValue] : 0;

    id options = map[@"options"];
    if ([options isKindOfClass:[NSArray class]]) {
        NSMutableSet *set = [NSMutableSet set];
        for (id option in options) {
            if ([option isKindOfClass:[NSString class]]) [set addObject:option];
        }
        contact.options = set;
    } else {
        contact.options = [NSSet set];
    }

    return contact;
}

@end
