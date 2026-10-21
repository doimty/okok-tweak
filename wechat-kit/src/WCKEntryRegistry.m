#import "WCKEntryRegistry.h"
#import "WCKRuntime.h"
#import <objc/message.h>

static NSString *const WCKControllerName = @"WCKSettingsViewController";
static BOOL sRegistrationInProgress;

static NSArray *WCKReadHubPlugins(id hub) {
    if (!hub || !WCKMethodMatches(object_getClass(hub),
        NSSelectorFromString(@"plugins"), "@", NULL, 0)) return nil;
    id value = ((id (*)(id, SEL))objc_msgSend)(hub, NSSelectorFromString(@"plugins"));
    if (![value isKindOfClass:NSArray.class] || [value count] > 2048) return nil;
    return [value copy];
}

static BOOL WCKHubContainsController(NSArray *plugins, BOOL *readable) {
    *readable = YES;
    for (id model in plugins) {
        if (!WCKMethodMatches(object_getClass(model),
            NSSelectorFromString(@"controller"), "@", NULL, 0)) {
            *readable = NO; return NO;
        }
        id name = ((id (*)(id, SEL))objc_msgSend)(model, NSSelectorFromString(@"controller"));
        if (name && ![name isKindOfClass:NSString.class]) { *readable = NO; return NO; }
        if ([name isEqualToString:WCKControllerName]) return YES;
    }
    return NO;
}

BOOL WCKRegisterPluginEntry(void) {
    if (!NSThread.isMainThread || !WCKHostIsSupported() || sRegistrationInProgress) return NO;
    // Never depend on a feature toggle or on Substrate/navigation hook availability.
    Class managerClass = NSClassFromString(@"WCPluginsMgr");
    if (!managerClass || !NSClassFromString(WCKControllerName)) {
        WCKSetModuleStatus(@"pluginHubEntry", @"未发现插件收纳；使用设置页兜底");
        return NO;
    }
    const char *args[] = {"@", "@", "@"};
    SEL shared = NSSelectorFromString(@"sharedInstance");
    SEL registration = NSSelectorFromString(@"registerControllerWithTitle:version:controller:");
    if (!WCKMethodMatches(object_getClass(managerClass), shared, "@", NULL, 0) ||
        !WCKMethodMatches(managerClass, registration, "v", args, 3)) {
        WCKSetModuleStatus(@"pluginHubEntry", @"收纳接口不匹配；使用设置页兜底");
        return NO;
    }
    sRegistrationInProgress = YES;
    @try {
        id hub = ((id (*)(id, SEL))objc_msgSend)(managerClass, shared);
        if (!hub || ![hub isKindOfClass:managerClass]) {
            WCKSetModuleStatus(@"pluginHubEntry", @"收纳尚未就绪"); return NO;
        }
        NSArray *before = WCKReadHubPlugins(hub);
        BOOL readable = NO;
        if (!before) { WCKSetModuleStatus(@"pluginHubEntry", @"收纳列表不可读"); return NO; }
        if (WCKHubContainsController(before, &readable)) {
            WCKSetModuleStatus(@"pluginHubEntry", @"ready"); return YES;
        }
        if (!readable) { WCKSetModuleStatus(@"pluginHubEntry", @"收纳模型不匹配"); return NO; }
        // WCPluginModel.controller is NSString; the hub calls NSClassFromString on open.
        ((void (*)(id, SEL, id, id, id))objc_msgSend)(hub, registration,
            @"WeChatKit", @"0.1.0-alpha4", WCKControllerName);
        NSArray *after = WCKReadHubPlugins(hub);
        BOOL present = after && WCKHubContainsController(after, &readable);
        WCKSetModuleStatus(@"pluginHubEntry", present ? @"ready" : @"登记未回读；使用兜底");
        return present;
    } @catch (__unused NSException *exception) {
        WCKSetModuleStatus(@"pluginHubEntry", @"收纳登记异常；使用设置页兜底");
        return NO;
    } @finally { sRegistrationInProgress = NO; }
}
