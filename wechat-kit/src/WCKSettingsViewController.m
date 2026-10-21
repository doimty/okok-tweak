#import "WCKSettingsViewController.h"
#import "WCKSettings.h"
#import "WCKRuntime.h"

static NSArray<NSDictionary<NSString *, NSString *> *> *WCKModuleRows(void) {
    static NSArray *rows;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        rows = @[
            @{@"id": @"toolbar", @"title": @"工具栏位"},
            @{@"id": @"keyboardSwipe", @"title": @"上滑展开键盘", @"key": @"keyboardSwipe"},
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

static NSDictionary<NSString *, NSString *> *WCKTextRow(NSIndexPath *path) {
    static NSArray *rows;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        rows = @[
            @{@"key": @"svgTintLight", @"module": @"svgTint", @"title": @"浅色图标颜色", @"help": @"请输入 #RRGGBB，例如 #07C160。"},
            @{@"key": @"svgTintDark", @"module": @"svgTint", @"title": @"深色图标颜色", @"help": @"请输入 #RRGGBB，例如 #07C160。"},
            @{@"key": @"svgInclude", @"module": @"svgTint", @"title": @"包含图标名单", @"help": @"逗号分隔，最多 2048 字符。留空表示没有改色，不是全局改色。"},
            @{@"key": @"svgExclude", @"module": @"svgTint", @"title": @"排除图标名单", @"help": @"逗号分隔，最多 2048 字符。排除名单优先。"},
            @{@"key": @"momentsFormat", @"module": @"momentsTime", @"title": @"时间格式", @"help": @"使用日期格式，1–128 字符。例如 yyyy-MM-dd HH:mm:ss。"}
        ];
    });
    return rows[path.section == 2 ? path.row : 4];
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
        text = @"已就绪，尚未真机验证";
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

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 4; }

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return section == 0 ? 1 : (section == 1 ? WCKModuleRows().count : (section == 2 ? 4 : 1));
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return @[@"总开关", @"功能状态（13 项）", @"SVG 图标改色", @"朋友圈时间格式"][section];
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    return @[
        @"默认全部关闭。总开关关闭时所有功能均不生效。不保存账号或聊天内容。",
        @"仅宿主支持且状态已就绪的项目可开启；未完成项保留说明。已存开关仍可关闭。",
        @"功能已就绪且宿主支持时可编辑。名单用逗号分隔；包含名单为空时不改任何图标，排除优先。",
        @"功能已就绪且宿主支持时可编辑。默认 yyyy-MM-dd HH:mm:ss。"
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
    if (path.section < 2) {
        NSDictionary *row = path.section == 1 ? WCKModuleRows()[path.row] : nil;
        NSString *key = path.section == 0 ? @"enabled" : row[@"key"];
        cell.textLabel.text = path.section == 0 ? @"启用 WeChatKit" : row[@"title"];
        cell.detailTextLabel.text = path.section == 0 ?
            (self.hostSupported ? @"仅已就绪模块可生效；各项仍需分别开启。" : @"当前宿主不支持；已存总开关仍可关闭。") :
            [self statusForRow:row];
        if (key) {
            BOOL stored = [self.settings boolForKey:key];
            BOOL canEnable = self.hostSupported && (path.section == 0 || [self isReady:row[@"id"]]);
            UISwitch *toggle = [[UISwitch alloc] init];
            toggle.on = stored;
            toggle.enabled = canEnable || stored;
            toggle.tag = path.section == 0 ? 0 : path.row + 1;
            toggle.accessibilityIdentifier = [@"wck.switch." stringByAppendingString:key];
            toggle.accessibilityLabel = cell.textLabel.text;
            toggle.accessibilityHint = cell.detailTextLabel.text;
            [toggle addTarget:self action:@selector(toggleChanged:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = toggle;
        }
    } else {
        NSDictionary *row = WCKTextRow(path);
        NSString *value = [self.settings stringForKey:row[@"key"] defaultValue:@""];
        BOOL editable = self.hostSupported && [self isReady:row[@"module"]];
        cell.textLabel.text = row[@"title"];
        cell.detailTextLabel.text = value.length ? value :
            ([row[@"key"] isEqualToString:@"svgInclude"] ? @"空（不改任何图标）" : @"空");
        cell.textLabel.enabled = editable;
        cell.detailTextLabel.enabled = editable;
        cell.accessoryType = editable ? UITableViewCellAccessoryDisclosureIndicator : UITableViewCellAccessoryNone;
        cell.selectionStyle = editable ? UITableViewCellSelectionStyleDefault : UITableViewCellSelectionStyleNone;
        cell.accessibilityIdentifier = [@"wck.text." stringByAppendingString:row[@"key"]];
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
    }
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path {
    [tableView deselectRowAtIndexPath:path animated:YES];
    if (path.section < 2) return;
    NSDictionary *row = WCKTextRow(path);
    if (![self canEnableKey:row[@"module"]]) {
        [self refreshState];
        return;
    }
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:row[@"title"]
        message:row[@"help"] preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.text = [self.settings stringForKey:row[@"key"] defaultValue:@""];
        field.autocorrectionType = UITextAutocorrectionTypeNo;
        field.spellCheckingType = UITextSpellCheckingTypeNo;
        field.autocapitalizationType = UITextAutocapitalizationTypeNone;
        field.clearButtonMode = UITextFieldViewModeWhileEditing;
        field.accessibilityIdentifier = [@"wck.input." stringByAppendingString:row[@"key"]];
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    __weak typeof(self) weakSelf = self;
    __weak UIAlertController *weakAlert = alert;
    [alert addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        (void)action;
        typeof(self) self = weakSelf;
        if (!self) return;
        NSError *error = nil;
        if (![self canEnableKey:row[@"module"]]) {
            error = [NSError errorWithDomain:@"com.doimty.wechatkit.settings" code:5
                userInfo:@{NSLocalizedDescriptionKey: @"当前宿主不支持或功能尚未就绪，不能编辑。"}];
        } else {
            [self.settings setObject:weakAlert.textFields.firstObject.text ?: @"" forKey:row[@"key"] error:&error];
        }
        if (error) [self showError:error];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
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
