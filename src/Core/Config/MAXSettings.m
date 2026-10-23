//
//  MAXSettings.m
//

#import "MAXSettings.h"

NSString *const MAXSettingsDidChangeNotification = @"MAXSettingsDidChangeNotification";

static NSString *const MAXGhostModeKey = @"ghost_mode";
static NSString *const MAXAntiReadKey = @"anti_read";
static NSString *const MAXAntiTypingKey = @"anti_typing";

@implementation MAXSettings

+ (BOOL)boolForKey:(NSString *)key {
    return [[NSUserDefaults standardUserDefaults] boolForKey:key];
}

+ (void)setBool:(BOOL)value forKey:(NSString *)key {
    [[NSUserDefaults standardUserDefaults] setBool:value forKey:key];
    [[NSUserDefaults standardUserDefaults] synchronize];
    [[NSNotificationCenter defaultCenter] postNotificationName:MAXSettingsDidChangeNotification
                                                        object:key];
}

+ (BOOL)ghostMode { return [self boolForKey:MAXGhostModeKey]; }
+ (void)setGhostMode:(BOOL)value { [self setBool:value forKey:MAXGhostModeKey]; }

+ (BOOL)antiRead { return [self boolForKey:MAXAntiReadKey]; }
+ (void)setAntiRead:(BOOL)value { [self setBool:value forKey:MAXAntiReadKey]; }

+ (BOOL)antiTyping { return [self boolForKey:MAXAntiTypingKey]; }
+ (void)setAntiTyping:(BOOL)value { [self setBool:value forKey:MAXAntiTypingKey]; }

+ (BOOL)interactive { return ![self ghostMode]; }

@end
