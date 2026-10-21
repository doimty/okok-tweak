#import "WCKHostIdentity.h"
#import "WCKPolicy.h"

BOOL WCKHostMatchesBundle(NSBundle *bundle, BOOL *readable) {
    *readable = NO;
    NSURL *base = bundle.bundleURL;
    NSURL *executable = bundle.executableURL;
    if (!base.isFileURL || !executable.isFileURL) return NO;
    NSURL *infoURL = [base URLByAppendingPathComponent:@"Info.plist" isDirectory:NO];
    NSNumber *fileSize = nil;
    if (![infoURL getResourceValue:&fileSize forKey:NSURLFileSizeKey error:NULL] ||
        ![fileSize isKindOfClass:NSNumber.class] || fileSize.unsignedLongLongValue == 0 ||
        fileSize.unsignedLongLongValue > 1024 * 1024) return NO;
    NSData *data = [NSData dataWithContentsOfURL:infoURL options:NSDataReadingUncached error:NULL];
    if (!data.length || data.length > 1024 * 1024) return NO;
    id parsed = [NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable
        format:NULL error:NULL];
    if (![parsed isKindOfClass:NSDictionary.class]) return NO;
    NSDictionary *identity = parsed;
    for (NSString *key in @[@"CFBundleIdentifier", @"CFBundleShortVersionString",
                            @"CFBundleVersion", @"CFBundleExecutable"]) {
        id value = identity[key];
        if (![value isKindOfClass:NSString.class] || ![value length] || [value length] > 256) return NO;
    }
    *readable = YES;
    NSString *identifier = identity[@"CFBundleIdentifier"];
    NSString *version = identity[@"CFBundleShortVersionString"];
    NSString *build = identity[@"CFBundleVersion"];
    NSString *name = identity[@"CFBundleExecutable"];
    if (![identifier isEqualToString:bundle.bundleIdentifier] || ![name isEqualToString:@"WeChat"])
        return NO;
    NSURL *expectedExecutable = [base URLByAppendingPathComponent:name isDirectory:NO];
    NSString *expectedPath = expectedExecutable.URLByResolvingSymlinksInPath.URLByStandardizingPath.path;
    NSString *actualPath = executable.URLByResolvingSymlinksInPath.URLByStandardizingPath.path;
    if (![expectedPath isEqualToString:actualPath]) return NO;
    return WCKHostMatches(identifier.UTF8String, version.UTF8String, build.UTF8String);
}
