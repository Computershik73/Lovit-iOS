//
//  MAXQuickLook.h
//  Max — просмотр скачанного документа.
//
//  Показывает сама система: QuickLook умеет PDF, тексты, картинки,
//  документы Word, Excel, Keynote и ещё десяток видов — всё это в iOS есть
//  с четвёртой прошивки, и своего к этому добавлять нечего.
//
//  До этого скачанный файл просто ложился в Documents, и открыть его на
//  самом устройстве было нечем: «Файлов» на iOS 6 ещё нет, и документ
//  приходилось забирать через iTunes.
//
//  Сделано по QuickLookController.m из iTgLegacy — там то же самое и теми
//  же тремя строками.
//

#import <UIKit/UIKit.h>
#import <QuickLook/QuickLook.h>

@interface MAXQuickLook : QLPreviewController <QLPreviewControllerDataSource>

/// Умеет ли система показать такой файл. По расширению, не по содержимому:
/// сама QuickLook судит так же.
+ (BOOL)canShowFileAtPath:(NSString *)path;

/// Показать файл поверх `host`. NO — не взялась: такого файла нет либо
/// система его не понимает; тогда звать больше некого, кроме сообщения
/// «лежит в Documents».
+ (BOOL)showFileAtPath:(NSString *)path from:(UIViewController *)host;

@end
