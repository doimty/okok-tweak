#import "WCKSettingsViewController.h"
#import "WCKSettings.h"
#import "WCKRuntime.h"
#import "WCKSVGColorViewController.h"
#import "WCKFeatureDetailViewController.h"
#import "WCKSVGPalette.h"

static NSArray<NSDictionary<NSString *, id> *> *WCKModuleRows(void) {
    static NSArray *rows;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        rows = @[
            @{@"id": @"toolbar", @"title": @"工具栏位",
              @"icon": @"square.grid.2x2", @"tint": UIColor.systemPurpleColor},
            @{@"id": @"keyboardSwipe", @"title": @"聊天底部滑动展开键盘", @"key": @"keyboardSwipe",
              @"icon": @"keyboard", @"tint": UIColor.systemBlueColor},
            @{@"id": @"friendRank", @"title": @"群内好友时间榜",
              @"icon": @"chart.bar", @"tint": UIColor.systemOrangeColor},
            @{@"id": @"readAll", @"title": @"底栏微信长按一键已读", @"key": @"readAll",
              @"icon": @"checkmark.circle", @"tint": UIColor.systemGreenColor},
            @{@"id": @"cleanUI", @"title": @"界面净化",
              @"icon": @"sparkles", @"tint": UIColor.systemTealColor},
            @{@"id": @"corners", @"title": @"全局圆角", @"key": @"corners",
              @"icon": @"square.on.square", @"tint": UIColor.systemIndigoColor},
            @{@"id": @"momentsTime", @"title": @"朋友圈详细时间", @"key": @"momentsTime",
              @"icon": @"clock", @"tint": UIColor.systemPinkColor},
            @{@"id": @"albumSheet", @"title": @"聊天页半屏相册", @"key": @"albumSheet",
              @"icon": @"photo.on.rectangle", @"tint": UIColor.systemCyanColor},
            @{@"id": @"noHotUpdate", @"title": @"禁止热更新",
              @"icon": @"shield.slash", @"tint": UIColor.systemRedColor},
            @{@"id": @"topLabels", @"title": @"专属命名（顶部标签自定义）",
              @"icon": @"tag", @"tint": UIColor.systemBrownColor},
            @{@"id": @"svgTint", @"title": @"Svg图标改色", @"key": @"svgTint",
              @"icon": @"paintpalette", @"tint": UIColor.systemPurpleColor},
            @{@"id": @"repeatLabel", @"title": @"消息复读标签", @"note": @"标签含义待确认",
              @"icon": @"repeat", @"tint": UIColor.systemBlueColor},
            @{@"id": @"groupLabels", @"title": @"群聊标签", @"note": @"标签含义待确认",
              @"icon": @"person.2", @"tint": UIColor.systemGreenColor}
        ];
    });
    return rows;
}

// Pastel tile with a tinted glyph, drawn by WCK itself: no third-party asset
// is copied in. An unknown symbol falls back to the row's first character.
static UIImage *WCKTileImage(NSString *symbolName, UIColor *tint, NSString *fallback, CGFloat size) {
    CGSize tile = CGSizeMake(size, size);
    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat defaultFormat];
    format.opaque = NO;
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:tile format:format];
    return [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        (void)context;
        CGRect bounds = CGRectMake(0, 0, size, size);
        UIBezierPath *path = [UIBezierPath bezierPathWithRoundedRect:bounds cornerRadius:size * 0.28];
        [[tint colorWithAlphaComponent:0.16] setFill];
        [path fill];
        UIImage *symbol = symbolName.length ? [UIImage systemImageNamed:symbolName] : nil;
        if (symbol) {
            UIImage *tinted = [symbol imageWithTintColor:tint];
            CGFloat box = size * 0.52;
            CGFloat scale = MIN(box / symbol.size.width, box / symbol.size.height);
            CGSize draw = CGSizeMake(symbol.size.width * scale, symbol.size.height * scale);
            [tinted drawInRect:CGRectMake((size - draw.width) / 2, (size - draw.height) / 2,
                draw.width, draw.height)];
        } else if (fallback.length) {
            NSString *glyph = [fallback substringToIndex:1];
            NSDictionary *attrs = @{ NSFontAttributeName:
                [UIFont systemFontOfSize:size * 0.44 weight:UIFontWeightSemibold],
                NSForegroundColorAttributeName: tint };
            CGSize text = [glyph sizeWithAttributes:attrs];
            [glyph drawAtPoint:CGPointMake((size - text.width) / 2, (size - text.height) / 2)
                withAttributes:attrs];
        }
    }];
}

// Header card in the LuckyDam manner: icon tile, name, one-line subtitle and
// a status pill. It sits on the page background, not inside a white card.
@interface WCKSettingsHeroView : UIView
@property (nonatomic, strong) UILabel *pillLabel;
- (void)setPillText:(NSString *)text highlighted:(BOOL)highlighted;
@end

@implementation WCKSettingsHeroView {
    UIImageView *_iconView;
    UILabel *_nameLabel;
    UILabel *_subtitleLabel;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        _iconView = [[UIImageView alloc] initWithImage:WCKTileImage(@"shield.fill",
            UIColor.systemGreenColor, @"W", 64)];
        [self addSubview:_iconView];
        _nameLabel = [UILabel new];
        _nameLabel.text = @"WeChatKit";
        _nameLabel.font = [UIFont systemFontOfSize:22 weight:UIFontWeightBold];
        _nameLabel.textColor = UIColor.labelColor;
        [self addSubview:_nameLabel];
        _subtitleLabel = [UILabel new];
        _subtitleLabel.text = @"微信界面小工具";
        _subtitleLabel.font = [UIFont systemFontOfSize:14];
        _subtitleLabel.textColor = UIColor.secondaryLabelColor;
        [self addSubview:_subtitleLabel];
        _pillLabel = [UILabel new];
        _pillLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
        _pillLabel.textAlignment = NSTextAlignmentCenter;
        _pillLabel.layer.cornerRadius = 13;
        _pillLabel.layer.masksToBounds = YES;
        [self addSubview:_pillLabel];
    }
    return self;
}

- (void)setPillText:(NSString *)text highlighted:(BOOL)highlighted {
    self.pillLabel.text = text;
    if (highlighted) {
        self.pillLabel.textColor = UIColor.systemGreenColor;
        self.pillLabel.backgroundColor = [UIColor.systemGreenColor colorWithAlphaComponent:0.12];
    } else {
        self.pillLabel.textColor = UIColor.secondaryLabelColor;
        self.pillLabel.backgroundColor = UIColor.systemGray5Color;
    }
    [self setNeedsLayout];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = self.bounds.size.width;
    CGFloat pad = 20, icon = 64, gap = 12;
    _iconView.frame = CGRectMake(pad, 12, icon, icon);
    CGFloat textX = pad + icon + gap;
    CGFloat textW = width - pad - textX;
    _nameLabel.frame = CGRectMake(textX, 14, textW, 28);
    _subtitleLabel.frame = CGRectMake(textX, 44, textW, 20);
    CGSize textSize = [self.pillLabel.text sizeWithAttributes:
        @{ NSFontAttributeName: self.pillLabel.font }];
    _pillLabel.frame = CGRectMake(textX, 84, textSize.width + 24, 26);
}

@end

static NSDictionary<NSString *, id> *WCKCornerSwitchRow(NSString *key, NSString *title, NSString *help) {
    return @{ @"type": @"switch", @"key": key, @"title": title, @"help": help };
}
static NSDictionary<NSString *, id> *WCKCornerSliderRow(NSString *key, NSString *title,
                                                         NSNumber *max, NSString *help) {
    return @{ @"type": @"slider", @"key": key, @"title": title,
              @"min": @0, @"max": max, @"help": help };
}
static NSDictionary<NSString *, id> *WCKCornerHeaderRow(NSString *title, NSString *help) {
    return @{ @"type": @"header", @"title": title, @"help": help ?: @"" };
}
static NSArray<NSDictionary<NSString *, id> *> *WCKCornerExtraRows(void) {
    static NSArray *rows;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSMutableArray *result = [NSMutableArray array];
        [result addObject:WCKCornerHeaderRow(@"全局卡片页面", @"页面开关与 WCR 全局卡片参数分开保存。")];
        NSArray *pages = @[
            @[ @"homepageCornerEnabled", @"首页卡片", @"首页主列表卡片。" ],
            @[ @"mainFrameCornerEnabled", @"会话列表卡片", @"微信首页会话列表。" ],
            @[ @"myPageCornerEnabled", @"我的页面卡片", @"我页面的功能列表。" ],
            @[ @"friendProfileCornerEnabled", @"好友资料页卡片", @"联系人资料页的列表与卡片。" ],
            @[ @"discoverPageCornerEnabled", @"发现页卡片", @"发现页列表。" ],
            @[ @"tpModeCornerEnabled", @"TP 模式卡片", @"WCR 单独保留的 TP 模式页面。" ]
        ];
        for (NSArray *row in pages)
            [result addObject:WCKCornerSwitchRow(row[0], row[1], row[2])];
        [result addObject:WCKCornerSliderRow(@"globalCornerRadius", @"全局卡片半径", @24,
            @"只作用于全局卡片路径，不覆盖组件自己的半径。")];
        [result addObject:WCKCornerSliderRow(@"globalCornerMargin", @"全局卡片边距", @30,
            @"卡片左右边距，WCR 范围 0–30。")];
        [result addObject:WCKCornerSliderRow(@"globalCornerSpacing", @"全局卡片间距", @50,
            @"卡片之间的间距；分组间距另有置顶/置底设置。")];
        [result addObject:WCKCornerSliderRow(@"mainFramePinnedTopSpacing", @"置顶会话顶部间距", @50,
            @"置顶分组上方间距；未单独设置时沿用全局间距。")];
        [result addObject:WCKCornerSliderRow(@"mainFrameBelowPinnedSpacing", @"置顶会话下方间距", @50,
            @"置顶分组下方间距；未单独设置时沿用全局间距。")];
        [result addObject:WCKCornerSliderRow(@"globalCornerStroke", @"全局描边宽度", @4,
            @"统一描边宽度。组件专属描边暂按统一描边色/宽度处理。")];
        [result addObject:@{ @"type": @"choice", @"key": @"globalCornerStrokeStyle",
            @"title": @"全局描边样式", @"help": @"WCR 的描边样式。",
            @"items": @[ @{ @"value": @"0", @"title": @"实线" },
                          @{ @"value": @"1", @"title": @"虚线" },
                          @{ @"value": @"2", @"title": @"点线" } ] }];
        [result addObject:@{ @"key": @"globalCornerFill", @"title": @"全局卡片背景色",
            @"help": @"留空使用深浅色默认卡片色；格式 #RRGGBB。" }];
        [result addObject:@{ @"key": @"globalCornerStrokeColor", @"title": @"全局描边颜色",
            @"help": @"留空不改变宿主描边色；格式 #RRGGBB。" }];
        [result addObject:@{ @"key": @"globalCornerCustomExcludedVCClassNames",
            @"title": @"全局排除页面", @"help": @"按 VC 类名逗号分隔；匹配后不应用全局卡片。" }];

        NSArray *families = @[
            @[ @"searchCorner", @"搜索框", @"搜索栏及其专用输入容器。" ],
            @[ @"inputCorner", @"输入框", @"消息输入框容器，不等同于搜索框。" ],
            @[ @"topbarCorner", @"顶栏", @"页面顶部栏，WCR 另有顶部平角开关。" ],
            @[ @"toolbarCorner", @"工具栏", @"聊天工具栏，WCR 另有底部平角开关。" ],
            @[ @"chatToolbarCorner", @"聊天工具栏", @"聊天工具栏专用半径，独立于输入框和通用工具栏。" ],
            @[ @"menuCorner", @"长按菜单", @"通用菜单/操作面板。" ],
            @[ @"plusMenuCorner", @"加号菜单", @"聊天页加号菜单，独立于长按菜单。" ],
            @[ @"mainFrameSwipeMenuCorner", @"会话左滑菜单", @"会话列表左滑操作菜单。" ],
            @[ @"systemPopupCorner", @"系统弹窗", @"系统弹窗容器。" ],
            @[ @"imeKeyboardCorner", @"输入法键盘", @"键盘窗口顶部容器，不改输入框本身。" ],
            @[ @"emojiCorner", @"表情控件", @"表情面板与表情卡片。" ],
            @[ @"chatImageCorner", @"聊天图片", @"图片消息及其卡片。" ],
            @[ @"chatFileCorner", @"聊天文件", @"文件消息开关（WCR 无独立半径，跟随图片族半径）。" ],
            @[ @"chatLocationCorner", @"聊天位置", @"位置卡片开关（WCR 无独立半径，跟随图片族半径）。" ],
            @[ @"chatBubbleCorner", @"聊天气泡", @"聊天消息气泡。" ],
            @[ @"chatTimeRoundCorner", @"聊天时间", @"聊天时间胶囊。" ],
            @[ @"msgReferCorner", @"消息引用", @"消息引用卡片。" ],
            @[ @"systemMessageCorner", @"系统消息", @"系统消息卡片。" ],
            @[ @"systemNoticeCorner", @"系统通知", @"系统通知/横幅。" ],
            @[ @"voiceTranslateCorner", @"语音转文字", @"语音转文字结果卡片。" ],
            @[ @"momentCorner", @"朋友圈", @"朋友圈卡片及操作区域。" ],
            @[ @"finderCorner", @"视频号/发现", @"视频号与发现内容卡片。" ],
            @[ @"serviceCorner", @"服务页", @"服务/小程序内容卡片。" ],
            @[ @"sendPublishButtonCorner", @"发送/发布按钮", @"发送与发布按钮。" ],
            @[ @"avatarCorner", @"头像", @"头像圆角；资料头像另有资料卡开关。" ],
            @[ @"profileCorner", @"资料卡", @"资料卡容器与资料页卡片。" ],
            @[ @"otherCorner", @"其他已识别控件", @"未能归入 WCR 专用路径的控件，默认关闭。" ]
        ];
        [result addObject:WCKCornerHeaderRow(@"列表装饰图（独立）", @"不依赖全局卡片开关；只在下方页面画一张用户文件夹里的图。")];
        [result addObject:WCKCornerSwitchRow(@"decorationEnabled", @"装饰图开关",
            @"开启后按页面与文件夹画图；关闭或清空文件夹即清除已画的图。")];
        [result addObject:@{ @"key": @"decorationFolder", @"title": @"装饰图文件夹",
            @"help": @"放 浅色/深色 + @1x/@2x/@3x.png 的文件夹完整路径；留空不画。" }];
        [result addObject:@{ @"key": @"decorationVisiblePages", @"title": @"装饰图可见页面",
            @"help": @"数字位：1 会话、2 通讯录、3 发现、4 我、5 插件页；默认 1@2@3@4@5，留空也表示全部。" }];
        [result addObject:@{ @"type": @"slider", @"key": @"decorationOffsetX",
            @"title": @"装饰图横向偏移", @"min": @(-200), @"max": @200,
            @"help": @"图片横向偏移，-200 到 200；正数向右。每次布局重新赋值，不会累积。" }];
        [result addObject:@{ @"type": @"choice", @"key": @"decorationScale",
            @"title": @"装饰图缩放", @"help": @"图片整体缩放；每次布局重新赋值，不会累积。",
            @"items": @[ @{ @"value": @"0.5", @"title": @"0.5×" },
                          @{ @"value": @"0.75", @"title": @"0.75×" },
                          @{ @"value": @"1", @"title": @"1×" },
                          @{ @"value": @"1.25", @"title": @"1.25×" },
                          @{ @"value": @"1.5", @"title": @"1.5×" },
                          @{ @"value": @"2", @"title": @"2×" } ] }];
        [result addObject:WCKCornerHeaderRow(@"组件圆角（全部独立）", @"每个开关和半径对应 WCR 的独立配置族。")];
        for (NSArray *family in families) {
            NSString *base = family[0];
            [result addObject:WCKCornerSwitchRow([base stringByAppendingString:@"Enabled"], family[1], family[2])];
            BOOL radiusAvailable = ![base isEqualToString:@"chatFileCorner"] &&
                ![base isEqualToString:@"chatLocationCorner"];
            if (radiusAvailable) [result addObject:WCKCornerSliderRow([base stringByAppendingString:@"Radius"],
                [family[1] stringByAppendingString:@"半径"], @24,
                @"只作用于这一类控件；不会改动其他圆角类别。")];
        }
        rows = [result copy];
    });
    return rows;
}

@interface WCKSettingsViewController ()
@property (nonatomic, strong) WCKSettings *settings;
@property (nonatomic, copy) NSDictionary<NSString *, NSString *> *statuses;
@property (nonatomic, strong) UINavigationBar *standaloneBar;
@property (nonatomic, strong) WCKSettingsHeroView *heroView;
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
    self.tableView.estimatedRowHeight = 60;
    // One card per section, no hairlines inside it, as in the reference page.
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
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
    if (!self.heroView) {
        self.heroView = [[WCKSettingsHeroView alloc] initWithFrame:
            CGRectMake(0, 0, self.tableView.bounds.size.width, 124)];
        self.heroView.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    }
    CGFloat width = self.tableView.bounds.size.width;
    // Direct presentation has no navigation controller to render navigationItem.
    if (!nav) {
        if (!self.standaloneBar) {
            self.standaloneBar = [[UINavigationBar alloc] initWithFrame:
                CGRectMake(0, 0, width, 44)];
            self.standaloneBar.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        }
        self.standaloneBar.items = @[self.navigationItem];
        UIView *container = [[UIView alloc] initWithFrame:CGRectMake(0, 0, width, 44 + 124)];
        container.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        self.standaloneBar.frame = CGRectMake(0, 0, width, 44);
        self.heroView.frame = CGRectMake(0, 44, width, 124);
        [container addSubview:self.standaloneBar];
        [container addSubview:self.heroView];
        self.tableView.tableHeaderView = container;
    } else {
        self.standaloneBar.items = @[];
        self.heroView.frame = CGRectMake(0, 0, width, 124);
        self.tableView.tableHeaderView = self.heroView;
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
    NSDictionary *reported = WCKRuntimeStatuses();
    self.statuses = [reported isKindOfClass:NSDictionary.class] ? [reported copy] : @{};
    [self.tableView reloadData];
    [self updateHeroPill];
}

// The pill counts implemented features actually switched on, never a promise.
- (void)updateHeroPill {
    if (!self.heroView) return;
    BOOL master = [self.settings boolForKey:@"enabled"];
    NSInteger total = 0, enabled = 0;
    for (NSDictionary *row in WCKModuleRows()) {
        if (!row[@"key"]) continue;
        total += 1;
        if ([self.settings boolForKey:row[@"key"]]) enabled += 1;
    }
    NSString *text = master ? [NSString stringWithFormat:@"已开启 %ld/%ld", (long)enabled, (long)total]
                            : @"总开关关闭";
    [self.heroView setPillText:text highlighted:master];
}

- (BOOL)isReady:(NSString *)moduleID {
    id status = self.statuses[moduleID];
    return [status isKindOfClass:NSString.class] && [status isEqualToString:@"ready"];
}

// Any declared setting may be stored; runtime status is informational only.
- (BOOL)canEnableKey:(NSString *)key {
    return [key isKindOfClass:NSString.class] && self.settings.snapshot[key] != nil;
}

- (NSString *)shortStatusForRow:(NSDictionary<NSString *, id> *)row {
    if (!row[@"key"]) return @"待实现，暂无可用开关";
    if (![self.settings boolForKey:@"enabled"]) return @"总开关关闭，当前不生效";
    BOOL feature = [self.settings boolForKey:row[@"key"]];
    if ([self isReady:row[@"id"]]) return feature ? @"已开启" : @"已关闭";
    return feature ? @"已保存开启，状态未确认" : @"已接入，当前关闭";
}

- (NSString *)statusForRow:(NSDictionary<NSString *, id> *)row {
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
        text = [@"Hook 状态未确认，允许尝试：" stringByAppendingString:status];
    } else {
        text = @"尚无状态报告，允许尝试";
    }
    if (row[@"note"]) text = [text stringByAppendingFormat:@"；%@", row[@"note"]];
    if ([row[@"id"] isEqualToString:@"corners"]) {
        // Last cell the corner pass looked at, for device-side diagnosis.
        NSString *diag = self.statuses[@"corners.debug"];
        if (diag.length) text = [text stringByAppendingFormat:@"\n%@", diag];
    }
    if (row[@"key"] && [self.settings boolForKey:row[@"key"]] && ![self isReady:row[@"id"]])
        text = [text stringByAppendingString:@"；已保存开启，Hook 状态未确认，仍会尝试运行"];
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
    cell.textLabel.numberOfLines = 1;
    cell.detailTextLabel.numberOfLines = 1;
    cell.textLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    cell.detailTextLabel.font = [UIFont systemFontOfSize:13];
    cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
    cell.textLabel.enabled = YES;
    cell.detailTextLabel.enabled = YES;
    cell.accessoryView = nil;
    cell.accessibilityIdentifier = nil;
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    if (path.section == 0) {
        BOOL stored = [self.settings boolForKey:@"enabled"];
        cell.imageView.image = WCKTileImage(@"power", UIColor.systemGreenColor, @"", 36);
        cell.textLabel.text = @"启用 WeChatKit";
        cell.detailTextLabel.text = @"关闭后所有功能立即失效";
        UISwitch *toggle = [[UISwitch alloc] init];
        toggle.on = stored;
        toggle.enabled = YES;
        toggle.tag = 0;
        toggle.accessibilityIdentifier = @"wck.switch.enabled";
        toggle.accessibilityLabel = cell.textLabel.text;
        toggle.accessibilityHint = cell.detailTextLabel.text;
        [toggle addTarget:self action:@selector(toggleChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = toggle;
    } else if (path.section == 1) {
        // Each implemented feature is an entry: its switch and values live on
        // the second-level page, never twice on this list. The list row keeps
        // only a one-line state; the full diagnostic text moves to that page.
        NSDictionary<NSString *, id> *row = WCKModuleRows()[path.row];
        NSString *symbol = [row[@"icon"] isKindOfClass:NSString.class] ? row[@"icon"] : nil;
        UIColor *tint = [row[@"tint"] isKindOfClass:UIColor.class] ? row[@"tint"] : UIColor.systemGrayColor;
        cell.imageView.image = WCKTileImage(symbol, tint, row[@"title"], 36);
        cell.textLabel.text = row[@"title"];
        cell.detailTextLabel.text = [self shortStatusForRow:row];
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
            userInfo:@{NSLocalizedDescriptionKey: @"设置项不存在，无法保存。"}]];
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
        return @"聊天页半屏相册会尝试设置微信实验开关；不同版本可能忽略该开关，行为未保证。";
    if ([featureID isEqualToString:@"corners"])
        return @"按 WCR 的具体功能分别开关：页面卡片、搜索框、输入框、顶栏、工具栏、菜单、聊天内容、系统弹窗、头像和资料卡等互不共用开关。全局卡片参数只作用于卡片路径；组件半径独立保存。源码证据显示 WCR 不是把所有 UIView 按类名粗分。";
    return @"";
}

- (UIViewController *)detailPageForFeature:(NSDictionary<NSString *, id> *)row {
    NSString *featureID = row[@"id"];
    if ([featureID isEqualToString:@"svgTint"])
        return [[WCKSVGColorViewController alloc] initWithSettings:self.settings];
    NSArray<NSDictionary<NSString *, id> *> *extra = nil;
    if ([featureID isEqualToString:@"momentsTime"])
        extra = @[@{@"key": @"momentsFormat", @"title": @"时间格式",
                    @"help": @"使用日期格式，1–128 字符。例如 yyyy-MM-dd HH:mm:ss。"}];
    else if ([featureID isEqualToString:@"corners"]) extra = WCKCornerExtraRows();
    // The list row now shows one line only; the full diagnostic text lives
    // here, in the detail page's description, so nothing is lost.
    NSString *detail = [self detailForFeatureID:featureID];
    NSString *status = [self statusForRow:row];
    if (status.length) {
        detail = detail.length ? [detail stringByAppendingFormat:@"\n\n当前状态：%@", status]
                               : [@"当前状态：" stringByAppendingString:status];
    }
    return [[WCKFeatureDetailViewController alloc] initWithSettings:self.settings
        featureID:featureID settingsKey:row[@"key"] title:row[@"title"]
        detail:detail extraRows:extra];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path {
    [tableView deselectRowAtIndexPath:path animated:YES];
    if (path.section != 1) return;
    NSDictionary<NSString *, id> *row = WCKModuleRows()[path.row];
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
