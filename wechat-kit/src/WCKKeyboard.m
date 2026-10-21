#import <UIKit/UIKit.h>
#import <objc/message.h>
#import "WCKRuntime.h"
#import "WCKSettings.h"

static char sKeyboardDriverKey;
static NSHashTable *sKeyboardDrivers;
static void (*sOriginalMove)(UIView *, SEL);

@interface WCKKeyboardDriver : NSObject <UIGestureRecognizerDelegate>
@property (nonatomic, weak) UIView *host;
@property (nonatomic, strong) UISwipeGestureRecognizer *swipe;
- (void)refresh;
- (void)swiped:(UISwipeGestureRecognizer *)gesture;
@end

@implementation WCKKeyboardDriver
- (void)refresh {
    NSAssert(NSThread.isMainThread, @"UI must run on main thread");
    self.swipe.enabled = WCKEnabled(@"keyboardSwipe") && self.host.window != nil;
}
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)recognizer shouldReceiveTouch:(UITouch *)touch {
    UIView *host = self.host;
    if (!host.window || !WCKEnabled(@"keyboardSwipe") || host.hidden || host.alpha < 0.01)
        return NO;
    // Never steal the voice-record, send, attachment or expression buttons.
    for (UIView *view = touch.view; view && view != host; view = view.superview)
        if ([view isKindOfClass:UIControl.class]) return NO;
    return YES;
}
- (void)swiped:(UISwipeGestureRecognizer *)gesture {
    UIView *host = self.host;
    if (gesture.state != UIGestureRecognizerStateRecognized || !host.window ||
        UIApplication.sharedApplication.applicationState != UIApplicationStateActive ||
        !WCKEnabled(@"keyboardSwipe")) return;
    SEL controllerSelector = NSSelectorFromString(@"getViewController");
    id controller = ((id (*)(id, SEL))objc_msgSend)(host, controllerSelector);
    Class chat = NSClassFromString(@"BaseMsgContentViewController");
    if (!chat || ![controller isKindOfClass:chat] ||
        ![controller isKindOfClass:UIViewController.class]) return;
    UIViewController *vc = controller;
    if (vc.presentedViewController || (vc.navigationController &&
        vc.navigationController.topViewController != vc)) return;
    // Use the host's normal responder state machine; do not set private ivars/mode numbers.
    [host becomeFirstResponder];
}
@end

static void WCKKeyboardMoved(UIView *host, SEL selector) {
    if (sOriginalMove) sOriginalMove(host, selector);
    if (!NSThread.isMainThread) return;
    WCKKeyboardDriver *driver = objc_getAssociatedObject(host, &sKeyboardDriverKey);
    if (!driver && host.window) {
        driver = [WCKKeyboardDriver new];
        driver.host = host;
        driver.swipe = [[UISwipeGestureRecognizer alloc] initWithTarget:driver
            action:@selector(swiped:)];
        driver.swipe.direction = UISwipeGestureRecognizerDirectionUp;
        driver.swipe.cancelsTouchesInView = NO;
        driver.swipe.delaysTouchesBegan = NO;
        driver.swipe.delegate = driver;
        objc_setAssociatedObject(host, &sKeyboardDriverKey, driver, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [host addGestureRecognizer:driver.swipe];
        [sKeyboardDrivers addObject:driver];
    }
    [driver refresh];
}

void WCKInstallKeyboard(void) {
    Class cls = NSClassFromString(@"MMInputToolView");
    if (!WCKMethodMatches(cls, NSSelectorFromString(@"getViewController"), "@", NULL, 0) ||
        !WCKMethodMatches(cls, @selector(becomeFirstResponder), @encode(BOOL), NULL, 0)) {
        WCKSetModuleStatus(@"keyboardSwipe", @"ABI 不匹配"); return;
    }
    sKeyboardDrivers = [NSHashTable weakObjectsHashTable];
    BOOL installed = WCKInstallHook(cls, @selector(didMoveToWindow), (IMP)WCKKeyboardMoved,
        (IMP *)&sOriginalMove, "v", NULL, 0);
    WCKSetModuleStatus(@"keyboardSwipe", installed ? @"ready" : @"Hook 不可用");
    if (installed) {
        // NotificationCenter retains this process-lifetime observer; no view controller captured.
        [NSNotificationCenter.defaultCenter addObserverForName:WCKSettingsDidChangeNotification
            object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
                for (WCKKeyboardDriver *driver in sKeyboardDrivers.allObjects) [driver refresh];
            }];
    }
}
