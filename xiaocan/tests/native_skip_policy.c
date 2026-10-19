#include "../XCLaunchPolicy.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>

static unsigned tests;

static void expectReject(void *instance, uint8_t *bytes, size_t size,
                         ptrdiff_t flag, ptrdiff_t view) {
    uint8_t before[32];
    memcpy(before, bytes, sizeof before);
    assert(!XCSetNativeSplashIgnore(instance, size, flag, view));
    assert(memcmp(before, bytes, sizeof before) == 0);
    ++tests;
}

int main(void) {
    uint8_t bytes[32], before[32];
    memset(bytes, 0xa5, sizeof bytes);
    bytes[8] = 0;
    memcpy(before, bytes, sizeof before);
    assert(XCSetNativeSplashIgnore(bytes, 24, 8, 16));
    before[8] = 1;
    assert(memcmp(before, bytes, sizeof before) == 0);
    ++tests;
    assert(XCSetNativeSplashIgnore(bytes, 24, 8, 16));
    assert(memcmp(before, bytes, sizeof before) == 0);
    ++tests;

    expectReject(NULL, bytes, 24, 8, 16);
    const size_t badSizes[] = {0, 8, 16, 23, 25, 32, (size_t)-1};
    for (size_t i = 0; i < sizeof badSizes / sizeof badSizes[0]; ++i)
        expectReject(bytes, bytes, badSizes[i], 8, 16);
    const ptrdiff_t badOffsets[] = {-1, 0, 7, 9, 16, 1000};
    for (size_t i = 0; i < sizeof badOffsets / sizeof badOffsets[0]; ++i)
        expectReject(bytes, bytes, 24, badOffsets[i], 16);
    expectReject(bytes, bytes, 24, 8, -1);
    expectReject(bytes, bytes, 24, 8, 8);
    expectReject(bytes, bytes, 24, 8, 17);
    expectReject(bytes, bytes, 24, 8, 1000);
    bytes[8] = 2;
    expectReject(bytes, bytes, 24, 8, 16);
    bytes[8] = 255;
    expectReject(bytes, bytes, 24, 8, 16);
    printf("PASS: %u native-skip memory-policy cases\n", tests);
    return 0;
}
