#!/usr/bin/env python3
"""Source-contract checks for the DY778-style settings pages.

The main page and every second-level detail page share one language: no
header card, one vivid-green accent for every row glyph and switch,
hairlines between rows inside cards, and one-line subtitles in the
"state · what it does" pattern. Behaviour is unchanged: the full
diagnostic text moves to the feature detail page, and no switch is added
or removed. Nothing is copied from the reference tweak: no identifiers,
strings, or assets of DY778 appear here, only the visual language.
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

    def test_no_header_card(self):
        # The reference home page has no header card: navigation, then sections.
        self.assertNotIn("WCKSettingsHeroView", self.vm)
        self.assertNotIn("setPillText:", self.vm)
        self.assertNotIn("已开启 %ld/%ld", self.vm)
        # The standalone bar stays for direct presentation without navigation.
        self.assertIn("tableHeaderView", self.vm)
        self.assertIn("standaloneBar", self.vm)

    def test_accent_glyphs(self):
        self.assertIn("WCKAccentColor", self.vm)
        self.assertIn("WCKAccentImage", self.vm)
        self.assertIn("systemImageNamed", self.vm)
        self.assertIn("UIImageRenderingModeAlwaysTemplate", self.vm)
        self.assertIn("imageView.tintColor", self.vm)
        self.assertIn("onTintColor", self.vm)
        self.assertIn('@\"power\"', self.vm)
        # One accent, not one tint per module.
        self.assertNotIn('@"tint":', self.vm)
        self.assertNotIn("WCKTileImage", self.vm)

    def test_every_module_row_has_an_icon(self):
        rows = self.vm.split("rows = @[", 1)[1].split("];", 1)[0]
        matches = list(re.finditer(r'@"id": @"([^"]+)"', rows))
        self.assertEqual(len(matches), 14)
        for i, match in enumerate(matches):
            end = matches[i + 1].start() if i + 1 < len(matches) else len(rows)
            block = rows[match.start():end]
            self.assertIn('@"icon":', block, match.group(1))
            if '@"key":' in block:
                self.assertIn('@"desc":', block, match.group(1))

    def test_one_line_rows_with_hairlines(self):
        # Hairlines inside cards, taller rows, tighter section spacing.
        self.assertNotIn("UITableViewCellSeparatorStyleNone", self.vm)
        self.assertNotIn("UITableViewCellSeparatorStyleNone", self.detail)
        self.assertIn("estimatedRowHeight = 72", self.vm)
        self.assertIn("sectionHeaderTopPadding = 6", self.vm)
        self.assertIn("detailTextLabel.numberOfLines = 1", self.vm)
        self.assertIn("UIFontWeightSemibold", self.vm)
        self.assertIn("secondaryLabelColor", self.vm)

    def test_subtitle_state_and_description(self):
        self.assertIn("shortStatusForRow", self.vm)
        self.assertIn("statusForRow", self.vm)
        # Reference subtitle pattern: state, then one line of what it does.
        self.assertIn('@" · %@"', self.vm)
        # The list shows one line; the detail page carries the full text.
        self.assertIn("当前状态：", self.vm)
        self.assertIn("detailPageForFeature", self.vm)

    def test_detail_pages_share_the_hero(self):
        self.assertIn("WCKDetailHeroView", self.detail)
        self.assertIn("WCKDetailTileImage", self.detail)
        self.assertIn("tableHeaderView", self.detail)
        self.assertIn("heroIconName", self.detail_h)
        self.assertIn("heroTintColor", self.detail_h)
        # The first-level row hands its own icon and the shared accent.
        self.assertIn("detailPage.heroIconName", self.vm)
        self.assertIn("detailPage.heroTintColor", self.vm)
        # The detail tile is a bare glyph now, not a pastel tile.
        self.assertNotIn("colorWithAlphaComponent:0.16", self.detail)
        # The hero subtitle tracks the same one-line status as the switch row.
        self.assertIn("heroSubtitleLabel", self.detail)
        self.assertIn("已保存开启，状态未确认", self.detail)

    def test_inactive_rows_are_dimmed(self):
        # A finished page does not paint dead rows as live: unimplemented
        # rows get a gray glyph, and when the master switch is off the
        # implemented rows dim too.
        self.assertIn("systemGrayColor", self.vm)
        self.assertIn("tertiaryLabelColor", self.vm)
        self.assertIn('if (!row[@"key"])', self.vm)

    def test_page_and_card_backgrounds(self):
        # Dynamic page/card colours, same values on both levels.
        for source in (self.vm, self.detail):
            self.assertIn("WCKPageBackgroundColor", source)
            self.assertIn("WCKCardBackgroundColor", source)
            self.assertIn("tableView.backgroundColor", source)
            self.assertIn("cell.backgroundColor", source)
        self.assertIn("0.055", self.vm)
        self.assertIn("0.951", self.vm)

    def test_no_new_forbidden_apis(self):
        for forbidden in ("NSLog(", "NSUserDefaults", "method_exchangeImplementations"):
            self.assertNotIn(forbidden, self.vm)
        # No reference-tweak identifiers, strings, or assets are copied.
        self.assertNotIn("DY778", self.vm)
        self.assertNotIn("DY778", self.detail)


if __name__ == "__main__":
    unittest.main(verbosity=2)
