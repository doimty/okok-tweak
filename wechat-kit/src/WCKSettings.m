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
        defaults = @{
            @"enabled": @NO, @"keyboardSwipe": @NO, @"svgTint": @NO,
            @"momentsTime": @NO, @"albumSheet": @NO, @"readAll": @NO, @"corners": @NO,
            @"svgTintLight": @"#07C160", @"svgTintDark": @"#07C160",
            @"svgInclude": @"", @"svgExclude": @"",
            @"svgUseFixedColor": @YES, @"svgPaletteHexes": WCKDefaultSVGPalette(),
            @"svgRandomAlpha": @1.0,
            @"cornersRadius": @12.0, @"cornersScope": @"list",
            @"cornersMargin": @8.0, @"cornersSpacing": @6.0, @"cornersStrokeWidth": @0.0,
            @"cornersFill": @"", @"cornersStrokeColor": @"",
            @"momentsFormat": @"yyyy-MM-dd HH:mm:ss"
        };
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
        // Only the alpha key is numeric; every other number key is a switch.
        if ([key isEqualToString:@"svgRandomAlpha"]) {
            if (isBoolean) return nil;
            double alpha = [value doubleValue];
            if (!isfinite(alpha)) return nil;
            return @(MIN(1.0, MAX(0.2, alpha)));
        }
        if ([key isEqualToString:@"cornersRadius"]) {
            if (isBoolean) return nil;
            double radius = [value doubleValue];
            if (!isfinite(radius)) return nil;
            return @(MIN(24.0, MAX(0.0, radius)));
        }
        if ([key isEqualToString:@"cornersMargin"] || [key isEqualToString:@"cornersSpacing"] ||
            [key isEqualToString:@"cornersStrokeWidth"]) {
            if (isBoolean) return nil;
            double number = [value doubleValue];
            if (!isfinite(number)) return nil;
            double high = [key isEqualToString:@"cornersStrokeWidth"] ? 4.0 :
                ([key isEqualToString:@"cornersMargin"] ? 30.0 : 24.0);
            return @(MIN(high, MAX(0.0, number)));
        }
        if (!isBoolean) return nil;
        return @([value boolValue]);
    }
    if (![value isKindOfClass:NSString.class]) return nil;
    NSString *text = [value copy];
    NSUInteger limit = [key isEqualToString:@"momentsFormat"] ? WCKMaximumFormatLength :
        (([key isEqualToString:@"svgInclude"] || [key isEqualToString:@"svgExclude"]) ?
         WCKMaximumCSVLength : 7);
    if (text.length > limit ||
        [text rangeOfCharacterFromSet:NSCharacterSet.controlCharacterSet].location != NSNotFound) return nil;
    if ([key isEqualToString:@"cornersFill"] || [key isEqualToString:@"cornersStrokeColor"]) {
        // Empty means "leave the host colour alone".
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
    if ([key isEqualToString:@"cornersScope"])
        return ([text isEqualToString:@"list"] || [text isEqualToString:@"all"]) ? text : nil;
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
