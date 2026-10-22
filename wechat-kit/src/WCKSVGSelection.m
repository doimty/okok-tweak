#import "WCKSVGSelection.h"
#import "WCKPolicy.h"
#import "WCKSVGPalette.h"
#import <math.h>

static BOOL WCKSVGPassesGates(NSDictionary *settings, NSString *name) {
    if (![settings isKindOfClass:NSDictionary.class] || ![name isKindOfClass:NSString.class]) return NO;
    // A single immutable snapshot drives both gates and values.
    id master = settings[@"enabled"], feature = settings[@"svgTint"];
    if (![master isKindOfClass:NSNumber.class] || ![master boolValue] ||
        ![feature isKindOfClass:NSNumber.class] || ![feature boolValue]) return NO;
    id include = settings[@"svgInclude"], exclude = settings[@"svgExclude"];
    if (![include isKindOfClass:NSString.class] || ![exclude isKindOfClass:NSString.class] ||
        !WCKShouldTintName(name.UTF8String, [include UTF8String], [exclude UTF8String])) return NO;
    return YES;
}

static NSArray<NSString *> *WCKSVGSanitisedPalette(id stored) {
    NSMutableArray<NSString *> *palette = [NSMutableArray array];
    if ([stored isKindOfClass:NSArray.class]) {
        for (id entry in (NSArray *)stored) {
            NSString *hex = WCKNormalizeHex([entry isKindOfClass:NSString.class] ? entry : nil);
            if (hex && ![palette containsObject:hex] && palette.count < 32) [palette addObject:hex];
        }
    }
    // An emptied or broken palette must not disable colouring entirely.
    return palette.count ? palette : WCKDefaultSVGPalette();
}

static double WCKSVGRandomAlpha(NSDictionary *settings) {
    id value = settings[@"svgRandomAlpha"];
    if (![value isKindOfClass:NSNumber.class]) return 1.0;
    double alpha = [value doubleValue];
    if (!isfinite(alpha)) return 1.0;
    // Keep icons visible: fully transparent would silently erase them.
    return MIN(1.0, MAX(0.2, alpha));
}

BOOL WCKSVGSelectRGB(NSDictionary *settings, NSString *name, BOOL dark, uint32_t *rgb) {
    uint32_t packed = 0;
    if (!WCKSVGSelectPacked(settings, name, dark, &packed)) return NO;
    if (rgb) *rgb = packed & 0x00FFFFFFu;
    return YES;
}

BOOL WCKSVGSelectPacked(NSDictionary *settings, NSString *name, BOOL dark, uint32_t *packed) {
    if (!WCKSVGPassesGates(settings, name)) return NO;
    id fixedFlag = settings[@"svgUseFixedColor"];
    BOOL fixed = ![fixedFlag isKindOfClass:NSNumber.class] || [fixedFlag boolValue];
    uint32_t colour = 0;
    double alpha = 1.0;
    if (fixed) {
        id text = settings[dark ? @"svgTintDark" : @"svgTintLight"];
        if (![text isKindOfClass:NSString.class] || !WCKHexToRGB(text, &colour)) return NO;
    } else {
        NSArray<NSString *> *palette = WCKSVGSanitisedPalette(settings[@"svgPaletteHexes"]);
        NSUInteger slot = WCKPaletteIndexForName(name, palette.count);
        if (!WCKHexToRGB(palette[slot], &colour)) return NO;
        alpha = WCKSVGRandomAlpha(settings);
    }
    if (packed) *packed = ((uint32_t)llround(alpha * 255.0) << 24) | (colour & 0x00FFFFFFu);
    return YES;
}

void WCKSVGUnpack(uint32_t packed, uint32_t *rgb, double *alpha) {
    if (rgb) *rgb = packed & 0x00FFFFFFu;
    if (alpha) *alpha = (double)((packed >> 24) & 0xFF) / 255.0;
}
