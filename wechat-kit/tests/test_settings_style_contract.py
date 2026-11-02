#!/usr/bin/env python3
"""Source-contract checks for the LuckyDam-style settings pages.

The main page and every second-level detail page share one language: a
header card, pastel icon tiles and one-line subtitles. Behaviour is
unchanged: the full diagnostic text moves to the feature detail page,
and no switch is added or removed.
These checks do not execute UIKit.
"""
import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]


class SettingsStyleContract(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.vm = (ROOT / "src/WCKSettingsViewController.m").read_text()
        cls.detail = (ROOT / "src/WCKFeatureDetailViewController.m").read_text()
        cls.detail_h = (ROOT / "src/WCKFeatureDetailViewController.h").read_text()

    def test_hero_header_card(self):
        self.assertIn("WCKSettingsHeroView", self.vm)
        self.assertIn("setPillText:", self.vm)
        self.assertIn('@\"WeChatKit\"', self.vm)
        self.assertIn("tableHeaderView", self.vm)
        # The pill counts implemented features actually switched on.
        self.assertIn("已开启 %ld/%ld", self.vm)
        self.assertIn('@\"总开关关闭\"', self.vm)

    def test_icon_tiles_are_drawn_here(self):
        self.assertIn("WCKTileImage", self.vm)
        self.assertIn("systemImageNamed", self.vm)
        self.assertIn("imageWithTintColor", self.vm)
        # Unknown symbols fall back to a character, never a blank tile.
        self.assertIn("substringToIndex:1", self.vm)
        self.assertIn('@\"power\"', self.vm)

    def test_every_module_row_has_an_icon(self):
        rows = self.vm.split("rows = @[", 1)[1].split("];", 1)[0]
        matches = list(re.finditer(r'@"id": @"([^"]+)"', rows))
        self.assertEqual(len(matches), 13)
        for i, match in enumerate(matches):
            end = matches[i + 1].start() if i + 1 < len(matches) else len(rows)
            block = rows[match.start():end]
            self.assertIn('@"icon":', block, match.group(1))
            self.assertIn('@"tint":', block, match.group(1))

    def test_one_line_rows_and_no_hairlines(self):
        self.assertIn("UITableViewCellSeparatorStyleNone", self.vm)
        self.assertIn("UITableViewCellSeparatorStyleNone", self.detail)
        self.assertIn("detailTextLabel.numberOfLines = 1", self.vm)
        self.assertIn("UIFontWeightSemibold", self.vm)
        self.assertIn("secondaryLabelColor", self.vm)

    def test_short_list_state_keeps_full_diagnosis_on_detail(self):
        self.assertIn("shortStatusForRow", self.vm)
        self.assertIn("statusForRow", self.vm)
        # The list shows one line; the detail page carries the full text.
        self.assertIn("当前状态：", self.vm)
        self.assertIn("detailPageForFeature", self.vm)

    def test_detail_pages_share_the_hero(self):
        self.assertIn("WCKDetailHeroView", self.detail)
        self.assertIn("WCKDetailTileImage", self.detail)
        self.assertIn("tableHeaderView", self.detail)
        self.assertIn("heroIconName", self.detail_h)
        self.assertIn("heroTintColor", self.detail_h)
        # The first-level row hands its own icon and tint to the detail page.
        self.assertIn("detailPage.heroIconName", self.vm)
        self.assertIn("detailPage.heroTintColor", self.vm)
        # The hero subtitle tracks the same one-line status as the switch row.
        self.assertIn("heroSubtitleLabel", self.detail)
        self.assertIn("已保存开启，状态未确认", self.detail)

    def test_no_new_forbidden_apis(self):
        for forbidden in ("NSLog(", "NSUserDefaults", "method_exchangeImplementations"):
            self.assertNotIn(forbidden, self.vm)


if __name__ == "__main__":
    unittest.main(verbosity=2)
