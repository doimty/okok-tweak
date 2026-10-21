#include "WCKPolicy.h"
#include <assert.h>
#include <stdio.h>

#define CHECK(x) do { ++checks; assert(x); } while (0)
int main(void) {
    unsigned int checks=0;
    CHECK(WCKHostMatches("com.tencent.xin", "8.0.69", "8.0.69.33"));
    CHECK(!WCKHostMatches("com.example.other", "8.0.69", "8.0.69.33"));
    CHECK(!WCKHostMatches("com.tencent.xin.WeChatNotificationServiceExtension", "8.0.69", "8.0.69.33"));
    CHECK(!WCKHostMatches("com.tencent.xin", "8.0.70", "8.0.69.33"));
    CHECK(!WCKHostMatches("com.tencent.xin", "8.0.69", "8.0.69.34"));
    CHECK(!WCKHostMatches("com.tencent.xin", "8.0.69", "8.0.69.33suffix"));
    CHECK(!WCKHostMatches(NULL, NULL, NULL));
    CHECK(WCKTypeMatches("v","v"));
    CHECK(WCKTypeMatches("r@","@"));
    CHECK(WCKTypeMatches("@\"UILabel\"","@"));
    CHECK(!WCKTypeMatches("@?","@"));
    CHECK(!WCKTypeMatches("@","#"));
    CHECK(!WCKTypeMatches("q","Q"));
    CHECK(!WCKTypeMatches("d","f"));
    CHECK(WCKTypeMatches("{CGSize=dd}","{CGSize=dd}"));
    CHECK(!WCKTypeMatches("{CGSize=ff}","{CGSize=dd}"));
    CHECK(!WCKTypeMatches("@\"bad", "@"));
    CHECK(!WCKTypeMatches("@\"", "@"));
    CHECK(!WCKTypeMatches("@\"\"", "@"));
    CHECK(!WCKTypeMatches(NULL,"@"));
    CHECK(!WCKTypeMatches("","v"));
    uint32_t value=0;
    CHECK(WCKParseRGB("#07C160", &value) && value==0x07c160);
    CHECK(WCKParseRGB("#aBcDeF", &value) && value==0xabcdef);
    CHECK(WCKParseRGB("#000000", &value) && value==0);
    CHECK(WCKParseRGB("#FFFFFF", NULL));
    CHECK(!WCKParseRGB("#fff", &value));
    CHECK(!WCKParseRGB("07C160", &value));
    CHECK(!WCKParseRGB("#12345g", &value));
    CHECK(!WCKParseRGB(" #07c160", &value));
    CHECK(!WCKParseRGB("#07c160\n", &value));
    CHECK(!WCKParseRGB(NULL, &value));
    CHECK(WCKNameInCSV("icon_a", "icon_a"));
    CHECK(WCKNameInCSV("icon_a", " , icon_b, icon_a, "));
    CHECK(!WCKNameInCSV("icon_a", "icon_abc"));
    CHECK(!WCKNameInCSV("icon_A", "icon_a"));
    CHECK(!WCKNameInCSV("icon_a", "*"));
    CHECK(!WCKNameInCSV("icon_a", ""));
    CHECK(!WCKNameInCSV("", ",,"));
    CHECK(!WCKNameInCSV(NULL,NULL));
    CHECK(WCKShouldTintName("icon_a","icon_a,icon_b","icon_c"));
    CHECK(!WCKShouldTintName("icon_a","icon_a","icon_a"));
    CHECK(!WCKShouldTintName("icon_a","",""));
    CHECK(!WCKShouldTintName("icon_a","icon_b",""));
    CHECK(!WCKShouldTintName("icon_a",NULL,NULL));
    printf("WCK production policy: %u assertions PASS\n",checks);
    return 0;
}
