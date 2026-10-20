#ifndef XC_HOME_PROMOTION_POLICY_H
#define XC_HOME_PROMOTION_POLICY_H
#include <stdbool.h>
#include <string.h>

#define XC_HOME_PROMOTION_MATERIAL_URL \
    "https://jpg.realtech-inc.com/silkworm_explore/xiaohongshu_jpg/17924017335172747c960f5953823e343bacaf070b148.gif"

static inline bool XCHomePromotionAppIsSupported(const char *bundle, const char *version) {
    return bundle && version && strcmp(bundle, "com.realtech.xiaocan") == 0 &&
        strcmp(version, "3.21.6") == 0;
}
static inline bool XCHomePromotionShouldFilter(bool ready, bool exactCell, const char *url) {
    return ready && exactCell && url && strcmp(url, XC_HOME_PROMOTION_MATERIAL_URL) == 0;
}
#endif
