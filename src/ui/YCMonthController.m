#import "YCMonthController.h"

#import "YCTheme.h"
#import "YCTime.h"

/**
 * Сколько месяцев в ленте и с какого она начинается.
 *
 * Три назад и девять вперёд от текущего. Назад — потому что «а когда она
 * была в прошлый раз» спрашивают не реже, чем записывают вперёд; вперёд —
 * потому что дальше квартала не записывают почти никогда, а лента
 * не бесконечная и её нужно где-то кончить.
 */
static const NSInteger YCMonthsBack = 3;
static const NSInteger YCMonthsTotal = 12;

@implementation YCMonthController {
    NSDate *_day;
    void (^_onChoose)(NSDate *);

    UIScrollView *_scroll;
    NSMutableArray *_buttons;   // пары «кнопка, дата»
    NSDate *_firstMonth;
}

- (id)initWithDay:(NSDate *)day onChoose:(void (^)(NSDate *))onChoose {
    self = [super init];

    if (self != nil) {
        _day = YCStartOfDay(day ?: [NSDate date]);
        _onChoose = [onChoose copy];
        _buttons = [NSMutableArray array];
    }

    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = @"Календарь";
    self.view.backgroundColor = [YCTheme background];

    if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)]) {
        self.edgesForExtendedLayout = UIRectEdgeNone;
    }

    _scroll = [[UIScrollView alloc] initWithFrame:self.view.bounds];
    _scroll.autoresizingMask = UIViewAutoresizingFlexibleWidth |
                               UIViewAutoresizingFlexibleHeight;
    _scroll.alwaysBounceVertical = YES;
    _scroll.backgroundColor = [YCTheme background];
    [self.view addSubview:_scroll];

    [self buildMonths];
}

#pragma mark Сборка

/** Полночь первого числа месяца, в который попадает date. */
static NSDate *YCFirstOfMonth(NSDate *date) {
    NSCalendar *calendar = YCCalendar();
    NSDateComponents *parts =
        [calendar components:(NSYearCalendarUnit | NSMonthCalendarUnit) fromDate:date];

    return [calendar dateFromComponents:parts];
}

- (void)buildMonths {
    NSCalendar *calendar = YCCalendar();
    NSDateComponents *shift = [[NSDateComponents alloc] init];

    shift.month = -YCMonthsBack;

    _firstMonth = [calendar dateByAddingComponents:shift
                                            toDate:YCFirstOfMonth(_day)
                                           options:0];

    NSArray *names = @[ @"пн", @"вт", @"ср", @"чт", @"пт", @"сб", @"вс" ];
    NSDate *month = _firstMonth;

    for (NSInteger i = 0; i < YCMonthsTotal; i++) {
        UILabel *title = [[UILabel alloc] initWithFrame:CGRectZero];

        title.text = YCMonthTitleFromDate(month);
        title.font = [YCTheme titleFont];
        title.textColor = [YCTheme text];
        title.backgroundColor = [UIColor clearColor];
        title.tag = 1000 + i;
        [_scroll addSubview:title];

        for (NSInteger d = 0; d < 7; d++) {
            UILabel *caption = [[UILabel alloc] initWithFrame:CGRectZero];

            caption.text = [names objectAtIndex:d];
            caption.font = [YCTheme captionFont];
            caption.textColor = (d >= 5) ? [YCTheme weekend] : [YCTheme mutedText];
            caption.textAlignment = NSTextAlignmentCenter;
            caption.backgroundColor = [UIColor clearColor];
            caption.tag = 2000 + i * 7 + d;
            [_scroll addSubview:caption];
        }

        NSRange days = [calendar rangeOfUnit:NSDayCalendarUnit
                                      inUnit:NSMonthCalendarUnit
                                     forDate:month];

        for (NSInteger day = 1; day <= (NSInteger)days.length; day++) {
            NSDate *date = YCDayByAdding(month, day - 1);
            UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];

            [button setTitle:[NSString stringWithFormat:@"%ld", (long)day]
                    forState:UIControlStateNormal];

            button.titleLabel.font = [YCTheme bodyFont];

            [button addTarget:self action:@selector(dayTapped:)
             forControlEvents:UIControlEventTouchUpInside];

            [_scroll addSubview:button];
            [_buttons addObject:@[ button, date ]];
        }

        shift.month = 1;
        month = [calendar dateByAddingComponents:shift toDate:month options:0];
    }

    [self recolorDays];
}

- (void)recolorDays {
    NSDate *today = YCStartOfDay([NSDate date]);

    for (NSArray *pair in _buttons) {
        UIButton *button = [pair objectAtIndex:0];
        NSDate *date = [pair objectAtIndex:1];

        BOOL selected = YCSameDay(date, _day);
        BOOL isToday = YCSameDay(date, today);

        NSDateComponents *parts =
            [YCCalendar() components:NSWeekdayCalendarUnit fromDate:date];
        BOOL weekend = (parts.weekday == 1 || parts.weekday == 7);

        UIColor *fill = selected ? [YCTheme accent]
                      : isToday  ? [[YCTheme accent] colorWithAlphaComponent:0.35]
                                 : [UIColor clearColor];

        [YCTheme decorateButton:button color:fill radius:18.0];

        UIColor *ink = selected ? [YCTheme text]
                     : weekend  ? [YCTheme weekend]
                                : [YCTheme text];

        [button setTitleColor:ink forState:UIControlStateNormal];
    }
}

#pragma mark Разметка

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];

    _scroll.frame = self.view.bounds;

    CGFloat width = _scroll.bounds.size.width;

    // Столбец ограничен: на iPad клетка в сто точек шириной выглядит
    // не календарём, а шахматной доской.
    CGFloat inner = MIN(width - 32, 420);
    CGFloat inset = (width - inner) / 2;
    CGFloat cell = floor(inner / 7.0);
    CGFloat y = 16;

    NSCalendar *calendar = YCCalendar();
    NSUInteger index = 0;

    for (NSInteger i = 0; i < YCMonthsTotal; i++) {
        UILabel *title = (UILabel *)[_scroll viewWithTag:1000 + i];

        title.frame = CGRectMake(inset, y, inner, 28);
        y += 34;

        for (NSInteger d = 0; d < 7; d++) {
            UILabel *caption = (UILabel *)[_scroll viewWithTag:2000 + i * 7 + d];

            caption.frame = CGRectMake(inset + d * cell, y, cell, 18);
        }

        y += 22;

        if (index >= [_buttons count]) {
            break;
        }

        // Первое число — в свою колонку недели, считая с понедельника.
        NSArray *firstPair = [_buttons objectAtIndex:index];
        NSDate *firstDate = [firstPair objectAtIndex:1];
        NSInteger weekday =
            [calendar components:NSWeekdayCalendarUnit fromDate:firstDate].weekday;
        NSInteger column = (weekday + 5) % 7;

        NSRange days = [calendar rangeOfUnit:NSDayCalendarUnit
                                      inUnit:NSMonthCalendarUnit
                                     forDate:firstDate];

        for (NSInteger day = 0; day < (NSInteger)days.length; day++) {
            if (index >= [_buttons count]) {
                break;
            }

            UIButton *button = [[_buttons objectAtIndex:index] objectAtIndex:0];
            NSInteger position = column + day;
            NSInteger row = position / 7;

            button.frame = CGRectMake(inset + (position % 7) * cell + 2,
                                      y + row * cell + 2,
                                      cell - 4, cell - 4);

            index++;
        }

        NSInteger rows = (column + (NSInteger)days.length + 6) / 7;

        y += rows * cell + 20;
    }

    _scroll.contentSize = CGSizeMake(width, y);
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];

    [self scrollToSelected];
}

/**
 * Показанный день должен быть на экране сразу.
 *
 * Лента начинается за три месяца до него, и без этого шага она
 * открывалась бы на давно прошедшем месяце — а искали, как правило,
 * рядом с сегодняшним.
 */
- (void)scrollToSelected {
    for (NSArray *pair in _buttons) {
        if (YCSameDay([pair objectAtIndex:1], _day)) {
            UIButton *button = [pair objectAtIndex:0];

            [_scroll scrollRectToVisible:CGRectInset(button.frame, 0, -120) animated:NO];
            return;
        }
    }
}

#pragma mark Выбор

- (void)dayTapped:(UIButton *)button {
    for (NSArray *pair in _buttons) {
        if ([pair objectAtIndex:0] != button) {
            continue;
        }

        NSDate *chosen = [pair objectAtIndex:1];

        _day = chosen;

        [self recolorDays];

        if (_onChoose != nil) {
            _onChoose(chosen);
        }

        return;
    }
}

@end
