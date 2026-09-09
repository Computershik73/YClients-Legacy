#import "YCRecordFormController.h"

#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>

#import "YCAlert.h"
#import "YCApi.h"
#import "YCClientFormController.h"
#import "YCDateTimeController.h"
#import "YCIcons.h"
#import "YCSheet.h"
#import "YCStaffPickerController.h"
#import "YCTheme.h"
#import "YCTime.h"

typedef enum {
    YCRowClient = 0,
    YCRowServices,
    YCRowStaff,
    YCRowDateTime,
    YCRowExtraHeader,   // подпись «Дополнительные настройки»
    YCRowLength,
    YCRowColor,
    YCRowComment,
    YCRowCount
} YCFormRow;

/** Источник для колеса «часы : минуты» — см. -pickLength. */
@interface YCLengthWheel : NSObject <UIPickerViewDataSource, UIPickerViewDelegate>
@end

@interface YCRecordFormController () <UITextViewDelegate>
@end

@implementation YCRecordFormController {
    YCRecord *_record;      // nil у новой
    NSArray *_allStaff;

    NSString *_name;
    NSString *_phone;
    NSString *_email;
    NSInteger _staffId;
    NSDate *_start;
    NSTimeInterval _length;
    NSString *_color;       // hex без решётки, «» — нет
    NSInteger _serviceId;
    NSString *_serviceTitle;
    BOOL _serviceChanged;

    NSArray *_services;     // услуги текущего сотрудника
    NSString *_servicesError;

    UITextView *_comment;
    UIScrollView *_palette;
    BOOL _saving;
}

#pragma mark Создание

- (id)initWithNewRecordForStaff:(YCStaff *)staff
                         atTime:(NSDate *)time
                          staff:(NSArray *)allStaff {
    self = [super initWithStyle:UITableViewStylePlain buttonTitle:@"Создать"];

    if (self != nil) {
        _allStaff = allStaff;
        _staffId = staff.staffId;
        _start = time;
        _length = staff.seanceLength > 0 ? staff.seanceLength : 3600;
        _name = @"";
        _phone = @"";
        _email = @"";
        _color = @"";
    }

    return self;
}

- (id)initWithRecord:(YCRecord *)record staff:(NSArray *)allStaff {
    self = [super initWithStyle:UITableViewStylePlain buttonTitle:@"Сохранить"];

    if (self != nil) {
        _record = record;
        _allStaff = allStaff;
        _staffId = record.staffId;
        _start = record.start;
        _length = record.length;
        _name = record.clientName ?: @"";
        _phone = record.clientPhone ?: @"";
        _email = record.clientEmail ?: @"";
        _color = record.customColor ?: @"";
        _serviceId = [record.serviceIds count] > 0
            ? [[record.serviceIds objectAtIndex:0] integerValue] : 0;
        _serviceTitle = record.services;
    }

    return self;
}

- (void)prefillClientName:(NSString *)name phone:(NSString *)phone {
    _name = name ?: @"";
    _phone = phone ?: @"";

    // Вид может быть ещё не загружен — тогда таблица нарисуется потом
    // и возьмёт эти значения сама.
    if ([self isViewLoaded]) {
        [self.tableView reloadData];
    }
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = _record != nil ? @"Запись" : @"Новая запись";

    _comment = [[UITextView alloc] initWithFrame:CGRectZero];
    _comment.font = [YCTheme bodyFont];
    _comment.textColor = [YCTheme text];
    _comment.backgroundColor = [YCTheme isLegacy] ? [UIColor whiteColor]
                                                  : [YCTheme surface];
    _comment.text = _record.comment ?: @"";
    _comment.layer.cornerRadius = [YCTheme cornerRadius];
    _comment.layer.borderWidth = 1.0;
    _comment.layer.borderColor = [YCTheme border].CGColor;

    /**
     * На iOS 6 поле остаётся светлым и в тёмной теме.
     *
     * Причина та же, что у полей ввода: подложку системного бортика
     * не перекрасить, и белый текст лёг бы на белое. UITextView —
     * прокручиваемый вид, подложку картинкой в него не подложить,
     * так что углубление здесь изображает тёмная кайма по светлому.
     */
    if ([YCTheme isLegacy]) {
        _comment.textColor = [UIColor blackColor];
        _comment.layer.borderColor = [UIColor colorWithWhite:0.55 alpha:1.0].CGColor;
    }
    _comment.delegate = self;
    _comment.keyboardAppearance = [YCTheme keyboardAppearance];

    /**
     * Кнопка живёт в YCFormScreen и прибита к низу экрана.
     *
     * Раньше она лежала в tableFooterView — то есть внутри прокручиваемого
     * содержимого, — а по клавиатуре список ещё и доскролливался в самый
     * низ. На экране оставалась одна кнопка и белое поле под ней; на видео
     * это и выглядело как сломанная прокрутка.
     */
    [self loadServices];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];

    // Возвращаемся с подэкрана — строки перечитывают значения.
    [self.tableView reloadData];
}

#pragma mark Услуги

- (void)loadServices {
    NSInteger forStaff = _staffId;

    _services = nil;
    _servicesError = nil;

    [[YCApi shared] loadServicesForStaff:forStaff completion:^(NSArray *services, NSString *error) {
        if (forStaff != self->_staffId) {
            return;
        }

        if (error != nil) {
            self->_services = @[];
            self->_servicesError = error;
            [self.tableView reloadData];
            return;
        }

        self->_services = services;

        BOOL offered = NO;

        for (YCService *service in services) {
            if (service.serviceId == self->_serviceId) {
                offered = YES;
                self->_serviceTitle = service.title;
            }
        }

        /**
         * Услуга подставляется первой из списка, если выбранной там нет:
         * у новой записи — чтобы сохранение прошло с первого раза; при
         * смене сотрудника — потому что прежней у него может не быть,
         * а узнать об этом лучше здесь, чем отказом при сохранении.
         */
        if (!offered && [services count] > 0) {
            YCService *first = [services objectAtIndex:0];

            if (self->_serviceId != 0) {
                self->_serviceChanged = YES;
            }

            self->_serviceId = first.serviceId;
            self->_serviceTitle = first.title;

            if (self->_record == nil && first.duration > 0) {
                self->_length = first.duration;
            }
        }

        [self.tableView reloadData];
    }];
}

#pragma mark Клавиатура

/**
 * Отступ под клавиатуру ставит YCFormScreen; здесь только подводим
 * комментарий к видимой части.
 *
 * scrollRectToVisible: двигает список ровно настолько, насколько нужно.
 * Раньше здесь стоял scrollToRowAtIndexPath: с положением Bottom —
 * а комментарий последняя строка, и «прижать её к низу» при отступе
 * в высоту клавиатуры означало уехать в самый конец: на экране
 * оставалась одна кнопка и пустота.
 */
- (void)textViewDidBeginEditing:(UITextView *)textView {
    NSIndexPath *path = [NSIndexPath indexPathForRow:YCRowComment inSection:0];

    // Через задержку: отступ под клавиатуру встанет по своему уведомлению,
    // и до него подводить нечего — видимая часть ещё прежняя.
    dispatch_async(dispatch_get_main_queue(), ^{
        CGRect row = [self.tableView rectForRowAtIndexPath:path];

        [self.tableView scrollRectToVisible:row animated:YES];
    });
}

#pragma mark Список

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return YCRowCount;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)path {
    switch (path.row) {
        case YCRowExtraHeader: return [YCTheme isCompact] ? 42.0 : 48.0;
        case YCRowColor:       return [YCTheme isCompact] ? 94.0 : 108.0;
        case YCRowComment:     return [YCTheme isCompact] ? 128.0 : 148.0;
        case YCRowLength:      return [YCTheme rowHeight];
        default:               return [YCTheme formRowHeight];
    }
}

/** Двухстрочная строка «Заголовок / значение ›» — основа формы. */
- (UITableViewCell *)rowWithTitle:(NSString *)title value:(NSString *)value muted:(BOOL)muted {
    UITableViewCell *cell =
        [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
                               reuseIdentifier:nil];

    cell.textLabel.text = title;
    cell.textLabel.font = [YCTheme rowFont];
    cell.textLabel.textColor = [YCTheme text];

    cell.detailTextLabel.text = value;
    cell.detailTextLabel.font = [YCTheme bodyFont];
    cell.detailTextLabel.textColor = muted ? [YCTheme mutedText] : [YCTheme text];

    cell.accessoryView = [[UIImageView alloc]
        initWithImage:[YCIcons chevronRight:20 color:[YCTheme accent]]];

    return cell;
}

- (UITableViewCell *)tableView:(UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *)path {
    switch (path.row) {
        case YCRowClient: {
            BOOL empty = [_name length] == 0 && [_phone length] == 0;
            NSString *value = empty ? @"Клиент не выбран"
                            : [_name length] > 0 ? _name : _phone;

            return [self rowWithTitle:@"Клиент" value:value muted:empty];
        }

        case YCRowServices: {
            NSString *value = _serviceTitle;

            if ([value length] == 0) {
                value = _services == nil ? @"загружается…"
                      : _servicesError != nil ? @"Сотрудник не оказывает услуг"
                                              : @"Услуги не выбраны";
            }

            return [self rowWithTitle:@"Услуги" value:value muted:(_serviceId == 0)];
        }

        case YCRowStaff:
            return [self rowWithTitle:@"Сотрудник" value:[self staffName] muted:NO];

        case YCRowDateTime:
            return [self rowWithTitle:@"Дата и время" value:YCDateTimeFromDate(_start) muted:NO];

        case YCRowExtraHeader: {
            UITableViewCell *cell =
                [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
                                       reuseIdentifier:nil];

            cell.textLabel.text = @"Дополнительные настройки";
            cell.textLabel.font = [UIFont boldSystemFontOfSize:17.0];
            cell.textLabel.textColor = [YCTheme text];
            cell.selectionStyle = UITableViewCellSelectionStyleNone;

            return cell;
        }

        case YCRowLength: {
            UITableViewCell *cell =
                [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1
                                       reuseIdentifier:nil];

            cell.textLabel.text = @"Длительность";
            cell.textLabel.font = [YCTheme rowFont];
            cell.textLabel.textColor = [YCTheme text];
            cell.detailTextLabel.text = [self lengthTitle];
            cell.detailTextLabel.textColor = [YCTheme mutedText];
            cell.accessoryView = [[UIImageView alloc]
                initWithImage:[YCIcons chevronRight:20 color:[YCTheme accent]]];

            return cell;
        }

        case YCRowColor:
            return [self colorCell];

        case YCRowComment: {
            UITableViewCell *cell =
                [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
                                       reuseIdentifier:nil];

            cell.selectionStyle = UITableViewCellSelectionStyleNone;

            UILabel *caption = [[UILabel alloc] initWithFrame:
                CGRectMake(16, 10, cell.contentView.bounds.size.width - 32, 20)];

            caption.text = @"Комментарий";
            caption.font = [YCTheme bodyFont];
            caption.textColor = [YCTheme mutedText];
            caption.backgroundColor = [UIColor clearColor];
            caption.autoresizingMask = UIViewAutoresizingFlexibleWidth;
            [cell.contentView addSubview:caption];

            _comment.frame = CGRectMake(16, 32, cell.contentView.bounds.size.width - 32,
                                [YCTheme isCompact] ? 88 : 104);
            _comment.autoresizingMask = UIViewAutoresizingFlexibleWidth;
            [cell.contentView addSubview:_comment];

            return cell;
        }

        default:
            return [[UITableViewCell alloc] init];
    }
}

/**
 * Ряд кружков «Цвет записи», прокручиваемый вбок.
 *
 * Выбранный обведён тёмным кольцом; первый кружок — «без цвета»,
 * перечёркнутый.
 */
- (UITableViewCell *)colorCell {
    UITableViewCell *cell =
        [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
                               reuseIdentifier:nil];

    cell.selectionStyle = UITableViewCellSelectionStyleNone;

    UILabel *caption = [[UILabel alloc] initWithFrame:
        CGRectMake(16, 10, cell.contentView.bounds.size.width - 32, 20)];

    caption.text = @"Цвет записи";
    caption.font = [YCTheme bodyFont];
    caption.textColor = [YCTheme mutedText];
    caption.backgroundColor = [UIColor clearColor];
    caption.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [cell.contentView addSubview:caption];

    _palette = [[UIScrollView alloc] initWithFrame:
        CGRectMake(0, 38, cell.contentView.bounds.size.width, 72)];

    _palette.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    _palette.showsHorizontalScrollIndicator = NO;

    NSArray *palette = [YCTheme recordPalette];
    CGFloat x = 16;

    for (NSUInteger i = 0; i < [palette count]; i++) {
        NSString *hex = [palette objectAtIndex:i];

        UIButton *dot = [UIButton buttonWithType:UIButtonTypeCustom];

        CGFloat dotSize = [YCTheme isCompact] ? 42.0 : 48.0;

        dot.frame = CGRectMake(x, 6, dotSize, dotSize);
        dot.tag = i;

        UIColor *fill = [YCTheme surface];

        if ([hex length] == 0) {
            [dot setTitle:@"∅" forState:UIControlStateNormal];
            [dot setTitleColor:[YCTheme mutedText] forState:UIControlStateNormal];
        } else {
            fill = [YCTheme recordColorForAttendance:0 customColor:hex];
        }

        [YCTheme decorateButton:dot color:fill radius:dotSize / 2];

        if ([hex caseInsensitiveCompare:_color] == NSOrderedSame) {
            // Выбранный цвет обведён: у выпуклой плашки своя кайма уже
            // есть, поэтому обводка кладётся поверх, на слой самой кнопки.
            dot.layer.cornerRadius = dotSize / 2;
            dot.layer.borderWidth = 3.0;
            dot.layer.borderColor = [YCTheme text].CGColor;
        }

        [dot addTarget:self action:@selector(colorTapped:)
      forControlEvents:UIControlEventTouchUpInside];
        [_palette addSubview:dot];

        x += ([YCTheme isCompact] ? 52 : 60);
    }

    _palette.contentSize = CGSizeMake(x + 8, 72);
    [cell.contentView addSubview:_palette];

    return cell;
}

- (void)colorTapped:(UIButton *)dot {
    _color = [[YCTheme recordPalette] objectAtIndex:dot.tag];

    [self.tableView reloadRowsAtIndexPaths:@[ [NSIndexPath indexPathForRow:YCRowColor inSection:0] ]
                          withRowAnimation:UITableViewRowAnimationNone];
}

- (NSString *)staffName {
    for (YCStaff *member in _allStaff) {
        if (member.staffId == _staffId) {
            return member.name;
        }
    }

    return _staffId > 0 ? [NSString stringWithFormat:@"№%ld", (long)_staffId] : @"Не выбран";
}

- (NSString *)lengthTitle {
    NSInteger minutes = (NSInteger)round(_length / 60.0);

    if (minutes < 60) {
        return [NSString stringWithFormat:@"%ld мин", (long)minutes];
    }

    if (minutes % 60 == 0) {
        return [NSString stringWithFormat:@"%ld ч", (long)(minutes / 60)];
    }

    return [NSString stringWithFormat:@"%ld ч %ld мин", (long)(minutes / 60), (long)(minutes % 60)];
}

#pragma mark Нажатия

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path {
    [tableView deselectRowAtIndexPath:path animated:YES];
    [self.view endEditing:YES];

    switch (path.row) {
        case YCRowClient: {
            YCClientFormController *form =
                [[YCClientFormController alloc] initWithName:_name phone:_phone email:_email
                                                    onChoose:^(NSString *name, NSString *phone,
                                                               NSString *email) {
                self->_name = name;
                self->_phone = phone;
                self->_email = email;
            }];

            [self.navigationController pushViewController:form animated:YES];
            break;
        }

        case YCRowServices: {
            if (_services == nil) {
                [self loadServices];
                return;
            }

            YCServicePickerController *picker =
                [[YCServicePickerController alloc] initWithServices:_services
                                                           selected:_serviceId
                                                           onChoose:^(YCService *service) {
                if (service == nil) {
                    return;
                }

                self->_serviceId = service.serviceId;
                self->_serviceTitle = service.title;
                self->_serviceChanged = YES;

                if (self->_record == nil && service.duration > 0) {
                    self->_length = service.duration;
                }
            }];

            [self.navigationController pushViewController:picker animated:YES];
            break;
        }

        case YCRowStaff: {
            YCStaffPickerController *picker =
                [[YCStaffPickerController alloc] initWithStaff:_allStaff
                                                      selected:_staffId
                                                      onChoose:^(YCStaff *staff) {
                if (staff == nil || staff.staffId == self->_staffId) {
                    return;
                }

                self->_staffId = staff.staffId;
                self->_serviceTitle = nil;

                // У другого мастера свой набор услуг — перечитываем.
                [self loadServices];
            }];

            [self.navigationController pushViewController:picker animated:YES];
            break;
        }

        case YCRowDateTime: {
            YCDateTimeController *picker =
                [[YCDateTimeController alloc] initWithDate:_start onChoose:^(NSDate *chosen) {
                self->_start = chosen;
            }];

            [self.navigationController pushViewController:picker animated:YES];
            break;
        }

        case YCRowLength:
            [self pickLength];
            break;

        default:
            break;
    }
}

/**
 * Длительность — колесо «часы : минуты» в панели снизу, как в оригинале.
 *
 * Компонентов два: часы 0–23 и минуты с шагом 5. Панель — YCSheet
 * с UIPickerView внутри; источник данных у панели свой, здесь только
 * чтение результата.
 */
- (void)pickLength {
    UIPickerView *wheel = [[UIPickerView alloc] initWithFrame:CGRectMake(0, 0, 320, 216)];

    YCLengthWheel *source = [[YCLengthWheel alloc] init];

    wheel.dataSource = source;
    wheel.delegate = source;
    wheel.showsSelectionIndicator = YES;

    [YCTheme decoratePicker:wheel];

    NSInteger minutes = (NSInteger)round(_length / 60.0);

    [wheel selectRow:minutes / 60 inComponent:0 animated:NO];
    [wheel selectRow:(minutes % 60) / 5 inComponent:1 animated:NO];

    // Источник живёт, пока жива панель: колесо держит его слабо.
    objc_setAssociatedObject(wheel, "source", source, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    [YCSheet presentWithTitle:@"Выберите длительность" content:wheel
                  buttonTitle:@"Выбрать" onButton:^{
        NSInteger hours = [wheel selectedRowInComponent:0];
        NSInteger mins = [wheel selectedRowInComponent:1] * 5;

        if (hours == 0 && mins == 0) {
            mins = 5;
        }

        self->_length = hours * 3600 + mins * 60;
        [self.tableView reloadData];
    }];
}

#pragma mark Сохранение

- (void)setBusy:(BOOL)busy {
    _saving = busy;
    self.button.enabled = !busy;
    self.button.alpha = busy ? 0.5 : 1.0;
    self.tableView.userInteractionEnabled = !busy;
}

/**
 * Создаёт запись; при отказе предлагает записать поверх занятого времени.
 *
 * Сервер отказывает не только из-за занятого времени — бывает, что
 * сотрудник не оказывает выбранную услугу, — поэтому предложение звучит
 * после его слов, а не вместо них: человек читает причину и решает сам.
 * Повторная попытка идёт с save_if_busy, и если причина была другая,
 * сервер откажет снова тем же текстом. Это честнее, чем разбирать его
 * сообщение по словам и угадывать, когда предлагать, а когда нет.
 */
- (void)createForced:(BOOL)force comment:(NSString *)comment {
    [[YCApi shared] createRecordForStaff:_staffId name:_name phone:_phone
                                   start:_start length:_length comment:comment
                               serviceId:_serviceId color:_color force:force
                              completion:^(NSInteger recordId, NSString *error) {
        [self setBusy:NO];

        if (recordId != 0) {
            [self.delegate recordFormDidChangeRecords:self];
            YCDismissModal(self);
            return;
        }

        if (force) {
            YCAlertMessage(self, @"Не создалась", error);
            return;
        }

        YCAlertConfirm(self, @"Не создалась",
                       [NSString stringWithFormat:@"%@\n\nЗаписать всё равно?",
                        error ?: @"Сервер отказал."],
                       @"Записать", NO, ^{
            [self setBusy:YES];
            [self createForced:YES comment:comment];
        });
    }];
}

- (void)buttonTapped {
    if (_saving) {
        return;
    }

    [self.view endEditing:YES];

    /**
     * Услуга больше не обязательна.
     *
     * Отказывать здесь было неправильно: чаще всего запись заводят
     * на слух — «Мария, вот телефон», — а услугу подставляет
     * администратор, когда перезвонит. Если сервер такую запись
     * не примет, он скажет об этом сам, и мы покажем его слова;
     * решать за него, не отправив запрос, ни к чему.
     */
    if (_staffId == 0) {
        YCAlertMessage(self, @"Выберите сотрудника", @"Без сотрудника записи некуда встать.");
        return;
    }

    [self setBusy:YES];

    NSString *comment = _comment.text ?: @"";

    if (_record == nil) {
        [self createForced:NO comment:comment];
        return;
    }

    NSArray *serviceIds = (!_serviceChanged && [_record.serviceIds count] > 0)
        ? _record.serviceIds : @[ @(_serviceId) ];

    [[YCApi shared] updateRecord:_record name:_name phone:_phone email:_email
                           staff:_staffId start:_start length:_length comment:comment
                      serviceIds:serviceIds color:_color
                      completion:^(BOOL ok, NSString *error) {
        [self setBusy:NO];

        if (!ok) {
            YCAlertMessage(self, @"Не сохранилось", error);
            return;
        }

        [self.delegate recordFormDidChangeRecords:self];
        [self.navigationController popViewControllerAnimated:YES];
    }];
}

@end


#pragma mark - Колесо длительности

@implementation YCLengthWheel

- (NSInteger)numberOfComponentsInPickerView:(UIPickerView *)pickerView {
    return 2;
}

- (NSInteger)pickerView:(UIPickerView *)pickerView numberOfRowsInComponent:(NSInteger)component {
    return component == 0 ? 24 : 12;
}

- (NSString *)pickerView:(UIPickerView *)pickerView
             titleForRow:(NSInteger)row
            forComponent:(NSInteger)component {
    return [NSString stringWithFormat:@"%02ld", (long)(component == 0 ? row : row * 5)];
}

@end
