#import <UIKit/UIKit.h>

/**
 * Значки, нарисованные кодом.
 *
 * Картинок в связке нет намеренно: значки в оригинале — простые контуры,
 * и десяток таких рисуется CoreGraphics за строчку каждый. Это снимает
 * и заботу о наборах @2x/@3x, и вопрос, откуда брать чужие PNG.
 *
 * Все значки монохромные. Цвет задаётся при рисовании, размер — в точках.
 * Результат кешируется по имени, размеру и цвету: рисовать заново на каждую
 * ячейку списка незачем.
 */
@interface YCIcons : NSObject

+ (UIImage *)plus:(CGFloat)size color:(UIColor *)color;
+ (UIImage *)close:(CGFloat)size color:(UIColor *)color;
+ (UIImage *)chevronDown:(CGFloat)size color:(UIColor *)color;
+ (UIImage *)chevronRight:(CGFloat)size color:(UIColor *)color;
+ (UIImage *)chevronLeft:(CGFloat)size color:(UIColor *)color;
+ (UIImage *)clock:(CGFloat)size color:(UIColor *)color;
+ (UIImage *)trash:(CGFloat)size color:(UIColor *)color;
+ (UIImage *)pencil:(CGFloat)size color:(UIColor *)color;
+ (UIImage *)search:(CGFloat)size color:(UIColor *)color;
+ (UIImage *)person:(CGFloat)size color:(UIColor *)color;
+ (UIImage *)people:(CGFloat)size color:(UIColor *)color;
+ (UIImage *)calendar:(CGFloat)size color:(UIColor *)color;
+ (UIImage *)menu:(CGFloat)size color:(UIColor *)color;
+ (UIImage *)check:(CGFloat)size color:(UIColor *)color;
+ (UIImage *)comment:(CGFloat)size color:(UIColor *)color;

/** Глаз — показать пароль. Перечёркнутый, когда пароль уже виден. */
+ (UIImage *)eye:(CGFloat)size color:(UIColor *)color crossed:(BOOL)crossed;

/** Стрелка «назад» с чертой — плоская кнопка возврата для iOS 6. */
+ (UIImage *)back:(CGFloat)size color:(UIColor *)color;

/** Круглая заглушка аватара: светлый круг с силуэтом, как в оригинале. */
+ (UIImage *)avatar:(CGFloat)size;

@end
