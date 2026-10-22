#import <UIKit/UIKit.h>
#import <objc/message.h>
#import "WCKRuntime.h"
#import "WCKSettings.h"
#import <math.h>

// Reference UUID 525BA5E4... installs BaseMsgContentViewController's
// scrollViewWillEndDragging:withVelocity:targetContentOffset: at 0x2e29c4.
// The original calls the host first, then tests bottom<=10pt and velocity.y>0.5,
// and after 100ms asks toolView.textView to becomeFirstResponder.
static void (*sOriginalKeyboardDrag)(id, SEL, UIScrollView *, CGPoint, CGPoint *);
static char sKeyboardStateKey;
static NSUInteger sKeyboardEpoch;
@interface WCKKeyboardPending : NSObject
@property(nonatomic) NSUInteger generation;
@end
@implementation WCKKeyboardPending @end

static BOOL WCKKeyboardVisible(UIViewController *vc, UIScrollView *scroll) {
    return NSThread.isMainThread && WCKEnabled(@"keyboardSwipe") &&
        UIApplication.sharedApplication.applicationState == UIApplicationStateActive &&
        [vc isKindOfClass:UIViewController.class] && vc.isViewLoaded && vc.view.window &&
        !vc.view.hidden && vc.view.alpha >= 0.01 && !vc.presentedViewController &&
        (!vc.navigationController || vc.navigationController.topViewController == vc) &&
        [scroll isKindOfClass:UIScrollView.class] && scroll.window &&
        !scroll.hidden && scroll.alpha >= 0.01 && [scroll isDescendantOfView:vc.view];
}
static id WCKKeyboardTool(UIViewController *vc) {
    SEL selector = NSSelectorFromString(@"toolView");
    if (!WCKMethodMatches(object_getClass(vc), selector, "@", NULL, 0)) return nil;
    id tool = ((id (*)(id,SEL))objc_msgSend)(vc, selector);
    // Original's narrowly named fallback, not a scan of unknown private ivars.
    if (!tool) tool = [vc valueForKey:@"_inputToolView"];
    return [tool isKindOfClass:UIView.class] ? tool : nil;
}
static UIResponder *WCKKeyboardText(id tool) {
    SEL selector = NSSelectorFromString(@"textView");
    if (!tool || !WCKMethodMatches(object_getClass(tool), selector, "@", NULL, 0)) return nil;
    id text = ((id (*)(id,SEL))objc_msgSend)(tool, selector);
    if (![text isKindOfClass:UIResponder.class] ||
        !WCKMethodMatches(object_getClass(text), @selector(isFirstResponder), @encode(BOOL), NULL, 0) ||
        !WCKMethodMatches(object_getClass(text), @selector(becomeFirstResponder), @encode(BOOL), NULL, 0)) return nil;
    return text;
}
static void WCKKeyboardWillEndDragging(UIViewController *vc, SEL cmd,
        UIScrollView *scroll, CGPoint velocity, CGPoint *target) {
    // Preserve the host's parameters and target pointer; exactly one original call.
    sOriginalKeyboardDrag(vc, cmd, scroll, velocity, target);
    if (!NSThread.isMainThread) return;
    WCKKeyboardPending *state = objc_getAssociatedObject(vc, &sKeyboardStateKey);
    if (state) ++state.generation; // Later gestures invalidate a pending request.
    @try {
        if (!WCKKeyboardVisible(vc, scroll)) return;
        CGFloat offset = scroll.contentOffset.y, height = scroll.bounds.size.height;
        CGFloat content = scroll.contentSize.height;
        if (!isfinite(offset) || !isfinite(height) || !isfinite(content) ||
            !isfinite(velocity.y) || height <= 0 || content < 0 ||
            !(offset + height >= content - 10.0) || !(velocity.y > 0.5)) return;
        id tool = WCKKeyboardTool(vc);
        UIResponder *text = WCKKeyboardText(tool);
        if (!text || text.isFirstResponder) return;
        if (!state) {
            state = [WCKKeyboardPending new];
            objc_setAssociatedObject(vc, &sKeyboardStateKey, state, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        NSUInteger generation = ++state.generation, epoch = sKeyboardEpoch;
        __weak UIViewController *weakVC = vc;
        __weak UIScrollView *weakScroll = scroll;
        __weak id weakTool = tool;
        __weak UIResponder *weakText = text;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 100 * NSEC_PER_MSEC),
            dispatch_get_main_queue(), ^{
                @try {
                    UIViewController *current = weakVC; UIScrollView *list = weakScroll;
                    if (!current || epoch != sKeyboardEpoch ||
                        state.generation != generation || !WCKKeyboardVisible(current, list)) return;
                    id currentTool = WCKKeyboardTool(current);
                    UIResponder *currentText = WCKKeyboardText(currentTool);
                    if (!currentTool || currentTool != weakTool || !currentText ||
                        currentText != weakText || currentText.isFirstResponder) return;
                    BOOL accepted = [currentText becomeFirstResponder];
                    WCKSetModuleStatus(@"keyboardSwipe.debug.last", accepted ?
                        @"已请求聊天文本框响应" : @"聊天文本框拒绝响应");
                } @catch (__unused NSException *exception) {
                    WCKSetModuleStatus(@"keyboardSwipe.debug.last", @"文本框状态变化，已跳过");
                }
            });
    } @catch (__unused NSException *exception) {
        WCKSetModuleStatus(@"keyboardSwipe.debug.last", @"聊天输入接口异常，已保留原行为");
    }
}
void WCKInstallKeyboard(void) {
    Class cls = NSClassFromString(@"BaseMsgContentViewController");
    if (!WCKMethodMatches(cls, NSSelectorFromString(@"toolView"), "@", NULL, 0)) {
        WCKSetModuleStatus(@"keyboardSwipe", @"聊天输入栏 getter ABI 不可用"); return;
    }
    const char *args[] = {"@", @encode(CGPoint), @encode(CGPoint *)};
    BOOL installed = WCKInstallHook(cls,
        NSSelectorFromString(@"scrollViewWillEndDragging:withVelocity:targetContentOffset:"),
        (IMP)WCKKeyboardWillEndDragging, (IMP *)&sOriginalKeyboardDrag, "v", args, 3);
    WCKSetModuleStatus(@"keyboardSwipe", installed && sOriginalKeyboardDrag ? @"ready" : @"聊天滚动回调 ABI 不可用");
    if (installed) [NSNotificationCenter.defaultCenter addObserverForName:WCKSettingsDidChangeNotification
        object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *note) {
            ++sKeyboardEpoch;
        }];
}
