#import "YCWeekStrip.h"

#import <QuartzCore/QuartzCore.h>

#import "YCTheme.h"
#import "YCTime.h"

@implementation YCWeekStrip {
    NSMutableArray *_buttons;   // 7 кнопок, по одной на день
    NSMutableArray *_captions;  // подписи «пн», «вт»…
    NSMutableArray *_numbers;   // числа
    NSDate *_weekStart;

    UIView *_row;               // семь дней одним видом — чтобы листались вместе
    BOOL _sliding;
}

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];

    if (self != nil) {
        // Полоса лежит ниже плоскости экрана — оттого жёлоб, а не плашка.
        [YCTheme decorateWell:self color:[YCTheme darkPanel]
                       radius:[YCTheme cornerRadius]];

        // Уезжающая неделя должна пропадать за краем полосы, а не ползти
        // по экрану.
        self.clipsToBounds = YES;

        _row = [[UIView alloc] initWithFrame:CGRectZero];
        [self addSubview:_row];

        _buttons = [NSMutableArray array];
        _captions = [NSMutableArray array];
        _numbers = [NSMutableArray array];

        for (int i = 0; i < 7; i++) {
            UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];

            button.tag = i;

            [button addTarget:self action:@selector(dayTapped:)
             forControlEvents:UIControlEventTouchUpInside];
            [_row addSubview:button];
            [_buttons addObject:button];

            UILabel *caption = [[UILabel alloc] initWithFrame:CGRectZero];
            caption.font = [UIFont systemFontOfSize:12.0];
            caption.textAlignment = NSTextAlignmentCenter;
            caption.backgroundColor = [UIColor clearColor];
            caption.userInteractionEnabled = NO;
            [button addSubview:caption];
            [_captions addObject:caption];

            UILabel *number = [[UILabel alloc] initWithFrame:CGRectZero];
            number.font = [UIFont systemFontOfSize:16.0];
            number.textAlignment = NSTextAlignmentCenter;
            number.backgroundColor = [UIColor clearColor];
            number.userInteractionEnabled = NO;
            [button addSubview:number];
            [_numbers addObject:number];
        }

        UISwipeGestureRecognizer *left =
            [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(swipeLeft)];
        left.direction = UISwipeGestureRecognizerDirectionLeft;
        [self addGestureRecognizer:left];

        UISwipeGestureRecognizer *right =
            [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(swipeRight)];
        right.direction = UISwipeGestureRecognizerDirectionRight;
        [self addGestureRecognizer:right];
    }

    return self;
}

- (void)setDay:(NSDate *)day {
    _day = YCStartOfDay(day);

    // Неделя с понедельника: календарь приложения так и настроен.
    NSDateComponents *parts = [YCCalendar() components:NSWeekdayCalendarUnit fromDate:_day];
    NSInteger weekday = parts.weekday;           // 1 = вс … 7 = сб
    NSInteger sinceMonday = (weekday + 5) % 7;   // пн → 0, вс → 6

    NSDate *previous = _weekStart;

    _weekStart = YCDayByAdding(_day, -sinceMonday);

    /**
     * Неделя сменилась — листаем, а не подменяем.
     *
     * Раньше семь подписей просто переписывались на месте: было «8–14»,
     * стало «15–21», и по какую сторону ушла неделя, понять было не по чему.
     * Теперь ряд уезжает в сторону смахивания, а следующий приходит
     * с противоположной — направление видно.
     *
     * Первая установка дня (previous ещё пуста) проходит без движения:
     * полосе неоткуда листаться, она только появилась.
     */
    if (previous != nil && !YCSameDay(previous, _weekStart)) {
        [self slideForward:[_weekStart compare:previous] == NSOrderedDescending];

        return;
    }

    [self refresh];
}

- (void)slideForward:(BOOL)forward {
    // Быстрое двойное смахивание не должно наслаивать движения: пока идёт
    // одно, следующая неделя просто встаёт на место.
    if (_sliding || self.bounds.size.width < 1.0) {
        [self refresh];

        return;
    }

    _sliding = YES;

    CGRect home = self.bounds;
    CGFloat away = forward ? -home.size.width : home.size.width;

    [UIView animateWithDuration:0.15
                          delay:0.0
                        options:UIViewAnimationOptionCurveEaseIn
                     animations:^{
        _row.frame = CGRectOffset(home, away, 0);
    }
                     completion:^(BOOL finished) {
        [self refresh];

        // Новая неделя заводится с противоположной стороны и въезжает.
        _row.frame = CGRectOffset(home, -away, 0);

        [UIView animateWithDuration:0.19
                              delay:0.0
                            options:UIViewAnimationOptionCurveEaseOut
                         animations:^{
            _row.frame = home;
        }
                         completion:^(BOOL done) {
            _sliding = NO;
        }];
    }];
}

- (void)refresh {
    static NSArray *names;
    static dispatch_once_t once;

    dispatch_once(&once, ^{ names = @[ @"пн", @"вт", @"ср", @"чт", @"пт", @"сб", @"вс" ]; });

    for (int i = 0; i < 7; i++) {
        NSDate *date = YCDayByAdding(_weekStart, i);

        BOOL selected = YCSameDay(date, self.day);
        BOOL weekend = (i >= 5);

        UIButton *button = [_buttons objectAtIndex:i];
        UILabel *caption = [_captions objectAtIndex:i];
        UILabel *number = [_numbers objectAtIndex:i];

        NSDateComponents *parts = [YCCalendar() components:NSDayCalendarUnit fromDate:date];

        caption.text = [names objectAtIndex:i];
        number.text = [NSString stringWithFormat:@"%ld", (long)parts.day];

        [YCTheme decorateButton:button
                          color:(selected ? [YCTheme accent] : [UIColor clearColor])
                         radius:10.0];

        UIColor *ink = selected ? [YCTheme text]
                     : weekend  ? [YCTheme weekend]
                                : [UIColor colorWithWhite:0.85 alpha:1.0];

        caption.textColor = ink;
        number.textColor = ink;
    }
}

- (void)layoutSubviews {
    [super layoutSubviews];

    // Во время листания рамку ряда трогать нельзя — она и есть движение.
    if (!_sliding) {
        _row.frame = self.bounds;
    }

    CGFloat inset = 8.0;
    CGFloat width = (self.bounds.size.width - inset * 2) / 7.0;
    CGFloat height = self.bounds.size.height - inset * 2;

    for (int i = 0; i < 7; i++) {
        UIButton *button = [_buttons objectAtIndex:i];

        button.frame = CGRectMake(inset + i * width + 2, inset, width - 4, height);

        [[_captions objectAtIndex:i] setFrame:CGRectMake(0, 4, width - 4, 18)];
        [[_numbers objectAtIndex:i] setFrame:CGRectMake(0, 22, width - 4, height - 26)];
    }
}

- (void)dayTapped:(UIButton *)button {
    [self.delegate weekStrip:self didPickDay:YCDayByAdding(_weekStart, button.tag)];
}

- (void)swipeLeft {
    [self.delegate weekStrip:self didPickDay:YCDayByAdding(self.day, 7)];
}

- (void)swipeRight {
    [self.delegate weekStrip:self didPickDay:YCDayByAdding(self.day, -7)];
}

@end
