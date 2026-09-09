#import "YCModel.h"

@implementation YCCompany

- (NSString *)description {
    return [NSString stringWithFormat:@"<YCCompany %ld %@>", (long)self.companyId, self.title];
}

@end


@implementation YCService

- (NSString *)description {
    return [NSString stringWithFormat:@"<YCService %ld %@>", (long)self.serviceId, self.title];
}

@end


@implementation YCSlot

+ (id)slotFrom:(NSInteger)from to:(NSInteger)to {
    YCSlot *slot = [[YCSlot alloc] init];

    slot.from = from;
    slot.to = to;

    return slot;
}

/** Минуты от полуночи в «ЧЧ:ММ». */
static NSString *YCClockFromMinutes(NSInteger minutes) {
    return [NSString stringWithFormat:@"%02ld:%02ld",
            (long)(minutes / 60), (long)(minutes % 60)];
}

- (NSString *)fromText { return YCClockFromMinutes(self.from); }
- (NSString *)toText   { return YCClockFromMinutes(self.to); }

- (NSString *)description {
    return [NSString stringWithFormat:@"<YCSlot %@–%@>", [self fromText], [self toText]];
}

@end


@implementation YCScheduleDay

- (BOOL)isWorking {
    return [self.slots count] > 0;
}

- (NSInteger)earliest {
    NSInteger best = 0;

    for (YCSlot *slot in self.slots) {
        if (best == 0 || slot.from < best) {
            best = slot.from;
        }
    }

    return best;
}

- (NSInteger)latest {
    NSInteger best = 0;

    for (YCSlot *slot in self.slots) {
        if (slot.to > best) {
            best = slot.to;
        }
    }

    return best;
}

- (BOOL)coversMinute:(NSInteger)minute {
    for (YCSlot *slot in self.slots) {
        if (minute >= slot.from && minute < slot.to) {
            return YES;
        }
    }

    return NO;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<YCScheduleDay %ld %@ %@>",
            (long)self.staffId, self.date, self.slots];
}

@end


@implementation YCClient

- (NSString *)description {
    return [NSString stringWithFormat:@"<YCClient %ld %@ %@>",
                                      (long)self.clientId, self.name, self.phone];
}


/** Склеивает непустые части через пробел. */
NSString *YCJoinName(NSString *surname, NSString *name, NSString *patronymic) {
    NSMutableArray *parts = [NSMutableArray array];

    for (NSString *part in @[ surname ?: @"", name ?: @"", patronymic ?: @"" ]) {
        NSString *trimmed = [part stringByTrimmingCharactersInSet:
            [NSCharacterSet whitespaceAndNewlineCharacterSet]];

        if ([trimmed length] > 0) {
            [parts addObject:trimmed];
        }
    }

    return [parts componentsJoinedByString:@" "];
}

- (NSString *)fullName {
    return YCJoinName(self.surname, self.name, self.patronymic);
}

@end


@implementation YCStaff

- (NSString *)description {
    return [NSString stringWithFormat:@"<YCStaff %ld %@>", (long)self.staffId, self.name];
}

@end


@implementation YCRecord

- (NSDate *)end {
    return [self.start dateByAddingTimeInterval:self.length];
}

- (NSString *)title {
    if ([self.clientName length] > 0) {
        return self.clientName;
    }

    if ([self.clientPhone length] > 0) {
        return self.clientPhone;
    }

    return @"Без имени";
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<YCRecord %ld %@ %@ %.0fмин>",
                                      (long)self.recordId, self.title,
                                      self.start, self.length / 60.0];
}

@end
