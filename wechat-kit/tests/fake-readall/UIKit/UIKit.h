// Foundation/CoreGraphics-only behavioral fixture. NOT UIKit or a device.
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <dispatch/dispatch.h>
@class UIView, UIGestureRecognizer, UIAlertAction;
@protocol UIGestureRecognizerDelegate <NSObject>
@end
@interface UIResponder : NSObject
@property(nonatomic,weak) UIResponder *nextResponder;
@end
@interface UIView : UIResponder
@property(nonatomic,weak) UIView *superview;
@property(nonatomic,strong) id window;
@property(nonatomic,getter=isHidden) BOOL hidden;
@property(nonatomic) CGFloat alpha;
@property(nonatomic) CGRect bounds;
@property(nonatomic,strong) NSMutableArray *gestures;
- (void)addGestureRecognizer:(UIGestureRecognizer *)g;
- (void)removeGestureRecognizer:(UIGestureRecognizer *)g;
- (void)didMoveToWindow;
- (void)layoutSubviews;
@end
@interface UIViewController : UIResponder
@property(nonatomic,strong) UIViewController *presentedViewController;
- (void)presentViewController:(UIViewController *)c animated:(BOOL)b completion:(void (^)(void))completion;
@end
@interface UITabBarController : UIViewController
@property(nonatomic) NSUInteger selectedIndex;
@property(nonatomic,strong) UIViewController *selectedViewController;
@end
@interface UINavigationController : UIViewController
@property(nonatomic,strong) UIViewController *topViewController;
@end
@interface UITouch : NSObject
- (CGPoint)locationInView:(UIView *)view;
@end
typedef NS_ENUM(NSInteger,UIGestureRecognizerState) { UIGestureRecognizerStatePossible, UIGestureRecognizerStateBegan, UIGestureRecognizerStateChanged, UIGestureRecognizerStateEnded, UIGestureRecognizerStateCancelled };
@interface UIGestureRecognizer : NSObject
@property(nonatomic) UIGestureRecognizerState state;
@property(nonatomic) BOOL enabled;
@property(nonatomic) BOOL cancelsTouchesInView;
@property(nonatomic,weak) id<UIGestureRecognizerDelegate> delegate;
@property(nonatomic,weak) UIView *view;
@property(nonatomic,weak) id actionTarget;
@property(nonatomic) SEL action;
- (instancetype)initWithTarget:(id)target action:(SEL)action;
- (void)fire;
@end
@interface UILongPressGestureRecognizer : UIGestureRecognizer
@property(nonatomic) NSTimeInterval minimumPressDuration;
@end
typedef NS_ENUM(NSInteger,UIApplicationState) { UIApplicationStateActive, UIApplicationStateInactive, UIApplicationStateBackground };
@interface UIApplication : NSObject
@property(nonatomic) UIApplicationState applicationState;
+ (instancetype)sharedApplication;
@end
typedef NS_ENUM(NSInteger,UIAlertControllerStyle) { UIAlertControllerStyleAlert };
typedef NS_ENUM(NSInteger,UIAlertActionStyle) { UIAlertActionStyleDefault };
@interface UIAlertController : UIViewController
@property(nonatomic,copy) NSString *message;
+ (instancetype)alertControllerWithTitle:(NSString *)title message:(NSString *)message preferredStyle:(UIAlertControllerStyle)style;
- (void)addAction:(UIAlertAction *)action;
@end
@interface UIAlertAction : NSObject
+ (instancetype)actionWithTitle:(NSString *)title style:(UIAlertActionStyle)style handler:(void (^)(UIAlertAction *))handler;
@end
