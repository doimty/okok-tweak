#import <UIKit/UIKit.h>
#import <objc/message.h>
#import "WCKRuntime.h"
#import "WCKSettings.h"

static char sReadDriverKey;
static NSHashTable *sReadDrivers;
static void (*sOriginalTabMove)(UIView *, SEL);

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
@property (nonatomic) BOOL busy;
- (void)refresh;
- (void)pressed:(UILongPressGestureRecognizer *)recognizer;
@end

@implementation WCKReadAllDriver
- (void)refresh { self.press.enabled = WCKEnabled(@"readAll") && self.bar.window != nil; }
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
    id items = ((id (*)(id,SEL))objc_msgSend)(bar, NSSelectorFromString(@"tabBarItemViews"));
    if (![items isKindOfClass:NSArray.class] || [items count] != 4) return NO;
    id first = [items firstObject];
    if (![first isKindOfClass:UIView.class] || [(UIView *)first superview] != bar) return NO;
    CGPoint point = [touch locationInView:first];
    return ![(UIView *)first isHidden] && CGRectContainsPoint([(UIView *)first bounds], point);
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
        center:(id)center manager:(id)manager sessions:(id)sessions cleared:(NSUInteger)cleared {
    if (!WCKEnabled(@"readAll") || UIApplication.sharedApplication.applicationState != UIApplicationStateActive ||
        !self.bar.window || !self.mainFrame || WCKServiceCenter() != center ||
        WCKService(center, @"CMessageMgr") != manager ||
        WCKService(center, @"MMNewSessionMgr") != sessions) {
        [self finish:@"操作已停止，未继续处理剩余会话。"]; return;
    }
    NSUInteger end = MIN(index + 16, names.count);
    SEL countSelector = NSSelectorFromString(@"GetUnReadCount:");
    SEL clearSelector = NSSelectorFromString(@"ClearUnRead:FromID:ToID:");
    for (NSUInteger i = index; i < end; ++i) {
        NSString *name = names[i];
        unsigned int before = ((unsigned int (*)(id,SEL,id))objc_msgSend)(manager, countSelector, name);
        if (!before) continue;
        ((void (*)(id,SEL,id,unsigned int,unsigned int))objc_msgSend)
            (manager, clearSelector, name, 0, UINT32_MAX);
        unsigned int after = ((unsigned int (*)(id,SEL,id))objc_msgSend)(manager, countSelector, name);
        if (!after) ++cleared;
    }
    if (end == names.count) {
        [self finish:[NSString stringWithFormat:@"已核实 %lu 个会话的未读数清零。", (unsigned long)cleared]];
    } else {
        // Yield the main queue instead of blocking it with an unbounded session loop.
        dispatch_async(dispatch_get_main_queue(), ^{
            [self consume:names index:end center:center manager:manager sessions:sessions cleared:cleared];
        });
    }
}
- (void)pressed:(UILongPressGestureRecognizer *)recognizer {
    if (recognizer.state != UIGestureRecognizerStateBegan || self.busy || !WCKEnabled(@"readAll") ||
        !self.bar.window || !self.mainFrame) return;
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
    NSMutableArray *names = [NSMutableArray arrayWithCapacity:[raw count]];
    for (id name in raw) {
        if (![name isKindOfClass:NSString.class] || ![name length] || [name length] > 512) {
            [self finish:@"会话列表类型异常，未做修改。"]; return;
        }
        [names addObject:[name copy]];
    }
    self.busy = YES;
    [self consume:names.copy index:0 center:center manager:manager sessions:sessions cleared:0];
}
@end

static void WCKReadBarMoved(UIView *bar, SEL selector) {
    if (sOriginalTabMove) sOriginalTabMove(bar, selector);
    if (!NSThread.isMainThread) return;
    WCKReadAllDriver *driver = objc_getAssociatedObject(bar, &sReadDriverKey);
    if (!driver && bar.window) {
        driver = [WCKReadAllDriver new]; driver.bar = bar;
        driver.press = [[UILongPressGestureRecognizer alloc] initWithTarget:driver action:@selector(pressed:)];
        driver.press.minimumPressDuration = 0.8;
        driver.press.cancelsTouchesInView = NO;
        driver.press.delegate = driver;
        objc_setAssociatedObject(bar, &sReadDriverKey, driver, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [bar addGestureRecognizer:driver.press];
        [sReadDrivers addObject:driver];
    }
    [driver refresh];
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
    BOOL installed = WCKInstallHook(bar, @selector(didMoveToWindow), (IMP)WCKReadBarMoved,
        (IMP *)&sOriginalTabMove, "v", NULL, 0);
    WCKSetModuleStatus(@"readAll", installed ? @"ready" : @"Hook 不可用");
    if (installed)
        [NSNotificationCenter.defaultCenter addObserverForName:WCKSettingsDidChangeNotification
            object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
                for (WCKReadAllDriver *driver in sReadDrivers.allObjects) [driver refresh];
            }];
}
