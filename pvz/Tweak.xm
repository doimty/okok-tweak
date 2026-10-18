#import <UIKit/UIKit.h>

static BOOL PVZIsAdViewController(UIViewController *vc) {
    if (!vc) return NO;
    NSString *name = NSStringFromClass([vc class]);
    if (name.length == 0) return NO;
    NSArray<NSString *> *markers = @[
        @"FBAd", @"GAD", @"MAAd", @"ALAd", @"UnityAds", @"Vungle",
        @"MTG", @"IronSource", @"LevelPlay", @"PAG", @"BidMachine", @"AppLovin"
    ];
    for (NSString *m in markers) {
        if ([name hasPrefix:m] || [name containsString:m]) return YES;
    }
    return NO;
}

static void PVZCloseAfter(UIViewController *vc, double delay) {
    __weak UIViewController *weakVC = vc;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        UIViewController *strongVC = weakVC;
        if (!strongVC) return;
        if (strongVC.presentingViewController) {
            [strongVC dismissViewControllerAnimated:NO completion:nil];
        } else if (strongVC.view.window) {
            strongVC.view.window.hidden = YES;
        }
    });
}

%hook UIViewController

- (void)presentViewController:(UIViewController *)viewControllerToPresent
                     animated:(BOOL)flag
                   completion:(void (^)(void))completion {
    %orig;
    if (PVZIsAdViewController(viewControllerToPresent)) {
        PVZCloseAfter(viewControllerToPresent, 0.4);
    }
}

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    if (PVZIsAdViewController(self)) {
        PVZCloseAfter(self, 0.3);
    }
}

%end
