#ifndef XC_LAUNCH_POLICY_H
#define XC_LAUNCH_POLICY_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

// Byte layout independently observed in the Xiaocan 3.21.6 LaunchUtil metadata.
// A mismatch must not mutate an object, even if field names still match.
static inline bool XCSetNativeSplashIgnore(void *instance, size_t instanceSize,
                                           ptrdiff_t ignoreOffset,
                                           ptrdiff_t launchViewOffset) {
    if (!instance || instanceSize != 24 || ignoreOffset != 8 ||
        launchViewOffset != 16) return false;
    uint8_t *bytes = (uint8_t *)instance;
    if (bytes[ignoreOffset] > 1) return false;
    bytes[ignoreOffset] = 1;
    return true;
}

#endif
