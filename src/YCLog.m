#import "YCLog.h"

/**
 * Здесь NSLog нужен настоящий.
 *
 * Ключ -include подставляет YCLog.h в самое начало каждого файла, включая
 * этот, — раньше любых наших строк. Поэтому объявить что-либо «до» подмены
 * нельзя, её можно только снять, и делается это здесь.
 */
#undef NSLog

/**
 * И собственные имена тоже: в молчаливой сборке они подменены пустышкой,
 * а пустышка на месте определения превратила бы его в бессмыслицу.
 */
#undef YCLogWrite
#undef YCLogWriteNow

#import <unistd.h>

#ifdef YC_NO_LOG

/**
 * Молчаливая сборка: имена остаются, дела за ними нет.
 *
 * Вызовы NSLog до сюда не доходят вовсе — их выбросил разбор, — но пустые
 * определения оставлены нарочно. Во-первых, на них может сослаться код,
 * забывший про пометку, и такая ссылка должна связаться, а не свалить сборку
 * в непонятную ошибку компоновщика. Во-вторых, так видно с одного взгляда:
 * в готовой сборке журнала нет — ни очереди, ни файла, ни даже пути к нему.
 */
NSString *YCLogPath(void) { return @""; }
void YCLogClear(void) {}
void YCLogWrite(NSString *format, ...) {}
void YCLogWriteNow(NSString *format, ...) {}
void YCLogCaptureStderr(void) {}

#else

/**
 * Потолок на размер файла.
 *
 * Журнал пишется всё время работы, и на устройстве, где приложение открывают
 * каждый день, без потолка он растёт до сотен мегабайт — на iPhone 4 с его
 * восемью гигабайтами это заметная доля свободного места. При достижении
 * потолка файл начинается заново: хранить хвост, перекладывая мегабайты при
 * каждом переполнении, дороже, чем потерять старое.
 */
static const unsigned long long YCLogLimit = 2 * 1024 * 1024;

/**
 * Очередь записи — одна на всё приложение и последовательная.
 *
 * Запись отложенная: вызывающий не ждёт диска. Порядок строк при этом
 * сохраняется — очередь последовательная, — а вот порядок относительно
 * системного журнала нет: NSLog печатает сразу, файл догоняет.
 */
static dispatch_queue_t YCLogQueue(void) {
    static dispatch_queue_t queue;
    static dispatch_once_t once;

    dispatch_once(&once, ^{
        queue = dispatch_queue_create("ru.computershik.yclients.log", DISPATCH_QUEUE_SERIAL);
    });

    return queue;
}

NSString *YCLogPath(void) {
    static NSString *path;
    static dispatch_once_t once;

    dispatch_once(&once, ^{
        NSArray *dirs = NSSearchPathForDirectoriesInDomains(
            NSDocumentDirectory, NSUserDomainMask, YES);

        path = [[dirs objectAtIndex:0] stringByAppendingPathComponent:@"yclients.log"];
    });

    return path;
}

/** Дописывает готовую строку в файл. Зовётся только с очереди журнала. */
static void YCLogAppend(NSString *line) {
    NSString *path = YCLogPath();
    NSFileManager *fm = [NSFileManager defaultManager];

    if (![fm fileExistsAtPath:path]) {
        [fm createFileAtPath:path contents:nil attributes:nil];
    }

    NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:path];

    if (handle == nil) {
        return;
    }

    @try {
        unsigned long long size = [handle seekToEndOfFile];

        // Переполнение: начинаем заново. Файл именно обрезается, а не
        // удаляется, — открытый дескриптор пережил бы удаление и продолжал
        // писать в файл, которого уже нет ни в одном каталоге.
        if (size >= YCLogLimit) {
            [handle truncateFileAtOffset:0];
            [handle writeData:[@"— журнал начат заново по достижении потолка —\n"
                dataUsingEncoding:NSUTF8StringEncoding]];
        }

        [handle writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
    }
    @catch (NSException *e) {
        // Диск переполнен или файл забрали из-под нас. Сообщить об этом
        // некуда — мы и есть журнал.
    }
    @finally {
        [handle closeFile];
    }
}

/** Отметка времени. Формат постоянный, часовой пояс — местный. */
static NSString *YCLogStamp(void) {
    static NSDateFormatter *formatter;
    static dispatch_once_t once;

    dispatch_once(&once, ^{
        formatter = [[NSDateFormatter alloc] init];

        // Локаль задана явно: под персидским или буддийским календарём
        // отметка была бы не той, что в системном журнале, и строки
        // перестали бы сопоставляться.
        formatter.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
        formatter.dateFormat = @"HH:mm:ss.SSS";
    });

    return [formatter stringFromDate:[NSDate date]];
}

/**
 * Кладёт готовую строку в файл — и **только** в файл.
 *
 * Отдельно от YCLogv затем, что перехватчик stderr обязан писать именно
 * так. Стоило ему позвать что-нибудь, доходящее до NSLog, — и получалась
 * петля: NSLog пишет не только в системный журнал, но и в stderr, stderr
 * у нас перенаправлен в канал, канал читает поток, поток снова зовёт
 * NSLog. Каждый оборот дописывал к строке очередной заголовок, строка
 * росла без предела, и на одноядерном A4 это съедало процессор целиком —
 * приложение переставало отвечать на нажатия.
 */
static void YCLogFileOnly(NSString *message, BOOL now) {
    NSString *line = [NSString stringWithFormat:@"%@ %@\n", YCLogStamp(), message];

    if (now) {
        dispatch_sync(YCLogQueue(), ^{ YCLogAppend(line); });
    } else {
        dispatch_async(YCLogQueue(), ^{ YCLogAppend(line); });
    }
}

static void YCLogv(NSString *format, va_list args, BOOL now) {
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];

    // Системный журнал получает строку как была, без отметки: там своя.
    NSLog(@"%@", message);

    YCLogFileOnly(message, now);
}

void YCLogWrite(NSString *format, ...) {
    va_list args;
    va_start(args, format);
    YCLogv(format, args, NO);
    va_end(args);
}

void YCLogWriteNow(NSString *format, ...) {
    va_list args;
    va_start(args, format);
    YCLogv(format, args, YES);
    va_end(args);
}

void YCLogClear(void) {
    dispatch_sync(YCLogQueue(), ^{
        [[NSFileManager defaultManager] removeItemAtPath:YCLogPath() error:NULL];
    });
}

/**
 * Заголовок, которым NSLog помечает свои строки в stderr: `YClients[123:`.
 *
 * Нужен, чтобы отличить наше собственное эхо от того, ради чего перехват
 * и заведён. NSLog пишет одну и ту же строку дважды — в системный журнал
 * и в stderr, — а stderr у нас идёт в канал. То есть каждое наше сообщение
 * возвращается сюда же, уже записанное в файл обычным путём.
 *
 * Петли от этого больше не будет (читатель пишет прямо в файл, минуя NSLog),
 * но в журнале каждая строка двоилась бы: один раз своя, другой раз с чужим
 * заголовком. Поэтому эхо просто отбрасывается.
 *
 * Строки самой библиотеки cYclients такого заголовка не несут: она пишет
 * обычным fprintf, без имени процесса и номера потока, — а нужны здесь
 * именно они.
 */
static NSString *YCSelfBanner(void) {
    static NSString *banner;
    static dispatch_once_t once;

    dispatch_once(&once, ^{
        banner = [NSString stringWithFormat:@"%@[%d:",
                  [[NSProcessInfo processInfo] processName], (int)getpid()];
    });

    return banner;
}

/**
 * Читатель канала, в который перенаправлен stderr.
 *
 * Отдельным классом только потому, что detachNewThreadSelector требует цели
 * с методом; блока он не принимает — это iOS 6, NSThread с блоком появится
 * лишь в iOS 10.
 */
@interface YCLogPump : NSObject
+ (void)pump:(NSFileHandle *)reader;
@end

@implementation YCLogPump

+ (void)pump:(NSFileHandle *)reader {
    @autoreleasepool {
        NSMutableData *tail = [NSMutableData data];

        for (;;) {
            @autoreleasepool {
                NSData *chunk = nil;

                // Чтение блокирующее и до конца жизни процесса; исключение
                // здесь означает, что канал закрыт, и тогда поток кончается.
                @try {
                    chunk = [reader availableData];
                }
                @catch (NSException *e) {
                    return;
                }

                if (chunk.length == 0) {
                    return;
                }

                [tail appendData:chunk];

                /**
                 * Предохранитель на случай потока без переводов строки.
                 *
                 * Накопитель ждёт `\n`, чтобы не разорвать сообщение
                 * библиотеки пополам, — но если пишущий его не ставит,
                 * ждать пришлось бы до конца памяти. Шестьдесят четыре
                 * килобайта на одну строку журнала это заведомо больше,
                 * чем бывает у осмысленного сообщения.
                 */
                if (tail.length > 64 * 1024) {
                    [tail setLength:0];
                    YCLogFileOnly(@"[cYclients] (строка без конца отброшена)", NO);
                    continue;
                }

                // Разбираем по строкам: fprintf может отдать полстроки,
                // и записывать её отдельно значило бы рвать сообщения
                // библиотеки пополам в случайных местах.
                for (;;) {
                    const char *bytes = (const char *)tail.bytes;
                    NSUInteger length = tail.length, i = 0;

                    while (i < length && bytes[i] != '\n') {
                        i++;
                    }

                    if (i == length) {
                        break;
                    }

                    NSString *line = [[NSString alloc] initWithBytes:bytes
                                                             length:i
                                                           encoding:NSUTF8StringEncoding];

                    /**
                     * Пишем **прямо в файл**, а не через YCLogWrite.
                     *
                     * Через него получалась петля: YCLogWrite зовёт NSLog,
                     * NSLog пишет в stderr, stderr — это мы. Приложение
                     * уходило в бесконечный круг, дописывая к строке
                     * очередной заголовок, и переставало отвечать.
                     */
                    if (line.length > 0 &&
                        [line rangeOfString:YCSelfBanner()].location == NSNotFound) {
                        YCLogFileOnly([@"[cYclients] " stringByAppendingString:line], NO);
                    }

                    [tail replaceBytesInRange:NSMakeRange(0, i + 1) withBytes:NULL length:0];
                }
            }
        }
    }
}

@end

void YCLogCaptureStderr(void) {
    static dispatch_once_t once;

    dispatch_once(&once, ^{
        int fds[2];

        if (pipe(fds) != 0) {
            return;
        }

        // Дескриптор 2 становится вторым концом канала. Всё, что библиотека
        // печатает через fprintf(stderr, …), теперь идёт сюда, а не в ASL.
        if (dup2(fds[1], STDERR_FILENO) < 0) {
            close(fds[0]);
            close(fds[1]);
            return;
        }

        close(fds[1]);

        // Буферизация снимается: stderr небуферизован по стандарту, но после
        // подмены дескриптора на канал libc вправе решить иначе — канал это
        // не терминал. Без этого строки копились бы в буфере и доходили
        // пачками, уже после того, как стали не нужны.
        setvbuf(stderr, NULL, _IONBF, 0);

        NSFileHandle *reader = [[NSFileHandle alloc] initWithFileDescriptor:fds[0]
                                                             closeOnDealloc:NO];

        // Отдельный поток, а не readabilityHandler: тот работает через
        // главный цикл выполнения, то есть строки из библиотеки ждали бы,
        // пока освободится главный поток. А зовут её как раз тогда,
        // когда он занят.
        [NSThread detachNewThreadSelector:@selector(pump:)
                                 toTarget:[YCLogPump class]
                               withObject:reader];
    });
}

#endif // YC_NO_LOG
