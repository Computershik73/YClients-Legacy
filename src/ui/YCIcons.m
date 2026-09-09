#import "YCIcons.h"

#import "YCTheme.h"

typedef void (^YCDrawBlock)(CGContextRef context, CGFloat size);

@implementation YCIcons

/**
 * Общая обёртка: холст, кеш, толщина линии.
 *
 * Толщина — 1/12 размера с нижним пределом в 1.5 точки: так значок в 24
 * точки рисуется линией в 2, а в 44 — в 3.7, и оба выглядят одной семьёй.
 */
+ (UIImage *)draw:(NSString *)name size:(CGFloat)size color:(UIColor *)color
            block:(YCDrawBlock)block {
    static NSMutableDictionary *cache;
    static dispatch_once_t once;

    dispatch_once(&once, ^{ cache = [NSMutableDictionary dictionary]; });

    NSString *key = [NSString stringWithFormat:@"%@/%.0f/%@",
                     name, size, [YCTheme hexFromColor:color]];

    @synchronized (cache) {
        UIImage *cached = [cache objectForKey:key];

        if (cached != nil) {
            return cached;
        }
    }

    // Нулевой масштаб — «как у экрана»: на ретине холст удвоится сам.
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(size, size), NO, 0);

    CGContextRef context = UIGraphicsGetCurrentContext();

    CGContextSetLineWidth(context, MAX(1.5, size / 12.0));
    CGContextSetLineCap(context, kCGLineCapRound);
    CGContextSetLineJoin(context, kCGLineJoinRound);

    /**
     * Тиснение под старое оформление.
     *
     * До iOS 7 значки не были тонкими линиями на пустом месте: под каждым
     * лежала светлая грань в точку ниже, отчего рисунок казался
     * продавленным в поверхность. Один и тот же рисунок кладётся дважды —
     * сперва белым со сдвигом вниз, затем своим цветом.
     *
     * Полупрозрачным белым, а не сплошным: значок может лежать и на тёмной
     * панели, где сплошная белая грань смотрелась бы обводкой.
     */
    /**
     * Аватар из этого исключён: он задаёт свои цвета внутри и на грань
     * не отзовётся — вышел бы просто второй круг на точку ниже.
     */
    if ([YCTheme isLegacy] && ![name hasPrefix:@"avatar"]) {
        CGContextSaveGState(context);
        CGContextTranslateCTM(context, 0, 1);

        UIColor *edge = [UIColor colorWithWhite:1.0 alpha:0.5];

        CGContextSetStrokeColorWithColor(context, edge.CGColor);
        CGContextSetFillColorWithColor(context, edge.CGColor);

        block(context, size);

        CGContextRestoreGState(context);
    }

    CGContextSetStrokeColorWithColor(context, color.CGColor);
    CGContextSetFillColorWithColor(context, color.CGColor);

    block(context, size);

    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();

    UIGraphicsEndImageContext();

    @synchronized (cache) {
        if (image != nil) {
            [cache setObject:image forKey:key];
        }
    }

    return image;
}

static void YCLine(CGContextRef c, CGFloat x1, CGFloat y1, CGFloat x2, CGFloat y2) {
    CGContextMoveToPoint(c, x1, y1);
    CGContextAddLineToPoint(c, x2, y2);
}

+ (UIImage *)plus:(CGFloat)s color:(UIColor *)color {
    return [self draw:@"plus" size:s color:color block:^(CGContextRef c, CGFloat n) {
        YCLine(c, n * 0.5, n * 0.18, n * 0.5, n * 0.82);
        YCLine(c, n * 0.18, n * 0.5, n * 0.82, n * 0.5);
        CGContextStrokePath(c);
    }];
}

+ (UIImage *)close:(CGFloat)s color:(UIColor *)color {
    return [self draw:@"close" size:s color:color block:^(CGContextRef c, CGFloat n) {
        YCLine(c, n * 0.25, n * 0.25, n * 0.75, n * 0.75);
        YCLine(c, n * 0.75, n * 0.25, n * 0.25, n * 0.75);
        CGContextStrokePath(c);
    }];
}

+ (UIImage *)chevronDown:(CGFloat)s color:(UIColor *)color {
    return [self draw:@"down" size:s color:color block:^(CGContextRef c, CGFloat n) {
        CGContextMoveToPoint(c, n * 0.25, n * 0.4);
        CGContextAddLineToPoint(c, n * 0.5, n * 0.65);
        CGContextAddLineToPoint(c, n * 0.75, n * 0.4);
        CGContextStrokePath(c);
    }];
}

+ (UIImage *)chevronRight:(CGFloat)s color:(UIColor *)color {
    return [self draw:@"right" size:s color:color block:^(CGContextRef c, CGFloat n) {
        CGContextMoveToPoint(c, n * 0.38, n * 0.25);
        CGContextAddLineToPoint(c, n * 0.63, n * 0.5);
        CGContextAddLineToPoint(c, n * 0.38, n * 0.75);
        CGContextStrokePath(c);
    }];
}

+ (UIImage *)chevronLeft:(CGFloat)s color:(UIColor *)color {
    return [self draw:@"left" size:s color:color block:^(CGContextRef c, CGFloat n) {
        CGContextMoveToPoint(c, n * 0.62, n * 0.25);
        CGContextAddLineToPoint(c, n * 0.37, n * 0.5);
        CGContextAddLineToPoint(c, n * 0.62, n * 0.75);
        CGContextStrokePath(c);
    }];
}

+ (UIImage *)clock:(CGFloat)s color:(UIColor *)color {
    return [self draw:@"clock" size:s color:color block:^(CGContextRef c, CGFloat n) {
        // Круг заливкой и стрелки цветом фона — как белый кружок в шапке
        // карточки; фон здесь прозрачный, поэтому стрелки вырезаются.
        CGContextFillEllipseInRect(c, CGRectMake(n * 0.1, n * 0.1, n * 0.8, n * 0.8));
        CGContextSetBlendMode(c, kCGBlendModeClear);
        CGContextSetLineWidth(c, MAX(1.2, n / 14.0));
        YCLine(c, n * 0.5, n * 0.28, n * 0.5, n * 0.52);
        YCLine(c, n * 0.5, n * 0.52, n * 0.66, n * 0.62);
        CGContextStrokePath(c);
    }];
}

+ (UIImage *)trash:(CGFloat)s color:(UIColor *)color {
    return [self draw:@"trash" size:s color:color block:^(CGContextRef c, CGFloat n) {
        YCLine(c, n * 0.2, n * 0.3, n * 0.8, n * 0.3);
        YCLine(c, n * 0.4, n * 0.3, n * 0.4, n * 0.2);
        YCLine(c, n * 0.4, n * 0.2, n * 0.6, n * 0.2);
        YCLine(c, n * 0.6, n * 0.2, n * 0.6, n * 0.3);
        CGContextStrokePath(c);

        CGContextAddRect(c, CGRectMake(n * 0.28, n * 0.3, n * 0.44, n * 0.5));
        CGContextStrokePath(c);
    }];
}

+ (UIImage *)pencil:(CGFloat)s color:(UIColor *)color {
    return [self draw:@"pencil" size:s color:color block:^(CGContextRef c, CGFloat n) {
        YCLine(c, n * 0.25, n * 0.75, n * 0.7, n * 0.3);
        YCLine(c, n * 0.25, n * 0.75, n * 0.27, n * 0.62);
        YCLine(c, n * 0.25, n * 0.75, n * 0.38, n * 0.73);
        CGContextStrokePath(c);
    }];
}

+ (UIImage *)search:(CGFloat)s color:(UIColor *)color {
    return [self draw:@"search" size:s color:color block:^(CGContextRef c, CGFloat n) {
        CGContextStrokeEllipseInRect(c, CGRectMake(n * 0.2, n * 0.2, n * 0.42, n * 0.42));
        YCLine(c, n * 0.58, n * 0.58, n * 0.8, n * 0.8);
        CGContextStrokePath(c);
    }];
}

+ (UIImage *)person:(CGFloat)s color:(UIColor *)color {
    return [self draw:@"person" size:s color:color block:^(CGContextRef c, CGFloat n) {
        CGContextStrokeEllipseInRect(c, CGRectMake(n * 0.36, n * 0.2, n * 0.28, n * 0.28));
        CGContextMoveToPoint(c, n * 0.22, n * 0.8);
        CGContextAddCurveToPoint(c, n * 0.22, n * 0.55, n * 0.78, n * 0.55, n * 0.78, n * 0.8);
        CGContextStrokePath(c);
    }];
}

+ (UIImage *)people:(CGFloat)s color:(UIColor *)color {
    return [self draw:@"people" size:s color:color block:^(CGContextRef c, CGFloat n) {
        CGContextStrokeEllipseInRect(c, CGRectMake(n * 0.38, n * 0.2, n * 0.24, n * 0.24));
        CGContextMoveToPoint(c, n * 0.26, n * 0.78);
        CGContextAddCurveToPoint(c, n * 0.26, n * 0.52, n * 0.74, n * 0.52, n * 0.74, n * 0.78);
        CGContextStrokePath(c);

        CGContextStrokeEllipseInRect(c, CGRectMake(n * 0.12, n * 0.3, n * 0.16, n * 0.16));
        CGContextStrokeEllipseInRect(c, CGRectMake(n * 0.72, n * 0.3, n * 0.16, n * 0.16));
    }];
}

+ (UIImage *)calendar:(CGFloat)s color:(UIColor *)color {
    return [self draw:@"calendar" size:s color:color block:^(CGContextRef c, CGFloat n) {
        CGContextAddRect(c, CGRectMake(n * 0.16, n * 0.24, n * 0.68, n * 0.6));
        CGContextStrokePath(c);
        YCLine(c, n * 0.16, n * 0.4, n * 0.84, n * 0.4);
        YCLine(c, n * 0.34, n * 0.14, n * 0.34, n * 0.3);
        YCLine(c, n * 0.66, n * 0.14, n * 0.66, n * 0.3);
        CGContextStrokePath(c);

        CGContextFillEllipseInRect(c, CGRectMake(n * 0.3, n * 0.52, n * 0.09, n * 0.09));
        CGContextFillEllipseInRect(c, CGRectMake(n * 0.46, n * 0.52, n * 0.09, n * 0.09));
        CGContextFillEllipseInRect(c, CGRectMake(n * 0.62, n * 0.52, n * 0.09, n * 0.09));
    }];
}

+ (UIImage *)menu:(CGFloat)s color:(UIColor *)color {
    return [self draw:@"menu" size:s color:color block:^(CGContextRef c, CGFloat n) {
        YCLine(c, n * 0.2, n * 0.3, n * 0.8, n * 0.3);
        YCLine(c, n * 0.2, n * 0.5, n * 0.8, n * 0.5);
        YCLine(c, n * 0.2, n * 0.7, n * 0.8, n * 0.7);
        CGContextStrokePath(c);
    }];
}

+ (UIImage *)check:(CGFloat)s color:(UIColor *)color {
    return [self draw:@"check" size:s color:color block:^(CGContextRef c, CGFloat n) {
        CGContextMoveToPoint(c, n * 0.22, n * 0.52);
        CGContextAddLineToPoint(c, n * 0.42, n * 0.72);
        CGContextAddLineToPoint(c, n * 0.78, n * 0.32);
        CGContextStrokePath(c);
    }];
}

+ (UIImage *)comment:(CGFloat)s color:(UIColor *)color {
    return [self draw:@"comment" size:s color:color block:^(CGContextRef c, CGFloat n) {
        CGRect box = CGRectMake(n * 0.16, n * 0.2, n * 0.68, n * 0.5);
        CGFloat r = n * 0.14;

        CGContextMoveToPoint(c, CGRectGetMinX(box) + r, CGRectGetMinY(box));
        CGContextAddArcToPoint(c, CGRectGetMaxX(box), CGRectGetMinY(box),
                               CGRectGetMaxX(box), CGRectGetMaxY(box), r);
        CGContextAddArcToPoint(c, CGRectGetMaxX(box), CGRectGetMaxY(box),
                               CGRectGetMinX(box), CGRectGetMaxY(box), r);
        CGContextAddLineToPoint(c, n * 0.4, CGRectGetMaxY(box));
        CGContextAddLineToPoint(c, n * 0.3, n * 0.84);
        CGContextAddLineToPoint(c, n * 0.28, CGRectGetMaxY(box));
        CGContextAddArcToPoint(c, CGRectGetMinX(box), CGRectGetMaxY(box),
                               CGRectGetMinX(box), CGRectGetMinY(box), r);
        CGContextAddArcToPoint(c, CGRectGetMinX(box), CGRectGetMinY(box),
                               CGRectGetMaxX(box), CGRectGetMinY(box), r);
        CGContextClosePath(c);
        CGContextStrokePath(c);

        YCLine(c, n * 0.34, n * 0.38, n * 0.66, n * 0.38);
        YCLine(c, n * 0.34, n * 0.52, n * 0.58, n * 0.52);
        CGContextStrokePath(c);
    }];
}

+ (UIImage *)eye:(CGFloat)s color:(UIColor *)color crossed:(BOOL)crossed {
    /**
     * Раньше здесь стоял знак 👁 обычной строкой.
     *
     * На iOS 6 такого знака в шрифтах нет вовсе, и вместо глаза
     * рисовался пустой квадрат — это и было видно на снимке с iPad 2.
     * Нарисованный контур выглядит одинаково везде.
     */
    NSString *name = crossed ? @"eye-off" : @"eye";

    return [self draw:name size:s color:color block:^(CGContextRef c, CGFloat n) {
        // Миндалевидный контур: две дуги навстречу друг другу.
        CGContextMoveToPoint(c, n * 0.12, n * 0.5);
        CGContextAddQuadCurveToPoint(c, n * 0.5, n * 0.16, n * 0.88, n * 0.5);
        CGContextAddQuadCurveToPoint(c, n * 0.5, n * 0.84, n * 0.12, n * 0.5);
        CGContextStrokePath(c);

        CGContextStrokeEllipseInRect(c, CGRectMake(n * 0.39, n * 0.39, n * 0.22, n * 0.22));

        if (crossed) {
            YCLine(c, n * 0.2, n * 0.8, n * 0.8, n * 0.2);
            CGContextStrokePath(c);
        }
    }];
}

+ (UIImage *)back:(CGFloat)s color:(UIColor *)color {
    return [self draw:@"back" size:s color:color block:^(CGContextRef c, CGFloat n) {
        CGContextMoveToPoint(c, n * 0.6, n * 0.22);
        CGContextAddLineToPoint(c, n * 0.3, n * 0.5);
        CGContextAddLineToPoint(c, n * 0.6, n * 0.78);
        CGContextStrokePath(c);
    }];
}

/**
 * Заглушка сотрудника для старого оформления.
 *
 * Плоский кружок с тонким контуром человечка — язык 2015 года, и рядом
 * с выпуклыми панелями он выдавал себя первым. Здесь всё наоборот:
 * кружок стеклянный — светлеет кверху, обведён по краю и с бликом
 * поверху, — а силуэт залитый, а не нарисованный линией. Тонких контуров
 * в этом языке оформления не было вовсе.
 *
 * Силуэт обрезается по самому кружку: плечи уходят за нижний край,
 * как на портрете в рамке.
 */
+ (UIImage *)legacyAvatar:(CGFloat)s {
    UIColor *top = [UIColor colorWithRed:0.97 green:0.97 blue:1.00 alpha:1.0];
    UIColor *bottom = [UIColor colorWithRed:0.82 green:0.82 blue:0.90 alpha:1.0];
    UIColor *rim = [UIColor colorWithRed:0.62 green:0.62 blue:0.74 alpha:1.0];
    UIColor *body = [UIColor colorWithRed:0.55 green:0.55 blue:0.70 alpha:1.0];

    return [self draw:@"avatar-legacy" size:s color:body block:^(CGContextRef c, CGFloat n) {
        CGRect circle = CGRectInset(CGRectMake(0, 0, n, n), 0.5, 0.5);

        CGContextSaveGState(c);
        CGContextAddEllipseInRect(c, circle);
        CGContextClip(c);

        CGFloat components[8];

        [top getRed:&components[0] green:&components[1] blue:&components[2] alpha:&components[3]];
        [bottom getRed:&components[4] green:&components[5] blue:&components[6] alpha:&components[7]];

        CGFloat stops[2] = { 0.0, 1.0 };
        CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
        CGGradientRef gradient =
            CGGradientCreateWithColorComponents(space, components, stops, 2);

        CGContextDrawLinearGradient(c, gradient, CGPointMake(0, 0),
                                    CGPointMake(0, n), 0);

        CGGradientRelease(gradient);
        CGColorSpaceRelease(space);

        // Голова и плечи — заливкой; плечи шире круга и им же обрезаются.
        CGContextSetFillColorWithColor(c, body.CGColor);
        CGContextFillEllipseInRect(c, CGRectMake(n * 0.35, n * 0.20, n * 0.30, n * 0.30));
        CGContextFillEllipseInRect(c, CGRectMake(n * 0.16, n * 0.58, n * 0.68, n * 0.60));

        // Блик поверху — то самое стекло.
        CGContextSetFillColorWithColor(c,
            [UIColor colorWithWhite:1.0 alpha:0.45].CGColor);
        CGContextFillEllipseInRect(c, CGRectMake(-n * 0.15, -n * 0.55, n * 1.30, n * 0.90));

        CGContextRestoreGState(c);

        CGContextSetStrokeColorWithColor(c, rim.CGColor);
        CGContextSetLineWidth(c, 1.0);
        CGContextStrokeEllipseInRect(c, circle);
    }];
}

+ (UIImage *)avatar:(CGFloat)s {
    // Сиреневый круг с силуэтом — заглушка аватара из оригинала.
    UIColor *ring = [UIColor colorWithRed:0.93 green:0.93 blue:0.98 alpha:1.0];
    UIColor *glyph = [UIColor colorWithRed:0.62 green:0.62 blue:0.80 alpha:1.0];

    if ([YCTheme isLegacy]) {
        return [self legacyAvatar:s];
    }

    return [self draw:@"avatar" size:s color:glyph block:^(CGContextRef c, CGFloat n) {
        CGContextSetFillColorWithColor(c, ring.CGColor);
        CGContextFillEllipseInRect(c, CGRectMake(0, 0, n, n));

        CGContextSetStrokeColorWithColor(c, glyph.CGColor);
        CGContextSetLineWidth(c, MAX(1.2, n / 22.0));
        CGContextStrokeEllipseInRect(c, CGRectMake(n * 0.4, n * 0.28, n * 0.2, n * 0.2));
        CGContextMoveToPoint(c, n * 0.3, n * 0.72);
        CGContextAddCurveToPoint(c, n * 0.3, n * 0.54, n * 0.7, n * 0.54, n * 0.7, n * 0.72);
        CGContextStrokePath(c);
    }];
}

@end
