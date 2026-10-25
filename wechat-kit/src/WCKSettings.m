#import "WCKSettings.h"
#import "WCKSVGPalette.h"
#import <math.h>
#import <CoreFoundation/CoreFoundation.h>
#import <dispatch/dispatch.h>

NSNotificationName const WCKSettingsDidChangeNotification = @"WCKSettingsDidChangeNotification";
static NSString * const WCKSettingsErrorDomain = @"com.doimty.wechatkit.settings";
static const NSUInteger WCKMaximumFileBytes = 65536;
static const NSUInteger WCKMaximumCSVLength = 2048;
static const NSUInteger WCKMaximumFormatLength = 128;

static NSDictionary<NSString *, id> *WCKDefaults(void) {
    static NSDictionary *defaults;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSMutableDictionary *d = [@{
            @"enabled": @NO, @"keyboardSwipe": @NO, @"svgTint": @NO,
            @"momentsTime": @NO, @"albumSheet": @NO, @"readAll": @NO, @"corners": @NO,
            @"svgTintLight": @"#07C160", @"svgTintDark": @"#07C160",
            @"svgInclude": @"", @"svgExclude": @"",
            @"svgUseFixedColor": @YES, @"svgPaletteHexes": WCKDefaultSVGPalette(),
            @"svgRandomAlpha": @1.0, @"momentsFormat": @"yyyy-MM-dd HH:mm:ss"
        } mutableCopy];
        // WCR keeps the six page gates separate from each control family.
        NSArray *pageKeys = @[@"homepageCornerEnabled", @"mainFrameCornerEnabled",
            @"myPageCornerEnabled", @"friendProfileCornerEnabled",
            @"discoverPageCornerEnabled", @"tpModeCornerEnabled"];
        for (NSString *key in pageKeys) d[key] = @YES;

        // One switch and one radius per independently configurable WCR family.
        NSArray *families = @[
            @"searchCorner", @"inputCorner", @"topbarCorner", @"toolbarCorner",
            @"menuCorner", @"plusMenuCorner", @"mainFrameSwipeMenuCorner",
            @"systemPopupCorner", @"imeKeyboardCorner", @"chatToolbarCorner", @"emojiCorner",
            @"chatImageCorner", @"chatBubbleCorner", @"chatTimeRoundCorner", @"msgReferCorner",
            @"systemMessageCorner", @"systemNoticeCorner", @"voiceTranslateCorner",
            @"momentCorner", @"finderCorner", @"serviceCorner",
            @"sendPublishButtonCorner", @"avatarCorner", @"profileCorner", @"otherCorner"
        ];
        for (NSString *family in families) {
            d[[family stringByAppendingString:@"Enabled"]] = @NO;
            d[[family stringByAppendingString:@"Radius"]] = @12.0;
        }
        // WCR exposes these two as switches only; their visuals reuse the
        // chat-image family radius rather than inventing a second radius.
        d[@"chatFileCornerEnabled"] = @NO;
        d[@"chatLocationCornerEnabled"] = @NO;
        d[@"avatarCornerChatPageEnabled"] = @NO;
        d[@"avatarCornerChatPageRadius"] = @12.0;
        d[@"topbarCornerTopFlatEnabled"] = @NO;
        d[@"toolbarCornerBottomFlatEnabled"] = @NO;
        d[@"globalCornerRadius"] = @12.0;
        d[@"globalCornerMargin"] = @8.0;
        d[@"globalCornerSpacing"] = @8.0;
        d[@"globalCornerStroke"] = @0.0;
        d[@"globalCornerFill"] = @"";
        d[@"globalCornerStrokeColor"] = @"";
        d[@"globalCornerStrokeStyle"] = @0;
        d[@"globalCornerCustomExcludedVCClassNames"] = @"";
        d[@"mainFramePinnedTopSpacing"] = @8.0;
        d[@"mainFrameBelowPinnedSpacing"] = @8.0;
        defaults = [d copy];
    });
    return defaults;
}
static NSError *WCKError(NSInteger code, NSString *message, NSError *underlying) {
    NSMutableDictionary *info = [@{NSLocalizedDescriptionKey: message} mutableCopy];
    if (underlying) info[NSUnderlyingErrorKey] = underlying;
    return [NSError errorWithDomain:WCKSettingsErrorDomain code:code userInfo:info];
}

// Returns a canonical, immutable value, or nil. No input values are logged or echoed.
static id WCKValidatedValue(NSString *key, id value) {
    id defaultValue = WCKDefaults()[key];
    if (!defaultValue) return nil;
    if ([defaultValue isKindOfClass:NSArray.class]) {
        // Palette: 1...32 unique "#RRGGBB" entries, order preserved.
        if (![value isKindOfClass:NSArray.class]) return nil;
        NSArray *list = (NSArray *)value;
        if (list.count == 0 || list.count > 32) return nil;
        NSMutableArray<NSString *> *canonical = [NSMutableArray array];
        for (id entry in list) {
            NSString *hex = WCKNormalizeHex([entry isKindOfClass:NSString.class] ? entry : nil);
            if (!hex || [canonical containsObject:hex]) return nil;
            [canonical addObject:hex];
        }
        return [canonical copy];
    }
    if ([defaultValue isKindOfClass:NSNumber.class]) {
        if (![value isKindOfClass:NSNumber.class]) return nil;
        BOOL isBoolean = CFGetTypeID((__bridge CFTypeRef)value) == CFBooleanGetTypeID();
        if ([key isEqualToString:@"svgRandomAlpha"]) {
            if (isBoolean) return nil;
            double alpha = [value doubleValue];
            if (!isfinite(alpha)) return nil;
            return @(MIN(1.0, MAX(0.2, alpha)));
        }
        BOOL numericCorner = [key hasSuffix:@"Radius"] || [key hasSuffix:@"Margin"] ||
            [key hasSuffix:@"Spacing"] || [key hasSuffix:@"BorderSize"] ||
            [key isEqualToString:@"globalCornerStroke"] ||
            [key isEqualToString:@"globalCornerStrokeStyle"] ||
            [key isEqualToString:@"mainFramePinnedTopSpacing"] ||
            [key isEqualToString:@"mainFrameBelowPinnedSpacing"];
        if (numericCorner) {
            if (isBoolean) return nil;
            double number = [value doubleValue];
            if (!isfinite(number)) return nil;
            double high = 24.0;
            if ([key hasSuffix:@"Margin"]) high = 30.0;
            else if ([key hasSuffix:@"Spacing"] ||
                     [key isEqualToString:@"mainFramePinnedTopSpacing"] ||
                     [key isEqualToString:@"mainFrameBelowPinnedSpacing"]) high = 50.0;
            else if ([key hasSuffix:@"BorderSize"] || [key isEqualToString:@"globalCornerStroke"]) high = 4.0;
            else if ([key isEqualToString:@"globalCornerStrokeStyle"]) high = 2.0;
            return @(MIN(high, MAX(0.0, number)));
        }
        if (!isBoolean) return nil;
        return @([value boolValue]);
    }
    if (![value isKindOfClass:NSString.class]) return nil;
    NSString *text = [value copy];
    BOOL longText = [key isEqualToString:@"momentsFormat"] ||
        [key isEqualToString:@"globalCornerCustomExcludedVCClassNames"];
    NSUInteger limit = [key isEqualToString:@"momentsFormat"] ? WCKMaximumFormatLength :
        (longText || [key isEqualToString:@"svgInclude"] || [key isEqualToString:@"svgExclude"] ?
         WCKMaximumCSVLength : 7);
    if (text.length > limit ||
        [text rangeOfCharacterFromSet:NSCharacterSet.controlCharacterSet].location != NSNotFound) return nil;
    if ([key isEqualToString:@"globalCornerFill"] || [key isEqualToString:@"globalCornerStrokeColor"]) {
        // Empty means "use the resolved host/default colour".
        return text.length == 0 ? @"" : WCKNormalizeHex(text);
    }
    if ([key isEqualToString:@"svgTintLight"] || [key isEqualToString:@"svgTintDark"]) {
        if (text.length != 7 || [text characterAtIndex:0] != '#') return nil;
        for (NSUInteger i = 1; i < 7; i++) {
            unichar c = [text characterAtIndex:i];
            if (!((c >= '0' && c <= '9') || (c >= 'A' && c <= 'F') ||
                  (c >= 'a' && c <= 'f'))) return nil;
        }
        return text.uppercaseString;
    }
    if ([key isEqualToString:@"momentsFormat"] &&
        [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].length == 0) return nil;
    return text;
}

static NSDictionary<NSString *, id> *WCKLoad(NSURL *fileURL) {
    NSMutableDictionary *values = [WCKDefaults() mutableCopy];
    if (!fileURL) return [values copy];
    NSFileHandle *handle = [NSFileHandle fileHandleForReadingFromURL:fileURL error:NULL];
    if (!handle) return [values copy];
    // Bound the read itself, not a racy pre-read file-size check.
    NSData *data = [handle readDataUpToLength:WCKMaximumFileBytes + 1 error:NULL];
    [handle closeAndReturnError:NULL];
    if (!data || data.length > WCKMaximumFileBytes) return [values copy];
    id plist = [NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable
                                                        format:NULL error:NULL];
    if (![plist isKindOfClass:NSDictionary.class]) return [values copy];
    for (NSString *key in WCKDefaults()) {
        id canonical = WCKValidatedValue(key, plist[key]);
        if (canonical) values[key] = canonical;
    }
    return [values copy];
}

@interface WCKSettings () {
    NSLock *_lock;
    NSDictionary<NSString *, id> *_values;
    NSURL *_fileURL;
}
// Private seam for isolated regression tests; never changes the shared store's path.
- (instancetype)initWithFileURL:(NSURL *)fileURL;
@end

@implementation WCKSettings

+ (instancetype)shared {
    static WCKSettings *settings;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ settings = [[WCKSettings alloc] init]; });
    return settings;
}

- (instancetype)init {
    NSURL *library = [NSFileManager.defaultManager URLsForDirectory:NSLibraryDirectory
                                                        inDomains:NSUserDomainMask].firstObject;
    NSURL *directory = [library URLByAppendingPathComponent:@"Preferences" isDirectory:YES];
    return [self initWithFileURL:[directory URLByAppendingPathComponent:@"com.doimty.wechatkit.plist"]];
}

- (instancetype)initWithFileURL:(NSURL *)fileURL {
    self = [super init];
    if (self) {
        _lock = [[NSLock alloc] init];
        _fileURL = [fileURL copy];
        _values = WCKLoad(_fileURL);
    }
    return self;
}

- (NSDictionary<NSString *, id> *)snapshot {
    [_lock lock];
    NSDictionary *snapshot = _values;
    [_lock unlock];
    return snapshot;
}

- (BOOL)boolForKey:(NSString *)key {
    id value = [self snapshot][key];
    return [value isKindOfClass:NSNumber.class] && [value boolValue];
}

- (NSString *)stringForKey:(NSString *)key defaultValue:(NSString *)fallback {
    id value = [self snapshot][key];
    return [value isKindOfClass:NSString.class] ? value : [fallback copy];
}

- (BOOL)setObject:(id)value forKey:(NSString *)key error:(NSError **)error {
    if (error) *error = nil;
    if (!NSThread.isMainThread) {
        if (error) *error = WCKError(1, @"请在主线程修改设置。", nil);
        return NO;
    }
    if (![key isKindOfClass:NSString.class] || key.length > 64 || !WCKDefaults()[key]) {
        if (error) *error = WCKError(2, @"不支持的设置项。", nil);
        return NO;
    }
    NSString *safeKey = [key copy];
    id canonical = WCKValidatedValue(safeKey, value);
    if (!canonical) {
        NSString *message = @"输入无效：颜色须为 #RRGGBB；名单最多 2048 字符；时间格式须为 1–128 字符；不可含控制字符。";
        if (error) *error = WCKError(3, message, nil);
        return NO;
    }
    NSMutableDictionary *draft = [[self snapshot] mutableCopy];
    draft[safeKey] = canonical;
    NSDictionary *next = [draft copy];
    NSError *failure = nil;
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:next
        format:NSPropertyListBinaryFormat_v1_0 options:0 error:&failure];
    if (!data || !_fileURL) {
        if (error) *error = WCKError(4, @"设置无法保存，原设置未变。", failure);
        return NO;
    }
    BOOL directoryOK = [NSFileManager.defaultManager createDirectoryAtURL:_fileURL.URLByDeletingLastPathComponent
        withIntermediateDirectories:YES attributes:nil error:&failure];
    BOOL written = directoryOK && [data writeToURL:_fileURL options:NSDataWritingAtomic error:&failure];
    if (!written) {
        if (error) *error = WCKError(4, @"设置写入失败，原设置未变。", failure);
        return NO;
    }
    [_lock lock];
    _values = next;
    [_lock unlock];
    [NSNotificationCenter.defaultCenter postNotificationName:WCKSettingsDidChangeNotification object:self];
    return YES;
}

@end
