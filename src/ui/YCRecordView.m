#import "YCRecordView.h"

#import <QuartzCore/QuartzCore.h>

#import "YCIcons.h"
#import "YCTheme.h"
#import "YCTime.h"

/**
 * Высота цветной шапки со временем.
 *
 * Было 24 на всех устройствах. На четырёхдюймовом экране час занимает
 * 56 точек, и шапка съедала почти половину того, что остаётся под текст:
 * ниже помещались ровно две строки, и третья — комментарий — отрезалась.
 * Двадцати точек подписи в десять пунктов хватает с запасом.
 */
static CGFloat YCRecordHeadHeight(void) {
    return [YCTheme isCompact] ? 20.0 : 22.0;
}

static const CGFloat YCRecordPadding = 8.0;

/** Отступ от шапки до первой строки. */
static const CGFloat YCRecordTextGap = 2.0;

@implementation YCRecordView {
    UIView *_head;
    UILabel *_time;
    UIImageView *_clock;
    UILabel *_title;
    UILabel *_detail;
    UILabel *_note;

    /**
     * Услуги и комментарий держатся строками, а не в подписях.
     *
     * Что из них показать, решается при разметке — там известна высота,
     * а значит и сколько строк поместится. До разметки этого не знает
     * никто: одна и та же запись в час и в три часа выглядит по-разному.
     */
    NSString *_services;
    NSString *_note_text;
}

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];

    if (self != nil) {
        self.layer.cornerRadius = [YCTheme isLegacy] ? 6.0 : 8.0;
        self.clipsToBounds = YES;

        /**
         * Шапка со временем и тело с именем — как карточка в оригинале:
         * тёмная полоса статуса сверху, светлое поле под ней. Цвет тела
         * может быть свой у записи, цвет шапки — только статус.
         */
        _head = [[UIView alloc] initWithFrame:CGRectZero];
        [self addSubview:_head];

        _time = [[UILabel alloc] initWithFrame:CGRectZero];
        _time.backgroundColor = [UIColor clearColor];
        _time.font = [YCTheme recordDetailFont];
        _time.textColor = [UIColor whiteColor];
        [_head addSubview:_time];

        _clock = [[UIImageView alloc] initWithImage:[YCIcons clock:16 color:[UIColor whiteColor]]];
        [_head addSubview:_clock];

        _title = [[UILabel alloc] initWithFrame:CGRectZero];
        _title.backgroundColor = [UIColor clearColor];
        _title.font = [YCTheme recordTitleFont];
        _title.lineBreakMode = NSLineBreakByTruncatingTail;
        [self addSubview:_title];

        _detail = [[UILabel alloc] initWithFrame:CGRectZero];
        _detail.backgroundColor = [UIColor clearColor];
        _detail.font = [YCTheme recordTitleFont];
        _detail.lineBreakMode = NSLineBreakByTruncatingTail;
        [self addSubview:_detail];

        /**
         * Комментарий третьей строкой.
         *
         * В нём чаще всего лежит то, ради чего запись и открывают: имя
         * с телефоном, когда клиента не заводили в базу, или пометка вроде
         * «звонить за час». Раньше его приходилось искать нажатием, хотя
         * место на карточке есть — при записи в час помещаются три строки.
         */
        _note = [[UILabel alloc] initWithFrame:CGRectZero];
        _note.backgroundColor = [UIColor clearColor];
        _note.font = [YCTheme recordDetailFont];
        _note.lineBreakMode = NSLineBreakByTruncatingTail;
        [self addSubview:_note];

        self.layer.shadowColor = [UIColor blackColor].CGColor;
        self.layer.shadowOffset = CGSizeMake(0, 2);
        self.layer.shadowRadius = 3.0;
        self.layer.shadowOpacity = 0.0;
    }

    return self;
}

- (void)setRecord:(YCRecord *)record {
    _record = record;

    UIColor *status = [YCTheme statusColorForAttendance:record.attendance];
    UIColor *fill = [YCTheme recordColorForAttendance:record.attendance
                                          customColor:record.customColor];

    // Тело карточки и полоса статуса — выпуклыми плашками на iOS 6.
    // Вид переиспользуется под другие записи, поэтому красится заново
    // при каждой записи, а не один раз при создании.
    [YCTheme decoratePanel:self color:fill radius:self.layer.cornerRadius];
    [YCTheme decoratePanel:_head color:status radius:0.0];

    UIColor *ink = [YCTheme textColorOnColor:fill];

    _title.textColor = ink;
    _title.text = record.title;

    _time.text = [NSString stringWithFormat:@"%@ – %@",
                  YCClockFromDate(record.start), YCClockFromDate(record.end)];

    _detail.textColor = [ink colorWithAlphaComponent:0.8];
    _note.textColor = [ink colorWithAlphaComponent:0.9];

    _services = [record.services copy];
    _note_text = [record.comment copy];

    [self setNeedsLayout];
}

- (void)setLifted:(BOOL)lifted {
    if (_lifted == lifted) {
        return;
    }

    _lifted = lifted;

    self.layer.shadowOpacity = lifted ? 0.35 : 0.0;

    if (lifted) {
        [self.superview bringSubviewToFront:self];
    }

    // Обрезка снимается вместе с подъёмом: тень рисуется за границами.
    self.clipsToBounds = !lifted;
    self.alpha = lifted ? 0.92 : 1.0;
}

- (void)layoutSubviews {
    [super layoutSubviews];

    CGFloat width = self.bounds.size.width;
    CGFloat height = self.bounds.size.height;

    /**
     * Низкая запись — только шапка: в четверть часа помещается ровно
     * полоса со временем, и имя в ней всё равно не прочесть. Шапка при
     * этом ужимается до высоты записи, чтобы тело не выглядывало.
     */
    CGFloat head = MIN(YCRecordHeadHeight(), height);

    _head.frame = CGRectMake(0, 0, width, head);
    _time.frame = CGRectMake(YCRecordPadding, 0, width - 40, head);
    _clock.frame = CGRectMake(width - 24, (head - 16) / 2, 16, 16);
    _clock.hidden = (width < 70);

    CGFloat top = head + YCRecordTextGap;
    CGFloat line = [YCTheme recordTitleFont].lineHeight + 1.0;
    CGFloat inner = width - YCRecordPadding * 2;

    /**
     * Сколько строк поместится — столько и показываем.
     *
     * Раньше каждая строка сама решала, влезла ли она, и решала по своей
     * мерке. Выходило, что запись на час показывала имя и услуги,
     * а комментарий пропадал — при том что именно в нём чаще всего
     * и лежит то, ради чего запись открывают: «имплант 2 шт», «звонить
     * за час», имя с телефоном, если клиента не заводили в базу.
     */
    NSInteger fits = (NSInteger)floor((height - top) / line);

    NSString *second = nil;
    NSString *third = nil;

    if (fits >= 3) {
        second = _services;
        third = _note_text;
    } else if (fits == 2) {
        /**
         * Места на одну строку — она достаётся комментарию.
         *
         * Услуга в записи чаще всего одна и та же и предсказуема по
         * сотруднику; комментарий писали руками именно для этого визита.
         * Если комментария нет, строка достаётся услугам — пустой её
         * оставлять незачем.
         */
        second = [_note_text length] > 0 ? _note_text : _services;
    }

    // Комментарий на второй строке рисуется тем же полужирным, что и на
    // третьей: иначе одна и та же запись меняла бы начертание от высоты.
    BOOL secondIsNote = (second != nil && second == _note_text);

    _detail.font = secondIsNote ? [YCTheme recordDetailFont]
                                : [YCTheme recordTitleFont];

    _title.frame = CGRectMake(YCRecordPadding, top, inner, line);
    _title.hidden = (fits < 1);

    _detail.text = second;
    _detail.frame = CGRectMake(YCRecordPadding, top + line, inner, line);
    _detail.hidden = (fits < 2) || [second length] == 0;

    _note.text = third;
    _note.frame = CGRectMake(YCRecordPadding, top + line * 2, inner, line);
    _note.hidden = (fits < 3) || [third length] == 0;
}

@end
