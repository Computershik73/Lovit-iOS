//
//  MAXCertificates.h
//  Max — вшитые корни НУЦ Минцифры и профиль для их установки в систему.
//
//  Сервер MAX (`api2.oneme.ru`) удостоверяется цепочкой
//  `*.oneme.ru` ← Russian Trusted Sub CA ← Russian Trusted Root CA,
//  а этого корня нет в хранилище ни одной iOS. Раньше проект обходил это
//  отключением проверки цепочки целиком (`trustMincifryCa` в Komet и в первой
//  версии порта). Здесь корень лежит в связке и добавляется отдельным якорем:
//  цепочка проверяется полностью, просто с одним дополнительным доверенным
//  корнем — как это делает TRCertificates в «Трубаче».
//
//  Файлы в Resources/certs скачаны с gu-st.ru (то, на что ссылается
//  gosuslugi.ru/crt), отпечатки SHA-256:
//
//    root: D2:6D:2D:02:31:B7:C3:9F:92:CC:73:85:12:BA:54:10
//          35:19:E4:40:5D:68:B5:BD:70:3E:97:88:CA:8E:CF:31
//    sub:  BB:BD:E2:10:3E:79:0B:99:9E:C6:2B:D0:3C:F6:25:A5
//          A2:E7:C3:16:E1:0A:FE:6A:49:0E:ED:EA:D8:B3:FD:9B
//

#import <Foundation/Foundation.h>
#import <Security/Security.h>

@interface MAXCertificates : NSObject

/// Имена файлов в Resources/certs без расширения.
+ (NSArray *)fileNames;

/// Человеческое название корня — оно же попадает в профиль.
+ (NSString *)titleForName:(NSString *)name;

+ (NSData *)dataForName:(NSString *)name;

/// Массив SecCertificateRef для SecTrustSetAnchorCertificates.
+ (NSArray *)anchorCertificates;

/// Готовый .mobileconfig со всеми корнями — на случай, если доверие нужно
/// починить системе целиком, а не только внутри приложения.
+ (NSData *)configurationProfile;

@end
