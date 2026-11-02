#import "WCKFeatureDetailViewController.h"
#import "WCKRuntime.h"

@interface WCKFeatureDetailViewController ()
@property (nonatomic, strong) WCKSettings *settings;
@property (nonatomic, copy) NSString *featureID;
@property (nonatomic, copy) NSString *settingsKey;
@property (nonatomic, copy) NSString *detailText;
@property (nonatomic, copy) NSArray<NSDictionary<NSString *, id> *> *extraRows;
@property (nonatomic, strong) UISwitch *toggle;
@property (nonatomic, strong) UIView *heroView;
@property (nonatomic, strong) UILabel *heroSubtitleLabel;
@end

// Bare accent glyph, no tile: the reference home language, kept on detail pages
// so both levels still share one look.
static UIImage *WCKDetailTileImage(NSString *symbolName, UIColor *tint, NSString *fallback, CGFloat size) {
    tint = tint ?: UIColor.systemGrayColor;
    fallback = fallback.length ? fallback : @"W";
    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat defaultFormat];
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(size, size) format:format];
    return [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        (void)context;
        UIImage *symbol = [UIImage systemImageNamed:symbolName];
        if (symbol) {
            UIImage *tinted = [symbol imageWithTintColor:tint];
            CGFloat box = size * 0.64;
            [tinted drawInRect:CGRectMake((size - box) / 2.0, (size - box) / 2.0, box, box)];
        } else {
            NSString *ch = [fallback substringToIndex:1];
            NSDictionary *attrs = @{ NSFontAttributeName: [UIFont systemFontOfSize:size * 0.42 weight:UIFontWeightSemibold], NSForegroundColorAttributeName: tint };
            CGSize textSize = [ch sizeWithAttributes:attrs];
            [ch drawAtPoint:CGPointMake((size - textSize.width) / 2.0, (size - textSize.height) / 2.0) withAttributes:attrs];
        }
    }];
}

@interface WCKDetailHeroView : UIView
@property (nonatomic, strong) UIImageView *tileView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;
- (instancetype)initWithIcon:(NSString *)iconName tint:(UIColor *)tint title:(NSString *)title fallback:(NSString *)fallback;
@end

@implementation WCKDetailHeroView
- (instancetype)initWithIcon:(NSString *)iconName tint:(UIColor *)tint title:(NSString *)title fallback:(NSString *)fallback {
    self = [super initWithFrame:CGRectMake(0, 0, 0, 96)];
    if (self) {
        _tileView = [[UIImageView alloc] initWithImage:WCKDetailTileImage(iconName, tint, fallback, 56)];
        [self addSubview:_tileView];
        _titleLabel = [UILabel new];
        _titleLabel.font = [UIFont systemFontOfSize:18 weight:UIFontWeightSemibold];
        _titleLabel.textColor = UIColor.labelColor;
        _titleLabel.text = title;
        [self addSubview:_titleLabel];
        _subtitleLabel = [UILabel new];
        _subtitleLabel.font = [UIFont systemFontOfSize:13];
        _subtitleLabel.textColor = UIColor.secondaryLabelColor;
        [self addSubview:_subtitleLabel];
    }
    return self;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = self.bounds.size.width;
    self.tileView.frame = CGRectMake(20, 20, 56, 56);
    CGFloat textX = 92, textWidth = MAX(0, width - textX - 20);
    self.titleLabel.frame = CGRectMake(textX, 24, textWidth, 24);
    self.subtitleLabel.frame = CGRectMake(textX, 52, textWidth, 20);
}
@end

@implementation WCKFeatureDetailViewController

- (instancetype)initWithSettings:(WCKSettings *)settings
                       featureID:(NSString *)featureID
                      settingsKey:(NSString *)key
                           title:(NSString *)title
                          detail:(NSString *)detail
                     extraRows:(NSArray<NSDictionary<NSString *, id> *> *)extraRows {
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
    // Same card language as the home page: hairlines between rows.
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

- (BOOL)canEditFeature {
    return self.settings.snapshot[self.settingsKey] != nil;
}

- (BOOL)featureReady {
    id status = WCKRuntimeStatuses()[self.featureID];
    return [status isKindOfClass:NSString.class] && [status isEqualToString:@"ready"];
}

- (void)refreshToggle {
    BOOL stored = [self.settings boolForKey:self.settingsKey];
    self.toggle.on = stored;
    self.toggle.enabled = [self canEditFeature];
    if (self.heroSubtitleLabel) {
        BOOL ready = [self featureReady];
        self.heroSubtitleLabel.text = ready ? (stored ? @"已开启" : @"已关闭")
            : (stored ? @"已保存开启，状态未确认" : @"Hook 状态未确认");
    }
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    if (!self.heroView && self.heroIconName.length) {
        WCKDetailHeroView *hero = [[WCKDetailHeroView alloc] initWithIcon:self.heroIconName
            tint:self.heroTintColor title:self.title fallback:self.title];
        hero.frame = CGRectMake(0, 0, self.tableView.bounds.size.width, 96);
        hero.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        self.heroView = hero;
        self.heroSubtitleLabel = hero.subtitleLabel;
        self.tableView.tableHeaderView = hero;
    }
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

- (NSDictionary<NSString *, id> *)extraRowAtRow:(NSInteger)row {
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
        cell.textLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
        cell.textLabel.text = @"启用";
        BOOL ready = [self featureReady];
        BOOL stored = [self.settings boolForKey:self.settingsKey];
        cell.detailTextLabel.text = ready ? (stored ? @"已开启" : @"已关闭")
            : (stored ? @"已保存开启；当前 Hook 状态未就绪，仍会尝试运行"
                      : @"Hook 状态未就绪；仍可尝试开启");
        UISwitch *toggle = [UISwitch new];
        toggle.on = stored;
        toggle.enabled = [self canEditFeature];
        toggle.accessibilityIdentifier = [@"wck.feature.switch." stringByAppendingString:self.settingsKey];
        [toggle addTarget:self action:@selector(toggleChanged:) forControlEvents:UIControlEventValueChanged];
        self.toggle = toggle;
        cell.accessoryView = toggle;
    } else if (path.section == 1) {
        cell.textLabel.text = self.detailText;
        cell.textLabel.textColor = UIColor.secondaryLabelColor;
        cell.textLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    } else {
        NSDictionary<NSString *, id> *row = [self extraRowAtRow:path.row];
        NSString *type = row[@"type"];
        cell.textLabel.text = row[@"title"];
        cell.textLabel.textColor = UIColor.labelColor;
        cell.textLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
        cell.detailTextLabel.font = [UIFont systemFontOfSize:15];
        cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
        BOOL editable = YES;
        cell.textLabel.enabled = YES;
        if ([type isEqualToString:@"header"]) {
            cell.textLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
            cell.textLabel.textColor = UIColor.secondaryLabelColor;
            cell.detailTextLabel.text = row[@"help"];
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
        } else if ([type isEqualToString:@"slider"]) {
            double minimum = [row[@"min"] doubleValue], maximum = [row[@"max"] doubleValue];
            id stored = self.settings.snapshot[row[@"key"]];
            double value = [stored isKindOfClass:NSNumber.class] ? [stored doubleValue] : minimum;
            UISlider *slider = [UISlider new];
            slider.minimumValue = (float)minimum;
            slider.maximumValue = (float)maximum;
            slider.value = (float)MIN(maximum, MAX(minimum, value));
            slider.enabled = editable;
            slider.tag = path.row;   // several sliders share this page
            slider.accessibilityIdentifier = [@"wck.feature.slider." stringByAppendingString:row[@"key"]];
            [slider addTarget:self action:@selector(sliderChanged:) forControlEvents:UIControlEventValueChanged];
            [slider addTarget:self action:@selector(sliderCommitted:) forControlEvents:
                UIControlEventTouchUpInside | UIControlEventTouchUpOutside];
            [slider.widthAnchor constraintGreaterThanOrEqualToConstant:140].active = YES;
            cell.accessoryView = slider;
            cell.detailTextLabel.text = [NSString stringWithFormat:@"%.0f", slider.value];
        } else if ([type isEqualToString:@"switch"]) {
            UISwitch *toggle = [UISwitch new];
            toggle.on = [self.settings boolForKey:row[@"key"]];
            toggle.enabled = editable;
            toggle.tag = path.row;
            toggle.accessibilityIdentifier = [@"wck.feature.option." stringByAppendingString:row[@"key"]];
            [toggle addTarget:self action:@selector(optionSwitchChanged:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = toggle;
        } else if ([type isEqualToString:@"choice"]) {
            id raw = self.settings.snapshot[row[@"key"]];
            NSString *value;
            if ([raw isKindOfClass:NSNumber.class] &&
                [row[@"key"] isEqualToString:@"decorationScale"])
                value = [NSString stringWithFormat:@"%g", [raw doubleValue]];
            else value = [raw isKindOfClass:NSNumber.class] ?
                [NSString stringWithFormat:@"%ld", (long)[raw integerValue]] :
                ([raw isKindOfClass:NSString.class] ? raw : @"");
            NSArray<NSDictionary<NSString *, NSString *> *> *items = row[@"items"];
            NSString *shown = value;
            for (NSDictionary<NSString *, NSString *> *item in items)
                if ([item[@"value"] isEqualToString:value]) { shown = item[@"title"]; break; }
            cell.detailTextLabel.text = shown.length ? shown : @"未设置";
            cell.accessoryType = editable ? UITableViewCellAccessoryDisclosureIndicator
                                          : UITableViewCellAccessoryNone;
            cell.selectionStyle = editable ? UITableViewCellSelectionStyleDefault
                                           : UITableViewCellSelectionStyleNone;
        } else {
            NSString *value = [self.settings stringForKey:row[@"key"] defaultValue:@""];
            cell.detailTextLabel.text = value.length ? value : @"空";
            cell.accessoryType = editable ? UITableViewCellAccessoryDisclosureIndicator
                                          : UITableViewCellAccessoryNone;
            cell.selectionStyle = editable ? UITableViewCellSelectionStyleDefault
                                           : UITableViewCellSelectionStyleNone;
        }
    }
    return cell;
}

- (void)toggleChanged:(UISwitch *)sender {
    if (sender.isOn && ![self canEditFeature]) {
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

- (void)optionSwitchChanged:(UISwitch *)sender {
    NSDictionary<NSString *, id> *row = [self extraRowAtRow:sender.tag];
    if (!row) return;
    NSError *error = nil;
    if (![self.settings setObject:@(sender.isOn) forKey:row[@"key"] error:&error]) {
        [self.tableView reloadData];
        return;
    }
}

- (void)sliderChanged:(UISlider *)sender {
    UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:
        [NSIndexPath indexPathForRow:sender.tag inSection:2]];
    if (cell) cell.detailTextLabel.text = [NSString stringWithFormat:@"%.0f", sender.value];
}

- (void)sliderCommitted:(UISlider *)sender {
    NSDictionary<NSString *, id> *row = [self extraRowAtRow:sender.tag];
    if (!row) return;
    NSError *error = nil;
    if (![self.settings setObject:@(round(sender.value)) forKey:row[@"key"] error:&error]) {
        [self.tableView reloadData];
        return;
    }
    [self.tableView reloadData];
}

- (void)presentChoiceForRow:(NSDictionary<NSString *, id> *)row {
    NSArray<NSDictionary<NSString *, NSString *> *> *items = row[@"items"];
    if (!items.count) return;
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:row[@"title"]
        message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    for (NSDictionary<NSString *, NSString *> *item in items) {
        __weak typeof(self) weakSelf = self;
        [sheet addAction:[UIAlertAction actionWithTitle:item[@"title"]
            style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                (void)action;
                typeof(self) self = weakSelf;
                if (!self) return;
                NSError *error = nil;
                id value = item[@"value"];
                if ([row[@"key"] isEqualToString:@"globalCornerStrokeStyle"])
                    value = @([value integerValue]);
                else if ([row[@"key"] isEqualToString:@"decorationScale"])
                    value = @([value doubleValue]);
                [self.settings setObject:value forKey:row[@"key"] error:&error];
                [self.tableView reloadData];
            }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.sourceView = self.view;
    sheet.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(self.view.bounds),
        CGRectGetMidY(self.view.bounds), 1, 1);
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path {
    [tableView deselectRowAtIndexPath:path animated:YES];
    if (path.section != 2) return;
    NSDictionary<NSString *, id> *row = [self extraRowAtRow:path.row];
    if (!row || ![self canEditFeature]) return;
    if ([row[@"type"] isEqualToString:@"choice"]) {
        [self presentChoiceForRow:row];
        return;
    }
    if ([row[@"type"] isEqualToString:@"header"] ||
        [row[@"type"] isEqualToString:@"slider"] ||
        [row[@"type"] isEqualToString:@"switch"]) return;
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
