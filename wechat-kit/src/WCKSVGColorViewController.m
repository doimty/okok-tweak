#import "WCKSVGColorViewController.h"
#import "WCKSVGPalette.h"

// Keys mirror the reference plug-in's stored preference names so an existing
// configuration style stays recognisable. Values are our own implementation.
static NSString *const kFixedFlag = @"svgUseFixedColor";
static NSString *const kLight = @"svgTintLight";
static NSString *const kDark = @"svgTintDark";
static NSString *const kPalette = @"svgPaletteHexes";
static NSString *const kAlpha = @"svgRandomAlpha";
static NSString *const kInclude = @"svgInclude";
static NSString *const kExclude = @"svgExclude";

static NSString *WCKHexFromColor(UIColor *color) {
    if (![color isKindOfClass:UIColor.class]) return nil;
    CGFloat r = 0, g = 0, b = 0, a = 0;
    if (![color getRed:&r green:&g blue:&b alpha:&a]) {
        // Convert wide-gamut colours into sRGB before reading components.
        CGFloat white = 0;
        if (![color getWhite:&white alpha:&a]) return nil;
        r = g = b = white;
    }
    if (!isfinite(r) || !isfinite(g) || !isfinite(b)) return nil;
    unsigned ri = (unsigned)lround(MIN(1.0, MAX(0.0, r)) * 255.0);
    unsigned gi = (unsigned)lround(MIN(1.0, MAX(0.0, g)) * 255.0);
    unsigned bi = (unsigned)lround(MIN(1.0, MAX(0.0, b)) * 255.0);
    return [NSString stringWithFormat:@"#%02X%02X%02X", ri, gi, bi];
}

static UIColor *WCKColorFromHex(NSString *hex, UIColor *fallback) {
    uint32_t rgb = 0;
    if (!WCKHexToRGB(hex, &rgb)) return fallback;
    return [UIColor colorWithRed:((rgb >> 16) & 255) / 255.0 green:((rgb >> 8) & 255) / 255.0
        blue:(rgb & 255) / 255.0 alpha:1];
}

@interface WCKSVGPaletteEditorViewController : UITableViewController <UIColorPickerViewControllerDelegate>
@property (nonatomic, strong) WCKSettings *settings;
@property (nonatomic, copy) NSArray<NSString *> *colors;
@property (nonatomic, copy) void (^onChange)(NSArray<NSString *> *colors);
@property (nonatomic) BOOL pickingNew;
@property (nonatomic) NSUInteger editingIndex;
@end

@interface WCKSVGColorViewController () <UIColorPickerViewControllerDelegate>
@property (nonatomic, strong) WCKSettings *settings;
@property (nonatomic, copy) NSString *pickKey;   // light / dark
@property (nonatomic, strong) UISlider *alphaSlider;
@end

@implementation WCKSVGColorViewController

- (instancetype)initWithSettings:(WCKSettings *)settings {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if (self) {
        _settings = settings;
        self.title = @"Svg 图标改色";
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
    [self reload];
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)settingsChanged:(NSNotification *)notification {
    (void)notification;
    [self reload];
}

- (void)reload {
    [self.tableView reloadData];
}

- (BOOL)usesFixed {
    id flag = self.settings.snapshot[kFixedFlag];
    return ![flag isKindOfClass:NSNumber.class] || [flag boolValue];
}

- (NSArray<NSString *> *)palette {
    id stored = self.settings.snapshot[kPalette];
    NSMutableArray<NSString *> *list = [NSMutableArray array];
    if ([stored isKindOfClass:NSArray.class]) {
        for (id entry in (NSArray *)stored) {
            NSString *hex = WCKNormalizeHex([entry isKindOfClass:NSString.class] ? entry : nil);
            if (hex && ![list containsObject:hex] && list.count < 32) [list addObject:hex];
        }
    }
    return list.count ? list : WCKDefaultSVGPalette();
}

- (BOOL)save:(id)value forKey:(NSString *)key {
    NSError *error = nil;
    if (![self.settings setObject:value forKey:key error:&error]) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"未能保存"
            message:error.localizedDescription ?: @"设置未变，请重试。"
            preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return NO;
    }
    return YES;
}

#pragma mark - Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 4; }

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) return 1;
    if (section == 1) return [self usesFixed] ? 2 : 0;
    if (section == 2) return [self usesFixed] ? 0 : 3;   // palette, alpha, reset
    return 2;                                            // include, exclude
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return @[@"配色方式", @"固定颜色", @"随机色板", @"图标名单"][section];
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 0) return @"固定颜色：浅色与深色各一色。随机色板：按图标名固定取色，同一图标不会每次变化。";
    if (section == 2) return @"色板顺序决定取色，同一图标始终落在同一格。透明度不低于 20%，避免图标不可见。";
    if (section == 3) return @"留空为全局改色。填写后仅作用名单内图标；排除优先，逗号分隔，最多 2048 字符。";
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"WCKSVGColor"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"WCKSVGColor"];
    cell.textLabel.textColor = UIColor.labelColor;
    cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
    cell.accessoryView = nil;
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;

    if (path.section == 0) {
        UISegmentedControl *segments = [[UISegmentedControl alloc]
            initWithItems:@[@"固定颜色", @"随机色板"]];
        segments.selectedSegmentIndex = [self usesFixed] ? 0 : 1;
        segments.accessibilityIdentifier = @"wck.svg.mode";
        [segments addTarget:self action:@selector(modeChanged:) forControlEvents:UIControlEventValueChanged];
        cell.textLabel.text = @"方式";
        cell.accessoryView = segments;
    } else if (path.section == 1) {
        BOOL dark = path.row == 1;
        NSString *hex = [self.settings stringForKey:dark ? kDark : kLight defaultValue:@""];
        cell.textLabel.text = dark ? @"深色图标颜色" : @"浅色图标颜色";
        cell.detailTextLabel.text = WCKHexDisplay(hex);
        cell.imageView.image = [self swatchForHex:hex];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        cell.selectionStyle = UITableViewCellSelectionStyleDefault;
        cell.accessibilityIdentifier = dark ? @"wck.svg.dark" : @"wck.svg.light";
    } else if (path.section == 2) {
        if (path.row == 0) {
            NSArray<NSString *> *palette = [self palette];
            cell.textLabel.text = @"调色盘";
            cell.detailTextLabel.text = [NSString stringWithFormat:@"%lu 色", (unsigned long)palette.count];
            cell.imageView.image = [self paletteStrip:palette];
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            cell.selectionStyle = UITableViewCellSelectionStyleDefault;
            cell.accessibilityIdentifier = @"wck.svg.palette";
        } else if (path.row == 1) {
            cell.textLabel.text = @"透明度";
            UISlider *slider = [UISlider new];
            slider.minimumValue = 0.2f;
            slider.maximumValue = 1.0f;
            slider.value = [self alphaValue];
            slider.accessibilityIdentifier = @"wck.svg.alpha";
            [slider addTarget:self action:@selector(alphaChanged:) forControlEvents:UIControlEventValueChanged];
            [slider addTarget:self action:@selector(alphaCommitted:) forControlEvents:
                UIControlEventTouchUpInside | UIControlEventTouchUpOutside];
            [slider.widthAnchor constraintGreaterThanOrEqualToConstant:150].active = YES;
            cell.accessoryView = slider;
            cell.detailTextLabel.text = [NSString stringWithFormat:@"%.0f%%", slider.value * 100];
        } else {
            cell.textLabel.text = @"恢复默认调色盘";
            cell.selectionStyle = UITableViewCellSelectionStyleDefault;
            cell.accessibilityIdentifier = @"wck.svg.reset";
        }
    } else {
        BOOL include = path.row == 0;
        NSString *value = [self.settings stringForKey:include ? kInclude : kExclude defaultValue:@""];
        cell.textLabel.text = include ? @"限定图标名单" : @"排除图标名单";
        cell.detailTextLabel.text = value.length ? value : (include ? @"全局（无限制）" : @"无");
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        cell.selectionStyle = UITableViewCellSelectionStyleDefault;
        cell.accessibilityIdentifier = include ? @"wck.svg.include" : @"wck.svg.exclude";
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path {
    [tableView deselectRowAtIndexPath:path animated:YES];
    if (path.section == 1) {
        [self pickColourForDark:path.row == 1];
    } else if (path.section == 2 && path.row == 0) {
        [self openPaletteEditor];
    } else if (path.section == 2 && path.row == 2) {
        [self confirmResetPalette];
    } else if (path.section == 3) {
        [self editListAtRow:path.row];
    }
}

#pragma mark - Actions

- (void)modeChanged:(UISegmentedControl *)sender {
    BOOL fixed = sender.selectedSegmentIndex == 0;
    if (![self save:@(fixed) forKey:kFixedFlag]) { [self reload]; return; }
    [self reload];
}

- (double)alphaValue {
    id value = self.settings.snapshot[kAlpha];
    if (![value isKindOfClass:NSNumber.class]) return 1.0;
    double alpha = [value doubleValue];
    return isfinite(alpha) ? MIN(1.0, MAX(0.2, alpha)) : 1.0;
}

- (void)alphaChanged:(UISlider *)sender {
    // Live feedback without a write per pixel of travel.
    UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:
        [NSIndexPath indexPathForRow:1 inSection:2]];
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%.0f%%", sender.value * 100];
}

- (void)alphaCommitted:(UISlider *)sender {
    [self save:@(sender.value) forKey:kAlpha];
    [self reload];
}

- (void)pickColourForDark:(BOOL)dark {
    self.pickKey = dark ? kDark : kLight;
    NSString *hex = [self.settings stringForKey:self.pickKey defaultValue:@""];
    UIColorPickerViewController *picker = [UIColorPickerViewController new];
    picker.delegate = self;
    picker.supportsAlpha = NO;
    picker.selectedColor = WCKColorFromHex(hex, UIColor.systemGreenColor);
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)colorPickerViewController:(UIColorPickerViewController *)picker
    didSelectColor:(UIColor *)color continuously:(BOOL)continuously {
    if (continuously || !self.pickKey) return;   // commit on dismissal, not every drag
}

- (void)colorPickerViewControllerDidFinish:(UIColorPickerViewController *)picker {
    if (self.pickKey) {
        NSString *hex = WCKHexFromColor(picker.selectedColor);
        if (hex) [self save:hex forKey:self.pickKey];
        self.pickKey = nil;
    }
    [self reload];
}

- (void)openPaletteEditor {
    WCKSVGPaletteEditorViewController *editor = [WCKSVGPaletteEditorViewController new];
    editor.settings = self.settings;
    editor.colors = [self palette];
    __weak typeof(self) weakSelf = self;
    editor.onChange = ^(NSArray<NSString *> *colors) {
        typeof(self) self = weakSelf;
        if (!self) return;
        [self save:colors forKey:kPalette];
        [self reload];
    };
    [self.navigationController pushViewController:editor animated:YES];
}

- (void)confirmResetPalette {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"恢复默认调色盘"
        message:@"当前色板将被默认色板替换。" preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"恢复" style:UIAlertActionStyleDestructive
        handler:^(UIAlertAction *action) {
            (void)action;
            [weakSelf save:WCKDefaultSVGPalette() forKey:kPalette];
            [weakSelf reload];
        }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)editListAtRow:(NSInteger)row {
    BOOL include = row == 0;
    NSString *key = include ? kInclude : kExclude;
    NSString *title = include ? @"限定图标名单" : @"排除图标名单";
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
        message:@"逗号分隔的图标名，最多 2048 字符。留空表示不限制。"
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.text = [self.settings stringForKey:key defaultValue:@""];
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
            [self save:weakAlert.textFields.firstObject.text ?: @"" forKey:key];
            [self reload];
        }]];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Swatches

- (UIImage *)swatchForHex:(NSString *)hex {
    CGFloat side = 22;
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc]
        initWithSize:CGSizeMake(side, side)];
    return [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        UIBezierPath *path = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(1, 1, side - 2, side - 2)
            cornerRadius:5];
        UIColor *colour = WCKColorFromHex(hex, UIColor.tertiarySystemFillColor);
        [colour setFill];
        [path fill];
        [UIColor.separatorColor setStroke];
        path.lineWidth = 1;
        [path stroke];
    }];
}

- (UIImage *)paletteStrip:(NSArray<NSString *> *)palette {
    CGFloat side = 22, gap = 2;
    NSUInteger count = MIN(palette.count, (NSUInteger)6);
    CGFloat width = count * side + (count > 1 ? (count - 1) * gap : 0);
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc]
        initWithSize:CGSizeMake(MAX(width, side), side)];
    return [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        for (NSUInteger i = 0; i < count; ++i) {
            CGRect rect = CGRectMake(i * (side + gap), 1, side, side - 2);
            UIBezierPath *path = [UIBezierPath bezierPathWithRoundedRect:rect cornerRadius:4];
            [WCKColorFromHex(palette[i], UIColor.tertiarySystemFillColor) setFill];
            [path fill];
        }
    }];
}

@end

#pragma mark - Palette editor

@implementation WCKSVGPaletteEditorViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"调色盘";
    self.tableView.rowHeight = 52;
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
        initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:self action:@selector(addColour)];
    self.navigationItem.rightBarButtonItem.accessibilityIdentifier = @"wck.svg.palette.add";
    if (!self.colors) self.colors = WCKDefaultSVGPalette();
}

- (NSArray<NSString *> *)colors {
    return _colors ?: @[];
}

- (void)notify {
    if (self.onChange) self.onChange(self.colors);
    [self.tableView reloadData];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.colors.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    return @"同一图标按名称固定取色。至少保留一个颜色；顺序会影响图标取到哪一格。";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"WCKSVGPaletteRow"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1
        reuseIdentifier:@"WCKSVGPaletteRow"];
    NSString *hex = self.colors[path.row];
    cell.textLabel.text = hex;
    cell.imageView.image = [self swatch:hex];
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%ld", (long)path.row + 1];
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

- (UIImage *)swatch:(NSString *)hex {
    CGFloat side = 26;
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc]
        initWithSize:CGSizeMake(side, side)];
    return [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        UIBezierPath *path = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(1, 1, side - 2, side - 2)
            cornerRadius:6];
        [WCKColorFromHex(hex, UIColor.tertiarySystemFillColor) setFill];
        [path fill];
        [UIColor.separatorColor setStroke];
        path.lineWidth = 1;
        [path stroke];
    }];
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)path { return YES; }

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)style
    forRowAtIndexPath:(NSIndexPath *)path {
    if (style != UITableViewCellEditingStyleDelete) return;
    if (self.colors.count <= 1) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"至少保留一个颜色"
            message:@"调色盘为空会让图标恢复原色。" preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    NSMutableArray *next = [self.colors mutableCopy];
    [next removeObjectAtIndex:path.row];
    self.colors = next;
    [self notify];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path {
    [tableView deselectRowAtIndexPath:path animated:YES];
    self.pickingNew = NO;
    self.editingIndex = (NSUInteger)path.row;
    [self presentPickerAtIndex:path.row];
}

- (void)addColour {
    if (self.colors.count >= 32) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"最多 32 色"
            message:@"请先删除不用的颜色。" preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    self.pickingNew = YES;
    self.editingIndex = NSNotFound;
    [self presentPickerAtIndex:NSNotFound];
}

- (void)presentPickerAtIndex:(NSUInteger)index {
    UIColor *initial = index == NSNotFound ? UIColor.systemGreenColor
        : WCKColorFromHex(self.colors[index], UIColor.systemGreenColor);
    UIColorPickerViewController *picker = [UIColorPickerViewController new];
    picker.delegate = self;
    picker.supportsAlpha = NO;
    picker.selectedColor = initial;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)colorPickerViewController:(UIColorPickerViewController *)picker
    didSelectColor:(UIColor *)color continuously:(BOOL)continuously {
    (void)picker; (void)color; (void)continuously;
}

- (void)colorPickerViewControllerDidFinish:(UIColorPickerViewController *)picker {
    NSString *hex = WCKHexFromColor(picker.selectedColor);
    if (hex) {
        NSMutableArray *next = [self.colors mutableCopy];
        if (self.pickingNew) {
            if (![next containsObject:hex]) [next addObject:hex];
        } else if (self.editingIndex != NSNotFound && self.editingIndex < next.count) {
            // Replace exactly the row the picker was opened from.
            next[self.editingIndex] = hex;
        } else if (![next containsObject:hex]) {
            [next addObject:hex];
        }
        self.colors = next;
        [self notify];
    }
    self.pickingNew = NO;
}

@end
