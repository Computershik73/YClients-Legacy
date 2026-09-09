#import "YCDayChrome.h"

#import "YCIcons.h"
#import "YCModel.h"
#import "YCTheme.h"

@implementation YCRulerView

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];

    if (self != nil) {
        self.backgroundColor = [YCTheme background];
        self.contentMode = UIViewContentModeRedraw;
    }

    return self;
}

- (void)setStartHour:(NSInteger)startHour {
    _startHour = startHour;
    [self setNeedsDisplay];
}

- (void)setEndHour:(NSInteger)endHour {
    _endHour = endHour;
    [self setNeedsDisplay];
}

- (void)drawRect:(CGRect)rect {
    CGFloat hourHeight = [YCTheme hourHeight];
    CGFloat width = self.bounds.size.width;

    /**
     * Шкала — приподнятая полоса, а не часть сетки.
     *
     * Подложку сюда не подложить: цифры рисуются в собственном слое вида,
     * и любой подвид накрыл бы их. Поэтому градиент кладётся прямо здесь,
     * первым делом, до подписей. Свет падает слева, к сетке полоса
     * притемняется, у самого края — тёмная грань со светлой гранью рядом.
     */
    if ([YCTheme isLegacy]) {
        CGContextRef ground = UIGraphicsGetCurrentContext();

        /**
         * Оттенки берутся от цвета темы, а не заданы белым.
         *
         * Белым я их и вписал — и в тёмной теме слева от сетки повисла
         * светлая полоса с невидимыми на ней цифрами: подписи-то рисуются
         * цветом темы, то есть почти белым по белому.
         */
        CGFloat base[4] = { 1.0, 1.0, 1.0, 1.0 };

        if (![[YCTheme background] getRed:&base[0] green:&base[1]
                                     blue:&base[2] alpha:&base[3]]) {
            [[YCTheme background] getWhite:&base[0] alpha:&base[3]];
            base[1] = base[2] = base[0];
        }

        CGFloat components[8] = {
            MIN(1.0, base[0] + (1.0 - base[0]) * 0.30),
            MIN(1.0, base[1] + (1.0 - base[1]) * 0.30),
            MIN(1.0, base[2] + (1.0 - base[2]) * 0.30),
            base[3],
            base[0] * 0.86, base[1] * 0.86, base[2] * 0.86, base[3]
        };

        CGFloat stops[2] = { 0.0, 1.0 };

        CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
        CGGradientRef gradient =
            CGGradientCreateWithColorComponents(space, components, stops, 2);

        CGContextDrawLinearGradient(ground, gradient, CGPointMake(0, 0),
                                    CGPointMake(width, 0), 0);

        CGGradientRelease(gradient);
        CGColorSpaceRelease(space);

        CGFloat hair = 1.0 / [UIScreen mainScreen].scale;

        CGContextSetLineWidth(ground, hair);

        CGContextSetStrokeColorWithColor(ground, [YCTheme gridLine].CGColor);
        CGContextMoveToPoint(ground, width - hair, 0);
        CGContextAddLineToPoint(ground, width - hair, self.bounds.size.height);
        CGContextStrokePath(ground);

        CGContextSetStrokeColorWithColor(ground,
            [UIColor colorWithWhite:1.0 alpha:([YCTheme isDark] ? 0.16 : 0.9)].CGColor);
        CGContextMoveToPoint(ground, width - hair * 2, 0);
        CGContextAddLineToPoint(ground, width - hair * 2, self.bounds.size.height);
        CGContextStrokePath(ground);
    }

    UIFont *font = [YCTheme rulerFont];
    UIColor *ink = [YCTheme text];

    for (NSInteger hour = self.startHour; hour <= self.endHour; hour++) {
        CGFloat y = (hour - self.startHour) * hourHeight;

        NSString *label = [NSString stringWithFormat:@"%02ld:00", (long)hour];

        /**
         * Подпись серединой на часовой линии — иначе «10:00» под линией
         * читается как отметка следующего часа.
         *
         * У самой первой отметки середина приходится на ноль, и верхняя
         * половина цифр уходила за край вида: на видео «08:00» было
         * срезано пополам. Поэтому у неё подпись прижимается к верху.
         */
        CGFloat top = y - font.lineHeight / 2.0;

        CGRect box = CGRectMake(0, MAX(0, top), width - 8.0, font.lineHeight);

        [ink set];

        /**
         * Ветка выбирается по версии оформления, а не опросом объекта.
         *
         * Напрашивалось `respondsToSelector:@selector(drawInRect:withAttributes:)`,
         * и именно так здесь и было — но на iOS 6 строка отвечает «да».
         * Метод объявлен как появившийся в iOS 7, однако в UIKit шестёрки он
         * уже есть: там завели атрибутованные строки, а рисование по
         * атрибутам оставили внутренним. Вызов такого метода не отвергается,
         * а уходит в недоделанную реализацию и роняет приложение обращением
         * по мусорному указателю — прямо при первой отрисовке шкалы часов.
         *
         * Опрос объекта отвечает на вопрос «есть ли метод», а нужен ответ
         * на «можно ли им пользоваться». Для этого годится только версия.
         */
        if (![YCTheme isLegacy]) {
            NSMutableParagraphStyle *style = [[NSMutableParagraphStyle alloc] init];

            style.alignment = NSTextAlignmentRight;

            [label drawInRect:box withAttributes:@{
                NSFontAttributeName: font,
                NSForegroundColorAttributeName: ink,
                NSParagraphStyleAttributeName: style
            }];
        } else {
            [label drawInRect:box withFont:font
                lineBreakMode:NSLineBreakByClipping
                    alignment:NSTextAlignmentRight];
        }
    }
}

@end


@implementation YCHeaderView {
    NSMutableArray *_labels;
    NSMutableArray *_avatars;
}

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];

    if (self != nil) {
        // Шапка со списком сотрудников — приподнятой полосой над сеткой.
        // Подписи и кружки добавляются позже и ложатся поверх подложки.
        [YCTheme decoratePanel:self color:[YCTheme background] radius:0.0];

        _labels = [NSMutableArray array];
        _avatars = [NSMutableArray array];
        _columnWidth = [YCTheme minColumnWidth];
    }

    return self;
}

- (void)setStaff:(NSArray *)staff {
    _staff = [staff copy];

    for (UIView *view in _labels) {
        [view removeFromSuperview];
    }

    for (UIView *view in _avatars) {
        [view removeFromSuperview];
    }

    [_labels removeAllObjects];
    [_avatars removeAllObjects];

    for (YCStaff *member in _staff) {
        // Кружок-аватар над именем, как в оригинале. Картинок с сервера
        // не грузим: на iPhone 4 каждая обошлась бы дороже, чем стоит.
        UIImageView *avatar = [[UIImageView alloc] initWithImage:[YCIcons avatar:[YCTheme avatarSize]]];
        [self addSubview:avatar];
        [_avatars addObject:avatar];

        UILabel *label = [[UILabel alloc] initWithFrame:CGRectZero];

        label.backgroundColor = [UIColor clearColor];
        label.font = [YCTheme headerFont];
        label.textColor = [YCTheme text];
        label.textAlignment = NSTextAlignmentCenter;

        // Нажатие по всей клетке столбца, а не только по буквам: попасть
        // пальцем в подпись высотой в восемнадцать точек трудно.
        label.userInteractionEnabled = YES;

        UITapGestureRecognizer *tap =
            [[UITapGestureRecognizer alloc] initWithTarget:self
                                                     action:@selector(labelTapped:)];

        [label addGestureRecognizer:tap];
        label.lineBreakMode = NSLineBreakByTruncatingTail;
        label.text = member.name;

        [self addSubview:label];
        [_labels addObject:label];
    }

    [self setNeedsLayout];
    [self setNeedsDisplay];
}

- (void)setColumnWidth:(CGFloat)columnWidth {
    _columnWidth = columnWidth;
    [self setNeedsLayout];
    [self setNeedsDisplay];
}

- (void)labelTapped:(UITapGestureRecognizer *)tap {
    NSUInteger index = [_labels indexOfObject:tap.view];

    if (index == NSNotFound || index >= [self.staff count]) {
        return;
    }

    [self.delegate headerView:self didTapStaff:[self.staff objectAtIndex:index]];
}

- (void)layoutSubviews {
    [super layoutSubviews];

    for (NSUInteger i = 0; i < [_labels count]; i++) {
        CGFloat x = i * self.columnWidth;

        [[_avatars objectAtIndex:i] setFrame:
            CGRectMake(x + (self.columnWidth - [YCTheme avatarSize]) / 2, 4,
                       [YCTheme avatarSize], [YCTheme avatarSize])];

        [[_labels objectAtIndex:i] setFrame:
            CGRectMake(x + 4, 6 + [YCTheme avatarSize], self.columnWidth - 8, 24)];
    }
}

- (void)drawRect:(CGRect)rect {
    CGContextRef context = UIGraphicsGetCurrentContext();

    CGContextSetStrokeColorWithColor(context, [YCTheme gridLine].CGColor);
    CGContextSetLineWidth(context, 1.0 / [UIScreen mainScreen].scale);
    CGContextBeginPath(context);

    CGFloat bottom = self.bounds.size.height - 0.5;

    CGContextMoveToPoint(context, 0, bottom);
    CGContextAddLineToPoint(context, self.bounds.size.width, bottom);
    CGContextStrokePath(context);
}

@end
