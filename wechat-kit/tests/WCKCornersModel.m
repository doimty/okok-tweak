// Actual production WCKCorners + Settings/Palette/Policy, Foundation fake UIKit.
// This is an isolation/ownership/hook-target model, NOT UIKit, pixels, WeChat or device coverage.
#import <UIKit/UIKit.h>
#import "WCKRuntime.h"
#import "WCKSettings.h"
#import "WCKPolicy.h"
#import <objc/runtime.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static unsigned checks;
#define CHECK_ID(tag, expr) do { ++checks; if (!(expr)) { \
    fprintf(stderr, "CORNERS ASSERT[%s] line %d: %s\n", tag, __LINE__, #expr); \
    exit(86); } } while (0)
static BOOL near(CGFloat a, CGFloat b) { return fabs(a-b) < 0.00001; }
static BOOL sameRect(CGRect a, CGRect b) {
    return near(a.origin.x,b.origin.x) && near(a.origin.y,b.origin.y) &&
        near(a.size.width,b.size.width) && near(a.size.height,b.size.height);
}
static BOOL sameColor(CGColorRef a, CGColorRef b) {
    return a == b || (a && b && CGColorEqualToColor(a,b));
}
static CACornerMask const allCorners = kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner |
    kCALayerMinXMaxYCorner | kCALayerMaxXMaxYCorner;
static UIColor *rgb(CGFloat r, CGFloat g, CGFloat b) {
    return [UIColor colorWithRed:r green:g blue:b alpha:1];
}
@implementation UIColor
+ (instancetype)colorWithRed:(CGFloat)r green:(CGFloat)g blue:(CGFloat)b alpha:(CGFloat)a {
    UIColor *c = [self new]; c->_fixtureColor = CGColorCreateGenericRGB(r,g,b,a); return c;
}
- (BOOL)getWhite:(CGFloat *)white alpha:(CGFloat *)alpha {
    if (!_fixtureColor) return NO;
    const CGFloat *c=CGColorGetComponents(_fixtureColor);
    size_t n=CGColorGetNumberOfComponents(_fixtureColor);
    if (n==2) { if (white) *white=c[0]; if (alpha) *alpha=c[1]; return YES; }
    if (n==4 && c[0]==c[1] && c[1]==c[2]) { if (white) *white=c[0]; if (alpha) *alpha=c[3]; return YES; }
    return NO;
}
- (BOOL)getRed:(CGFloat *)red green:(CGFloat *)green blue:(CGFloat *)blue alpha:(CGFloat *)alpha {
    if (!_fixtureColor) return NO;
    const CGFloat *c=CGColorGetComponents(_fixtureColor);
    if (CGColorGetNumberOfComponents(_fixtureColor)!=4) return NO;
    if (red) *red=c[0]; if (green) *green=c[1]; if (blue) *blue=c[2]; if (alpha) *alpha=c[3];
    return YES;
}
+ (instancetype)colorWithCGColor:(CGColorRef)cg {
    if (!cg) return nil;
    UIColor *c = [self new]; c->_fixtureColor = CGColorCreateCopy(cg); return c;
}
- (CGColorRef)CGColor { return _fixtureColor; }
- (void)dealloc { if (_fixtureColor) CGColorRelease(_fixtureColor); }
+ (instancetype)clearColor { return [self colorWithRed:0 green:0 blue:0 alpha:0]; }
+ (instancetype)whiteColor { return [self colorWithRed:1 green:1 blue:1 alpha:1]; }
+ (instancetype)blackColor { return [self colorWithRed:0 green:0 blue:0 alpha:1]; }
@end
@implementation CALayer
- (instancetype)init { if ((self=[super init])) { _maskedCorners=allCorners; _cornerCurve=@"host"; } return self; }
- (CGColorRef)borderColor { return _fixtureBorderColor; }
- (void)setBorderColor:(CGColorRef)c {
    if (c) CGColorRetain(c); if (_fixtureBorderColor) CGColorRelease(_fixtureBorderColor); _fixtureBorderColor=c;
}
- (void)dealloc { if (_fixtureBorderColor) CGColorRelease(_fixtureBorderColor); }
@end
@implementation UIResponder @end
@implementation UITraitCollection
- (UIUserInterfaceStyle)userInterfaceStyle { return UIUserInterfaceStyleLight; }
@end
@interface UIView ()
@property(nonatomic, strong) NSMutableArray<UIView *> *fixtureChildren;
@end
@implementation UIView
- (void)didMoveToWindow {}
- (instancetype)init {
    if ((self=[super init])) { _layer=[CALayer new]; _alpha=1; _fixtureChildren=[NSMutableArray new]; }
    return self;
}
- (instancetype)initWithFrame:(CGRect)r { if ((self=[self init])) [self setFrame:r]; return self; }
- (CGRect)frame { return _fixtureFrame; }
- (void)setFrame:(CGRect)r {
    ++_fixtureFrameCalls; _fixtureFrame=r;
    _fixtureBounds=(CGRect){_fixtureBounds.origin,r.size};
}
- (CGRect)bounds { return _fixtureBounds; }
- (void)setBounds:(CGRect)r { _fixtureBounds=r; }
- (NSArray<UIView *> *)subviews { return self.fixtureChildren.copy; }
- (CGPoint)fixtureOriginInWindow {
    CGPoint origin=CGPointZero; UIView *view=self;
    for (NSUInteger depth=0;view && depth<64;++depth,view=view.superview) {
        origin.x += view.frame.origin.x - view.bounds.origin.x;
        origin.y += view.frame.origin.y - view.bounds.origin.y;
    }
    return origin;
}
- (UITraitCollection *)traitCollection { return [UITraitCollection new]; }
- (CGRect)convertRect:(CGRect)rect toView:(UIView *)view {
    CGPoint from=[self fixtureOriginInWindow];
    CGPoint to=view ? [view fixtureOriginInWindow] : CGPointZero;
    return CGRectOffset(rect,from.x-to.x,from.y-to.y);
}
- (void)addSubview:(UIView *)v {
    [self.fixtureChildren addObject:v]; v.superview=self; v.nextResponder=self; v.window=self.window;
}
- (void)setNeedsLayout { ++_fixtureNeedsLayoutCalls; _fixtureNeedsLayout=YES; }
- (void)layoutIfNeeded { if (_fixtureNeedsLayout) { _fixtureNeedsLayout=NO; [self layoutSubviews]; } }
- (void)layoutSubviews { ++_fixtureLayoutCalls; }
@end
@implementation UIWindow @end
@implementation UIScene @end
@implementation UIWindowScene
- (NSArray<UIWindow *> *)windows { return @[]; }
@end
@implementation UIApplication
+ (instancetype)sharedApplication {
    static UIApplication *shared; static dispatch_once_t once;
    dispatch_once(&once, ^{ shared=[self new]; });
    return shared;
}
- (NSSet<UIScene *> *)connectedScenes { return [NSSet set]; }
@end
@implementation UIScrollView @end
@implementation UIButton @end
@implementation UICollectionViewCell @end
@implementation UITableViewCell
- (instancetype)init {
    if ((self=[super init])) {
        _contentView=[UIView new]; [self addSubview:_contentView];
        _backgroundView=[UIView new]; [self addSubview:_backgroundView];
        _selectedBackgroundView=[UIView new]; [self addSubview:_selectedBackgroundView];
    } return self;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    // Host, and only host, determines content geometry from the incoming cell bounds.
    self.contentView.frame=self.bounds;
    dispatch_block_t callback=self.fixtureLayoutCallback;
    self.fixtureLayoutCallback=nil;
    if (callback) callback();
}
- (void)prepareForReuse { ++self.fixtureReuseCalls; }
@end
@implementation UITableView
- (instancetype)init {
    if ((self=[super init])) { _numberOfSections=3; _fixtureRows=@[@1,@3,@0];
        _fixturePaths=[NSMapTable weakToStrongObjectsMapTable]; }
    return self;
}
- (void)beginUpdates { ++self.fixtureBeginUpdates; }
- (void)endUpdates { ++self.fixtureEndUpdates; }
- (NSIndexPath *)indexPathForCell:(UITableViewCell *)c { return [self.fixturePaths objectForKey:c]; }
- (NSInteger)numberOfRowsInSection:(NSInteger)s {
    return s>=0 && s<(NSInteger)self.fixtureRows.count ? self.fixtureRows[(NSUInteger)s].integerValue : 0;
}
@end
@implementation NSIndexPath (WCKCornersFixture)
+ (instancetype)indexPathForRow:(NSInteger)r inSection:(NSInteger)s {
    NSUInteger indexes[2]={(NSUInteger)s,(NSUInteger)r}; return [self indexPathWithIndexes:indexes length:2];
}
- (NSInteger)section { return (NSInteger)[self indexAtPosition:0]; }
- (NSInteger)row { return (NSInteger)[self indexAtPosition:1]; }
@end
@implementation UIViewController
- (instancetype)init { if ((self=[super init])) { _view=[UIView new]; _view.nextResponder=self; } return self; }
@end
// The shared fake UIKit header only declares these; a linked executable needs
// real implementations or the macOS CI link step fails with undefined symbols.
@implementation NewMainFrameViewController @end
@implementation ContactsViewController @end
@implementation FindFriendEntryViewController @end
@implementation MoreViewController @end
@implementation ContactInfoViewController @end
@implementation WCKSettingsViewController @end
@implementation WCKUnknownViewController @end
@implementation MMTableViewCell @end
@implementation MMMultiMenuTableViewCell @end
@implementation UIImageView @end
@implementation MMHeadImageView @end
@implementation TLProfileImageView @end
@implementation FakeHeadImageView @end
@implementation MMMsgContentNavBar @end
@implementation MMNewMsgContentNavBar @end
@implementation MMTabBar @end
@implementation NewMainFrameCell
#if WCK_CORNERS_HOST_OVERRIDE
- (void)setFrame:(CGRect)r { [super setFrame:r]; }
- (void)layoutSubviews { [super layoutSubviews]; }
- (void)prepareForReuse { [super prepareForReuse]; }
#endif
@end
static WCKSettings *store;
static NSMutableDictionary *statuses;
static NSMutableArray<NSDictionary *> *hookTargets;
@interface WCKSettings (CornersPrivateStore)
- (instancetype)initWithFileURL:(NSURL *)url;
@end
@interface WCKSettings (CornersStore)
+ (instancetype)cornersFixtureShared;
@end
@implementation WCKSettings (CornersStore)
+ (instancetype)cornersFixtureShared { return store; }
@end
BOOL WCKHostIsSupported(void) { return YES; }
NSDictionary *WCKRuntimeStatuses(void) { return statuses.copy; }
void WCKSetModuleStatus(NSString *k, NSString *v) { statuses[k]=v; }
BOOL WCKEnabled(NSString *k) {
    NSDictionary *s=WCKSettings.shared.snapshot;
    return [s[@"enabled"] boolValue] && [s[k] boolValue];
}
BOOL WCKMethodMatches(Class c, SEL s, const char *r, const char *const *a, unsigned n) {
    (void)r; (void)a; (void)n;
    return c && s && class_getInstanceMethod(c,s) != NULL;
}
BOOL WCKInstallHook(Class c, SEL s, IMP imp, IMP *old, const char *r, const char *const *a, unsigned n) {
    BOOL valid=WCKMethodMatches(c,s,r,a,n);
    [hookTargets addObject:@{@"class":c ? NSStringFromClass(c) : @"(nil)",
        @"selector":NSStringFromSelector(s), @"selectorPresent":@(valid)}];
    CHECK_ID("hooks.target-present",valid && imp && old);
    Method m=class_getInstanceMethod(c,s); *old=method_getImplementation(m);
    if (!class_addMethod(c,s,imp,method_getTypeEncoding(m))) method_setImplementation(m,imp);
    return YES;
}
static void setting(NSString *key, id value) {
    NSError *error=nil; CHECK_ID("settings.real-write",[store setObject:value forKey:key error:&error]);
    CHECK_ID("settings.no-error",!error);
}
static void defaults(void) {
    setting(@"enabled",@YES); setting(@"corners",@YES);
    for (NSString *key in @[@"homepageCornerEnabled", @"mainFrameCornerEnabled",
                            @"myPageCornerEnabled", @"friendProfileCornerEnabled",
                            @"discoverPageCornerEnabled", @"tpModeCornerEnabled"])
        setting(key,@YES);
    setting(@"globalCornerMargin",@24); setting(@"globalCornerRadius",@12);
    setting(@"globalCornerSpacing",@0); setting(@"globalCornerFill",@"");
    setting(@"globalCornerStroke",@0); setting(@"globalCornerStrokeColor",@"");
    for (NSString *family in @[@"searchCorner", @"inputCorner", @"topbarCorner", @"toolbarCorner",
                               @"menuCorner", @"plusMenuCorner", @"mainFrameSwipeMenuCorner",
                               @"systemPopupCorner", @"imeKeyboardCorner", @"chatToolbarCorner", @"emojiCorner",
                               @"chatImageCorner", @"chatBubbleCorner", @"chatTimeRoundCorner", @"msgReferCorner",
                               @"systemMessageCorner", @"systemNoticeCorner", @"voiceTranslateCorner",
                               @"momentCorner", @"finderCorner", @"serviceCorner",
                               @"sendPublishButtonCorner", @"avatarCorner", @"profileCorner", @"otherCorner"]) {
        setting([family stringByAppendingString:@"Enabled"],@NO);
        setting([family stringByAppendingString:@"Radius"],@12);
    }
}

@interface WCKCornerScene : NSObject
@property(nonatomic, strong) UIViewController *controller;
@property(nonatomic, strong) UIWindow *window;
@property(nonatomic, strong) UITableView *table;
@property(nonatomic, strong) UITableViewCell *cell;
@property(nonatomic, strong) UIColor *hostColor, *hostBorder;
@end
@implementation WCKCornerScene @end

static WCKCornerScene *sceneWithRows(Class controllerClass, NSInteger row, NSInteger section,
                                     NSInteger rows) {
    WCKCornerScene *s=[WCKCornerScene new];
    s.controller=[controllerClass new];
    s.window=[UIWindow new];
    s.controller.view.window=s.window;
    s.table=[UITableView new];
    s.table.frame=CGRectMake(0,0,420,900);
    s.table.fixtureRows=@[@1,@(rows),@0];
    s.table.superview=s.controller.view;
    s.table.nextResponder=s.controller.view;
    s.table.window=s.window;
    s.cell=[controllerClass isSubclassOfClass:NewMainFrameViewController.class]
        ? [NewMainFrameCell new] : [MMTableViewCell new];
    s.cell.superview=s.table;
    s.cell.nextResponder=s.table;
    s.cell.window=s.window;
    [s.table.fixturePaths setObject:[NSIndexPath indexPathForRow:row inSection:section] forKey:s.cell];
    s.cell.frame=CGRectMake(0,100,420,60);
    s.hostColor=rgb(.2,.3,.4);
    s.hostBorder=rgb(.4,.5,.6);
    s.cell.backgroundColor=s.hostColor;
    for (CALayer *l in @[s.cell.layer,s.cell.backgroundView.layer]) {
        l.cornerRadius=3; l.maskedCorners=allCorners; l.cornerCurve=@"host";
        l.borderWidth=1; l.borderColor=s.hostBorder.CGColor; l.masksToBounds=NO;
    }
    return s;
}
static void layout(WCKCornerScene *s) {
    NSUInteger frames=s.cell.fixtureFrameCalls;
    NSUInteger content=s.cell.contentView.fixtureFrameCalls;
    NSUInteger calls=s.cell.fixtureLayoutCalls;
    [s.cell layoutSubviews];
    CHECK_ID("layout.original-once",s.cell.fixtureLayoutCalls==calls+1);
    // The host owns both the cell frame and the content layout.
    CHECK_ID("layout.frame-untouched",s.cell.fixtureFrameCalls==frames);
    CHECK_ID("layout.content-host-only",s.cell.contentView.fixtureFrameCalls==content+1);
    CHECK_ID("layout.content-bounds",sameRect(s.cell.contentView.frame,s.cell.bounds));
    CHECK_ID("layout.content-untouched",s.cell.contentView.layer.cornerRadius==0 &&
        [s.cell.contentView.layer.cornerCurve isEqual:@"host"]);
    CHECK_ID("layout.cell-layer-untouched",s.cell.layer.cornerRadius==0 ||
        near(s.cell.layer.cornerRadius,3));
}
static CGRect cardRect(WCKCornerScene *s, CGFloat margin, CGFloat spacing, BOOL first, BOOL last) {
    CGRect b=s.cell.bounds;
    CGFloat top=first ? spacing/2.0 : 0.0, bottom=last ? spacing/2.0 : 0.0;
    return CGRectMake(margin,top,b.size.width-2*margin,b.size.height-top-bottom);
}
static void expectCard(WCKCornerScene *s, CGRect rect, CACornerMask mask, CGFloat radius,
                       const char *tag) {
    UIView *back=s.cell.backgroundView;
    CHECK_ID(tag,back!=nil && sameRect(back.frame,rect));
    CHECK_ID(tag,near(back.layer.cornerRadius,radius) && back.layer.maskedCorners==mask &&
        [back.layer.cornerCurve isEqual:kCACornerCurveContinuous]);
    CHECK_ID(tag,sameColor(s.cell.backgroundColor.CGColor,[UIColor clearColor].CGColor));
}
static void hostStyle(WCKCornerScene *s, const char *tag) {
    UIView *back=s.cell.backgroundView;
    CHECK_ID(tag,s.cell.backgroundColor==s.hostColor);
    if (back) {
        CHECK_ID(tag,near(back.layer.cornerRadius,3) &&
            [back.layer.cornerCurve isEqual:@"host"] && back.layer.maskedCorners==allCorners);
        CHECK_ID(tag,near(back.layer.borderWidth,1) &&
            sameColor(back.layer.borderColor,s.hostBorder.CGColor));
    }
}

static void geometry(void) {
    setting(@"globalCornerMargin",@31);
    CHECK_ID("settings.margin-max-30",[WCKSettings.shared.snapshot[@"globalCornerMargin"] doubleValue]==30);
    setting(@"globalCornerMargin",@24);
    setting(@"globalCornerSpacing",@8);
    setting(@"globalCornerRadius",@12);

    WCKCornerScene *first=sceneWithRows(NewMainFrameViewController.class,0,1,3);
    layout(first);
    UIView *firstCard=first.cell.backgroundView;
    CHECK_ID("geometry.frame",firstCard!=nil &&
        sameRect(firstCard.frame,CGRectMake(24,4,372,52)));
    expectCard(first,cardRect(first,24,8,YES,YES),allCorners,12,"geometry.first");

    // Every row is an independent card, whatever its position in the section.
    WCKCornerScene *middle=sceneWithRows(NewMainFrameViewController.class,1,1,3);
    layout(middle);
    expectCard(middle,cardRect(middle,24,8,YES,YES),allCorners,12,"geometry.middle");

    WCKCornerScene *last=sceneWithRows(NewMainFrameViewController.class,2,1,3);
    layout(last);
    expectCard(last,cardRect(last,24,8,YES,YES),allCorners,12,"geometry.last");

    WCKCornerScene *single=sceneWithRows(ContactsViewController.class,0,0,1);
    layout(single);
    expectCard(single,cardRect(single,24,8,YES,YES),allCorners,12,"geometry.single");

    // Spacing is a real per-row gap, so the slider keeps working row to row.
    setting(@"globalCornerSpacing",@0);
    layout(first);
    expectCard(first,CGRectMake(24,0,372,60),allCorners,12,"geometry.spacing-zero");
    setting(@"globalCornerSpacing",@8);
    layout(first);
    expectCard(first,CGRectMake(24,4,372,52),allCorners,12,"geometry.spacing-back");

    // Repeated layouts must stay idempotent: no growing insets, no double frames.
    for (unsigned i=0;i<20;++i) { layout(first); }
    expectCard(first,CGRectMake(24,4,372,52),allCorners,12,"geometry.stable");

    // Narrow hosts clamp the margin instead of producing a negative card.
    WCKCornerScene *narrow=sceneWithRows(NewMainFrameViewController.class,0,1,3);
    narrow.cell.frame=CGRectMake(40,100,20,60);
    layout(narrow);
    UIView *narrowCard=narrow.cell.backgroundView;
    CHECK_ID("geometry.narrow-card",narrowCard.frame.size.width>=1 &&
        narrowCard.frame.size.width<=20 && narrowCard.frame.size.height>0);
    CHECK_ID("geometry.narrow-radius",narrowCard.layer.cornerRadius<=
        MIN(narrowCard.frame.size.width,narrowCard.frame.size.height)/2.0+0.001);

    // Disabling restores host styling and detaches any card we created.
    setting(@"corners",@NO);
    layout(first);
    hostStyle(first,"geometry.disabled-host-restored");
}

static void isolation(void) {
    // Unknown controllers are outside every page gate.
    WCKCornerScene *unknown=sceneWithRows(WCKUnknownViewController.class,0,1,3);
    layout(unknown);
    hostStyle(unknown,"isolation.page-off");
    CHECK_ID("isolation.page-off-bg",sameColor(unknown.cell.backgroundColor.CGColor,
        unknown.hostColor.CGColor));

    // A host-authored background view is never replaced, only styled.
    WCKCornerScene *hostOwned=sceneWithRows(NewMainFrameViewController.class,0,1,3);
    UIView *hostBack=hostOwned.cell.backgroundView;
    layout(hostOwned);
    CHECK_ID("isolation.same-background-view",hostOwned.cell.backgroundView==hostBack);
    setting(@"corners",@NO);
    layout(hostOwned);
    CHECK_ID("isolation.background-kept",hostOwned.cell.backgroundView==hostBack);
    hostStyle(hostOwned,"isolation.background-restored");

    // Generic views outside the cell path keep their own layer untouched.
    setting(@"corners",@YES);
    UIImageView *image=[UIImageView new];
    image.layer.cornerRadius=4;
    image.frame=CGRectMake(0,0,40,40);
    [image layoutSubviews];
    CHECK_ID("isolation.image-layer",near(image.layer.cornerRadius,4));
    UIButton *button=[UIButton new];
    button.backgroundColor=rgb(.9,.9,.9);
    button.frame=CGRectMake(0,0,80,30);
    [button layoutSubviews];
    CHECK_ID("isolation.button-fill",sameColor(button.backgroundColor.CGColor,rgb(.9,.9,.9).CGColor));
}

static void restore(void) {
    setting(@"globalCornerSpacing",@8);
    WCKCornerScene *s=sceneWithRows(NewMainFrameViewController.class,0,1,3);
    s.cell.backgroundView=nil; // no host background: the card view is ours
    layout(s);
    CHECK_ID("restore.enabled-card",s.cell.backgroundView!=nil);
    setting(@"corners",@NO);
    layout(s);
    hostStyle(s,"restore.host-values");
    CHECK_ID("restore.detached",s.cell.backgroundView==nil);

    // Reuse drops the created card so a dequeued cell starts from the host state.
    setting(@"corners",@YES);
    layout(s);
    CHECK_ID("reuse.card-before",s.cell.backgroundView!=nil);
    [s.cell prepareForReuse];
    CHECK_ID("reuse.card-dropped",s.cell.backgroundView==nil);
    CHECK_ID("reuse.fill-restored",s.cell.backgroundColor==s.hostColor);
    CHECK_ID("reuse.reuse-called",s.cell.fixtureReuseCalls==1);
    layout(s);
    CHECK_ID("reuse.card-recreated",s.cell.backgroundView!=nil);

    // A host-owned background survives reuse.
    WCKCornerScene *owned=sceneWithRows(NewMainFrameViewController.class,0,1,3);
    UIView *hostBack=owned.cell.backgroundView;
    layout(owned);
    [owned.cell prepareForReuse];
    CHECK_ID("reuse.host-background-kept",owned.cell.backgroundView==hostBack);
}

static void drainRefresh(void) {
    __block BOOL finished=NO;
    dispatch_async(dispatch_get_main_queue(), ^{ finished=YES; });
    NSDate *limit=[NSDate dateWithTimeIntervalSinceNow:2];
    while (!finished && [limit timeIntervalSinceNow]>0)
        [NSRunLoop.currentRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:.01]];
    CHECK_ID("refresh.main-queue-drained",finished);
}
static void refresh(void) {
    setting(@"globalCornerSpacing",@8);
    WCKCornerScene *s=sceneWithRows(NewMainFrameViewController.class,0,1,3);
    layout(s);
    expectCard(s,cardRect(s,24,8,YES,NO),
        kCALayerMinXMinYCorner|kCALayerMaxXMinYCorner,12,"refresh.initial");
    NSUInteger needs=s.cell.fixtureNeedsLayoutCalls;
    setting(@"globalCornerRadius",@18);
    WCKRefreshCorners();
    drainRefresh();
    CHECK_ID("refresh.registered",s.cell.fixtureNeedsLayoutCalls==needs+1);
    layout(s);
    expectCard(s,cardRect(s,24,8,YES,NO),
        kCALayerMinXMinYCorner|kCALayerMaxXMinYCorner,18,"refresh.radius");
    setting(@"globalCornerRadius",@12);
    setting(@"corners",@NO);
    WCKRefreshCorners();
    drainRefresh();
    layout(s);
    hostStyle(s,"refresh.off-restored");
}

static void lifetime(void) {
    __weak UITableViewCell *weakCell=nil;
    @autoreleasepool {
        WCKCornerScene *s=sceneWithRows(NewMainFrameViewController.class,0,1,3);
        layout(s);
        weakCell=s.cell;
        CHECK_ID("lifetime.alive",weakCell!=nil);
    }
    CHECK_ID("lifetime.weak",weakCell==nil);
    WCKRefreshCorners();
    drainRefresh();
}

static void abi(void) {
    CHECK_ID("hooks.nonempty",hookTargets.count>0);
    for (NSDictionary *entry in hookTargets) {
        NSString *c=entry[@"class"], *sel=entry[@"selector"];
        BOOL cellTarget=[@[@"MMTableViewCell",@"NewMainFrameCell"] containsObject:c];
        BOOL verifiedTarget=[@[@"MMHeadImageView", @"TLProfileImageView", @"FakeHeadImageView",
                              @"MMMsgContentNavBar", @"MMNewMsgContentNavBar", @"MMTabBar"] containsObject:c];
        BOOL viewTarget=[c isEqual:@"UIView"];
        BOOL allowedSelector=viewTarget
            ? ([sel isEqual:@"didMoveToWindow"] || [sel isEqual:@"setBackgroundColor:"] ||
               [sel isEqual:@"layoutSubviews"])
            : ([sel isEqual:@"layoutSubviews"] || [sel isEqual:@"prepareForReuse"]);
        CHECK_ID("abi.allowed-target",(cellTarget || verifiedTarget || viewTarget) && allowedSelector);
        CHECK_ID("abi.no-frame-hook",![sel isEqual:@"setFrame:"]);
        CHECK_ID("abi.selector-present",[entry[@"selectorPresent"] boolValue]);
    }
    // frame geometry is host-owned now, so it must not be part of our ABI surface.
    CHECK_ID("abi.frame",WCKMethodMatches(UITableViewCell.class,@selector(layoutSubviews),
        @encode(void),NULL,0));
}

int main(int argc, char **argv) {
    @autoreleasepool {
        CHECK_ID("fixture.argument",argc==2);
        CHECK_ID("fixture.main-thread",NSThread.isMainThread);
        NSString *home=NSProcessInfo.processInfo.environment[@"HOME"];
        CHECK_ID("fixture.isolated-home",home.length>0 && [home.lastPathComponent hasPrefix:@"corners-"]);
        NSURL *file=[NSURL fileURLWithPath:[home stringByAppendingPathComponent:@"Preferences/corners.plist"]];
        store=[[WCKSettings alloc] initWithFileURL:file];
        Method shared=class_getClassMethod(WCKSettings.class,@selector(shared));
        Method replacement=class_getClassMethod(WCKSettings.class,@selector(cornersFixtureShared));
        method_exchangeImplementations(shared,replacement);
        statuses=[NSMutableDictionary new];
        hookTargets=[NSMutableArray new];
        defaults();
        WCKInstallCorners();
        CHECK_ID("install.ready",[statuses[@"corners"] isEqual:@"ready"]);
        NSString *which=[NSString stringWithUTF8String:argv[1]];
        if ([which isEqual:@"geometry"]) geometry();
        else if ([which isEqual:@"isolation"]) isolation();
        else if ([which isEqual:@"restore"]) restore();
        else if ([which isEqual:@"refresh"]) refresh();
        else if ([which isEqual:@"lifetime"]) lifetime();
        else if ([which isEqual:@"abi"]) abi();
        else CHECK_ID("fixture.known-case",NO);
        NSData *data=[NSJSONSerialization dataWithJSONObject:hookTargets options:0 error:NULL];
        printf("HOOK_TARGETS %s\n",[[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] UTF8String]);
        printf("CORNERS CASE %s PASS (%u checks)\n",argv[1],checks);
    } return 0;
}
