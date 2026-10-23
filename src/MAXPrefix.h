//
//  MAXPrefix.h
//  Подключается ко всем файлам флагом -include (см. Makefile).
//
//  В проекте Xcode это делал Max-Prefix.pch; theos своего префикса не ставит,
//  поэтому заголовок подключается явно. Нужен он ровно затем же: несколько
//  файлов рассчитывают, что UIKit и Foundation уже видны.
//

#ifdef __OBJC__
    #import <Foundation/Foundation.h>
    #import <UIKit/UIKit.h>
#endif
