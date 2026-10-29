#import <Foundation/Foundation.h>
#import <objc/runtime.h>

NS_ASSUME_NONNULL_BEGIN
FOUNDATION_EXPORT BOOL WCKHostIsSupported(void);
FOUNDATION_EXPORT NSDictionary<NSString *, NSString *> *WCKRuntimeStatuses(void);
FOUNDATION_EXPORT void WCKSetModuleStatus(NSString *key, NSString *status);
// Compare the declared return/argument types without full-encoding byte offsets.
// For class methods, pass the metaclass; host version is not part of this check.
FOUNDATION_EXPORT BOOL WCKMethodMatches(Class _Nullable cls, SEL selector,
    const char *returnType, const char * _Nullable const * _Nullable arguments,
    unsigned int argumentCount);
// YES means a verified direct replacement (or identical previously verified registration).
// NO after calling the backend can mean a partial/indeterminate hook, NOT an uninstall.
// After a backend attempt, preserve the preflight fallback or backend-provided next IMP.
// This is not a guarantee about arbitrary engine pointers; unverified targets are quarantined.
// Caller must dedicate each live original-output slot to one target/replacement.
// Per-target diagnostics live at hook.instance|class/<ClassName>/<selector> in statuses.
FOUNDATION_EXPORT BOOL WCKInstallHook(Class _Nullable cls, SEL selector,
    IMP replacement, IMP _Nullable * _Nonnull original, const char *returnType,
    const char * _Nullable const * _Nullable arguments, unsigned int argumentCount);
FOUNDATION_EXPORT BOOL WCKEnabled(NSString *feature);
FOUNDATION_EXPORT void WCKInstallEntryPoints(void);
FOUNDATION_EXPORT void WCKInstallKeyboard(void);
FOUNDATION_EXPORT void WCKInstallSVG(void);
FOUNDATION_EXPORT void WCKInstallReadAll(void);
FOUNDATION_EXPORT void WCKInstallAlbumSheet(void);
FOUNDATION_EXPORT void WCKInstallMomentsTime(void);
FOUNDATION_EXPORT void WCKInstallVerifiedFeatures(void);
FOUNDATION_EXPORT void WCKInstallCorners(void);
FOUNDATION_EXPORT void WCKRefreshCorners(void);
NS_ASSUME_NONNULL_END
