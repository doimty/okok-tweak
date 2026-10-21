#import "WCKRuntime.h"
#import "WCKPolicy.h"
#import "WCKHostIdentity.h"
#import "WCKSettings.h"
#import <dlfcn.h>
#import <stdlib.h>

// Resolved from the host's Substrate image. Missing support => no hooks.
// Signature checked against Substrate API: void MSHookMessageEx(Class,SEL,IMP,IMP*).
typedef void (*WCKHookFunction)(Class, SEL, IMP, IMP *);
static NSMutableDictionary<NSString *, NSString *> *sStatuses;
static NSMutableSet<NSString *> *sInstalled;

BOOL WCKHostIsSupported(void) {
    static NSLock *identityLock;
    static BOOL cached, supported;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ identityLock = [NSLock new]; });
    [identityLock lock];
    @try {
        if (!cached) {
            BOOL readable = NO;
            supported = WCKHostMatchesBundle(NSBundle.mainBundle, &readable);
            // Cache stable identities (including unsupported builds), not transient I/O failure.
            cached = readable;
        }
        return supported;
    } @catch (__unused NSException *exception) {
        // Never turn a property/I/O exception into an allow or a permanent negative cache.
        supported = NO; cached = NO;
        return NO;
    } @finally { [identityLock unlock]; }
}

static void WCKInitRegistry(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{ sStatuses = [NSMutableDictionary dictionary];
                           sInstalled = [NSMutableSet set]; });
}
void WCKSetModuleStatus(NSString *key, NSString *status) {
    WCKInitRegistry();
    @synchronized(sStatuses) { sStatuses[key] = status; }
}
NSDictionary<NSString *, NSString *> *WCKRuntimeStatuses(void) {
    WCKInitRegistry();
    @synchronized(sStatuses) { return sStatuses.copy; }
}
BOOL WCKEnabled(NSString *feature) {
    NSDictionary *snapshot = WCKSettings.shared.snapshot;
    return WCKHostIsSupported() &&
        [WCKRuntimeStatuses()[feature] isEqualToString:@"ready"] &&
        [snapshot[@"enabled"] boolValue] && [snapshot[feature] boolValue];
}

BOOL WCKMethodMatches(Class cls, SEL selector, const char *returnType,
                     const char *const *arguments, unsigned int count) {
    if (!cls || !selector || !returnType || (count && !arguments)) return NO;
    Method method = class_getInstanceMethod(cls, selector);
    if (!method || method_getNumberOfArguments(method) != count + 2) return NO;
    char *type = method_copyReturnType(method);
    BOOL matches = WCKTypeMatches(type, returnType);
    free(type);
    for (unsigned int i = 0; matches && i < count; ++i) {
        type = method_copyArgumentType(method, i + 2);
        matches = WCKTypeMatches(type, arguments[i]);
        free(type);
    }
    return matches;
}

BOOL WCKInstallHook(Class cls, SEL selector, IMP replacement, IMP *original,
                    const char *returnType, const char *const *arguments,
                    unsigned int count) {
    if (!WCKHostIsSupported() || !replacement || !original ||
        !WCKMethodMatches(cls, selector, returnType, arguments, count)) return NO;
    WCKInitRegistry();
    WCKHookFunction hook = (WCKHookFunction)dlsym(RTLD_DEFAULT, "MSHookMessageEx");
    if (!hook) return NO;
    NSString *key = [NSString stringWithFormat:@"%p/%s", cls, sel_getName(selector)];
    @synchronized(sInstalled) {
        if ([sInstalled containsObject:key]) return NO;
        IMP fallback = method_getImplementation(class_getInstanceMethod(cls, selector));
        if (!fallback) return NO;
        // The replacement always has a callable original, including an in-flight call
        // or a Substrate implementation which does not fill the result pointer.
        *original = fallback;
        hook(cls, selector, replacement, original);
        if (!*original) { *original = fallback; return NO; }
        [sInstalled addObject:key];
    }
    return YES;
}
