#import <UIKit/UIKit.h>
#import "WCKRuntime.h"
#import "WCKSettingsViewController.h"

static char sSettingsItemKey;
static void (*sOriginalSettingsLoad)(UIViewController *, SEL);
static void (*sOriginalSettingsAppear)(UIViewController *, SEL);
static BOOL sSettingsHookReady;

@interface WCKSettingsEntry : NSObject
@property (nonatomic, weak) UIViewController *host;
- (void)openSettings;
@end
@implementation WCKSettingsEntry
- (void)openSettings {
    UIViewController *host = self.host;
    if (!NSThread.isMainThread || !host.viewIfLoaded.window || host.presentedViewController) return;
    WCKSettingsViewController *settings = [WCKSettingsViewController new];
    if (host.navigationController)
        [host.navigationController pushViewController:settings animated:YES];
    else {
        UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:settings];
        [host presentViewController:nav animated:YES completion:nil];
    }
}
@end

static void WCKAddSettingsEntry(UIViewController *host) {
    if (!NSThread.isMainThread || !sSettingsHookReady) return;
    // Each controller owns a single item+driver; no global retained controller or timer.
    NSDictionary *state = objc_getAssociatedObject(host, &sSettingsItemKey);
    UIBarButtonItem *item = state[@"item"];
    if (!item) {
        WCKSettingsEntry *driver = [WCKSettingsEntry new]; driver.host = host;
        item = [[UIBarButtonItem alloc] initWithTitle:@"WCK" style:UIBarButtonItemStylePlain
            target:driver action:@selector(openSettings)];
        item.accessibilityLabel = @"WeChatKit 设置";
        item.accessibilityIdentifier = @"wck.settings.entry";
        state = @{@"item":item, @"driver":driver};
        objc_setAssociatedObject(host, &sSettingsItemKey, state, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    NSArray *existing = host.navigationItem.rightBarButtonItems ?: @[];
    if (![existing containsObject:item]) {
        NSMutableArray *next = [existing mutableCopy];
        // Append, never replace or remove the host's existing buttons.
        [next addObject:item]; host.navigationItem.rightBarButtonItems = next;
    }
}
static void WCKSettingsLoaded(UIViewController *host, SEL selector) {
    if (sOriginalSettingsLoad) sOriginalSettingsLoad(host,selector);
    WCKAddSettingsEntry(host);
}
static void WCKSettingsAppeared(UIViewController *host, SEL selector) {
    if (sOriginalSettingsAppear) sOriginalSettingsAppear(host,selector);
    WCKAddSettingsEntry(host);
}

__attribute__((constructor)) static void WCKStart(void) {
    // No side effects in extensions, other apps, or unsupported WeChat builds.
    if (!WCKHostIsSupported()) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        WCKInstallKeyboard(); WCKInstallSVG(); WCKInstallVerifiedFeatures();
        Class settings = NSClassFromString(@"NewSettingViewController");
        BOOL loaded = WCKInstallHook(settings, @selector(viewDidLoad), (IMP)WCKSettingsLoaded,
            (IMP *)&sOriginalSettingsLoad, "v", NULL, 0);
        BOOL appeared = WCKInstallHook(settings, NSSelectorFromString(@"willAppear"),
            (IMP)WCKSettingsAppeared, (IMP *)&sOriginalSettingsAppear, "v", NULL, 0);
        sSettingsHookReady = loaded && appeared;
        WCKSetModuleStatus(@"settingsEntry", sSettingsHookReady ? @"ready" : @"设置入口不可用");
    });
}
