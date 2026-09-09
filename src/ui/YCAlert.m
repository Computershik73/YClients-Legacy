#import "YCAlert.h"

/**
 * Делегат для UIAlertView и UIActionSheet — старого пути.
 *
 * Оба держат делегата слабо (assign, не retain), и объект, созданный
 * на месте вызова, умер бы, не дождавшись нажатия. Поэтому делегат
 * добавляет себя в общий набор и убирает оттуда, когда дело сделано.
 *
 * **Когда именно «сделано» — здесь и была главная тонкость.**
 *
 * Убирать себя из набора в `clickedButtonAtIndex:` нельзя: это не последний
 * вызов, а первый из трёх. За ним система зовёт `willDismiss…`
 * и `didDismiss…`, и зовёт их у указателя, который к тому времени указывает
 * на освобождённую память. Падало от этого **любое** нажатие в меню
 * и в любом окне сообщений; на iOS 7 это единственный доступный путь —
 * UIAlertController там ещё нет.
 *
 * Поэтому номер нажатой кнопки только запоминается, а и работа, и роспуск
 * делаются в `didDismiss…` — последнем вызове, после которого окно
 * к делегату уже не обращается.
 *
 * Второе следствие того же порядка приятное: блок вызывающего срабатывает,
 * когда окно уже убрано с экрана. Показать поверх него другое окно или
 * вытолкнуть экран — теперь безопасно, а из `clickedButtonAtIndex:` это
 * пришлось бы делать поверх уходящей анимации.
 */
@interface YCAlertProxy : NSObject <UIAlertViewDelegate, UIActionSheetDelegate>
@property (nonatomic, copy) void (^onConfirm)(void);
@property (nonatomic, assign) NSInteger confirmIndex;

/** Для меню: номера кнопок отображаются в номера строк, переданных вызывающим. */
@property (nonatomic, copy) void (^onChoose)(NSInteger index);

/** Что нажали. NSNotFound означает «ничего» — окно закрыли иначе. */
@property (nonatomic, assign) NSInteger clickedIndex;

/** Номер отменяющей кнопки листа; для окна сообщений не используется. */
@property (nonatomic, assign) NSInteger cancelIndex;
@end

static NSMutableSet *YCAliveProxies(void) {
    static NSMutableSet *alive;
    static dispatch_once_t once;

    dispatch_once(&once, ^{ alive = [NSMutableSet set]; });

    return alive;
}

@implementation YCAlertProxy

- (id)init {
    self = [super init];

    if (self != nil) {
        _clickedIndex = NSNotFound;
        _cancelIndex = NSNotFound;
        _confirmIndex = NSNotFound;
    }

    return self;
}

- (void)keepAlive {
    [YCAliveProxies() addObject:self];
}

/**
 * Общий конец для обоих окон.
 *
 * Роспуск — последней строкой: до неё объект ещё нужен живым, а блок
 * вызывающего вправе показать следующее окно, которое заведёт свой
 * собственный делегат.
 */
- (void)finishWithIndex:(NSInteger)index {
    if (index != NSNotFound) {
        if (index == self.confirmIndex && self.onConfirm != nil) {
            self.onConfirm();
        }

        // Отмена приходит сюда же; её номер надо отличить — иначе «Отмена»
        // выполнила бы последнее действие меню.
        if (index != self.cancelIndex && self.onChoose != nil) {
            self.onChoose(index);
        }
    }

    [YCAliveProxies() removeObject:self];
}

#pragma mark UIAlertView

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)index {
    self.clickedIndex = index;
}

- (void)alertView:(UIAlertView *)alertView didDismissWithButtonIndex:(NSInteger)index {
    [self finishWithIndex:self.clickedIndex];
}

#pragma mark UIActionSheet

- (void)actionSheet:(UIActionSheet *)sheet clickedButtonAtIndex:(NSInteger)index {
    self.clickedIndex = index;
}

- (void)actionSheet:(UIActionSheet *)sheet didDismissWithButtonIndex:(NSInteger)index {
    [self finishWithIndex:self.clickedIndex];
}

@end


/** Есть ли в этой системе UIAlertController. */
static Class YCAlertControllerClass(void) {
    return NSClassFromString(@"UIAlertController");
}

/**
 * Показывает UIAlertController, не ссылаясь на его символы напрямую.
 *
 * Прямое обращение к классу и к константам вроде UIAlertActionStyleDestructive
 * означало бы ссылку на символы, которых на iOS 6 в UIKit нет; приложение
 * не запустилось бы вовсе — отказом загрузчика, без записи в журнале.
 * Поэтому класс берётся по имени, а стили заданы числами: у них
 * задокументированные постоянные значения (0 — обычный, 1 — отменяющий,
 * 2 — разрушительный).
 */
static void YCShowModern(UIViewController *host,
                         NSString *title,
                         NSString *message,
                         NSString *confirmTitle,
                         NSString *cancelTitle,
                         BOOL destructive,
                         void (^onConfirm)(void)) {
    Class controllerClass = YCAlertControllerClass();
    Class actionClass = NSClassFromString(@"UIAlertAction");

    // UIAlertControllerStyleAlert == 1
    id alert = [controllerClass alertControllerWithTitle:title
                                                 message:message
                                          preferredStyle:1];

    if (confirmTitle != nil) {
        id confirm = [actionClass actionWithTitle:confirmTitle
                                            style:(destructive ? 2 : 0)
                                          handler:^(id action) {
            if (onConfirm != nil) {
                onConfirm();
            }
        }];

        [alert addAction:confirm];
    }

    /**
     * Отменяющая кнопка добавляется последней: система сама ставит её
     * на нужное место, а порядок добавления влияет на остальные.
     *
     * Обработчик пустой, а не nil, и это требование компилятора, а не
     * прихоть: в SDK 9.3 последний аргумент actionWithTitle:style:handler:
     * помечен непустым, и nil там — ошибка сборки. Своего смысла у пустого
     * блока нет: отмена ничего не делает по определению.
     */
    id cancel = [actionClass actionWithTitle:cancelTitle
                                       style:1
                                     handler:^(id action) {}];

    [alert addAction:cancel];

    [host presentViewController:alert animated:YES completion:nil];
}

static void YCShowLegacy(NSString *title,
                         NSString *message,
                         NSString *confirmTitle,
                         NSString *cancelTitle,
                         void (^onConfirm)(void)) {
    YCAlertProxy *proxy = [[YCAlertProxy alloc] init];

    proxy.onConfirm = onConfirm;

    UIAlertView *alert = [[UIAlertView alloc] initWithTitle:title
                                                    message:message
                                                   delegate:proxy
                                          cancelButtonTitle:cancelTitle
                                          otherButtonTitles:nil];

    if (confirmTitle != nil) {
        proxy.confirmIndex = [alert addButtonWithTitle:confirmTitle];
    } else {
        // Без второй кнопки подтверждать нечего; NSNotFound не совпадёт
        // ни с одним номером кнопки.
        proxy.confirmIndex = NSNotFound;
    }

    [proxy keepAlive];
    [alert show];
}

void YCAlertMessage(UIViewController *host, NSString *title, NSString *message) {
    if (YCAlertControllerClass() != nil && host != nil) {
        YCShowModern(host, title, message, nil, @"Понятно", NO, nil);
        return;
    }

    YCShowLegacy(title, message, nil, @"Понятно", nil);
}

void YCAlertConfirm(UIViewController *host,
                    NSString *title,
                    NSString *message,
                    NSString *confirmTitle,
                    BOOL destructive,
                    void (^onConfirm)(void)) {
    if (YCAlertControllerClass() != nil && host != nil) {
        YCShowModern(host, title, message, confirmTitle, @"Отмена", destructive, onConfirm);
        return;
    }

    YCShowLegacy(title, message, confirmTitle, @"Отмена", onConfirm);
}

void YCAlertMenu(UIViewController *host,
                 NSString *title,
                 NSArray *options,
                 UIView *anchor,
                 void (^onChoose)(NSInteger)) {
    if ([options count] == 0) {
        return;
    }

    Class controllerClass = YCAlertControllerClass();

    if (controllerClass != nil && host != nil) {
        Class actionClass = NSClassFromString(@"UIAlertAction");

        // UIAlertControllerStyleActionSheet == 0
        id sheet = [controllerClass alertControllerWithTitle:title
                                                     message:nil
                                              preferredStyle:0];

        for (NSUInteger i = 0; i < [options count]; i++) {
            NSUInteger index = i;

            id action = [actionClass actionWithTitle:[options objectAtIndex:i]
                                               style:0
                                             handler:^(id chosen) {
                if (onChoose != nil) {
                    onChoose(index);
                }
            }];

            [sheet addAction:action];
        }

        // Пустой блок, а не nil, — см. YCShowModern выше.
        [sheet addAction:[actionClass actionWithTitle:@"Отмена"
                                                style:1
                                              handler:^(id action) {}]];

        /**
         * На iPad меню показывается выноской, и ей нужен якорь.
         *
         * Без него UIAlertController не «показывается криво», а роняет
         * приложение исключением при показе. Проверка по наличию свойства:
         * popoverPresentationController появился в iOS 8 вместе с самим
         * UIAlertController, но на iPhone он равен nil, и присваивать
         * туда нечего.
         */
        if ([sheet respondsToSelector:@selector(popoverPresentationController)]) {
            id popover = [sheet popoverPresentationController];

            if (popover != nil && anchor != nil) {
                [popover setSourceView:anchor];
                [popover setSourceRect:anchor.bounds];
            }
        }

        [host presentViewController:sheet animated:YES completion:nil];
        return;
    }

    YCAlertProxy *proxy = [[YCAlertProxy alloc] init];

    proxy.onChoose = onChoose;

    UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:title
                                                       delegate:proxy
                                              cancelButtonTitle:nil
                                         destructiveButtonTitle:nil
                                              otherButtonTitles:nil];

    for (NSString *option in options) {
        [sheet addButtonWithTitle:option];
    }

    // Отмена добавляется последней и объявляется отменяющей: иначе система
    // не отодвинет её от остальных и не свяжет с нажатием мимо листа.
    sheet.cancelButtonIndex = [sheet addButtonWithTitle:@"Отмена"];

    // Делегат должен знать номер отменяющей сам: к моменту, когда он
    // разбирает нажатие, лист уже распущен и спрашивать не у кого.
    proxy.cancelIndex = sheet.cancelButtonIndex;

    [proxy keepAlive];

    /**
     * Показываем в окне, а не в виде контроллера.
     *
     * Лист в любом случае уезжает в окно, но `showInView:` с обычным видом
     * на iOS 7 умеет промахнуться мимо: если вид лежит в контроллере
     * навигации, лист прижимается к его границам, а не к экрану. Окно
     * известно точно и не зависит от того, откуда меню позвали.
     */
    UIWindow *window = [[UIApplication sharedApplication] keyWindow];

    [sheet showInView:(window != nil ? (UIView *)window : host.view)];
}
