#import <UIKit/UIKit.h>

@class YCLoginController;

@protocol YCLoginControllerDelegate <NSObject>

/** Вошли и выбрали филиал — можно показывать журнал. Шлют оба экрана, отсюда id. */
- (void)loginControllerDidFinish:(id)controller;

@end


/**
 * Экран входа — по снимку оригинала: знак, два поля, жёлтая кнопка,
 * «Регистрация» и «Сброс пароля», подпись с версией.
 *
 * Выбор филиала вынесен в YCCompaniesController: у него свой вид
 * со списком и поиском.
 */
@interface YCLoginController : UIViewController

@property (nonatomic, weak) id<YCLoginControllerDelegate> delegate;

@end


/** Список филиалов с поиском; при одном филиале при входе выбирается сам. */
@interface YCCompaniesController : UITableViewController

@property (nonatomic, weak) id<YCLoginControllerDelegate> delegate;

/** Открыт по «сменить филиал»: единственный филиал не выбирается сам. */
@property (nonatomic, assign) BOOL explicitChoice;

@end
