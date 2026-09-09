#import "YCRecordView.h"

#import <QuartzCore/QuartzCore.h>

#import "YCIcons.h"
#import "YCTheme.h"
#import "YCTime.h"

/** Высота цветной шапки со временем. */
static const CGFloat YCRecordHeadHeight = 24.0;
static const CGFloat YCRecordPadding = 8.0;

@implementation YCRecordView {
    UIView *_head;
    UILabel *_time;
    UIImageView *_clock;
    UILabel *_title;
    UILabel *_detail;
    UILabel *_note;
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
    _detail.text = record.services;

    _note.textColor = [ink colorWithAlphaComponent:0.7];
    _note.text = record.comment;

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
    CGFloat head = MIN(YCRecordHeadHeight, height);

    _head.frame = CGRectMake(0, 0, width, head);
    _time.frame = CGRectMake(YCRecordPadding, 0, width - 40, head);
    _clock.frame = CGRectMake(width - 24, (head - 16) / 2, 16, 16);
    _clock.hidden = (width < 70);

    CGFloat titleTop = head + 4.0;
    CGFloat line = [YCTheme recordTitleFont].lineHeight + 2.0;

    _title.frame = CGRectMake(YCRecordPadding, titleTop, width - YCRecordPadding * 2, line);
    _title.hidden = (height < head + line);

    _detail.frame = CGRectMake(YCRecordPadding, titleTop + line,
                               width - YCRecordPadding * 2, line);
    _detail.hidden = (height < head + line * 2 + 4) || [_detail.text length] == 0;

    /**
     * Комментарий занимает строку услуг, когда услуг нет.
     *
     * Запись без услуги — обычное дело: администратор пишет в комментарий
     * имя с телефоном и уточняет остальное потом. Держать под пустую
     * строку услуг место, а комментарий прятать ниже — потерять его
     * на записях в полчаса, где третьей строки уже нет.
     */
    CGFloat noteTop = _detail.hidden ? titleTop + line : titleTop + line * 2;

    _note.frame = CGRectMake(YCRecordPadding, noteTop,
                             width - YCRecordPadding * 2, line);
    _note.hidden = (height < noteTop + line) || [_note.text length] == 0;
}

@end
