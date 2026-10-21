#import <UIKit/UIKit.h>
#import <objc/message.h>
#import "WCKRuntime.h"
#import "WCKSettings.h"

static char sKeyboardDriverKey;
static NSHashTable *sKeyboardDrivers;
static void (*sOriginalMove)(UIView *, SEL);
static void (*sOriginalLayout)(UIView *, SEL);

// Bound the walk and require genuine membership. No foreign controls/recording
// gestures are accepted even when another plugin gives us a synthetic touch.
static BOOL WCKKeyboardContains(UIView *root, UIView *view, BOOL excludeControls) {
    if (!root || !view) return NO;
    for (NSUInteger depth = 0; view && depth < 32; ++depth, view = view.superview) {
        if (view.hidden || view.alpha < 0.01) return NO;
        if (view == root) return YES;
        if (excludeControls && [view isKindOfClass:UIControl.class]) return NO;
    }
    return NO;
}

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
    if (recognizer != self.swipe || recognizer.view != host) return NO;
    // Never steal the voice-record, send, attachment or expression buttons.
    return WCKKeyboardContains(host, touch.view, YES);
}
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)recognizer
        shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)other {
    UIView *host = self.host;
    if (recognizer != self.swipe || recognizer.view != host || !host.window ||
        !WCKEnabled(@"keyboardSwipe") || ![other isKindOfClass:UIPanGestureRecognizer.class] ||
        ![other.view isKindOfClass:UIScrollView.class] ||
        ((UIScrollView *)other.view).panGestureRecognizer != other ||
        !WCKKeyboardContains(host, other.view, YES)) return NO;
    SEL getter = NSSelectorFromString(@"getGrowTextView");
    if (!WCKMethodMatches(object_getClass(host), getter, "@", NULL, 0)) return NO;
    id text = ((id (*)(id,SEL))objc_msgSend)(host, getter);
    return [text isKindOfClass:UIView.class] && WCKKeyboardContains(text, other.view, YES);
}
- (void)swiped:(UISwipeGestureRecognizer *)gesture {
    UIView *host = self.host;
    if (gesture != self.swipe || gesture.view != host ||
        gesture.state != UIGestureRecognizerStateRecognized || !host.window ||
        host.hidden || host.alpha < 0.01 ||
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
    BOOL accepted = [host becomeFirstResponder];
    WCKSetModuleStatus(@"keyboardSwipe.debug.last", accepted ? @"已请求输入栏响应" : @"输入栏拒绝响应");
}
@end

static void WCKBindKeyboard(UIView *host) {
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

static void WCKKeyboardMoved(UIView *host, SEL selector) {
    if (sOriginalMove) sOriginalMove(host, selector);
    WCKBindKeyboard(host);
}
static void WCKKeyboardLayout(UIView *host, SEL selector) {
    if (sOriginalLayout) sOriginalLayout(host, selector);
    WCKBindKeyboard(host); // MMInputToolView only. Never traverse windows/chat contents.
}

void WCKInstallKeyboard(void) {
    Class cls = NSClassFromString(@"MMInputToolView");
    if (!WCKMethodMatches(cls, NSSelectorFromString(@"getViewController"), "@", NULL, 0) ||
        !WCKMethodMatches(cls, NSSelectorFromString(@"getGrowTextView"), "@", NULL, 0) ||
        !WCKMethodMatches(cls, @selector(becomeFirstResponder), @encode(BOOL), NULL, 0)) {
        WCKSetModuleStatus(@"keyboardSwipe", @"ABI 不匹配"); return;
    }
    sKeyboardDrivers = [NSHashTable weakObjectsHashTable];
    BOOL moved = WCKInstallHook(cls, @selector(didMoveToWindow), (IMP)WCKKeyboardMoved,
        (IMP *)&sOriginalMove, "v", NULL, 0);
    BOOL layout = WCKInstallHook(cls, @selector(layoutSubviews), (IMP)WCKKeyboardLayout,
        (IMP *)&sOriginalLayout, "v", NULL, 0);
    BOOL installed = moved || layout;
    WCKSetModuleStatus(@"keyboardSwipe", installed ? @"ready" : @"Hook 不可用");
    if (installed) {
        // NotificationCenter retains this process-lifetime observer; no view controller captured.
        [NSNotificationCenter.defaultCenter addObserverForName:WCKSettingsDidChangeNotification
            object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
                for (WCKKeyboardDriver *driver in sKeyboardDrivers.allObjects) [driver refresh];
            }];
    }
}
