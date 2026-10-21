#import <UIKit/UIKit.h>
#import <objc/message.h>
#import "WCKRuntime.h"
#import "WCKEntryRegistry.h"
#import "WCKSettingsViewController.h"

static char sEntryStateKey;
static void (*sSettingsLoad)(UIViewController *, SEL);
static void (*sSettingsWillAppear)(UIViewController *, SEL);
static void (*sSettingsDidAppear)(UIViewController *, SEL, BOOL);
static void (*sSettingsReload)(UIViewController *, SEL);
static void (*sHubLoad)(UIViewController *, SEL);
static BOOL sLoadReady, sWillReady, sDidReady, sReloadReady, sHubReady;

@interface WCKSettingsEntry : NSObject
@property (nonatomic, weak) UIViewController *host;
@property (nonatomic, weak) id section;
@property (nonatomic, weak) id manager;
@property (nonatomic) BOOL updating;
- (void)openSettings;
@end
@implementation WCKSettingsEntry
- (void)openSettings {
    UIViewController *host = self.host;
    if (!NSThread.isMainThread || !host.viewIfLoaded.window || host.presentedViewController) return;
    UINavigationController *navigation = host.navigationController;
    if (navigation && navigation.topViewController != host) return;
    WCKSettingsViewController *settings = [WCKSettingsViewController new];
    if (navigation) [navigation pushViewController:settings animated:YES];
    else [host presentViewController:[[UINavigationController alloc]
        initWithRootViewController:settings] animated:YES completion:nil];
}
@end

static WCKSettingsEntry *WCKDriver(UIViewController *host) {
    WCKSettingsEntry *driver = objc_getAssociatedObject(host, &sEntryStateKey);
    if (!driver) {
        driver = [WCKSettingsEntry new]; driver.host = host;
        objc_setAssociatedObject(host, &sEntryStateKey, driver, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return driver;
}

static BOOL WCKAddSettingsRow(UIViewController *host, WCKSettingsEntry *driver) {
    // Native list fallback: independently visible even with a hidden/custom nav bar.
    // This is the actual 8.0.69.33 setting controller ivar; no hard-coded offset/KVC.
    Ivar slot = class_getInstanceVariable(object_getClass(host), "m_tableViewMgr");
    const char *type = slot ? ivar_getTypeEncoding(slot) : NULL;
    if (!slot || !type || type[0] != '@') return NO;
    id manager = object_getIvar(host, slot);
    if (!manager) return NO;
    const char *objectArg[] = {"@"};
    if (!WCKMethodMatches(object_getClass(manager), NSSelectorFromString(@"sections"), "@", NULL, 0) ||
        !WCKMethodMatches(object_getClass(manager), NSSelectorFromString(@"addSection:"), "v", objectArg, 1) ||
        !WCKMethodMatches(object_getClass(manager), NSSelectorFromString(@"tableView"), "@", NULL, 0)) return NO;
    id sections = ((id (*)(id,SEL))objc_msgSend)(manager, NSSelectorFromString(@"sections"));
    if (![sections isKindOfClass:NSArray.class] || [sections count] > 1024) return NO;
    if (driver.manager == manager && driver.section && [sections containsObject:driver.section]) return YES;
    Class sectionClass = NSClassFromString(@"WCTableViewSectionManager");
    Class cellClass = NSClassFromString(@"WCTableViewCellManager");
    const char *cellArgs[] = {":", "@", "@"};
    SEL factory = NSSelectorFromString(@"normalCellForSel:target:title:");
    if (!WCKMethodMatches(object_getClass(sectionClass), NSSelectorFromString(@"sectionInfoDefaut"), "@", NULL, 0) ||
        !WCKMethodMatches(sectionClass, NSSelectorFromString(@"addCell:"), "v", objectArg, 1) ||
        !WCKMethodMatches(object_getClass(cellClass), factory, "@", cellArgs, 3)) return NO;
    id section = ((id (*)(id,SEL))objc_msgSend)(sectionClass, NSSelectorFromString(@"sectionInfoDefaut"));
    id cell = ((id (*)(id,SEL,SEL,id,id))objc_msgSend)(cellClass, factory,
        @selector(openSettings), driver, @"WeChatKit 设置（备用入口）");
    if (!section || !cell) return NO;
    ((void (*)(id,SEL,id))objc_msgSend)(section, NSSelectorFromString(@"addCell:"), cell);
    // Remember weak identities before a foreign addSection: can reenter or throw.
    driver.section = section; driver.manager = manager;
    ((void (*)(id,SEL,id))objc_msgSend)(manager, NSSelectorFromString(@"addSection:"), section);
    id after = ((id (*)(id,SEL))objc_msgSend)(manager, NSSelectorFromString(@"sections"));
    if (![after isKindOfClass:NSArray.class] || ![after containsObject:section]) return NO;
    id table = ((id (*)(id,SEL))objc_msgSend)(manager, NSSelectorFromString(@"tableView"));
    if ([table isKindOfClass:UITableView.class]) [(UITableView *)table reloadData];
    return YES;
}

static void WCKRefreshEntry(UIViewController *host) {
    if (!NSThread.isMainThread || !WCKHostIsSupported()) return;
    WCKRegisterPluginEntry();
    WCKSettingsEntry *driver = WCKDriver(host);
    if (driver.updating) return;
    driver.updating = YES;
    @try {
        BOOL row = WCKAddSettingsRow(host, driver);
        WCKSetModuleStatus(@"settingsListEntry", row ? @"ready" : @"设置列表接口不可用；使用插件收纳入口");
    } @catch (__unused NSException *exception) {
        WCKSetModuleStatus(@"settingsListEntry", @"列表入口异常；保留独立入口");
    } @finally { driver.updating = NO; }
}

static void WCKSettingsLoaded(UIViewController *host, SEL selector) {
    if (sSettingsLoad) sSettingsLoad(host, selector);
    WCKRefreshEntry(host);
}
static void WCKSettingsAppearing(UIViewController *host, SEL selector) {
    if (sSettingsWillAppear) sSettingsWillAppear(host, selector);
    WCKRefreshEntry(host);
}
static void WCKSettingsAppeared(UIViewController *host, SEL selector, BOOL animated) {
    if (sSettingsDidAppear) sSettingsDidAppear(host, selector, animated);
    WCKRefreshEntry(host);
    __weak UIViewController *weakHost = host;
    // One run-loop retry, not a timer/continuous overlay. Other plugins may set buttons later.
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *strongHost = weakHost;
        if (strongHost.viewIfLoaded.window && (!strongHost.navigationController ||
            strongHost.navigationController.topViewController == strongHost)) WCKRefreshEntry(strongHost);
    });
}
static void WCKSettingsReloaded(UIViewController *host, SEL selector) {
    if (sSettingsReload) sSettingsReload(host, selector);
    WCKRefreshEntry(host);
}
static void WCKHubLoaded(UIViewController *host, SEL selector) {
    // Register BEFORE the hub snapshots its models in the original viewDidLoad/initData.
    WCKRegisterPluginEntry();
    if (sHubLoad) sHubLoad(host, selector);
}

void WCKInstallEntryPoints(void) {
    if (!NSThread.isMainThread || !WCKHostIsSupported()) return;
    WCKRegisterPluginEntry();
    Class settings = NSClassFromString(@"NewSettingViewController");
    if (!sLoadReady) sLoadReady = WCKInstallHook(settings, @selector(viewDidLoad),
        (IMP)WCKSettingsLoaded, (IMP *)&sSettingsLoad, "v", NULL, 0);
    if (!sWillReady) sWillReady = WCKInstallHook(settings, NSSelectorFromString(@"willAppear"),
        (IMP)WCKSettingsAppearing, (IMP *)&sSettingsWillAppear, "v", NULL, 0);
    const char *boolArgs[] = {@encode(BOOL)};
    if (!sDidReady) sDidReady = WCKInstallHook(settings, @selector(viewDidAppear:),
        (IMP)WCKSettingsAppeared, (IMP *)&sSettingsDidAppear, "v", boolArgs, 1);
    if (!sReloadReady) sReloadReady = WCKInstallHook(settings, NSSelectorFromString(@"reloadTableData"),
        (IMP)WCKSettingsReloaded, (IMP *)&sSettingsReload, "v", NULL, 0);
    if (!sHubReady) sHubReady = WCKInstallHook(NSClassFromString(@"WCPluginsViewController"),
        @selector(viewDidLoad), (IMP)WCKHubLoaded, (IMP *)&sHubLoad, "v", NULL, 0);
    // A missing lifecycle method must NOT suppress successful fallback paths.
    BOOL any = sLoadReady || sWillReady || sDidReady || sReloadReady;
    WCKSetModuleStatus(@"settingsEntry", any ? @"ready" : @"设置兜底接口不可用");
}
