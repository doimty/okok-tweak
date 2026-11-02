#import <UIKit/UIKit.h>
#import "WCKRuntime.h"
#import "WCKSettings.h"

// Pinned-session limit for the home session list, implemented independently:
// the reference tweak caps the same host method, but every name, key and line
// here is WCK's own. The hook only changes what the host method returns; it
// never touches a frame, a cell, or the list's data source.
//
// Host method: -[NewMainFrameViewController maxSessionCountInOneScreen].
// Declared as NSInteger ("q"): a count on 64-bit ObjC. If the host method's
// real encoding differs, WCKInstallHook refuses with a signature-mismatch
// status and nothing is hooked; that status is visible on the settings page.

static IMP sOriginalMaxSessionCount = NULL;

typedef NSInteger (*WCKMaxSessionCountIMP)(id self, SEL _cmd);

static NSInteger WCKTopLimitMaxSessions(id self, SEL _cmd) {
    WCKMaxSessionCountIMP next = (WCKMaxSessionCountIMP)sOriginalMaxSessionCount;
    // Gate at call time, not at install time: the user can toggle without a
    // relaunch, and a disabled feature leaves the host value untouched.
    if (WCKEnabled(@"topLimitEnabled")) {
        NSNumber *configured = WCKSettings.shared.snapshot[@"topLimitCount"];
        NSInteger limit = [configured integerValue];
        if (limit > 0) return limit;
    }
    // Unreachable after a verified install (the installer only reports ready
    // with a non-NULL next implementation); 0 is a last-resort, never a cap.
    return next ? next(self, _cmd) : 0;
}

void WCKInstallTopLimit(void) {
    Class mainFrame = NSClassFromString(@"NewMainFrameViewController");
    if (!mainFrame) { WCKSetModuleStatus(@"topLimit", @"会话列表类不存在"); return; }
    BOOL installed = WCKInstallHook(mainFrame,
        NSSelectorFromString(@"maxSessionCountInOneScreen"),
        (IMP)WCKTopLimitMaxSessions, (IMP *)&sOriginalMaxSessionCount,
        "q", NULL, 0);
    WCKSetModuleStatus(@"topLimit", installed ? @"ready" : @"Hook 不可用");
}
