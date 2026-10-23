//
//  MAXContact.h
//  Max — контакт из CONTACTS_GET / CONTACT_INFO / payload логина.
//

#import <Foundation/Foundation.h>

@interface MAXContact : NSObject

@property (nonatomic, assign) long long contactId;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *avatarUrl;
/// «О себе»: сервер зовёт это поле то `description`, то `about`.
@property (nonatomic, copy) NSString *about;
@property (nonatomic, assign) long long phone;
/// Человек записан в адресную книгу: у такого в `names` есть запись типа
/// CUSTOM — имя, которое дал ему сам пользователь. Komet различает их так же.
@property (nonatomic, assign) BOOL isSavedContact;
@property (nonatomic, strong) NSSet *options;

/// `names` сервера: сначала запись с type == ONEME, иначе первая по списку.
+ (instancetype)contactFromServerMap:(NSDictionary *)map;

@end
