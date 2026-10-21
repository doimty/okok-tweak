#ifndef WCK_POLICY_H
#define WCK_POLICY_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

// All gates below are production code also executed by the host tests.
bool WCKHostMatches(const char *bundle, const char *version, const char *build);
bool WCKTypeMatches(const char *actual, const char *expected);
bool WCKParseRGB(const char *text, uint32_t *rgb);
bool WCKNameInCSV(const char *name, const char *csv);
bool WCKShouldTintName(const char *name, const char *include, const char *exclude);

#endif
