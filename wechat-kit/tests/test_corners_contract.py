#!/usr/bin/env python3
"""Static contracts for the 寰峰彂-style list-cell corners; not UIKit behavior tests."""
import argparse
import re
import unittest
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument('--root', type=Path)
args, rest = parser.parse_known_args()
root = args.root or Path(__file__).resolve().parents[1]
source = (root / 'src/WCKCorners.m').read_text()
settings = (root / 'src/WCKSettings.m').read_text()
page = (root / 'src/WCKSettingsViewController.m').read_text()
model = (root / 'tests/WCKCornersModel.m').read_text()
detail = (root / 'src/WCKFeatureDetailViewController.m').read_text()


def body(name):
    match = re.search(r'\b' + re.escape(name) + r'\([^;]*?\)\s*\{', source)
    if not match:
        raise AssertionError('missing ' + name)
    start = match.end()
    depth = 1
    for index in range(start, len(source)):
        depth += (source[index] == '{') - (source[index] == '}')
        if depth == 0:
            return source[start:index]
    raise AssertionError('unterminated ' + name)


class CornersContract(unittest.TestCase):
    def test_only_explicit_host_cell_hooks(self):
        self.assertIn('NSClassFromString(@"MMTableViewCell")', source)
        self.assertIn('NSClassFromString(@"NewMainFrameCell")', source)
        for forbidden in ['WCKInstallHook(UIButton.class', 'heightForHeaderInSection']:
            self.assertNotIn(forbidden, source)
        self.assertIn('WCKInstallHook(UIView.class, @selector(didMoveToWindow)', source)
        self.assertIn('WCKInstallHook(UIView.class, @selector(setBackgroundColor:)', source)
        install = body('WCKInstallCorners')
        self.assertIn('@selector(setFrame:)', install)
        self.assertIn('@selector(layoutSubviews)', install)
        self.assertIn('@selector(prepareForReuse)', install)
        # Base-class trampolines cover subclasses that bypass the cell hooks.
        self.assertIn('WCKInstallHook(UITableViewCell.class', install)
        # Row-height spacing recursed on iOS 15; it must stay out of the installer.
        self.assertNotIn('tableView:heightForRowAtIndexPath:', install)

    def test_supported_page_scope_is_fail_closed(self):
        # Fragments, not exact class names: a build may use a different owner.
        for name in ['MainFrame', 'Contacts', 'FindFriend', 'MoreViewController', 'ContactInfo']:
            self.assertIn(name, source)
        for key in ['homepageCornerEnabled', 'mainFrameCornerEnabled', 'myPageCornerEnabled',
                    'friendProfileCornerEnabled', 'discoverPageCornerEnabled']:
            self.assertIn(key, source)
            self.assertIn(key, page)
            self.assertIn(key, settings)
        enabled = body('WCKCornerPageEnabled')
        self.assertIn('WCKCornerPageKey(owner)', enabled)

    def test_geometry_is_applied_at_setframe_time(self):
        frame = body('WCKCornerSetFrame')
        self.assertIn('WCKCornerTargetFrame(cell, frame', frame)
        self.assertIn('++sCornerFrameDepth', frame)
        self.assertIn('original(cell, cmd, target);', frame)
        target = body('WCKCornerTargetFrame')
        self.assertIn('out.origin.x += margin', target)
        self.assertIn('out.size.width -= 2.0 * margin', target)
        # Vertical geometry stays untouched until spacing has a safe carrier.
        self.assertNotIn('out.origin.y +=', target)
        for marker in ['geometry.frame', 'geometry.first-style', 'geometry.stable']:
            self.assertIn(marker, model)

    def test_corners_are_a_mask_on_the_row(self):
        apply = body('WCKCornerApplyStyle')
        self.assertIn('[CAShapeLayer layer]', apply)
        self.assertIn('cell.layer.mask = maskLayer', apply)
        self.assertIn('bezierPathWithRoundedRect:bounds', apply)
        self.assertIn('byRoundingCorners:corners', apply)
        self.assertIn('cell.contentView.backgroundColor = WCKCornerTransparent()', apply)
        self.assertIn('WCKCornerApplyStyle(cell);', body('WCKCornerLayout'))
        self.assertNotIn('backgroundView = back', source)
        for marker in ['geometry.clear-content', 'geometry.middle-style', 'geometry.single-style']:
            self.assertIn(marker, model)

    def test_group_masks_follow_section_position(self):
        layout = body('WCKCornerApplyStyle')
        self.assertIn('path.row == 0', layout)
        self.assertIn('path.row == rows - 1', layout)
        self.assertIn('UIRectCornerTopLeft | UIRectCornerTopRight', layout)
        self.assertIn('UIRectCornerBottomLeft | UIRectCornerBottomRight', layout)
        for marker in ['geometry.first-style', 'geometry.middle-style',
                       'geometry.last-style', 'geometry.single-style']:
            self.assertIn(marker, model)

    def test_disable_and_reuse_restore_only_owned_values(self):
        restore = body('WCKCornerRestoreStyle')
        for token in ['layer.cornerRadius == saved.lastRadius',
                      'layer.maskedCorners == saved.lastMask',
                      'cell.layer.mask = state.hostMask',
                      'state.appliedFill', 'state.hostFill']:
            self.assertIn(token, restore)
        reuse = body('WCKCornerReuse')
        self.assertIn('WCKCornerRestoreStyle(cell, state)', reuse)
        self.assertIn('original(cell, cmd);', reuse)
        for marker in ['restore.host-values', 'reuse.host-style', 'reuse.reapplied']:
            self.assertIn(marker, model)

    def test_mask_is_restored_not_leaked(self):
        # The row mask is the only clipping mechanism; it must be handed back.
        restore = body('WCKCornerRestoreStyle')
        self.assertIn('if (state.ownsMask && cell.layer.mask == state.maskLayer)', restore)
        self.assertIn('cell.layer.mask = state.hostMask', restore)
        self.assertIn('cell.layer.mask = maskLayer', body('WCKCornerApplyStyle'))
        self.assertIn('geometry.disabled-style', model)

    def test_per_cell_reentrancy_guard(self):
        self.assertIn('sCornerFrameDepth', body('WCKCornerSetFrame'))
        self.assertIn('sCornerLayoutDepth && sCornerLayoutCell == cell', body('WCKCornerLayout'))
        self.assertIn('sCornerReuseDepth && sCornerReuseCell == cell', body('WCKCornerReuse'))
        self.assertIn('hooks.target-present', model)

    def test_component_families_attempted_without_abi_gate(self):
        apply = body('WCKCornerApplyToView')
        refresh = body('WCKRefreshCorners')
        self.assertNotIn('WCKEnableUnverifiedComponentFamilies', source)
        self.assertNotIn('WCKMethodMatches', apply)
        self.assertIn('WCKCornerVisitViews();', refresh)
        self.assertIn('visited < 4000', source)

    def test_settings_keys_and_controls_match(self):
        for key in ['corners', 'globalCornerRadius', 'globalCornerMargin', 'globalCornerSpacing',
                    'homepageCornerEnabled', 'mainFrameCornerEnabled', 'searchCorner',
                    'menuCorner', 'chatToolbarCorner', 'chatBubbleCorner', 'profileCorner']:
            self.assertIn(key, settings)
            self.assertIn(key, page)
        self.assertIn('WCKCornerExtraRows', page)
        self.assertIn('slider.tag = path.row;', detail)
        self.assertIn('extraRowAtRow:sender.tag', detail)
        self.assertIn('isEqualToString:@"header"', detail)

    def test_refresh_is_bounded_weak_and_cell_local(self):
        refresh = body('WCKRefreshCorners')
        self.assertIn('if (sCornerRefreshQueued) return;', refresh)
        self.assertIn('WCKCornerRefreshLimit', refresh)
        self.assertIn('NSHashTable weakObjectsHashTable', source)
        self.assertIn('[cell setNeedsLayout];', refresh)
        self.assertNotIn('layoutIfNeeded', refresh)
        self.assertNotIn('beginUpdates', refresh)
        self.assertIn('WCKCornerVisitViews', refresh)
        self.assertIn('visited < 4000', source)
        self.assertIn('refresh.registered', model)


if __name__ == '__main__':
    unittest.main(argv=[__file__] + rest, verbosity=2)
