#import <Foundation/Foundation.h>
#import <objc/runtime.h>

NS_ASSUME_NONNULL_BEGIN
FOUNDATION_EXPORT BOOL WCKHostIsSupported(void);
FOUNDATION_EXPORT NSDictionary<NSString *, NSString *> *WCKRuntimeStatuses(void);
FOUNDATION_EXPORT void WCKSetModuleStatus(NSString *key, NSString *status);
FOUNDATION_EXPORT BOOL WCKMethodMatches(Class _Nullable cls, SEL selector,
    const char *returnType, const char * _Nullable const * _Nullable arguments,
    unsigned int argumentCount);
FOUNDATION_EXPORT BOOL WCKInstallHook(Class _Nullable cls, SEL selector,
    IMP replacement, IMP _Nullable * _Nonnull original, const char *returnType,
    const char * _Nullable const * _Nullable arguments, unsigned int argumentCount);
FOUNDATION_EXPORT BOOL WCKEnabled(NSString *feature);
FOUNDATION_EXPORT void WCKInstallEntryPoints(void);
FOUNDATION_EXPORT void WCKInstallKeyboard(void);
FOUNDATION_EXPORT void WCKInstallSVG(void);
FOUNDATION_EXPORT void WCKInstallReadAll(void);
FOUNDATION_EXPORT void WCKInstallVerifiedFeatures(void);
NS_ASSUME_NONNULL_END
