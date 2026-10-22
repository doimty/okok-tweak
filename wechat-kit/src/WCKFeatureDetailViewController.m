#import "WCKFeatureDetailViewController.h"
#import "WCKRuntime.h"

@interface WCKFeatureDetailViewController ()
@property (nonatomic, strong) WCKSettings *settings;
@property (nonatomic, copy) NSString *featureID;
@property (nonatomic, copy) NSString *settingsKey;
@property (nonatomic, copy) NSString *detailText;
@property (nonatomic, copy) NSArray<NSDictionary<NSString *, NSString *> *> *extraRows;
@property (nonatomic, strong) UISwitch *toggle;
@end

@implementation WCKFeatureDetailViewController

- (instancetype)initWithSettings:(WCKSettings *)settings
                       featureID:(NSString *)featureID
                      settingsKey:(NSString *)key
                           title:(NSString *)title
                          detail:(NSString *)detail
                     extraRows:(NSArray<NSDictionary<NSString *, NSString *> *> *)extraRows {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if (self) {
        _settings = settings;
        _featureID = [featureID copy];
        _settingsKey = [key copy];
        _detailText = [detail copy];
        _extraRows = [extraRows copy];
        self.title = title;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 52;
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
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)settingsChanged:(NSNotification *)notification {
    (void)notification;
    [self refreshToggle];
    [self.tableView reloadData];
}

- (BOOL)hostSupportsFeature {
    id status = WCKRuntimeStatuses()[self.featureID];
    return WCKHostIsSupported() && [status isKindOfClass:NSString.class] && [status isEqualToString:@"ready"];
}

- (void)refreshToggle {
    BOOL stored = [self.settings boolForKey:self.settingsKey];
    self.toggle.on = stored;
    self.toggle.enabled = [self hostSupportsFeature] || stored;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self refreshToggle];
    [self.tableView reloadData];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return self.extraRows.count ? 3 : 2;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) return 1;
    if (section == 1) return 1;
    return self.extraRows.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == 0) return @"开关";
    if (section == 1) return @"说明";
    return @"设置";
}

- (NSDictionary<NSString *, NSString *> *)extraRowAtRow:(NSInteger)row {
    return row >= 0 && row < (NSInteger)self.extraRows.count ? self.extraRows[(NSUInteger)row] : nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"WCKFeatureDetail"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1
                                              reuseIdentifier:@"WCKFeatureDetail"];
    cell.textLabel.numberOfLines = 0;
    cell.detailTextLabel.numberOfLines = 0;
    cell.accessoryView = nil;
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    cell.textLabel.enabled = YES;
    cell.detailTextLabel.enabled = YES;

    if (path.section == 0) {
        cell.textLabel.text = @"启用";
        BOOL ready = [self hostSupportsFeature];
        BOOL stored = [self.settings boolForKey:self.settingsKey];
        cell.detailTextLabel.text = ready ? (stored ? @"已开启" : @"已关闭")
                                          : (stored ? @"宿主未就绪；已存开启仅可关闭" : @"宿主未就绪，暂不可开启");
        UISwitch *toggle = [UISwitch new];
        toggle.on = stored;
        toggle.enabled = ready || stored;
        toggle.accessibilityIdentifier = [@"wck.feature.switch." stringByAppendingString:self.settingsKey];
        [toggle addTarget:self action:@selector(toggleChanged:) forControlEvents:UIControlEventValueChanged];
        self.toggle = toggle;
        cell.accessoryView = toggle;
    } else if (path.section == 1) {
        cell.textLabel.text = self.detailText;
        cell.textLabel.textColor = UIColor.secondaryLabelColor;
        cell.textLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    } else {
        NSDictionary<NSString *, NSString *> *row = [self extraRowAtRow:path.row];
        NSString *value = [self.settings stringForKey:row[@"key"] defaultValue:@""];
        cell.textLabel.text = row[@"title"];
        cell.textLabel.textColor = UIColor.labelColor;
        cell.textLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
        cell.detailTextLabel.text = value.length ? value : @"空";
        BOOL editable = [self hostSupportsFeature];
        cell.textLabel.enabled = editable;
        cell.accessoryType = editable ? UITableViewCellAccessoryDisclosureIndicator : UITableViewCellAccessoryNone;
        cell.selectionStyle = editable ? UITableViewCellSelectionStyleDefault : UITableViewCellSelectionStyleNone;
    }
    return cell;
}

- (void)toggleChanged:(UISwitch *)sender {
    if (sender.isOn && ![self hostSupportsFeature]) {
        [self refreshToggle];
        [self.tableView reloadData];
        return;
    }
    NSError *error = nil;
    if (![self.settings setObject:@(sender.isOn) forKey:self.settingsKey error:&error]) {
        [self refreshToggle];
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"未能保存"
            message:error.localizedDescription ?: @"设置未变，请重试。"
            preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    [self.tableView reloadData];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path {
    [tableView deselectRowAtIndexPath:path animated:YES];
    if (path.section != 2) return;
    NSDictionary<NSString *, NSString *> *row = [self extraRowAtRow:path.row];
    if (!row || ![self hostSupportsFeature]) return;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:row[@"title"]
        message:row[@"help"] preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.text = [self.settings stringForKey:row[@"key"] defaultValue:@""];
        field.autocorrectionType = UITextAutocorrectionTypeNo;
        field.spellCheckingType = UITextSpellCheckingTypeNo;
        field.autocapitalizationType = UITextAutocapitalizationTypeNone;
        field.clearButtonMode = UITextFieldViewModeWhileEditing;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    __weak typeof(self) weakSelf = self;
    __weak UIAlertController *weakAlert = alert;
    [alert addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault
        handler:^(UIAlertAction *action) {
            (void)action;
            typeof(self) self = weakSelf;
            if (!self) return;
            NSError *error = nil;
            if (![self.settings setObject:weakAlert.textFields.firstObject.text ?: @""
                                    forKey:row[@"key"] error:&error]) {
                UIAlertController *failure = [UIAlertController alertControllerWithTitle:@"未能保存"
                    message:error.localizedDescription ?: @"设置未变，请重试。"
                    preferredStyle:UIAlertControllerStyleAlert];
                [failure addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
                [self presentViewController:failure animated:YES completion:nil];
            }
            [self.tableView reloadData];
        }]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
