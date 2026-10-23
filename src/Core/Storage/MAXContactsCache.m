//
//  MAXContactsCache.m
//

#import "MAXContactsCache.h"
#import "MAXContact.h"

/// Больше этого не храним. Тысяча карточек — около сотни килобайт; дальше
/// чтение при запуске уже дороже пользы: в списке видны первые несколько
/// десятков.
static const NSUInteger MAXContactsCacheLimit = 1000;

/// Чаще раза в пять секунд писать незачем.
static const NSTimeInterval MAXContactsCacheRest = 5.0;

static NSTimeInterval MAXContactsCacheSavedAt = 0.0;

/// Строка без разделителей: имя человека может содержать что угодно, а
/// табуляция и перевод строки здесь разбивают запись.
static NSString *MAXPlainField(NSString *text) {
    if (text.length == 0) return @"";
    NSCharacterSet *breaks = [NSCharacterSet characterSetWithCharactersInString:@"\t\r\n"];
    return [[text componentsSeparatedByCharactersInSet:breaks] componentsJoinedByString:@" "];
}

@implementation MAXContactsCache

+ (NSString *)pathForAccount:(long long)accountId {
    NSArray *dirs = NSSearchPathForDirectoriesInDomains(NSCachesDirectory,
                                                        NSUserDomainMask, YES);
    if (dirs.count == 0) return nil;
    NSString *name = [NSString stringWithFormat:@"contacts-%lld.txt", accountId];
    return [dirs[0] stringByAppendingPathComponent:name];
}

+ (NSArray *)loadForAccount:(long long)accountId {
    NSString *path = [self pathForAccount:accountId];
    if (path == nil) return @[];

    NSString *text = [NSString stringWithContentsOfFile:path
                                               encoding:NSUTF8StringEncoding
                                                  error:NULL];
    if (text.length == 0) return @[];

    NSMutableArray *made = [NSMutableArray array];
    for (NSString *line in [text componentsSeparatedByString:@"\n"]) {
        MAXContact *contact = [self parseLine:line];
        if (contact != nil) [made addObject:contact];
    }

    NSLog(@"[Max/Память] карточек из памяти: %lu", (unsigned long)made.count);
    return made;
}

+ (void)save:(NSArray *)contacts forAccount:(long long)accountId {
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    if (now - MAXContactsCacheSavedAt < MAXContactsCacheRest) return;
    [self forceSave:contacts forAccount:accountId];
}

+ (void)forceSave:(NSArray *)contacts forAccount:(long long)accountId {
    if (contacts.count == 0) return;

    NSString *path = [self pathForAccount:accountId];
    if (path == nil) return;

    MAXContactsCacheSavedAt = [NSDate timeIntervalSinceReferenceDate];

    NSMutableArray *lines = [NSMutableArray array];
    for (MAXContact *contact in contacts) {
        if (contact.contactId == 0 || contact.name.length == 0) continue;
        [lines addObject:[self writeLine:contact]];
        if (lines.count >= MAXContactsCacheLimit) break;
    }
    if (lines.count == 0) return;

    NSString *text = [lines componentsJoinedByString:@"\n"];
    NSError *error = nil;
    BOOL written = [text writeToFile:path
                          atomically:YES
                            encoding:NSUTF8StringEncoding
                               error:&error];
    if (!written) {
        NSLog(@"[Max/Память] карточки не сохранить — %@", error.localizedDescription);
    }
}

+ (void)clearForAccount:(long long)accountId {
    NSString *path = [self pathForAccount:accountId];
    if (path == nil) return;
    [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
}

#pragma mark - Формат

+ (NSString *)writeLine:(MAXContact *)contact {
    NSMutableArray *options = [NSMutableArray array];
    for (NSString *option in contact.options) {
        if ([option isKindOfClass:[NSString class]]) [options addObject:MAXPlainField(option)];
    }

    return [NSString stringWithFormat:@"%lld\t%@\t%@\t%@",
            contact.contactId,
            MAXPlainField(contact.name),
            MAXPlainField(contact.avatarUrl),
            [options componentsJoinedByString:@","]];
}

+ (MAXContact *)parseLine:(NSString *)line {
    if (line.length == 0) return nil;

    NSArray *parts = [line componentsSeparatedByString:@"\t"];
    if (parts.count < 3) return nil;

    long long identifier = [parts[0] longLongValue];
    if (identifier == 0) return nil;

    MAXContact *contact = [[MAXContact alloc] init];
    contact.contactId = identifier;
    contact.name = parts[1];
    contact.avatarUrl = [parts[2] length] > 0 ? parts[2] : nil;

    if (parts.count > 3 && [parts[3] length] > 0) {
        contact.options = [NSSet setWithArray:[parts[3] componentsSeparatedByString:@","]];
    }

    return contact;
}

@end
