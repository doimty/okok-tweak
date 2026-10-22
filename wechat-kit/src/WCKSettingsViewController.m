#import "WCKSettingsViewController.h"
#import "WCKSettings.h"
#import "WCKRuntime.h"
#import "WCKSVGColorViewController.h"
#import "WCKFeatureDetailViewController.h"
#import "WCKSVGPalette.h"

static NSArray<NSDictionary<NSString *, NSString *> *> *WCKModuleRows(void) {
    static NSArray *rows;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        rows = @[
            @{@"id": @"toolbar", @"title": @"工具栏位"},
            @{@"id": @"keyboardSwipe", @"title": @"聊天底部滑动展开键盘", @"key": @"keyboardSwipe"},
            @{@"id": @"friendRank", @"title": @"群内好友时间榜"},
            @{@"id": @"readAll", @"title": @"底栏微信长按一键已读", @"key": @"readAll"},
            @{@"id": @"cleanUI", @"title": @"界面净化"},
            @{@"id": @"corners", @"title": @"全局圆角"},
            @{@"id": @"momentsTime", @"title": @"朋友圈详细时间", @"key": @"momentsTime"},
            @{@"id": @"albumSheet", @"title": @"聊天页半屏相册", @"key": @"albumSheet"},
            @{@"id": @"noHotUpdate", @"title": @"禁止热更新"},
            @{@"id": @"topLabels", @"title": @"专属命名（顶部标签自定义）"},
            @{@"id": @"svgTint", @"title": @"Svg图标改色", @"key": @"svgTint"},
            @{@"id": @"repeatLabel", @"title": @"消息复读标签", @"note": @"标签含义待确认"},
            @{@"id": @"groupLabels", @"title": @"群聊标签", @"note": @"标签含义待确认"}
        ];
    });
    return rows;
}

@interface WCKSettingsViewController ()
@property (nonatomic, strong) WCKSettings *settings;
@property (nonatomic, copy) NSDictionary<NSString *, NSString *> *statuses;
@property (nonatomic) BOOL hostSupported;
@property (nonatomic, strong) UINavigationBar *standaloneBar;
- (instancetype)initWithSettings:(WCKSettings *)settings;
@end

@implementation WCKSettingsViewController

- (instancetype)init {
    return [self initWithSettings:WCKSettings.shared];
}

- (instancetype)initWithSettings:(WCKSettings *)settings {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if (self) {
        _settings = settings;
        _statuses = @{};
        self.title = @"WeChatKit";
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 72;
    self.edgesForExtendedLayout = UIRectEdgeNone;
    self.extendedLayoutIncludesOpaqueBars = NO;
    self.tableView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentAutomatic;
    // Per-item appearances: never alter the host navigation bar or other plugin pages.
    UINavigationBarAppearance *appearance = [UINavigationBarAppearance new];
    [appearance configureWithOpaqueBackground];
    appearance.backgroundColor = UIColor.systemGroupedBackgroundColor;
    self.navigationItem.standardAppearance = appearance;
    self.navigationItem.scrollEdgeAppearance = appearance;
    self.navigationItem.compactAppearance = appearance;
    self.navigationItem.compactScrollEdgeAppearance = appearance;
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(settingsChanged:)
        name:WCKSettingsDidChangeNotification object:self.settings];
    [self refreshState];
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    UINavigationController *nav = self.navigationController;
    BOOL modal = nav ? (nav.presentingViewController != nil && nav.viewControllers.firstObject == self) :
        self.presentingViewController != nil;
    self.navigationItem.rightBarButtonItem = modal ? [[UIBarButtonItem alloc] initWithTitle:@"Close"
        style:UIBarButtonItemStyleDone target:self action:@selector(close)] : nil;
    // Direct presentation has no navigation controller to render navigationItem.
    if (!nav) {
        if (!self.standaloneBar) {
            self.standaloneBar = [[UINavigationBar alloc] initWithFrame:
                CGRectMake(0, 0, self.tableView.bounds.size.width, 44)];
            self.standaloneBar.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        }
        self.standaloneBar.items = @[self.navigationItem];
        self.tableView.tableHeaderView = self.standaloneBar;
    } else {
        self.standaloneBar.items = @[];
        self.tableView.tableHeaderView = nil;
    }
    [self refreshState];
}

- (void)close {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)settingsChanged:(NSNotification *)notification {
    [self refreshState];
}

- (void)refreshState {
    self.hostSupported = WCKHostIsSupported();
    NSDictionary *reported = WCKRuntimeStatuses();
    self.statuses = [reported isKindOfClass:NSDictionary.class] ? [reported copy] : @{};
    [self.tableView reloadData];
}

- (BOOL)isReady:(NSString *)moduleID {
    id status = self.statuses[moduleID];
    return [status isKindOfClass:NSString.class] && [status isEqualToString:@"ready"];
}

// Re-read the live gates at action time; a stale enabled cell cannot bypass them.
- (BOOL)canEnableKey:(NSString *)key {
    if (!WCKHostIsSupported()) return NO;
    if ([key isEqualToString:@"enabled"]) return YES;
    id status = WCKRuntimeStatuses()[key];
    return [status isKindOfClass:NSString.class] && [status isEqualToString:@"ready"];
}

- (NSString *)statusForRow:(NSDictionary<NSString *, NSString *> *)row {
    NSString *status = self.statuses[row[@"id"]];
    NSString *text;
    if (!row[@"key"]) {
        text = @"待实现，暂无可用开关";
    } else if ([self isReady:row[@"id"]]) {
        BOOL master = [self.settings boolForKey:@"enabled"];
        BOOL feature = [self.settings boolForKey:row[@"key"]];
        text = !master ? @"总开关关闭，当前不生效" :
            (feature ? @"已开启，尚未完成效果验收" : @"已接入，当前关闭");
    } else if ([status isKindOfClass:NSString.class] && status.length) {
        text = [@"未就绪：" stringByAppendingString:status];
    } else {
        text = @"待实现，未注册";
    }
    if (!self.hostSupported) text = [text stringByAppendingString:@"；当前宿主不支持"];
    if (row[@"note"]) text = [text stringByAppendingFormat:@"；%@", row[@"note"]];
    if (row[@"key"] && [self.settings boolForKey:row[@"key"]] &&
        !(self.hostSupported && [self isReady:row[@"id"]])) {
        text = [text stringByAppendingString:@"；已存开启，仅可关闭"];
    }
    return text;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 2; }

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return section == 0 ? 1 : WCKModuleRows().count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return @[@"总开关", @"功能状态（13 项）"][section];
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    return @[
        @"默认全部关闭。总开关关闭时所有功能均不生效。不保存账号或聊天内容。",
        @"点开任意已实现项目可进入它的设置页；未完成项保留说明，不提供入口。"
    ][section];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"WCKSetting"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"WCKSetting"];
    cell.textLabel.numberOfLines = 0;
    cell.detailTextLabel.numberOfLines = 0;
    cell.textLabel.enabled = YES;
    cell.detailTextLabel.enabled = YES;
    cell.accessoryView = nil;
    cell.accessibilityIdentifier = nil;
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    if (path.section == 0) {
        BOOL stored = [self.settings boolForKey:@"enabled"];
        cell.textLabel.text = @"启用 WeChatKit";
        cell.detailTextLabel.text = self.hostSupported ?
            @"仅已就绪模块可生效；各项仍需分别开启。" : @"当前宿主不支持；已存总开关仍可关闭。";
        UISwitch *toggle = [[UISwitch alloc] init];
        toggle.on = stored;
        toggle.enabled = self.hostSupported || stored;
        toggle.tag = 0;
        toggle.accessibilityIdentifier = @"wck.switch.enabled";
        toggle.accessibilityLabel = cell.textLabel.text;
        toggle.accessibilityHint = cell.detailTextLabel.text;
        [toggle addTarget:self action:@selector(toggleChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = toggle;
    } else if (path.section == 1) {
        // Each implemented feature is an entry: its switch and values live on
        // the second-level page, never twice on this list.
        NSDictionary<NSString *, NSString *> *row = WCKModuleRows()[path.row];
        cell.textLabel.text = row[@"title"];
        cell.detailTextLabel.text = [self statusForRow:row];
        if (row[@"key"]) {
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            cell.selectionStyle = UITableViewCellSelectionStyleDefault;
            cell.accessibilityIdentifier = [@"wck.feature." stringByAppendingString:row[@"id"]];
        }
    }
    return cell;
}

- (void)toggleChanged:(UISwitch *)sender {
    if (sender.tag < 0 || sender.tag > (NSInteger)WCKModuleRows().count) return;
    NSString *key = sender.tag == 0 ? @"enabled" : WCKModuleRows()[sender.tag - 1][@"key"];
    if (!key) return;
    BOOL canEnable = [self canEnableKey:key];
    if (sender.isOn && !canEnable) {
        [self refreshState];
        [self showError:[NSError errorWithDomain:@"com.doimty.wechatkit.settings" code:5
            userInfo:@{NSLocalizedDescriptionKey: @"当前宿主不支持或功能尚未就绪，不能开启。"}]];
        return;
    }
    NSError *error = nil;
    if (![self.settings setObject:@(sender.isOn) forKey:key error:&error]) {
        [self refreshState];
        [self showError:error];
        return;
    }
    if (sender.isOn && ![key isEqualToString:@"enabled"] &&
        ![self.settings boolForKey:@"enabled"]) [self showMasterOffNotice];
}

- (void)showMasterOffNotice {
    if (self.presentedViewController) return;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"总开关仍关闭"
        message:@"子开关已保存，但功能不会执行。是否同时开启 WeChatKit 总开关？"
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"保持关闭" style:UIAlertActionStyleCancel handler:nil]];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"同时开启总开关" style:UIAlertActionStyleDefault
        handler:^(UIAlertAction *action) {
            (void)action;
            typeof(self) self = weakSelf;
            if (!self || ![self canEnableKey:@"enabled"]) return;
            NSError *error = nil;
            if (![self.settings setObject:@YES forKey:@"enabled" error:&error]) [self showError:error];
        }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (NSString *)detailForFeatureID:(NSString *)featureID {
    if ([featureID isEqualToString:@"keyboardSwipe"])
        return @"在聊天消息列表滑到最底部后继续上滑，即可展开键盘。只在这个位置生效，不影响列表正常浏览。";
    if ([featureID isEqualToString:@"readAll"])
        return @"长按底部第一个标签，把当前账号的未读会话标为已读。分批处理，逐条回读确认，可中途取消。";
    if ([featureID isEqualToString:@"momentsTime"])
        return @"调整朋友圈列表时间的显示格式，不影响消息与聊天记录。";
    if ([featureID isEqualToString:@"albumSheet"])
        return @"聊天页半屏相册依赖微信 8.0.76 及以上版本提供的实验开关；低版本不会启用，也不会强开。";
    return @"";
}

- (UIViewController *)detailPageForFeature:(NSDictionary<NSString *, NSString *> *)row {
    NSString *featureID = row[@"id"];
    if ([featureID isEqualToString:@"svgTint"])
        return [[WCKSVGColorViewController alloc] initWithSettings:self.settings];
    NSArray<NSDictionary<NSString *, NSString *> *> *extra = nil;
    if ([featureID isEqualToString:@"momentsTime"]) {
        extra = @[@{@"key": @"momentsFormat", @"title": @"时间格式",
                    @"help": @"使用日期格式，1–128 字符。例如 yyyy-MM-dd HH:mm:ss。"}];
    }
    return [[WCKFeatureDetailViewController alloc] initWithSettings:self.settings
        featureID:featureID settingsKey:row[@"key"] title:row[@"title"]
        detail:[self detailForFeatureID:featureID] extraRows:extra];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path {
    [tableView deselectRowAtIndexPath:path animated:YES];
    if (path.section != 1) return;
    NSDictionary<NSString *, NSString *> *row = WCKModuleRows()[path.row];
    if (!row[@"key"] || !self.navigationController) return;
    [self.navigationController pushViewController:[self detailPageForFeature:row] animated:YES];
}

- (void)showError:(NSError *)error {
    // Text-entry alerts auto-dismiss. Wait for that transition rather than stacking alerts.
    UIViewController *presented = self.presentedViewController;
    if (presented) {
        __weak typeof(self) weakSelf = self;
        if (presented.isBeingDismissed && presented.transitionCoordinator) {
            [presented.transitionCoordinator animateAlongsideTransition:nil completion:^(id<UIViewControllerTransitionCoordinatorContext> context) {
                (void)context;
                [weakSelf showError:error];
            }];
        } else {
            [presented dismissViewControllerAnimated:YES completion:^{ [weakSelf showError:error]; }];
        }
        return;
    }
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"未能保存"
        message:error.localizedDescription ?: @"设置未变，请重试。" preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
