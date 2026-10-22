#import "WCKRuntime.h"

// A feature-specific prerequisite from the reference, not a host-wide version lock.
// Read the on-disk main bundle: display metadata can be replaced by other plugins.
static BOOL WCKAlbumVersionSupported(id version) {
    if (![version isKindOfClass:NSString.class] || [version length] > 64) return NO;
    NSArray<NSString *> *parts = [version componentsSeparatedByString:@"."];
    if (parts.count < 3 || parts.count > 4) return NO;
    NSCharacterSet *invalid = [[NSCharacterSet characterSetWithCharactersInString:@"0123456789"] invertedSet];
    for (NSString *part in parts)
        if (!part.length || part.length > 9 || [part rangeOfCharacterFromSet:invalid].location != NSNotFound) return NO;
    return [version compare:@"8.0.76" options:NSNumericSearch] != NSOrderedAscending;
}
static BOOL WCKAlbumBundleSupported(NSBundle *bundle) {
    @try {
        NSURL *base = bundle.bundleURL;
        if (!base.isFileURL) return NO;
        NSURL *url = [base URLByAppendingPathComponent:@"Info.plist" isDirectory:NO];
        NSNumber *size = nil;
        if (![url getResourceValue:&size forKey:NSURLFileSizeKey error:NULL] ||
            ![size isKindOfClass:NSNumber.class] || !size.unsignedLongLongValue ||
            size.unsignedLongLongValue > 1024 * 1024) return NO;
        NSData *data = [NSData dataWithContentsOfURL:url options:NSDataReadingUncached error:NULL];
        if (!data.length || data.length > 1024 * 1024) return NO;
        id info = [NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable
            format:NULL error:NULL];
        return [info isKindOfClass:NSDictionary.class] &&
            [info[@"CFBundleIdentifier"] isEqual:@"com.tencent.xin"] &&
            [info[@"CFBundleExecutable"] isEqual:@"WeChat"] &&
            WCKAlbumVersionSupported(info[@"CFBundleShortVersionString"]);
    } @catch (__unused NSException *exception) { return NO; }
}

// Original reference installer targets ExptService -getExpt:withBoolDef:,
// not NewABTestMgr or MMConfigMgr. Only this exact display experiment is changed.
static BOOL (*sOriginalAlbumExpt)(id, SEL, id, BOOL);
static BOOL WCKAlbumExpt(id service, SEL cmd, id key, BOOL fallback) {
    if ([key isKindOfClass:NSString.class] &&
        [key isEqualToString:@"clicfg_chat_album_pagesheet_mode"] && WCKEnabled(@"albumSheet"))
        return YES;
    return sOriginalAlbumExpt(service, cmd, key, fallback);
}

void WCKInstallAlbumSheet(void) {
    if (!WCKAlbumBundleSupported(NSBundle.mainBundle)) {
        WCKSetModuleStatus(@"albumSheet", @"需微信 8.0.76+，或无法核实相册能力版本");
        return; // Older clients do not gain a page-sheet implementation from a flag.
    }
    const char *args[] = {"@", @encode(BOOL)};
    BOOL ready = WCKInstallHook(NSClassFromString(@"ExptService"),
        NSSelectorFromString(@"getExpt:withBoolDef:"), (IMP)WCKAlbumExpt,
        (IMP *)&sOriginalAlbumExpt, @encode(BOOL), args, 2);
    WCKSetModuleStatus(@"albumSheet", ready && sOriginalAlbumExpt ? @"ready" : @"相册实验 ABI 或 hook 不可用");
}
