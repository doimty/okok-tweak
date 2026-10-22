// Foundation/CoreGraphics UI model only. Never linked into the tweak.
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <dispatch/dispatch.h>
@class UIView,UIViewController,UINavigationController,UIGestureRecognizer;
@protocol UIGestureRecognizerDelegate <NSObject> @end
@interface UIResponder : NSObject
@property(nonatomic,weak) UIResponder *nextResponder;
@property(nonatomic,getter=isFirstResponder) BOOL firstResponder;
- (BOOL)becomeFirstResponder;
@end
@interface UIView : UIResponder
@property(nonatomic,weak) UIView *superview;
@property(nonatomic,strong) id window;
@property(nonatomic,getter=isHidden) BOOL hidden;
@property(nonatomic) CGFloat alpha;
@property(nonatomic) CGRect bounds;
@property(nonatomic,strong) NSMutableArray *gestures;
- (void)addGestureRecognizer:(UIGestureRecognizer *)gesture;
- (void)removeGestureRecognizer:(UIGestureRecognizer *)gesture;
- (void)didMoveToWindow;
- (void)layoutSubviews;
- (BOOL)isDescendantOfView:(UIView *)view;
@end
@interface UIControl : UIView @end
@interface UILabel : UIView
@property(nonatomic,copy) NSString *text;
@end
@interface UIViewController : UIResponder
@property(nonatomic,strong) UIView *view;
@property(nonatomic,getter=isViewLoaded) BOOL viewLoaded;
@property(nonatomic,strong) UIViewController *presentedViewController;
@property(nonatomic,weak) UINavigationController *navigationController;
@end
@interface UINavigationController : UIViewController
@property(nonatomic,strong) UIViewController *topViewController;
@end
@interface UITouch : NSObject
@property(nonatomic,strong) UIView *view;
@end
typedef NS_ENUM(NSInteger,UIGestureRecognizerState) { UIGestureRecognizerStatePossible, UIGestureRecognizerStateBegan, UIGestureRecognizerStateChanged, UIGestureRecognizerStateEnded, UIGestureRecognizerStateCancelled, UIGestureRecognizerStateFailed, UIGestureRecognizerStateRecognized=UIGestureRecognizerStateEnded };
@interface UIGestureRecognizer : NSObject
@property(nonatomic) UIGestureRecognizerState state;
@property(nonatomic) BOOL enabled,cancelsTouchesInView,delaysTouchesBegan;
@property(nonatomic,weak) id<UIGestureRecognizerDelegate> delegate;
@property(nonatomic,weak) UIView *view;
@property(nonatomic,weak) id actionTarget;
@property(nonatomic) SEL action;
- (instancetype)initWithTarget:(id)target action:(SEL)action;
- (void)fire;
@end
typedef NS_OPTIONS(NSUInteger,UISwipeGestureRecognizerDirection) { UISwipeGestureRecognizerDirectionRight=1, UISwipeGestureRecognizerDirectionLeft=2, UISwipeGestureRecognizerDirectionUp=4, UISwipeGestureRecognizerDirectionDown=8 };
@interface UISwipeGestureRecognizer : UIGestureRecognizer
@property(nonatomic) UISwipeGestureRecognizerDirection direction;
@end
@interface UIPanGestureRecognizer : UIGestureRecognizer @end
@interface UILongPressGestureRecognizer : UIGestureRecognizer @end
@interface UIScrollView : UIView
@property(nonatomic) CGPoint contentOffset;
@property(nonatomic) CGSize contentSize;
@property(nonatomic,strong) UIPanGestureRecognizer *panGestureRecognizer;
@end
typedef NS_ENUM(NSInteger,UIApplicationState) { UIApplicationStateActive,UIApplicationStateInactive,UIApplicationStateBackground };
@interface UIApplication : NSObject
@property(nonatomic) UIApplicationState applicationState;
+ (instancetype)sharedApplication;
@end
