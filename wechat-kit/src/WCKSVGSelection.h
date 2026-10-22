#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Legacy shape: colour only, alpha implied as opaque. Kept for existing callers.
FOUNDATION_EXPORT BOOL WCKSVGSelectRGB(NSDictionary *settings, NSString *name, BOOL dark, uint32_t *rgb);

/// Production entry: 0xAARRGGBB where AA is the alpha the caller should apply.
/// Fixed mode reads the light/dark hex; palette mode picks a stable slot per name.
FOUNDATION_EXPORT BOOL WCKSVGSelectPacked(NSDictionary *settings, NSString *name, BOOL dark, uint32_t *packed);

/// Splits a packed value back into colour and alpha.
FOUNDATION_EXPORT void WCKSVGUnpack(uint32_t packed, uint32_t *rgb, double *alpha);

NS_ASSUME_NONNULL_END
