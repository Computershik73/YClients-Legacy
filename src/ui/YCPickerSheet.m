#import "YCPickerSheet.h"

#import "YCSheet.h"
#import "YCTheme.h"
#import "YCTime.h"

static const CGFloat YCSheetBarHeight = 44.0;
static const CGFloat YCSheetPickerHeight = 216.0;

@interface YCPickerSheet () <UIPickerViewDataSource, UIPickerViewDelegate>
@property (nonatomic, strong) UIView *dimmer;
@property (nonatomic, strong) UIView *panel;
@property (nonatomic, strong) UIDatePicker *picker;
@property (nonatomic, strong) UIPickerView *list;
@property (nonatomic, copy) NSArray *options;
@property (nonatomic, copy) void (^onChoose)(NSDate *);
@property (nonatomic, copy) void (^onChooseRow)(NSInteger);
@end

/**
 * Показанная панель держится здесь.
 *
 * Виды удерживает окно, а вот сам объект-панель, который отвечает на нажатия
 * кнопок, не удерживает никто: цели у UIControl слабые. Без этого набора он
 * умер бы сразу после возврата из метода показа, и нажатие «Готово»
 * приходило бы уже мёртвому объекту.
 */
static NSMutableSet *YCSheetsOnScreen(void) {
    static NSMutableSet *shown;
    static dispatch_once_t once;

    dispatch_once(&once, ^{ shown = [NSMutableSet set]; });

    return shown;
}

@implementation YCPickerSheet

#pragma mark Точки входа

+ (void)presentWithTitle:(NSString *)title
                    date:(NSDate *)date
                    mode:(UIDatePickerMode)mode
          minuteInterval:(NSInteger)minuteInterval
                onChoose:(void (^)(NSDate *))onChoose {
    YCPickerSheet *sheet = [[YCPickerSheet alloc] init];

    sheet.onChoose = onChoose;

    UIDatePicker *picker = [[UIDatePicker alloc] initWithFrame:CGRectZero];

    picker.datePickerMode = mode;

    /**
     * Часовой пояс и календарь — те же, что у всего приложения.
     *
     * Без этого выбранное время уехало бы на разницу поясов: всё остальное
     * приложение живёт в настенном времени салона (см. YCTime.h), а
     * UIDatePicker по умолчанию показывает время устройства.
     */
    picker.timeZone = YCCalendar().timeZone;
    picker.calendar = YCCalendar();
    picker.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"ru_RU"];

    if (minuteInterval > 0) {
        picker.minuteInterval = minuteInterval;
    }

    if (date != nil) {
        picker.date = date;
    }

    /**
     * Колесо остаётся колесом и на новых системах.
     *
     * С iOS 14 UIDatePicker по умолчанию рисуется календариком, который
     * в панель такой высоты не помещается — снизу обрезается. Стиль 1 это
     * UIDatePickerStyleWheels; задаётся через setValue:forKey:, потому что
     * самого свойства в SDK 9.3 нет и назвать его прямо нельзя.
     */
    if ([picker respondsToSelector:@selector(setPreferredDatePickerStyle:)]) {
        [picker setValue:@1 forKey:@"preferredDatePickerStyle"];
    }

    [YCTheme decoratePicker:picker];

    sheet.picker = picker;

    [sheet showWithTitle:title content:picker];
}

+ (void)presentWithTitle:(NSString *)title
                 options:(NSArray *)options
           selectedIndex:(NSInteger)selectedIndex
             onChooseRow:(void (^)(NSInteger))onChooseRow {
    if ([options count] == 0) {
        return;
    }

    YCPickerSheet *sheet = [[YCPickerSheet alloc] init];

    sheet.options = options;
    sheet.onChooseRow = onChooseRow;

    UIPickerView *list = [[UIPickerView alloc] initWithFrame:CGRectZero];

    list.dataSource = sheet;
    list.delegate = sheet;
    list.showsSelectionIndicator = YES;

    [YCTheme decoratePicker:list];

    sheet.list = list;

    if (selectedIndex >= 0 && selectedIndex < (NSInteger)[options count]) {
        [list selectRow:selectedIndex inComponent:0 animated:NO];
    }

    [sheet showWithTitle:title content:list];
}

#pragma mark Показ

- (void)showWithTitle:(NSString *)title content:(UIView *)content {
    UIView *window = YCOverlayHost();

    if (window == nil) {
        return;
    }

    CGRect bounds = window.bounds;
    CGFloat panelHeight = YCSheetBarHeight + YCSheetPickerHeight;

    self.dimmer = [[UIView alloc] initWithFrame:bounds];
    self.dimmer.backgroundColor = [UIColor colorWithWhite:0 alpha:0.0];
    self.dimmer.autoresizingMask =
        UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;

    // Нажатие мимо панели равносильно отмене — так ведут себя все панели
    // в системе, и объяснять это отдельно не нужно.
    UITapGestureRecognizer *tap =
        [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(cancel)];

    [self.dimmer addGestureRecognizer:tap];

    self.panel = [[UIView alloc] initWithFrame:
        CGRectMake(0, bounds.size.height, bounds.size.width, panelHeight)];

    [YCTheme decoratePanel:self.panel color:[YCTheme surface]
                    radius:[YCTheme cornerRadius]];
    self.panel.autoresizingMask = UIViewAutoresizingFlexibleWidth |
                                  UIViewAutoresizingFlexibleTopMargin;

    [self.panel addSubview:[self barWithTitle:title width:bounds.size.width]];

    content.frame = CGRectMake(0, YCSheetBarHeight,
                               bounds.size.width, YCSheetPickerHeight);
    content.autoresizingMask = UIViewAutoresizingFlexibleWidth;

    [self.panel addSubview:content];

    [window addSubview:self.dimmer];
    [window addSubview:self.panel];

    [YCSheetsOnScreen() addObject:self];

    [UIView animateWithDuration:0.25 animations:^{
        self.dimmer.backgroundColor = [UIColor colorWithWhite:0 alpha:0.35];

        CGRect frame = self.panel.frame;

        frame.origin.y = window.bounds.size.height - frame.size.height;
        self.panel.frame = frame;
    }];
}

- (UIView *)barWithTitle:(NSString *)title width:(CGFloat)width {
    UIView *bar = [[UIView alloc] initWithFrame:CGRectMake(0, 0, width, YCSheetBarHeight)];

    [YCTheme decoratePanel:bar color:[YCTheme background] radius:0.0];
    bar.autoresizingMask = UIViewAutoresizingFlexibleWidth;

    /**
     * UIButtonTypeSystem у SDK 9.3 равен единице — тому же числу, что
     * и UIButtonTypeRoundedRect в iOS 6. То есть имя здесь новое, а кнопка
     * на старой системе получится старая, со скруглённой рамкой. Это верно
     * и намеренно: своей внешности у панели нет, пусть выглядит как система.
     */
    UIButton *cancel = [UIButton buttonWithType:UIButtonTypeSystem];

    [cancel setTitle:@"Отмена" forState:UIControlStateNormal];
    [cancel addTarget:self action:@selector(cancel)
     forControlEvents:UIControlEventTouchUpInside];
    cancel.frame = CGRectMake(8, 0, 88, YCSheetBarHeight);
    [bar addSubview:cancel];

    UILabel *caption = [[UILabel alloc] initWithFrame:
        CGRectMake(96, 0, width - 192, YCSheetBarHeight)];

    caption.text = title;
    caption.textAlignment = NSTextAlignmentCenter;
    caption.font = [UIFont boldSystemFontOfSize:15.0];
    caption.textColor = [YCTheme text];
    caption.backgroundColor = [UIColor clearColor];
    caption.adjustsFontSizeToFitWidth = YES;
    caption.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [bar addSubview:caption];

    UIButton *done = [UIButton buttonWithType:UIButtonTypeSystem];

    [done setTitle:@"Готово" forState:UIControlStateNormal];
    [done addTarget:self action:@selector(choose)
   forControlEvents:UIControlEventTouchUpInside];
    done.frame = CGRectMake(width - 96, 0, 88, YCSheetBarHeight);
    done.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    [bar addSubview:done];

    return bar;
}

- (void)dismissThen:(dispatch_block_t)then {
    [UIView animateWithDuration:0.2 animations:^{
        self.dimmer.backgroundColor = [UIColor colorWithWhite:0 alpha:0.0];

        CGRect frame = self.panel.frame;

        frame.origin.y = self.dimmer.bounds.size.height;
        self.panel.frame = frame;
    } completion:^(BOOL finished) {
        [self.dimmer removeFromSuperview];
        [self.panel removeFromSuperview];

        if (then != NULL) {
            then();
        }

        // Снимаем удержание последним: до этой строки объект нужен живым.
        [YCSheetsOnScreen() removeObject:self];
    }];
}

- (void)cancel {
    [self dismissThen:NULL];
}

- (void)choose {
    NSDate *chosenDate = self.picker.date;
    NSInteger chosenRow = self.list != nil ? [self.list selectedRowInComponent:0] : 0;

    void (^dateCallback)(NSDate *) = self.onChoose;
    void (^rowCallback)(NSInteger) = self.onChooseRow;

    [self dismissThen:^{
        if (dateCallback != NULL) {
            dateCallback(chosenDate);
        }

        if (rowCallback != NULL) {
            rowCallback(chosenRow);
        }
    }];
}

#pragma mark UIPickerView

- (NSInteger)numberOfComponentsInPickerView:(UIPickerView *)pickerView {
    return 1;
}

- (NSInteger)pickerView:(UIPickerView *)pickerView numberOfRowsInComponent:(NSInteger)component {
    return [self.options count];
}

- (NSString *)pickerView:(UIPickerView *)pickerView
             titleForRow:(NSInteger)row
            forComponent:(NSInteger)component {
    return [self.options objectAtIndex:row];
}

@end
