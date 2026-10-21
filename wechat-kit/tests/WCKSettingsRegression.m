// Apple-only behavioral regression harness. Not executable on Linux.
// Link WCKSettings.m + WCKSettingsViewController.m + this file, NOT WCKRuntime.m.
// From an isolated UIKit test host, call WCKRunSettingsRegression() on the main thread.
#import "WCKSettings.h"
#import "WCKSettingsViewController.h"
#import "WCKRuntime.h"

#define WCK_CHECK(condition) NSCAssert((condition), @"WCK settings regression at line %d", __LINE__)

@interface WCKSettings (Regression)
- (instancetype)initWithFileURL:(NSURL *)fileURL;
@end
@interface WCKSettingsViewController (Regression)
- (instancetype)initWithSettings:(WCKSettings *)settings;
@end

static BOOL WCKTestHost;
static NSDictionary<NSString *, NSString *> *WCKTestStatuses;
BOOL WCKHostIsSupported(void) { return WCKTestHost; }
NSDictionary<NSString *, NSString *> *WCKRuntimeStatuses(void) { return WCKTestStatuses ?: @{}; }

static void WCKWritePlist(NSDictionary *values, NSURL *url) {
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:values
        format:NSPropertyListBinaryFormat_v1_0 options:0 error:NULL];
    WCK_CHECK([data writeToURL:url options:NSDataWritingAtomic error:NULL]);
}

static void WCKStorageRegression(NSURL *base) {
    NSURL *url = [base URLByAppendingPathComponent:@"preferences/settings.plist"];
    WCKSettings *store = [[WCKSettings alloc] initWithFileURL:url];
    WCK_CHECK(store.snapshot.count == 11);
    for (NSString *key in @[@"enabled", @"keyboardSwipe", @"svgTint", @"momentsTime", @"albumSheet", @"readAll"])
        WCK_CHECK(![store boolForKey:key]);
    WCK_CHECK([[store stringForKey:@"svgInclude" defaultValue:@"wrong"] isEqualToString:@""]);
    WCK_CHECK([[store stringForKey:@"svgTintLight" defaultValue:@""] isEqualToString:@"#07C160"]);
    WCK_CHECK([[store stringForKey:@"momentsFormat" defaultValue:@""] isEqualToString:@"yyyy-MM-dd HH:mm:ss"]);
    WCK_CHECK(![store boolForKey:@"unknown"]);
    WCK_CHECK([[store stringForKey:@"enabled" defaultValue:@"fallback"] isEqualToString:@"fallback"]);
    __block NSUInteger notices = 0;
    id observer = [NSNotificationCenter.defaultCenter addObserverForName:WCKSettingsDidChangeNotification
        object:store queue:nil usingBlock:^(NSNotification *notification) {
        (void)notification;
        WCK_CHECK(NSThread.isMainThread);
        NSData *data = [NSData dataWithContentsOfURL:url];
        id persisted = [NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable format:NULL error:NULL];
        WCK_CHECK([persisted isEqual:store.snapshot]); // Disk + snapshot precede notification.
        notices++;
    }];
    @try {
        NSError *error = nil;
        NSDictionary *before = store.snapshot;
        WCK_CHECK(![store setObject:@1 forKey:@"enabled" error:&error] && error);
        WCK_CHECK(![store setObject:@"YES" forKey:@"enabled" error:&error]);
        WCK_CHECK(![store setObject:NSNull.null forKey:@"svgInclude" error:&error]);
        WCK_CHECK(![store setObject:@YES forKey:@"unknown" error:&error]);
        WCK_CHECK(![store setObject:@"#12345Z" forKey:@"svgTintLight" error:&error]);
        WCK_CHECK(![store setObject:@"" forKey:@"momentsFormat" error:&error]);
        WCK_CHECK(![store setObject:@"bad\n" forKey:@"svgInclude" error:&error]);
        NSString *longCSV = [@"a" stringByPaddingToLength:2049 withString:@"a" startingAtIndex:0];
        WCK_CHECK(![store setObject:longCSV forKey:@"svgExclude" error:&error]);
        NSString *longFormat = [@"y" stringByPaddingToLength:129 withString:@"y" startingAtIndex:0];
        WCK_CHECK(![store setObject:longFormat forKey:@"momentsFormat" error:&error]);
        WCK_CHECK([before isEqual:store.snapshot] && notices == 0);
        WCK_CHECK([store setObject:@YES forKey:@"enabled" error:&error] && !error);
        WCK_CHECK([store setObject:@"#aBcD01" forKey:@"svgTintDark" error:&error]);
        WCK_CHECK([[store stringForKey:@"svgTintDark" defaultValue:@""] isEqualToString:@"#ABCD01"]);
        NSMutableString *names = [@"icon_a,icon_b" mutableCopy];
        WCK_CHECK([store setObject:names forKey:@"svgInclude" error:&error]);
        [names appendString:@",later"];
        WCK_CHECK([[store stringForKey:@"svgInclude" defaultValue:@""] isEqualToString:@"icon_a,icon_b"]);
        WCK_CHECK(![store.snapshot isKindOfClass:NSMutableDictionary.class]);
        WCKSettings *reloaded = [[WCKSettings alloc] initWithFileURL:url];
        WCK_CHECK([reloaded.snapshot isEqual:store.snapshot] && notices == 3);
        dispatch_group_t readers = dispatch_group_create();
        __block BOOL backgroundRejected = NO;
        dispatch_group_async(readers, dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            NSError *backgroundError = nil;
            backgroundRejected = ![store setObject:@NO forKey:@"enabled" error:&backgroundError] && backgroundError;
            for (NSUInteger i = 0; i < 1000; i++) {
                NSDictionary *snapshot = store.snapshot;
                WCK_CHECK(snapshot.count == 11);
                WCK_CHECK([snapshot[@"enabled"] isKindOfClass:NSNumber.class]);
                (void)[store boolForKey:@"keyboardSwipe"];
                (void)[store stringForKey:@"svgInclude" defaultValue:@""];
            }
        });
        for (NSUInteger i = 0; i < 12; i++) WCK_CHECK([store setObject:@((BOOL)(i % 2 == 0)) forKey:@"keyboardSwipe" error:&error]);
        WCK_CHECK(dispatch_group_wait(readers, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC)) == 0);
        WCK_CHECK(backgroundRejected && notices == 15);
        WCKWritePlist(@{@"enabled": @42, @"keyboardSwipe": @YES, @"svgTintLight": @"bad",
                        @"svgTintDark": @[], @"momentsFormat": longFormat,
                        @"svgInclude": @"bad\n", @"foreignAccount": @"discard"}, url);
        reloaded = [[WCKSettings alloc] initWithFileURL:url];
        WCK_CHECK(![reloaded boolForKey:@"enabled"] && [reloaded boolForKey:@"keyboardSwipe"]);
        WCK_CHECK(reloaded.snapshot.count == 11 && !reloaded.snapshot[@"foreignAccount"]);
        WCK_CHECK([[reloaded stringForKey:@"svgTintLight" defaultValue:@""] isEqualToString:@"#07C160"]);
        WCK_CHECK([[reloaded stringForKey:@"svgInclude" defaultValue:@"wrong"] isEqualToString:@""]);
        WCK_CHECK([[reloaded stringForKey:@"momentsFormat" defaultValue:@""] isEqualToString:@"yyyy-MM-dd HH:mm:ss"]);
        WCK_CHECK([[NSMutableData dataWithLength:65537] writeToURL:url options:NSDataWritingAtomic error:NULL]);
        reloaded = [[WCKSettings alloc] initWithFileURL:url];
        WCK_CHECK(![reloaded boolForKey:@"keyboardSwipe"] && reloaded.snapshot.count == 11);
        WCK_CHECK([[@"not a plist" dataUsingEncoding:NSUTF8StringEncoding] writeToURL:url options:NSDataWritingAtomic error:NULL]);
        reloaded = [[WCKSettings alloc] initWithFileURL:url];
        WCK_CHECK(![reloaded boolForKey:@"enabled"] && reloaded.snapshot.count == 11);
    } @finally {
        [NSNotificationCenter.defaultCenter removeObserver:observer];
    }

    NSURL *blocked = [base URLByAppendingPathComponent:@"not-a-directory"];
    WCK_CHECK([[NSData data] writeToURL:blocked options:0 error:NULL]);
    WCKSettings *unwritable = [[WCKSettings alloc] initWithFileURL:[blocked URLByAppendingPathComponent:@"settings.plist"]];
    NSDictionary *before = unwritable.snapshot;
    __block BOOL notified = NO;
    observer = [NSNotificationCenter.defaultCenter addObserverForName:WCKSettingsDidChangeNotification
        object:unwritable queue:nil usingBlock:^(NSNotification *notification) { (void)notification; notified = YES; }];
    NSError *error = nil;
    WCK_CHECK(![unwritable setObject:@YES forKey:@"enabled" error:&error] && error);
    WCK_CHECK([before isEqual:unwritable.snapshot] && !notified);
    [NSNotificationCenter.defaultCenter removeObserver:observer];
}

static UITableViewCell *WCKCell(WCKSettingsViewController *vc, NSInteger section, NSInteger row) {
    return [vc tableView:vc.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:row inSection:section]];
}

static void WCKUIRegression(NSURL *base) {
    WCKSettings *store = [[WCKSettings alloc] initWithFileURL:[base URLByAppendingPathComponent:@"ui/settings.plist"]];
    WCKTestHost = YES;
    WCKTestStatuses = @{};
    WCKSettingsViewController *vc = [[WCKSettingsViewController alloc] initWithSettings:store];
    [vc loadViewIfNeeded];
    [vc viewWillAppear:NO];
    WCK_CHECK([vc.title isEqualToString:@"WeChatKit"]);
    WCK_CHECK([vc numberOfSectionsInTableView:vc.tableView] == 4);
    WCK_CHECK([vc tableView:vc.tableView numberOfRowsInSection:1] == 13);
    WCK_CHECK([vc tableView:vc.tableView numberOfRowsInSection:2] == 4);
    WCK_CHECK(WCKCell(vc, 1, 0).accessoryView == nil); // No fake toolbar switch.
    WCK_CHECK(!((UISwitch *)WCKCell(vc, 1, 1).accessoryView).enabled); // Missing status.
    WCKTestStatuses = @{@"keyboardSwipe": @"ready ", @"svgTint": @"not ready", @"toolbar": @"ready"};
    [vc viewWillAppear:NO];
    WCK_CHECK(!((UISwitch *)WCKCell(vc, 1, 1).accessoryView).enabled); // Exact equality.
    WCK_CHECK(WCKCell(vc, 1, 0).accessoryView == nil); // No schema for toolbar.
    WCK_CHECK(WCKCell(vc, 2, 0).accessoryType == UITableViewCellAccessoryNone);
    WCKTestStatuses = @{@"keyboardSwipe": @"ready", @"svgTint": @"ready"};
    [vc viewWillAppear:NO];
    UISwitch *toggle = (UISwitch *)WCKCell(vc, 1, 1).accessoryView;
    WCK_CHECK(toggle.enabled);
    toggle.on = YES;
    [toggle sendActionsForControlEvents:UIControlEventValueChanged];
    WCK_CHECK([store boolForKey:@"keyboardSwipe"]);
    WCK_CHECK(WCKCell(vc, 2, 0).accessoryType == UITableViewCellAccessoryDisclosureIndicator);
    WCKTestStatuses = @{};
    [vc viewWillAppear:NO];
    toggle = (UISwitch *)WCKCell(vc, 1, 1).accessoryView;
    WCK_CHECK(toggle.isOn && toggle.enabled); // Stored-on may always be disabled.
    toggle.on = NO;
    [toggle sendActionsForControlEvents:UIControlEventValueChanged];
    WCK_CHECK(![store boolForKey:@"keyboardSwipe"]);
    WCK_CHECK(!((UISwitch *)WCKCell(vc, 1, 1).accessoryView).enabled);
    WCKTestHost = NO;
    WCKTestStatuses = @{@"svgTint": @"ready"};
    WCK_CHECK([store setObject:@YES forKey:@"svgTint" error:NULL]);
    WCK_CHECK([store setObject:@YES forKey:@"enabled" error:NULL]);
    toggle = (UISwitch *)WCKCell(vc, 0, 0).accessoryView;
    WCK_CHECK(toggle.isOn && toggle.enabled);
    toggle.on = NO;
    [toggle sendActionsForControlEvents:UIControlEventValueChanged];
    WCK_CHECK(![store boolForKey:@"enabled"]);
    WCK_CHECK(!((UISwitch *)WCKCell(vc, 0, 0).accessoryView).enabled);
    toggle = (UISwitch *)WCKCell(vc, 1, 10).accessoryView;
    WCK_CHECK(toggle.isOn && toggle.enabled);
    toggle.on = NO;
    [toggle sendActionsForControlEvents:UIControlEventValueChanged];
    WCK_CHECK(![store boolForKey:@"svgTint"]);
    WCK_CHECK(!((UISwitch *)WCKCell(vc, 1, 10).accessoryView).enabled);
    WCK_CHECK(WCKCell(vc, 2, 0).accessoryType == UITableViewCellAccessoryNone);
}

void WCKRunSettingsRegression(void) {
    WCK_CHECK(NSThread.isMainThread);
    NSURL *base = [[NSURL fileURLWithPath:NSTemporaryDirectory() isDirectory:YES]
        URLByAppendingPathComponent:[@"WCKSettingsRegression-" stringByAppendingString:NSUUID.UUID.UUIDString] isDirectory:YES];
    @try {
        WCKStorageRegression(base);
        WCKUIRegression(base);
    } @finally {
        [NSFileManager.defaultManager removeItemAtURL:base error:NULL];
        WCKTestStatuses = nil;
    }
}
