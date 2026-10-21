#import "WCKSVGSelection.h"
#import "WCKPolicy.h"

BOOL WCKSVGSelectRGB(NSDictionary *settings, NSString *name, BOOL dark, uint32_t *rgb) {
    if (![settings isKindOfClass:NSDictionary.class] || ![name isKindOfClass:NSString.class]) return NO;
    // A single immutable snapshot drives both gates and values.
    id master = settings[@"enabled"], feature = settings[@"svgTint"];
    if (![master isKindOfClass:NSNumber.class] || ![master boolValue] ||
        ![feature isKindOfClass:NSNumber.class] || ![feature boolValue]) return NO;
    id include = settings[@"svgInclude"], exclude = settings[@"svgExclude"];
    if (![include isKindOfClass:NSString.class] || ![exclude isKindOfClass:NSString.class] ||
        !WCKShouldTintName(name.UTF8String, [include UTF8String], [exclude UTF8String])) return NO;
    id text = settings[dark ? @"svgTintDark" : @"svgTintLight"];
    return [text isKindOfClass:NSString.class] && WCKParseRGB([text UTF8String], rgb);
}
