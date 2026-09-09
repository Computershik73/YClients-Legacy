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
