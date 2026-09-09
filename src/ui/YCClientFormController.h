#import <UIKit/UIKit.h>

/**
 * «Клиент»: телефон, имя, почта и жёлтая кнопка.
 *
 * Кнопка внизу — «Продолжить без клиента», пока поля пусты, и «Сохранить»,
 * как только что-то набрано: так же ведёт себя оригинал. Блок получает
 * три строки; пустые означают «без клиента».
 */
@interface YCClientFormController : UIViewController

- (id)initWithName:(NSString *)name
             phone:(NSString *)phone
             email:(NSString *)email
          onChoose:(void (^)(NSString *name, NSString *phone, NSString *email))onChoose;

@end
