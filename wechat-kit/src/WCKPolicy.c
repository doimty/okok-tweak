#include "WCKPolicy.h"
#include <ctype.h>
#include <string.h>

bool WCKHostMatches(const char *bundle, const char *version, const char *build) {
    return bundle && version && build &&
        strcmp(bundle, "com.tencent.xin") == 0 &&
        strcmp(version, "8.0.69") == 0 && strcmp(build, "8.0.69.33") == 0;
}

bool WCKTypeMatches(const char *actual, const char *expected) {
    // method_copyArgumentType/ReturnType return a type, NOT the full encoding.
    // Permit const qualifiers and an annotated ObjC object; never equate @? to @.
    if (!actual || !expected || !*actual || !*expected) return false;
    while (*actual && strchr("rnNoORV", *actual)) ++actual;
    if (strcmp(expected, "@") == 0)
        return strcmp(actual, "@") == 0 ||
            (strlen(actual) >= 4 && actual[0] == '@' && actual[1] == '"' &&
             actual[strlen(actual)-1] == '"');
    return strcmp(actual, expected) == 0;
}

bool WCKParseRGB(const char *text, uint32_t *rgb) {
    if (!text || strlen(text) != 7 || text[0] != '#') return false;
    uint32_t value = 0;
    for (size_t i = 1; i < 7; ++i) {
        unsigned char ch = (unsigned char)text[i];
        unsigned int n;
        if (ch >= '0' && ch <= '9') n = ch - '0';
        else if (ch >= 'a' && ch <= 'f') n = ch - 'a' + 10;
        else if (ch >= 'A' && ch <= 'F') n = ch - 'A' + 10;
        else return false;
        value = (value << 4) | n;
    }
    if (rgb) *rgb = value;
    return true;
}

bool WCKNameInCSV(const char *name, const char *csv) {
    // Exact, trimmed icon names only. No glob/substring/regular-expression matching.
    if (!name || !*name || !csv) return false;
    size_t length = strlen(name);
    const char *start = csv;
    for (;;) {
        const char *end = strchr(start, ',');
        if (!end) end = start + strlen(start);
        const char *left = start, *right = end;
        while (left < right && isspace((unsigned char)*left)) ++left;
        while (right > left && isspace((unsigned char)right[-1])) --right;
        if ((size_t)(right-left) == length && memcmp(left, name, length) == 0)
            return true;
        if (!*end) break;
        start = end + 1;
    }
    return false;
}

bool WCKShouldTintName(const char *name, const char *include, const char *exclude) {
    // Empty allowlist means change nothing, never apply a broad global tint.
    return WCKNameInCSV(name, include) && !WCKNameInCSV(name, exclude);
}
