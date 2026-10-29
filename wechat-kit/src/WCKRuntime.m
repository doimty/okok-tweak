#import "WCKRuntime.h"
#import "WCKPolicy.h"
#import "WCKHostIdentity.h"
#import "WCKSettings.h"
#import <dlfcn.h>
#import <stdlib.h>
#if __has_feature(ptrauth_calls)
#import <ptrauth.h>
#endif

// Substrate-compatible API: void MSHookMessageEx(Class, SEL, IMP, IMP *).
// Its original may be a chaining trampoline, not the pre-install Method IMP.
typedef void (*WCKHookFunction)(Class, SEL, IMP, IMP *);
@interface WCKHookRecord : NSObject {
@public
    IMP backendOriginal; // Durable output storage, separate from the live caller slot.
}
@property (nonatomic) IMP replacement;
@property (nonatomic) IMP nextImplementation;
@property (nonatomic) BOOL installing;
@property (nonatomic) BOOL verified;
@property (nonatomic, copy) NSString *status;
@end
@implementation WCKHookRecord
@end

static NSMutableDictionary<NSString *, NSString *> *sStatuses;
static NSMutableDictionary<NSString *, WCKHookRecord *> *sInstalled;

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
                           sInstalled = [NSMutableDictionary dictionary]; });
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
    return [snapshot[@"enabled"] boolValue] && [snapshot[feature] boolValue];
}

// Check each ABI type separately: full encodings also contain compiler offsets.
// A metaclass is deliberately handled as a class with instance methods here.
// Neither host versions nor readiness strings are installation/feature gates.
static BOOL WCKSignatureMatches(Method method, const char *returnType,
                                const char *const *arguments, unsigned int count) {
    if (!method || !returnType || !*returnType || (count && !arguments)) return NO;
    unsigned int actualCount = method_getNumberOfArguments(method);
    if (actualCount < 2 || count != actualCount - 2) return NO;
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

BOOL WCKMethodMatches(Class cls, SEL selector, const char *returnType,
                     const char *const *arguments, unsigned int count) {
    if (!cls || !selector) return NO;
    return WCKSignatureMatches(class_getInstanceMethod(cls, selector), returnType, arguments, count);
}

static BOOL WCKSameImplementation(IMP left, IMP right) {
    if (!left || !right) return left == right;
#if __has_feature(ptrauth_calls)
    // Strip for identity ONLY. Keep backend-returned callable pointers intact.
    return ptrauth_strip(left, ptrauth_key_function_pointer) ==
           ptrauth_strip(right, ptrauth_key_function_pointer);
#else
    return left == right;
#endif
}

static BOOL WCKReportHookStatus(Class cls, SEL selector, NSString *status) {
    NSString *key = [NSString stringWithFormat:@"hook.%s/%s/%s",
        cls && class_isMetaClass(cls) ? "class" : "instance",
        cls ? class_getName(cls) : "<missing>",
        selector ? sel_getName(selector) : "<missing>"];
    WCKSetModuleStatus(key, status);
    return NO;
}

BOOL WCKInstallHook(Class cls, SEL selector, IMP replacement, IMP *original,
                    const char *returnType, const char *const *arguments,
                    unsigned int count) {
    if (!replacement || !original)
        return WCKReportHookStatus(cls, selector, @"install_failed.invalid_argument");
    if (!cls || !selector || !class_getInstanceMethod(cls, selector))
        return WCKReportHookStatus(cls, selector, @"target_missing");
    if (!WCKMethodMatches(cls, selector, returnType, arguments, count))
        return WCKReportHookStatus(cls, selector, @"install_failed.signature_mismatch");
    WCKInitRegistry();
    NSString *key = [NSString stringWithFormat:@"%p/%s", cls, sel_getName(selector)];
    WCKHookRecord *record = nil;
    WCKHookFunction hook = NULL;
    IMP fallback = NULL;
    @synchronized(sInstalled) {
        WCKHookRecord *existing = sInstalled[key];
        if (existing) {
            if (!WCKSameImplementation(existing.replacement, replacement))
                return WCKReportHookStatus(cls, selector, @"conflict_skipped");
            if (existing.installing)
                return WCKReportHookStatus(cls, selector, @"conflict_skipped.install_in_progress");
            // Same owner is idempotent, even if another plugin subsequently chains on top.
            // Never recompute its original from the currently installed method.
            *original = existing.nextImplementation;
            WCKReportHookStatus(cls, selector, existing.status);
            return existing.verified;
        }
        hook = (WCKHookFunction)dlsym(RTLD_DEFAULT, "MSHookMessageEx");
        if (!hook) return WCKReportHookStatus(cls, selector, @"hook_api_missing");
        Method method = class_getInstanceMethod(cls, selector);
        // Validate the same fresh Method used for the fallback snapshot.
        if (!WCKSignatureMatches(method, returnType, arguments, count))
            return WCKReportHookStatus(cls, selector, @"install_failed.signature_mismatch");
        fallback = method ? method_getImplementation(method) : NULL;
        if (!fallback)
            return WCKReportHookStatus(cls, selector, @"install_failed.original_imp_missing");
        if (WCKSameImplementation(fallback, replacement))
            return WCKReportHookStatus(cls, selector, @"conflict_skipped");

        record = [WCKHookRecord new];
        record.replacement = replacement;
        record.nextImplementation = fallback;
        record.installing = YES;
        record->backendOriginal = NULL;
        // Reserve BEFORE invoking foreign code: @synchronized is reentrant.
        sInstalled[key] = record;
        // A backend may publish the replacement before it provides the chaining stub.
        // Its NULL/untouched output must never blank the replacement's live original.
        *original = fallback;
    }
    // The reservation protects this target without holding our monitor across
    // foreign code that may synchronously wait for another thread to enter us.
    BOOL hookException = NO;
    @try { hook(cls, selector, replacement, &record->backendOriginal); }
    @catch (__unused NSException *exception) { hookException = YES; }

    @synchronized(sInstalled) {
        IMP candidate = record->backendOriginal;
        BOOL originalValid = candidate && !WCKSameImplementation(candidate, replacement);
        if (originalValid) {
            // Preserve the backend's actual next implementation, not the fallback snapshot.
            record.nextImplementation = candidate;
            *original = candidate;
        }
        Method installedMethod = class_getInstanceMethod(cls, selector);
        IMP current = installedMethod ? method_getImplementation(installedMethod) : NULL;
        BOOL directReplacement = WCKSameImplementation(current, replacement);
        record.installing = NO;
        if (hookException) record.status = @"attempted_unverified.hook_exception";
        else if (!candidate) record.status = @"attempted_unverified.original_imp_null";
        else if (!originalValid) record.status = @"attempted_unverified.original_imp_recursive";
        else if (!directReplacement) record.status = @"attempted_unverified.postcondition_failed";
        else {
            record.verified = YES;
            record.status = @"installed";
        }
        // Nonmatching readback may be a trampoline/outer hook, not proof of failure.
        // Quarantine every attempted-but-unverified target; do not blindly re-hook or
        // raw-replace its IMP, which could erase another plugin's inheritance chain.
        WCKReportHookStatus(cls, selector, record.status);
        return record.verified;
    }
}
