#import <UIKit/UIKit.h>
#import "WCKRuntime.h"

__attribute__((constructor)) static void WCKStart(void) {
    // Install the list hooks at dylib load, before WeChat builds its first table:
    // a class that does not exist yet would otherwise never be hooked at all.
    WCKInstallCorners();
    dispatch_async(dispatch_get_main_queue(), ^{
        // Entry is initialized first and has no feature/master-switch dependency.
        WCKInstallEntryPoints();
        WCKInstallKeyboard(); WCKInstallSVG(); WCKInstallVerifiedFeatures();
        // Retry after the window exists: late-loaded cell classes get picked up.
        WCKInstallCorners();
        // Bounded late-image retries, not a perpetual polling loop.
        for (NSNumber *delay in @[@0.25, @1.0, @3.0])
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay.doubleValue * NSEC_PER_SEC)),
                dispatch_get_main_queue(), ^{
                    WCKInstallEntryPoints();
                    WCKInstallCornersLate();
                });
        for (NSNotificationName name in @[UIApplicationDidFinishLaunchingNotification,
                                          UIApplicationDidBecomeActiveNotification])
            [NSNotificationCenter.defaultCenter addObserverForName:name object:nil
                queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
                    WCKInstallEntryPoints();
                    WCKInstallCornersLate();
                }];
    });
}
