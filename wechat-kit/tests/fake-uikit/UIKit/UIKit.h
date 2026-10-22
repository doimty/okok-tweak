#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
typedef struct { double top,left,bottom,right; } UIEdgeInsets;
static inline BOOL UIEdgeInsetsEqualToEdgeInsets(UIEdgeInsets a, UIEdgeInsets b) {
    return a.top==b.top && a.left==b.left && a.bottom==b.bottom && a.right==b.right;
}
typedef NS_ENUM(NSInteger, UIImageOrientation) { UIImageOrientationUp=0, UIImageOrientationRight=3, UIImageOrientationLeftMirrored=6 };
typedef NS_ENUM(NSInteger, UIImageRenderingMode) { UIImageRenderingModeAutomatic, UIImageRenderingModeAlwaysOriginal, UIImageRenderingModeAlwaysTemplate };
typedef NS_ENUM(NSInteger, UIImageResizingMode) { UIImageResizingModeTile, UIImageResizingModeStretch };
typedef NS_ENUM(NSInteger, UIUserInterfaceStyle) { UIUserInterfaceStyleUnspecified, UIUserInterfaceStyleLight, UIUserInterfaceStyleDark };
typedef NSUInteger UIControlState;
@interface UIColor : NSObject
@property uint32_t rgb;
+ (instancetype)colorWithRed:(double)r green:(double)g blue:(double)b alpha:(double)a;
@end
@interface UITraitCollection : NSObject
@property UIUserInterfaceStyle userInterfaceStyle;
+ (instancetype)currentTraitCollection;
@end
@interface UIImage : NSObject
@property CGImageRef CGImage;
@property CGSize size;
@property double scale;
@property UIImageOrientation imageOrientation;
@property UIImageRenderingMode renderingMode;
@property UIImageResizingMode resizingMode;
@property UIEdgeInsets capInsets, alignmentRectInsets;
@property(copy) NSArray *images;
@property uint32_t paintedRGB;
@property BOOL wasTinted;
- (instancetype)initWithCGImage:(CGImageRef)image scale:(double)scale orientation:(UIImageOrientation)orientation;
- (UIImage *)resizableImageWithCapInsets:(UIEdgeInsets)insets;
- (UIImage *)resizableImageWithCapInsets:(UIEdgeInsets)insets resizingMode:(UIImageResizingMode)mode;
- (UIImage *)imageWithAlignmentRectInsets:(UIEdgeInsets)insets;
- (UIImage *)imageWithRenderingMode:(UIImageRenderingMode)mode;
- (UIImage *)imageWithTintColor:(UIColor *)color renderingMode:(UIImageRenderingMode)mode;
@end
@interface UIView : NSObject
@property(strong) UITraitCollection *traitCollection;
- (void)traitCollectionDidChange:(UITraitCollection *)old;
@end
@interface UIImageView : UIView
@property(strong) UIImage *image,*highlightedImage;
@end
@interface UIButton : UIView
- (void)setImage:(UIImage *)image forState:(UIControlState)state;
- (UIImage *)imageForState:(UIControlState)state;
@end
