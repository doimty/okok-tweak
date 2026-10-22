#import "WCKSVGPalette.h"

static BOOL WCKHexDigit(unichar c, unsigned *value) {
    if (c >= '0' && c <= '9') { *value = c - '0'; return YES; }
    if (c >= 'a' && c <= 'f') { *value = c - 'a' + 10; return YES; }
    if (c >= 'A' && c <= 'F') { *value = c - 'A' + 10; return YES; }
    return NO;
}

NSString *WCKNormalizeHex(NSString *text) {
    if (![text isKindOfClass:NSString.class]) return nil;
    NSString *trimmed = [text stringByTrimmingCharactersInSet:
        NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if ([trimmed hasPrefix:@"#"]) trimmed = [trimmed substringFromIndex:1];
    // Only the six-digit form is accepted: no 3-digit shorthand, no alpha.
    if (trimmed.length != 6) return nil;
    unichar out[7];
    out[0] = '#';
    for (NSUInteger i = 0; i < 6; ++i) {
        unsigned value = 0;
        unichar c = [trimmed characterAtIndex:i];
        if (!WCKHexDigit(c, &value)) return nil;
        out[i + 1] = (unichar)("0123456789ABCDEF"[value]);
    }
    return [NSString stringWithCharacters:out length:7];
}

NSString *WCKHexDisplay(NSString *hex) {
    NSString *normalised = WCKNormalizeHex(hex);
    return normalised ?: @"未设置";
}

BOOL WCKHexToRGB(NSString *text, uint32_t *rgb) {
    NSString *hex = WCKNormalizeHex(text);
    if (!hex || !rgb) return NO;
    uint32_t value = 0;
    for (NSUInteger i = 1; i < 7; ++i) {
        unsigned digit = 0;
        if (!WCKHexDigit([hex characterAtIndex:i], &digit)) return NO;
        value = (value << 4) | digit;
    }
    *rgb = value;
    return YES;
}

NSUInteger WCKPaletteIndexForName(NSString *name, NSUInteger count) {
    if (count == 0) return 0;
    if (![name isKindOfClass:NSString.class] || name.length == 0) return 0;
    // FNV-1a over UTF-8: stable across launches and iOS versions, unlike
    // -hash which is salted per process.
    const char *bytes = name.UTF8String;
    if (!bytes) return 0;
    uint32_t hash = 2166136261u;
    for (const char *cursor = bytes; *cursor; ++cursor) {
        hash ^= (uint8_t)*cursor;
        hash *= 16777619u;
    }
    return (NSUInteger)(hash % (uint32_t)count);
}

NSArray<NSString *> *WCKDefaultSVGPalette(void) {
    // A restrained set: WeChat green first, then readable accents that stay
    // legible on both light and dark backgrounds.
    return @[@"#07C160", @"#2F7CF6", @"#FF8A00", @"#E5484D",
             @"#8E4EC6", @"#12A594", @"#D6409F", @"#6E7B8B"];
}
