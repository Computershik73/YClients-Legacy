#import "YCDateTimeController.h"

#import <QuartzCore/QuartzCore.h>

#import "YCSheet.h"
#import "YCTheme.h"
#import "YCTime.h"

/** Сколько месяцев показывать, начиная с текущего. */
static const NSInteger YCMonthsShown = 6;

/** Шаг списка времени, секунд. */
static const NSTimeInterval YCTimeListStep = 5 * 60;

@interface YCDateTimeController () <UITableViewDataSource, UITableViewDelegate>
@end

@implementation YCDateTimeController {
    NSDate *_day;              // выбранный день (полночь)
    NSTimeInterval _seconds;   // выбранное время от полуночи
    void (^_onChoose)(NSDate *);

    UIScrollView *_months;
    UITableView *_times;
    UIButton *_save;
    NSMutableArray *_dayButtons;   // все кнопки дней — чтобы перекрасить
}

- (id)initWithDate:(NSDate *)date onChoose:(void (^)(NSDate *))onChoose {
    self = [super init];

    if (self != nil) {
        _day = YCStartOfDay(date);
        _seconds = YCSecondsIntoDay(date);
        _onChoose = [onChoose copy];
        _dayButtons = [NSMutableArray array];
    }

    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = @"Дата и время";
    self.view.backgroundColor = [YCTheme background];

    if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)]) {
        self.edgesForExtendedLayout = UIRectEdgeNone;
    }

    _months = [[UIScrollView alloc] initWithFrame:CGRectZero];
    _months.alwaysBounceVertical = YES;
    _months.backgroundColor = [YCTheme background];
    [self.view addSubview:_months];

    _times = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    _times.dataSource = self;
    _times.delegate = self;
    _times.rowHeight = 52.0;
    _times.separatorColor = [YCTheme gridLine];
    _times.backgroundColor = [YCTheme background];
    [self.view addSubview:_times];

    _save = [YCSheet yellowButtonWithTitle:@"Сохранить"];
    [_save addTarget:self action:@selector(save) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:_save];

    [self buildMonths];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];

    CGRect bounds = self.view.bounds;
    CGFloat buttonArea = 88.0;
    CGFloat usable = bounds.size.height - buttonArea;

    // Календарю — три пятых, времени — две: месяц должен быть виден целиком.
    _months.frame = CGRectMake(0, 0, bounds.size.width, floor(usable * 0.6));
    _times.frame = CGRectMake(0, CGRectGetMaxY(_months.frame),
                              bounds.size.width, usable - _months.frame.size.height);
    _save.frame = CGRectMake(16, bounds.size.height - 72, bounds.size.width - 32, 56);

    [self layoutMonths];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];

    NSInteger row = (NSInteger)round(_seconds / YCTimeListStep);

    [_times scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:row inSection:0]
                  atScrollPosition:UITableViewScrollPositionTop
                          animated:NO];
}

#pragma mark Календарь

/**
 * Строит месяцы кнопками. Раскладка — в -layoutMonths, потому что ширина
 * известна только после появления на экране, а поворот её меняет.
 */
- (void)buildMonths {
    NSCalendar *calendar = YCCalendar();

    NSDateComponents *first = [calendar components:(NSYearCalendarUnit | NSMonthCalendarUnit)
                                          fromDate:[NSDate date]];
    first.day = 1;

    NSDate *month = [calendar dateFromComponents:first];

    for (NSInteger i = 0; i < YCMonthsShown; i++) {
        UILabel *title = [[UILabel alloc] initWithFrame:CGRectZero];

        title.text = YCMonthTitleFromDate(month);
        title.font = [UIFont boldSystemFontOfSize:20.0];
        title.textColor = [YCTheme text];
        title.backgroundColor = [UIColor clearColor];
        title.tag = 1000 + i;
        [_months addSubview:title];

        NSArray *names = @[ @"пн", @"вт", @"ср", @"чт", @"пт", @"сб", @"вс" ];

        for (NSInteger d = 0; d < 7; d++) {
            UILabel *caption = [[UILabel alloc] initWithFrame:CGRectZero];

            caption.text = [names objectAtIndex:d];
            caption.font = [YCTheme captionFont];
            caption.textColor = (d >= 5) ? [YCTheme weekend] : [YCTheme mutedText];
            caption.textAlignment = NSTextAlignmentCenter;
            caption.backgroundColor = [UIColor clearColor];
            caption.tag = 2000 + i * 7 + d;
            [_months addSubview:caption];
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


            // Дата кладётся в кнопку тегом через словарь — у UIButton нет
            // поля под объект, а таблица «кнопка → дата» держится здесь.
            [_dayButtons addObject:@[ button, date ]];

            [button addTarget:self action:@selector(dayTapped:)
             forControlEvents:UIControlEventTouchUpInside];
            [_months addSubview:button];
        }

        NSDateComponents *shift = [[NSDateComponents alloc] init];
        shift.month = 1;
        month = [calendar dateByAddingComponents:shift toDate:month options:0];
    }

    [self recolorDays];
}

- (void)layoutMonths {
    NSCalendar *calendar = YCCalendar();

    CGFloat width = _months.bounds.size.width;
    CGFloat cell = floor((width - 32) / 7.0);
    CGFloat y = 12;

    NSUInteger buttonIndex = 0;

    for (NSInteger i = 0; i < YCMonthsShown; i++) {
        UILabel *title = (UILabel *)[_months viewWithTag:1000 + i];

        title.frame = CGRectMake(16, y, width - 32, 28);
        y += 36;

        for (NSInteger d = 0; d < 7; d++) {
            UILabel *caption = (UILabel *)[_months viewWithTag:2000 + i * 7 + d];

            caption.frame = CGRectMake(16 + d * cell, y, cell, 18);
        }

        y += 24;

        // Первый день месяца — в его колонку недели, считая с понедельника.
        NSArray *firstPair = [_dayButtons objectAtIndex:buttonIndex];
        NSDate *firstDate = [firstPair objectAtIndex:1];
        NSInteger weekday = [calendar components:NSWeekdayCalendarUnit fromDate:firstDate].weekday;
        NSInteger column = (weekday + 5) % 7;

        NSRange days = [calendar rangeOfUnit:NSDayCalendarUnit
                                      inUnit:NSMonthCalendarUnit
                                     forDate:firstDate];

        for (NSInteger day = 0; day < (NSInteger)days.length; day++) {
            UIButton *button = [[_dayButtons objectAtIndex:buttonIndex++] objectAtIndex:0];

            button.frame = CGRectMake(16 + column * cell + (cell - 40) / 2, y, 40, 40);

            column++;

            if (column == 7) {
                column = 0;
                y += 48;
            }
        }

        if (column != 0) {
            y += 48;
        }

        y += 16;
    }

    _months.contentSize = CGSizeMake(width, y);
}

- (void)recolorDays {
    NSDate *today = YCStartOfDay([NSDate date]);

    for (NSArray *pair in _dayButtons) {
        UIButton *button = [pair objectAtIndex:0];
        NSDate *date = [pair objectAtIndex:1];

        BOOL selected = YCSameDay(date, _day);
        BOOL isToday = YCSameDay(date, today);

        // Выбранный — жёлтый круг; сегодня — бледно-жёлтый, как в оригинале.
        UIColor *fill = selected ? [YCTheme accent]
                      : isToday  ? [[YCTheme accent] colorWithAlphaComponent:0.35]
                                 : [UIColor clearColor];

        [YCTheme decorateButton:button color:fill radius:20.0];

        [button setTitleColor:(selected ? [YCTheme text] : [YCTheme mutedText])
                     forState:UIControlStateNormal];
    }
}

- (void)dayTapped:(UIButton *)button {
    for (NSArray *pair in _dayButtons) {
        if ([pair objectAtIndex:0] == button) {
            _day = [pair objectAtIndex:1];
            break;
        }
    }

    [self recolorDays];
}

#pragma mark Время

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)(24 * 3600 / YCTimeListStep);
}

- (UITableViewCell *)tableView:(UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *)path {
    static NSString *identifier = @"time";

    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];

    if (cell == nil) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
                                      reuseIdentifier:identifier];
        cell.textLabel.font = [YCTheme bodyFont];
    }

    NSTimeInterval seconds = path.row * YCTimeListStep;
    BOOL selected = fabs(seconds - _seconds) < 1.0;

    cell.textLabel.text = YCClockFromDate(YCDateWithSecondsIntoDay(_day, seconds));
    cell.textLabel.textColor = [YCTheme text];
    cell.backgroundColor = selected ? [[YCTheme accent] colorWithAlphaComponent:0.25]
                                    : [YCTheme background];

    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path {
    _seconds = path.row * YCTimeListStep;
    [tableView reloadData];
}

- (void)save {
    if (_onChoose != NULL) {
        _onChoose(YCDateWithSecondsIntoDay(_day, _seconds));
    }

    [self.navigationController popViewControllerAnimated:YES];
}

@end
