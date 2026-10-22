#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Pure, UIKit-free helpers for the SVG colour feature. Everything here is
// deterministic so the same icon keeps one colour for the whole session.

/// "#RRGGBB" (upper case) from loose input; nil when it is not a colour.
FOUNDATION_EXPORT NSString *_Nullable WCKNormalizeHex(NSString *_Nullable text);
/// Normalised hex plus a short display sample, never nil for valid input.
FOUNDATION_EXPORT NSString *WCKHexDisplay(NSString *hex);
/// Stable index for an icon name; identical names always map to one palette slot.
FOUNDATION_EXPORT NSUInteger WCKPaletteIndexForName(NSString *_Nullable name, NSUInteger count);
/// Default palette used before the user edits one.
FOUNDATION_EXPORT NSArray<NSString *> *WCKDefaultSVGPalette(void);
/// Parses "#RRGGBB" into 0xRRGGBB; NO on malformed input.
FOUNDATION_EXPORT BOOL WCKHexToRGB(NSString *_Nullable text, uint32_t *rgb);

NS_ASSUME_NONNULL_END
