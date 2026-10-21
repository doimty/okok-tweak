#import <Foundation/Foundation.h>
#import <stdint.h>
NS_ASSUME_NONNULL_BEGIN
// Pure Foundation selection seam for behavior tests; not UI and not host permission.
FOUNDATION_EXPORT BOOL WCKSVGSelectRGB(NSDictionary *settings, NSString *name,
    BOOL dark, uint32_t *rgb);
NS_ASSUME_NONNULL_END
