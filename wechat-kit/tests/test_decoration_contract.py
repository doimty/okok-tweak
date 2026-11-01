#!/usr/bin/env python3
"""Source-contract checks for WCK list decoration images.

These do not execute Foundation or UIKit: this repo's native model layers run
on macOS, and this VM has no iOS SDK. The checks pin the behaviour contract
from WeChatKit-decoration-reverse.md: gate, page allowlist, visible pages,
light/dark files, cache, single-view reuse, and assignment geometry.
"""
import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]


def body(source, name):
    start = source.index(name)
    depth = 0
    for i in range(start, len(source)):
        if source[i] == "{":
            depth += 1
        elif source[i] == "}":
            depth -= 1
            if depth == 0:
                return source[start:i + 1]
    raise AssertionError("unbalanced body for %s" % name)


class DecorationContract(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.h = (ROOT / "src/WCKDecoration.h").read_text()
        cls.m = (ROOT / "src/WCKDecoration.m").read_text()
        cls.settings = (ROOT / "src/WCKSettings.m").read_text()
        cls.corners = (ROOT / "src/WCKCorners.m").read_text()
        cls.makefile = (ROOT / "Makefile").read_text()

    def test_wired_into_build_and_layout_path(self):
        self.assertIn("src/WCKDecoration.m", self.makefile)
        self.assertIn("WCKDecorationApplyToCell(cell);", body(self.corners, "WCKCornerLayout"))
        self.assertIn("WCKDecorationRemoveFromCell(cell);", body(self.corners, "WCKCornerReuse"))
        self.assertIn("WCKDecorationInvalidateCache();", self.corners)

    def test_own_tag_not_the_sample_tag(self):
        self.assertIn("WCKDecorationViewTag", self.h)
        self.assertIn("0x57434B44", self.m)
        self.assertNotIn("9527", self.m)
        self.assertNotIn("HomeCell", self.m)

    def test_switch_off_or_missing_folder_clears(self):
        apply = body(self.m, "WCKDecorationApplyToCell")
        self.assertIn('![snapshot[@"decorationEnabled"] boolValue]', apply)
        self.assertIn("WCKDecorationRemoveFromCell(cell);", apply)
        self.assertIn("decorationFolder", apply)

    def test_page_allowlist_and_unknown_page(self):
        mapping = body(self.m, "WCKDecorationPageDigitForOwnerName")
        for fragment, digit in (("MainFrame", "1"), ("Contacts", "2"),
                                ("FindFriend", "3"), ("MoreViewController", "4"),
                                ("WCPlugins", "5")):
            self.assertIn(fragment, mapping)
            self.assertIn('@"%s"' % digit, mapping)
        self.assertIn("return nil;", mapping)

    def test_visible_pages_default_and_digit(self):
        visible = body(self.m, "WCKDecorationPageVisible")
        self.assertIn("if (!visiblePages.length) return YES;", visible)
        self.assertIn("containsString:digit", visible)
        self.assertIn('@"decorationVisiblePages"] = @"1@2@3@4@5"', self.settings)

    def test_light_dark_files_never_fall_back(self):
        names = body(self.m, "WCKDecorationCandidateNames")
        dark = names.split("dark ?")[1]
        self.assertIn("深色", dark)
        self.assertNotIn("浅色", dark.split(":")[0])
        order = re.findall(r"@(.)x\.png", names)
        self.assertEqual(order, ["3", "2", "1"])
        apply = body(self.m, "WCKDecorationApplyToCell")
        self.assertIn("WCKDecorationImage(folder, dark)", apply)

    def test_image_cached_by_path_and_invalidated_on_settings_change(self):
        loader = body(self.m, "WCKDecorationImage")
        self.assertIn("sDecorationCache[path]", loader)
        self.assertIn("fileExistsAtPath:path", loader)
        self.assertIn("imageWithContentsOfFile:path", loader)
        self.assertIn("sDecorationCache[path] = fixed;", loader)
        self.assertIn("[sDecorationCache removeAllObjects];",
                      body(self.m, "WCKDecorationInvalidateCache"))

    def test_geometry_is_assignment_not_accumulation(self):
        apply = body(self.m, "WCKDecorationApplyToCell")
        self.assertIn("view.transform = CGAffineTransformIdentity;", apply)
        self.assertIn("view.frame = cell.bounds;", apply)
        self.assertIn("CGRectGetMidX(cell.bounds) + offsetX", apply)
        self.assertIn("CGAffineTransformMakeScale(scale, scale)", apply)
        self.assertNotIn("cell.frame =", self.m)
        self.assertNotIn("setFrame:", self.m)

    def test_exactly_one_view_and_reuse_cleanup(self):
        apply = body(self.m, "WCKDecorationApplyToCell")
        self.assertIn("viewWithTag:WCKDecorationViewTag", apply)
        self.assertIn("insertSubview:view aboveSubview:cell.backgroundView", apply)
        self.assertIn("insertSubview:view atIndex:0", apply)
        self.assertIn("view.image = image;", apply)
        remove = body(self.m, "WCKDecorationRemoveFromCell")
        self.assertIn("removeFromSuperview", remove)

    def test_settings_ranges_and_visible_page_charset(self):
        self.assertIn('@"decorationOffsetX"] = @0', self.settings)
        self.assertIn('@"decorationScale"] = @1.0', self.settings)
        self.assertIn("MIN(200.0, MAX(-200.0, number))", self.settings)
        self.assertIn("MIN(2.0, MAX(0.5, number))", self.settings)
        self.assertIn("decorationVisiblePages", self.settings)
        self.assertIn("(c >= '1' && c <= '5') || c == '@'", self.settings)

    def test_no_sample_mechanisms_leak_in(self):
        for forbidden in ("NSUserDefaults", "MSHook", "9527", "HomeCell",
                          "method_exchangeImplementations"):
            self.assertNotIn(forbidden, self.m)


if __name__ == "__main__":
    unittest.main(verbosity=2)
