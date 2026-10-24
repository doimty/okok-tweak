// Foundation/CoreGraphics behavioural model, NOT UIKit and never linked into the tweak.
#pragma once
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <dispatch/dispatch.h>

typedef NS_OPTIONS(NSUInteger, CACornerMask) {
    kCALayerMinXMinYCorner = 1U << 0, kCALayerMaxXMinYCorner = 1U << 1,
    kCALayerMinXMaxYCorner = 1U << 2, kCALayerMaxXMaxYCorner = 1U << 3
};
typedef NSString *CALayerCornerCurve;
#define kCACornerCurveContinuous @"continuous"
#define kCACornerCurveCircular @"circular"

typedef NS_ENUM(NSInteger, UIUserInterfaceStyle) {
    UIUserInterfaceStyleUnspecified = 0, UIUserInterfaceStyleLight = 1, UIUserInterfaceStyleDark = 2
};
@interface UITraitCollection : NSObject
@property(nonatomic, readonly) UIUserInterfaceStyle userInterfaceStyle;
@end

@interface UIColor : NSObject {
    CGColorRef _fixtureColor;
}
@property(nonatomic, readonly) CGColorRef CGColor;
+ (instancetype)colorWithRed:(CGFloat)red green:(CGFloat)green blue:(CGFloat)blue alpha:(CGFloat)alpha;
+ (instancetype)colorWithCGColor:(CGColorRef)cgColor;
- (BOOL)getWhite:(CGFloat *)white alpha:(CGFloat *)alpha;
- (BOOL)getRed:(CGFloat *)red green:(CGFloat *)green blue:(CGFloat *)blue alpha:(CGFloat *)alpha;
+ (instancetype)clearColor;
+ (instancetype)whiteColor;
+ (instancetype)blackColor;
@end

@interface CALayer : NSObject {
    CGColorRef _fixtureBorderColor;
}
@property(nonatomic) CGFloat cornerRadius;
@property(nonatomic) CACornerMask maskedCorners;
@property(nonatomic, copy) CALayerCornerCurve cornerCurve;
@property(nonatomic) CGFloat borderWidth;
@property(nonatomic) CGColorRef borderColor;
@property(nonatomic) BOOL masksToBounds;
@end

@class UIView, UIWindow, UITableViewCell;
@interface UIResponder : NSObject
@property(nonatomic, weak) UIResponder *nextResponder;
@end

@interface UIView : UIResponder {
    CGRect _fixtureFrame;
    CGRect _fixtureBounds;
}
@property(nonatomic) CGRect frame;
@property(nonatomic) CGRect bounds;
@property(nonatomic, weak) UIView *superview;
- (CGRect)convertRect:(CGRect)rect toView:(UIView *)view;@property(nonatomic, weak) UIWindow *window;
@property(nonatomic, getter=isHidden) BOOL hidden;
@property(nonatomic) CGFloat alpha;
@property(nonatomic, strong) CALayer *layer;
@property(nonatomic, strong) UIColor *backgroundColor;
@property(nonatomic, readonly) UITraitCollection *traitCollection;
@property(nonatomic, readonly) NSArray<UIView *> *subviews;
// These counters observe the original methods, not the replacement IMPs.
@property(nonatomic) NSUInteger fixtureFrameCalls, fixtureLayoutCalls, fixtureReuseCalls;
@property(nonatomic) NSUInteger fixtureNeedsLayoutCalls;
@property(nonatomic) BOOL fixtureNeedsLayout;
@property(nonatomic, copy) dispatch_block_t fixtureLayoutCallback;
- (instancetype)initWithFrame:(CGRect)frame;
- (void)addSubview:(UIView *)view;
- (CGRect)convertRect:(CGRect)rect toView:(UIView *)view;
- (void)setNeedsLayout;
- (void)layoutIfNeeded;
- (void)layoutSubviews;
- (void)didMoveToWindow;
@end
@interface UIWindow : UIView @end
@interface UIScene : NSObject @end
@interface UIWindowScene : UIScene
@property(nonatomic, readonly) NSArray<UIWindow *> *windows;
@end
@interface UIApplication : NSObject
@property(class, nonatomic, readonly) UIApplication *sharedApplication;
@property(nonatomic, readonly) NSSet<UIScene *> *connectedScenes;
@end
@interface UIScrollView : UIView @end
@interface UIButton : UIView @end

@interface UITableViewCell : UIView
@property(nonatomic, strong) UIView *contentView;
@property(nonatomic, strong) UIView *backgroundView;
@property(nonatomic, strong) UIView *selectedBackgroundView;
- (void)prepareForReuse;
@end
@interface UICollectionViewCell : UIView @end
@interface UITableView : UIScrollView
@property(nonatomic) NSInteger numberOfSections;
@property(nonatomic) NSUInteger fixtureBeginUpdates, fixtureEndUpdates;
- (void)beginUpdates;
- (void)endUpdates;
@property(nonatomic, strong) NSArray<NSNumber *> *fixtureRows;
@property(nonatomic, strong) NSMapTable<UITableViewCell *, NSIndexPath *> *fixturePaths;
- (NSIndexPath *)indexPathForCell:(UITableViewCell *)cell;
- (NSInteger)numberOfRowsInSection:(NSInteger)section;
@end
@interface NSIndexPath (WCKCornersFixture)
@property(nonatomic, readonly) NSInteger row;
@property(nonatomic, readonly) NSInteger section;
+ (instancetype)indexPathForRow:(NSInteger)row inSection:(NSInteger)section;
@end

@interface UIViewController : UIResponder
@property(nonatomic, strong) UIView *view;
@end
@interface MMTableViewCell : UITableViewCell @end
@interface MMMultiMenuTableViewCell : UITableViewCell @end
@interface NewMainFrameCell : MMMultiMenuTableViewCell @end
#define WCK_FIXTURE_CONTROLLER(name) \
@interface name : UIViewController \
@end
WCK_FIXTURE_CONTROLLER(NewMainFrameViewController)
WCK_FIXTURE_CONTROLLER(ContactsViewController)
WCK_FIXTURE_CONTROLLER(FindFriendEntryViewController)
WCK_FIXTURE_CONTROLLER(MoreViewController)
WCK_FIXTURE_CONTROLLER(ContactInfoViewController)
WCK_FIXTURE_CONTROLLER(WCKSettingsViewController)
WCK_FIXTURE_CONTROLLER(WCKUnknownViewController)
#undef WCK_FIXTURE_CONTROLLER
