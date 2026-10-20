#include "../XCHomePromotionPolicy.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>

static unsigned tests;
#define CHECK(value) do { assert(value); ++tests; } while (0)

int main(void) {
    CHECK(XCHomePromotionAppIsSupported("com.realtech.xiaocan", "3.21.6"));
    CHECK(!XCHomePromotionAppIsSupported(NULL, "3.21.6"));
    CHECK(!XCHomePromotionAppIsSupported("com.realtech.xiaocan", NULL));
    CHECK(!XCHomePromotionAppIsSupported("other.app", "3.21.6"));
    CHECK(!XCHomePromotionAppIsSupported("com.realtech.xiaocan.test", "3.21.6"));
    CHECK(!XCHomePromotionAppIsSupported("com.realtech.xiaocan", "3.21.5"));
    CHECK(!XCHomePromotionAppIsSupported("com.realtech.xiaocan", "3.21.60"));
    CHECK(!XCHomePromotionAppIsSupported("com.realtech.xiaocan", ""));

    CHECK(XCHomePromotionShouldFilter(true, true, XC_HOME_PROMOTION_MATERIAL_URL));
    CHECK(!XCHomePromotionShouldFilter(false, true, XC_HOME_PROMOTION_MATERIAL_URL));
    CHECK(!XCHomePromotionShouldFilter(true, false, XC_HOME_PROMOTION_MATERIAL_URL));
    CHECK(!XCHomePromotionShouldFilter(false, false, XC_HOME_PROMOTION_MATERIAL_URL));
    CHECK(!XCHomePromotionShouldFilter(true, true, NULL));
    const char *unknown[] = {
        "", "https://jpg.realtech-inc.com/",
        "https://jpg.realtech-inc.com/business/order.jpg",
        "https://jpg.realtech-inc.com/silkworm_explore/xiaohongshu_jpg/",
        "https://jpg.realtech-inc.com/silkworm_explore/xiaohongshu_jpg/other.gif",
        "https://jpg.realtech-inc.com/silkworm_explore/xiaohongshu_jpg/17924017335172747c960f5953823e343bacaf070b149.gif",
        XC_HOME_PROMOTION_MATERIAL_URL "?v=1",
        XC_HOME_PROMOTION_MATERIAL_URL "?",
        XC_HOME_PROMOTION_MATERIAL_URL "#fragment",
        XC_HOME_PROMOTION_MATERIAL_URL "/suffix",
        "http://jpg.realtech-inc.com/silkworm_explore/xiaohongshu_jpg/17924017335172747c960f5953823e343bacaf070b148.gif",
        "https://jpg.realtech-inc.com:443/silkworm_explore/xiaohongshu_jpg/17924017335172747c960f5953823e343bacaf070b148.gif",
        "https://JPG.realtech-inc.com/silkworm_explore/xiaohongshu_jpg/17924017335172747c960f5953823e343bacaf070b148.gif",
        "https://jpg.realtech-inc.com.evil.test/silkworm_explore/xiaohongshu_jpg/17924017335172747c960f5953823e343bacaf070b148.gif"
    };
    for (size_t i = 0; i < sizeof unknown / sizeof unknown[0]; ++i)
        CHECK(!XCHomePromotionShouldFilter(true, true, unknown[i]));
    char changed[sizeof XC_HOME_PROMOTION_MATERIAL_URL];
    memcpy(changed, XC_HOME_PROMOTION_MATERIAL_URL, sizeof changed);
    changed[sizeof changed - 2] = 'G';
    CHECK(!XCHomePromotionShouldFilter(true, true, changed));
    CHECK(!XCHomePromotionShouldFilter(
        XCHomePromotionAppIsSupported("com.realtech.xiaocan", "3.22.0"),
        true, XC_HOME_PROMOTION_MATERIAL_URL));
    printf("PASS: %u home-promotion policy cases\n", tests);
    return 0;
}
