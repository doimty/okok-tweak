#!/usr/bin/env python3
"""Source-contract checks for the pinned-session limit only.

These do not execute Foundation or UIKit. The mechanism (which host method
is capped, and that the cap only applies when enabled with a positive
number) is asserted here; compile and link are proven by the cloud build,
and on-device behaviour still needs an authorised real-device check.
"""
import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]


class TopLimitContract(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.module = (ROOT / "src/WCKTopLimit.m").read_text()
        cls.runtime_h = (ROOT / "src/WCKRuntime.h").read_text()
        cls.bootstrap = (ROOT / "src/WCKBootstrap.m").read_text()
        cls.settings = (ROOT / "src/WCKSettings.m").read_text()
        cls.vc = (ROOT / "src/WCKSettingsViewController.m").read_text()
        cls.makefile = (ROOT / "Makefile").read_text()

    def test_hook_target_and_gate(self):
        # The host class and method are resolved at runtime, never linked.
        self.assertIn('NSClassFromString(@"NewMainFrameViewController")', self.module)
        self.assertIn('NSSelectorFromString(@"maxSessionCountInOneScreen")', self.module)
        self.assertIn("WCKInstallHook", self.module)
        # A count on 64-bit ObjC; a different host encoding must refuse,
        # never install blindly.
        self.assertIn('"q", NULL, 0', self.module)
        # Gated at call time so toggling needs no relaunch.
        self.assertIn('WCKEnabled(@"topLimitEnabled")', self.module)
        self.assertIn("if (limit > 0) return limit;", self.module)
        # Disabled or non-positive falls through to the host implementation.
        self.assertIn("next(self, _cmd)", self.module)
        # Status follows the ReadAll pattern: ready, or an honest failure.
        self.assertIn('WCKSetModuleStatus(@"topLimit", installed ? @"ready" : @"Hook 不可用")',
                      self.module)

    def test_wiring(self):
        self.assertIn("void WCKInstallTopLimit(void);", self.runtime_h)
        self.assertIn("WCKInstallTopLimit();", self.bootstrap)
        self.assertIn("src/WCKTopLimit.m", self.makefile)

    def test_settings_schema(self):
        self.assertIn('@"topLimitEnabled"] = @NO', self.settings)
        self.assertIn('@"topLimitCount"] = @9', self.settings)
        # Own 1-30 range, booleans and non-finite values rejected.
        self.assertIn('isEqualToString:@"topLimitCount"', self.settings)
        self.assertIn("MIN(30.0, MAX(1.0, number))", self.settings)

    def test_settings_ui(self):
        self.assertIn('@"id": @"topLimit"', self.vc)
        self.assertIn('@"key": @"topLimitEnabled"', self.vc)
        self.assertIn('@"icon": @"pin.fill"', self.vc)
        self.assertIn("功能状态（14 项）", self.vc)
        # Detail page: the master switch comes from the row key; extra rows
        # carry only the count slider.
        self.assertIn('isEqualToString:@"topLimit"', self.vc)
        self.assertIn('@"key": @"topLimitCount"', self.vc)
        self.assertIn('@"min": @1, @"max": @30', self.vc)

    def test_independence(self):
        # No reference-tweak keys, hook machinery, or account data is reused.
        for banned in ("TopSessionLimitValue", "EnableTopSessionLimit",
                       "HomeCellTopSession", "method_exchangeImplementations",
                       "MSHook", "MSHookMessageEx", "NSUserDefaults",
                       "CFPreferences", "NSLog(", "setFrame:"):
            self.assertNotIn(banned, self.module)
        # The reference UI's explanatory sentence is not copied either.
        self.assertNotIn("数值表示最多允许置顶的会话数量", self.vc)
        self.assertNotIn("数值表示最多允许置顶的会话数量", self.module)


if __name__ == "__main__":
    unittest.main()
