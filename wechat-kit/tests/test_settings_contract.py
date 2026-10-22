#!/usr/bin/env python3
"""Source-contract checks only; these do not execute Foundation or UIKit."""
import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]


class SettingsContract(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.h = (ROOT / "src/WCKSettings.h").read_text()
        cls.m = (ROOT / "src/WCKSettings.m").read_text()
        cls.vh = (ROOT / "src/WCKSettingsViewController.h").read_text()
        cls.vm = (ROOT / "src/WCKSettingsViewController.m").read_text()

    def test_public_contract(self):
        for name in ("WCKSettingsDidChangeNotification", "shared", "boolForKey:",
                     "stringForKey:", "defaultValue:", "setObject:", "forKey:",
                     "error:", "snapshot"):
            self.assertIn(name, self.h)
        self.assertIn("UITableViewController", self.vh)

    def test_exact_schema_and_safe_defaults(self):
        defaults = self.m.split("defaults = @{", 1)[1].split("};", 1)[0]
        keys = set(re.findall(r'@"([^"]+)"\s*:', defaults))
        self.assertEqual(keys, {"enabled", "keyboardSwipe", "svgTint", "momentsTime",
                               "albumSheet", "readAll", "svgTintLight", "svgTintDark",
                               "svgInclude", "svgExclude", "momentsFormat",
                               "svgUseFixedColor", "svgPaletteHexes", "svgRandomAlpha"})
        self.assertEqual(defaults.count("@NO"), 6)
        # Palette defaults to a usable non-empty set and fixed mode stays the default.
        self.assertIn('@"svgUseFixedColor": @YES', defaults)
        self.assertIn('@"svgPaletteHexes": WCKDefaultSVGPalette()', defaults)
        self.assertIn('@"svgRandomAlpha": @1.0', defaults)
        self.assertEqual(defaults.count('@"#07C160"'), 2)
        self.assertIn('@"svgInclude": @""', defaults)
        self.assertIn('@"momentsFormat": @"yyyy-MM-dd HH:mm:ss"', defaults)

    def test_bounded_loading_and_types(self):
        self.assertIn("readDataUpToLength:WCKMaximumFileBytes + 1", self.m)
        self.assertIn("NSPropertyListImmutable", self.m)
        self.assertIn("CFBooleanGetTypeID()", self.m)
        # Switch keys must still reject a plain number, and only the alpha key
        # may take a non-boolean number. A reversed condition broke every
        # switch write once; keep the polarity explicit.
        self.assertIn("BOOL isBoolean = CFGetTypeID((__bridge CFTypeRef)value) == CFBooleanGetTypeID()", self.m)
        self.assertIn("if (!isBoolean) return nil;", self.m)
        self.assertIn("WCKMaximumCSVLength", self.m)
        self.assertIn("WCKMaximumFormatLength", self.m)
        self.assertIn("controlCharacterSet", self.m)

    def test_transaction_and_notification_order(self):
        setter = self.m.split("- (BOOL)setObject:", 1)[1]
        self.assertIn("NSThread.isMainThread", setter)
        write = setter.index("writeToURL:")
        publish = setter.index("_values = next;")
        notify = setter.index("postNotificationName:")
        self.assertLess(write, publish)
        self.assertLess(publish, notify)
        self.assertIn("NSDataWritingAtomic", setter)
        self.assertIn("if (!written)", setter)
        self.assertIn("NSLock", self.m)
        self.assertIn("com.doimty.wechatkit.plist", self.m)
        self.assertIn("NSLibraryDirectory", self.m)

    def test_all_thirteen_modules(self):
        rows = self.vm.split("rows = @[", 1)[1].split("];", 1)[0]
        ids = re.findall(r'@"id": @"([^"]+)"', rows)
        self.assertEqual(ids, ["toolbar", "keyboardSwipe", "friendRank", "readAll",
                               "cleanUI", "corners", "momentsTime", "albumSheet",
                               "noHotUpdate", "topLabels", "svgTint", "repeatLabel",
                               "groupLabels"])
        self.assertIn("标签含义待确认", rows)
        self.assertNotIn("会话分组", self.vm)
        self.assertNotIn("底栏标题", self.vm)

    def test_runtime_gates_and_disable_escape(self):
        self.assertIn('#import "WCKRuntime.h"', self.vm)
        self.assertIn("WCKRuntimeStatuses()", self.vm)
        self.assertIn("WCKHostIsSupported()", self.vm)
        self.assertIn('isEqualToString:@"ready"', self.vm)
        # Only the master switch lives on the list; feature switches moved to
        # their second-level pages.
        self.assertIn("toggle.enabled = self.hostSupported || stored;", self.vm)
        self.assertNotIn('@"wck.switch." stringByAppendingString:key', self.vm)
        detail = (ROOT / "src/WCKFeatureDetailViewController.m").read_text()
        self.assertIn("toggle.enabled = ready || stored;", detail)
        self.assertIn("wck.feature.switch.", detail)
        self.assertIn("sender.isOn && !canEnable", self.vm)
        # The colour details moved to the second-level page; the first page only
        # promises a fixed colour or a palette and keeps the list warning reachable.
        self.assertIn("点开任意已实现项目可进入它的设置页", self.vm)
        self.assertIn("排除优先", (ROOT/"src/WCKSVGColorViewController.m").read_text())
        self.assertIn("总开关关闭，当前不生效", self.vm)
        self.assertIn("同时开启总开关", self.vm)
        self.assertNotIn("留空表示没有改色", self.vm)

    def test_ui_and_independence(self):
        self.assertIn("UITableViewStyleInsetGrouped", self.vm)
        self.assertIn('@"WeChatKit"', self.vm)
        self.assertIn('@"Close"', self.vm)
        self.assertIn("standaloneBar", self.vm)
        self.assertIn("UIAlertController", self.vm)
        source = self.m + self.vm
        for forbidden in ("NSUserDefaults", "CFPreferences", "NSLog(", "NSURLSession",
                          "NSURLConnection", "method_exchangeImplementations", "MSHook",
                          "WCPulse", "WCRefine", "WeX"):
            self.assertNotIn(forbidden, source)


if __name__ == "__main__":
    unittest.main(verbosity=2)
