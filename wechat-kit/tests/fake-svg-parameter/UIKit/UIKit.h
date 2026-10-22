// Test-only Foundation/CoreGraphics facade. Not UIKit, never a pixel oracle.
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <dispatch/dispatch.h>
typedef struct { CGFloat top,left,bottom,right; } UIEdgeInsets;
static inline BOOL UIEdgeInsetsEqualToEdgeInsets(UIEdgeInsets a,UIEdgeInsets b){return a.top==b.top&&a.left==b.left&&a.bottom==b.bottom&&a.right==b.right;}
static const UIEdgeInsets UIEdgeInsetsZero={0,0,0,0};
typedef NS_ENUM(NSInteger,UIImageOrientation){UIImageOrientationUp=0,UIImageOrientationRight=3,UIImageOrientationLeftMirrored=6};
typedef NS_ENUM(NSInteger,UIImageRenderingMode){UIImageRenderingModeAutomatic=0,UIImageRenderingModeAlwaysOriginal=1,UIImageRenderingModeAlwaysTemplate=2};
typedef NS_ENUM(NSInteger,UIImageResizingMode){UIImageResizingModeTile=0,UIImageResizingModeStretch=1};
typedef NS_ENUM(NSInteger,UIUserInterfaceStyle){UIUserInterfaceStyleUnspecified=0,UIUserInterfaceStyleLight=1,UIUserInterfaceStyleDark=2};
typedef NSUInteger UIControlState;
@interface UIColor:NSObject
@property uint32_t rgb;
+ (instancetype)colorWithRed:(CGFloat)r green:(CGFloat)g blue:(CGFloat)b alpha:(CGFloat)a;
@end
@interface UITraitCollection:NSObject
@property UIUserInterfaceStyle userInterfaceStyle;
+ (instancetype)currentTraitCollection;
@end
@interface UIImage:NSObject
@property CGSize size;
@property CGFloat scale;
@property UIImageOrientation imageOrientation;
@property UIImageRenderingMode renderingMode;
@property UIImageResizingMode resizingMode;
@property UIEdgeInsets capInsets,alignmentRectInsets;
@property(copy) NSArray *images;
@property NSTimeInterval duration;
@property uint32_t paintedRGB;
@property(copy) NSArray<NSString*> *operations;
@property BOOL returnSelf;
- (CGImageRef)CGImage;
- (instancetype)initWithCGImage:(CGImageRef)i scale:(CGFloat)s orientation:(UIImageOrientation)o;
- (UIImage*)imageWithTintColor:(UIColor*)color renderingMode:(UIImageRenderingMode)mode;
- (UIImage*)imageWithRenderingMode:(UIImageRenderingMode)mode;
- (UIImage*)resizableImageWithCapInsets:(UIEdgeInsets)insets;
- (UIImage*)resizableImageWithCapInsets:(UIEdgeInsets)insets resizingMode:(UIImageResizingMode)mode;
- (UIImage*)imageWithAlignmentRectInsets:(UIEdgeInsets)insets;
@end
@interface UIView:NSObject
@property(strong) UITraitCollection *traitCollection;
- (void)traitCollectionDidChange:(UITraitCollection*)previous;
@end
@interface UIImageView:UIView
@property(strong) UIImage *image,*highlightedImage;
- (void)replaceOutsideHook:(UIImage*)image;
@end
@interface UIButton:UIView
- (void)setImage:(UIImage*)image forState:(UIControlState)state;
- (UIImage*)imageForState:(UIControlState)state;
@end
