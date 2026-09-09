#import <UIKit/UIKit.h>

#import "YCAppDelegate.h"
#import "YCLog.h"

/**
 * Переносит язык и список клавиатур из общих настроек системы в свои.
 *
 * Без этого в поле «ФИО» нельзя переключиться на русскую клавиатуру:
 * на ней нет глобуса. Дело не в поле ввода и не в объявленных языках —
 * приложение вообще не видит общих настроек. И `AppleKeyboards`,
 * и `AppleLanguages` читаются как отсутствующие, отчего система считает
 * устройство английским, а UIKit, не найдя списка клавиатур, оставляет
 * одну английскую. Переключать не на что — глобус и не рисуется.
 *
 * Причина в том, где приложение живёт. Общие настройки лежат
 * в `.GlobalPreferences.plist` в домашнем каталоге пользователя, и обычному
 * приложению их подаёт система; программе, установленной в `/Applications`
 * мимо App Store, — не подаёт. Файл при этом никуда не делся и читается
 * обычным чтением файла, чем мы и пользуемся: берём оттуда нужные ключи
 * и кладём в собственный раздел настроек. Дальше их находит уже сам UIKit —
 * свой раздел он просматривает раньше общего.
 *
 * Для журнала записей это не мелочь: почти каждое поле, которое здесь
 * заполняют, — русское имя.
 *
 * Делается это до UIApplicationMain намеренно: и язык, и клавиатуры UIKit
 * читает один раз при запуске, и позже подменять их поздно.
 *
 * Значения не «дописываются, если пусто», а перезаписываются каждый запуск:
 * иначе однажды взятый список пережил бы смену языка в настройках системы.
 */
static void YCAdoptSystemPreferences(void) {
    NSArray *places = @[
        [NSHomeDirectory() stringByAppendingPathComponent:
            @"Library/Preferences/.GlobalPreferences.plist"],
        @"/var/mobile/Library/Preferences/.GlobalPreferences.plist"
    ];

    NSDictionary *global = nil;

    for (NSString *path in places) {
        global = [NSDictionary dictionaryWithContentsOfFile:path];

        if (global != nil) {
            NSLog(@"[YClients/Настройки] Общие настройки прочитаны: %@", path);
            break;
        }
    }

    if (global == nil) {
        NSLog(@"[YClients/Настройки] Общие настройки не читаются — язык "
              @"и клавиатуры останутся такими, какими их видит система");
        return;
    }

    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

    // AppleLocale нужен рядом с языком: по нему считаются форматы дат и чисел.
    for (NSString *key in @[ @"AppleLanguages", @"AppleKeyboards", @"AppleLocale" ]) {
        id value = [global objectForKey:key];

        if (value != nil) {
            [defaults setObject:value forKey:key];
        }
    }

    [defaults synchronize];

    NSLog(@"[YClients/Настройки] Язык системы: %@",
          [global objectForKey:@"AppleLocale"] ?: @"неизвестен");
}

int main(int argc, char *argv[]) {
    @autoreleasepool {
        // Перехват stderr ставится первым: до него не видно ни строчки
        // из самой библиотеки, а падать она может уже на первом запросе.
        YCLogCaptureStderr();

        YCAdoptSystemPreferences();

        return UIApplicationMain(argc, argv, nil,
                                 NSStringFromClass([YCAppDelegate class]));
    }
}
