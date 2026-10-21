#import <UIKit/UIKit.h>
#import <objc/message.h>
#import "WCKRuntime.h"
#import "WCKSettings.h"

static char sReadDriverKey;
static NSHashTable *sReadDrivers;
static void (*sOriginalTabMove)(UIView *, SEL);
static void (*sOriginalTabLayout)(UIView *, SEL);

static id WCKServiceCenter(void) {
    Class cls = NSClassFromString(@"MMServiceCenter");
    return ((id (*)(id,SEL))objc_msgSend)(cls, NSSelectorFromString(@"defaultCenter"));
}
static id WCKService(id center, NSString *name) {
    return ((id (*)(id,SEL,Class))objc_msgSend)(center, NSSelectorFromString(@"getService:"),
        NSClassFromString(name));
}

@interface WCKReadAllDriver : NSObject <UIGestureRecognizerDelegate>
@property (nonatomic, weak) UIView *bar;
@property (nonatomic, strong) UILongPressGestureRecognizer *press;
@property (nonatomic, weak) UIView *target;
@property (nonatomic) NSUInteger generation;
@property (nonatomic) BOOL busy;
- (void)refresh;
- (void)pressed:(UILongPressGestureRecognizer *)recognizer;
@end

@implementation WCKReadAllDriver
- (UIView *)firstItem {
    UIView *bar = self.bar;
    if (!bar.window || bar.hidden || bar.alpha < 0.01) return nil;
    id items = ((id (*)(id,SEL))objc_msgSend)(bar, NSSelectorFromString(@"tabBarItemViews"));
    if (![items isKindOfClass:NSArray.class] || [items count] != 4) return nil;
    id first = [items objectAtIndex:0];
    if (![first isKindOfClass:UIView.class] || ![first window] || [first isHidden] || [first alpha] < 0.01) return nil;
    UIView *ancestor = [first superview];
    for (NSUInteger depth = 0; ancestor && depth < 8; ++depth, ancestor = ancestor.superview) {
        if (ancestor.hidden || ancestor.alpha < 0.01) return nil;
        if (ancestor == bar) return first;
    }
    return nil;
}
- (void)refresh {
    UIView *first = [self firstItem];
    if (self.target != first) {
        [self.target removeGestureRecognizer:self.press];
        self.target = first;
        [first addGestureRecognizer:self.press];
        if (self.busy) { ++self.generation; self.busy = NO; }
    }
    self.press.enabled = WCKEnabled(@"readAll") && first != nil;
    if (!self.press.enabled && self.busy) { ++self.generation; self.busy = NO; }
}
- (UIViewController *)mainFrame {
    UIViewController *controller = nil;
    for (UIResponder *r = self.bar.nextResponder; r; r = r.nextResponder)
        if ([r isKindOfClass:UITabBarController.class]) {
            UITabBarController *tabs = (UITabBarController *)r;
            if (tabs.selectedIndex != 0) return nil;
            controller = tabs.selectedViewController; break;
        }
    if ([controller isKindOfClass:UINavigationController.class])
        controller = [(UINavigationController *)controller topViewController];
    Class home = NSClassFromString(@"NewMainFrameViewController");
    return home && [controller isKindOfClass:home] && !controller.presentedViewController
        ? controller : nil;
}
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)recognizer shouldReceiveTouch:(UITouch *)touch {
    UIView *bar = self.bar;
    if (self.busy || !WCKEnabled(@"readAll") || !bar.window || bar.hidden || bar.alpha < 0.01 ||
        !self.mainFrame) return NO;
    UIView *first = [self firstItem];
    if (!first || first != self.target || recognizer != self.press || recognizer.view != first) return NO;
    CGPoint point = [touch locationInView:first];
    return CGRectContainsPoint(first.bounds, point);
}
- (void)finish:(NSString *)message {
    self.busy = NO;
    UIViewController *host = self.mainFrame;
    if (!host || !self.bar.window) return;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"一键已读"
        message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    [host presentViewController:alert animated:YES completion:nil];
}
- (void)consume:(NSArray<NSString *> *)names index:(NSUInteger)index
        center:(id)center manager:(id)manager sessions:(id)sessions cleared:(NSUInteger)cleared
        generation:(NSUInteger)generation {
    if (generation != self.generation || !self.busy) return;
    if (!WCKEnabled(@"readAll") || UIApplication.sharedApplication.applicationState != UIApplicationStateActive ||
        ![self firstItem] || self.target != [self firstItem] || !self.mainFrame || WCKServiceCenter() != center ||
        WCKService(center, @"CMessageMgr") != manager ||
        WCKService(center, @"MMNewSessionMgr") != sessions) {
        [self finish:@"操作已停止，未继续处理剩余会话。"]; return;
    }
    NSUInteger end = MIN(index + 16, names.count);
    SEL countSelector = NSSelectorFromString(@"GetUnReadCount:");
    SEL clearSelector = NSSelectorFromString(@"ClearUnRead:FromID:ToID:");
    for (NSUInteger i = index; i < end; ++i) {
        if (!WCKEnabled(@"readAll") || generation != self.generation ||
            WCKServiceCenter() != center || WCKService(center, @"CMessageMgr") != manager ||
            WCKService(center, @"MMNewSessionMgr") != sessions) {
            [self finish:@"操作已停止，未继续处理剩余会话。"]; return;
        }
        NSString *name = names[i];
        unsigned int before = ((unsigned int (*)(id,SEL,id))objc_msgSend)(manager, countSelector, name);
        if (!before) continue;
        ((void (*)(id,SEL,id,unsigned int,unsigned int))objc_msgSend)
            (manager, clearSelector, name, 0, UINT32_MAX);
        unsigned int after = ((unsigned int (*)(id,SEL,id))objc_msgSend)(manager, countSelector, name);
        if (!after) ++cleared;
        else { [self finish:@"清理后仍有未读，未能核实全部完成。"]; return; }
    }
    if (end == names.count) {
        [self finish:[NSString stringWithFormat:@"已核实 %lu 个会话的未读数清零。", (unsigned long)cleared]];
    } else {
        // Yield the main queue instead of blocking it with an unbounded session loop.
        dispatch_async(dispatch_get_main_queue(), ^{
            [self consume:names index:end center:center manager:manager sessions:sessions cleared:cleared generation:generation];
        });
    }
}
- (void)pressed:(UILongPressGestureRecognizer *)recognizer {
    if (recognizer != self.press) return;
    if (recognizer.state == UIGestureRecognizerStateCancelled) {
        ++self.generation; if (self.busy) [self finish:@"操作已停止，未继续处理剩余会话。"]; return;
    }
    if (recognizer.state != UIGestureRecognizerStateBegan || self.busy || !WCKEnabled(@"readAll") ||
        UIApplication.sharedApplication.applicationState != UIApplicationStateActive ||
        !self.press.enabled || ![self firstItem] || self.target != [self firstItem] ||
        recognizer.view != self.target || !self.mainFrame) return;
    id center = WCKServiceCenter();
    id manager = WCKService(center, @"CMessageMgr");
    id sessions = WCKService(center, @"MMNewSessionMgr");
    if (![center isKindOfClass:NSClassFromString(@"MMServiceCenter")] ||
        ![manager isKindOfClass:NSClassFromString(@"CMessageMgr")] ||
        ![sessions isKindOfClass:NSClassFromString(@"MMNewSessionMgr")]) {
        [self finish:@"当前账号的消息服务不可用，未做修改。"]; return;
    }
    id raw = ((id (*)(id,SEL))objc_msgSend)(sessions, NSSelectorFromString(@"GetUserNamesOnSessionList"));
    if (![raw isKindOfClass:NSArray.class] || [raw count] > 5000) {
        [self finish:@"会话列表不可用或过大，未做修改。"]; return;
    }
    // The real GetUserNamesOnSessionList returns NSString elements, not MMSessionInfo.
    // Validate the entire snapshot before invoking any mutating message-service method.
    NSMutableArray *names = [NSMutableArray arrayWithCapacity:[raw count]];
    NSMutableSet *seen = [NSMutableSet set];
    for (id name in raw) {
        if (![name isKindOfClass:NSString.class] || ![name length] || [name length] > 512) {
            [self finish:@"会话列表类型异常，未做修改。"]; return;
        }
        if (![seen containsObject:name]) {
            NSString *stable = [name copy]; [seen addObject:stable]; [names addObject:stable];
        }
    }
    self.busy = YES;
    NSUInteger generation = ++self.generation;
    [self consume:names.copy index:0 center:center manager:manager sessions:sessions cleared:0 generation:generation];
}
@end

static void WCKBindReadBar(UIView *bar) {
    if (!NSThread.isMainThread) return;
    WCKReadAllDriver *driver = objc_getAssociatedObject(bar, &sReadDriverKey);
    if (!driver && bar.window) {
        driver = [WCKReadAllDriver new]; driver.bar = bar;
        driver.press = [[UILongPressGestureRecognizer alloc] initWithTarget:driver action:@selector(pressed:)];
        driver.press.minimumPressDuration = 0.8;
        driver.press.cancelsTouchesInView = NO;
        driver.press.delegate = driver;
        objc_setAssociatedObject(bar, &sReadDriverKey, driver, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [sReadDrivers addObject:driver];
    }
    [driver refresh];
}

static void WCKReadBarMoved(UIView *bar, SEL selector) {
    if (sOriginalTabMove) sOriginalTabMove(bar, selector);
    WCKBindReadBar(bar);
}
static void WCKReadBarLayout(UIView *bar, SEL selector) {
    if (sOriginalTabLayout) sOriginalTabLayout(bar, selector);
    WCKBindReadBar(bar); // MMTabBar only; never resolve account services during layout.
}

void WCKInstallReadAll(void) {
    Class center = NSClassFromString(@"MMServiceCenter");
    Class manager = NSClassFromString(@"CMessageMgr");
    Class sessions = NSClassFromString(@"MMNewSessionMgr");
    Class bar = NSClassFromString(@"MMTabBar");
    const char *serviceArgs[] = {"#"};
    const char *objectArgs[] = {"@"};
    const char *clearArgs[] = {"@", "I", "I"};
    // defaultCenter may be supplied by a category. Do not trust static presence.
    BOOL matched = WCKMethodMatches(object_getClass(center), NSSelectorFromString(@"defaultCenter"), "@", NULL, 0)
        && WCKMethodMatches(center, NSSelectorFromString(@"getService:"), "@", serviceArgs, 1)
        && WCKMethodMatches(sessions, NSSelectorFromString(@"GetUserNamesOnSessionList"), "@", NULL, 0)
        && WCKMethodMatches(manager, NSSelectorFromString(@"ClearUnRead:FromID:ToID:"), "v", clearArgs, 3)
        && WCKMethodMatches(manager, NSSelectorFromString(@"GetUnReadCount:"), "I", objectArgs, 1)
        && WCKMethodMatches(bar, NSSelectorFromString(@"tabBarItemViews"), "@", NULL, 0)
        && NSClassFromString(@"NewMainFrameViewController");
    if (!matched) { WCKSetModuleStatus(@"readAll", @"服务或底栏 ABI 不匹配"); return; }
    sReadDrivers = [NSHashTable weakObjectsHashTable];
    BOOL layoutInstalled = WCKInstallHook(bar, @selector(layoutSubviews), (IMP)WCKReadBarLayout,
        (IMP *)&sOriginalTabLayout, "v", NULL, 0);
    BOOL moveInstalled = WCKInstallHook(bar, @selector(didMoveToWindow), (IMP)WCKReadBarMoved,
        (IMP *)&sOriginalTabMove, "v", NULL, 0);
    BOOL installed = layoutInstalled || moveInstalled;
    WCKSetModuleStatus(@"readAll", installed ? @"ready" : @"Hook 不可用");
    if (installed)
        [NSNotificationCenter.defaultCenter addObserverForName:WCKSettingsDidChangeNotification
            object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
                for (WCKReadAllDriver *driver in sReadDrivers.allObjects) [driver refresh];
            }];
}
