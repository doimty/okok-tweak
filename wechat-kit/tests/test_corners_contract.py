#!/usr/bin/env python3
"""Static contracts for WCR-scoped list-cell corners; not UIKit behavior tests."""
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
        for forbidden in ['WCKInstallHook(UITableViewCell.class',
                          'WCKInstallHook(UIButton.class', 'heightForHeaderInSection']:
            self.assertNotIn(forbidden, source)
        self.assertIn('WCKInstallHook(UIView.class, @selector(didMoveToWindow)', source)
        self.assertIn('WCKInstallHook(UIView.class, @selector(setBackgroundColor:)', source)
        install = body('WCKInstallCorners')
        # Frame geometry is host-owned; hooking setFrame: is what shifted content.
        self.assertNotIn('@selector(setFrame:)', install)
        self.assertIn('@selector(layoutSubviews)', install)
        self.assertIn('@selector(prepareForReuse)', install)

    def test_supported_page_scope_is_fail_closed(self):
        for name in ['NewMainFrameViewController', 'ContactsViewController',
                     'FindFriendEntryViewController', 'MoreViewController',
                     'ContactInfoViewController']:
            self.assertIn('@"' + name + '"', source)
        for key in ['homepageCornerEnabled', 'mainFrameCornerEnabled', 'myPageCornerEnabled',
                    'friendProfileCornerEnabled', 'discoverPageCornerEnabled', 'tpModeCornerEnabled']:
            self.assertIn(key, source)
            self.assertIn(key, page)
            self.assertIn(key, settings)
        enabled = body('WCKCornerPageEnabled')
        self.assertIn('WCKCornerPageKey(owner)', enabled)
        self.assertNotIn('cornersList', source)
        self.assertNotIn('cornersMenu', source)
        self.assertNotIn('cornersSearch', source)
        self.assertNotIn('cornersOther', source)

    def test_card_is_an_inset_background_view(self):
        layout = body('WCKCornerLayout')
        # Host lays out first and keeps ownership of frame + content.
        self.assertIn('original(cell, cmd);', layout)
        self.assertNotIn('cell.frame =', layout)
        self.assertNotIn('contentView.frame =', source)
        self.assertNotIn('cell.frame =', source)
        self.assertIn('WCKCornerCardView(cell, state)', layout)
        self.assertIn('back.frame = card;', layout)
        self.assertIn('CGRectMake(margin, vertical, bounds.size.width - 2.0 * margin', layout)
        card = body('WCKCornerCardView')
        self.assertIn('cell.backgroundView', card)
        self.assertIn('state.createdBackground = YES', card)
        # The model proves the host frame and content are untouched.
        for marker in ['layout.frame-untouched', 'layout.content-untouched',
                       'geometry.first', 'geometry.single']:
            self.assertIn(marker, model)

    def test_every_row_is_its_own_inset_card(self):
        layout = body('WCKCornerLayout')
        # Per-row cards: no first/last special-casing, spacing stays a real gap.
        self.assertNotIn('path.row == 0', layout)
        self.assertNotIn('path.row == rows - 1', layout)
        self.assertIn('kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner', layout)
        self.assertIn('kCALayerMinXMaxYCorner | kCALayerMaxXMaxYCorner', layout)
        self.assertIn('CGFloat vertical = MIN(spacing', layout)
        self.assertIn('bounds.size.height - 2.0 * vertical', layout)
        for marker in ['geometry.first', 'geometry.middle', 'geometry.last', 'geometry.single',
                       'geometry.spacing-zero', 'geometry.spacing-back']:
            self.assertIn(marker, model)

    def test_disable_and_reuse_restore_only_owned_values(self):
        restore = body('WCKCornerRestoreStyle')
        for token in ['layer.cornerRadius == saved.lastRadius',
                      'layer.maskedCorners == saved.lastMask',
                      'layer.borderWidth == saved.lastWidth',
                      'state.appliedFill', 'state.hostFill',
                      'state.hostBackgroundView', 'state.ownsSelected']:
            self.assertIn(token, restore)
        detach = body('WCKCornerDetachCard')
        self.assertIn('state.createdBackground', detach)
        self.assertIn('cell.backgroundView = nil', detach)
        reuse = body('WCKCornerReuse')
        self.assertIn('WCKCornerRestoreStyle(cell, state)', reuse)
        self.assertIn('WCKCornerDetachCard(cell, state)', reuse)
        self.assertIn('original(cell, cmd);', reuse)
        for marker in ['restore.host-values', 'restore.detached',
                       'reuse.card-dropped', 'reuse.host-background-kept']:
            self.assertIn(marker, model)

    def test_host_clipping_and_button_background_are_untouched(self):
        self.assertNotIn('cell.layer.masksToBounds', source)
        self.assertIn('WCKCornerStyleLayer(back.layer', source)
        self.assertIn('layer.borderColor = border.CGColor', source)
        self.assertNotIn('WCKInstallHook(UIButton.class', source)

    def test_per_cell_reentrancy_guard(self):
        self.assertIn('sCornerLayoutDepth && sCornerLayoutCell == cell', body('WCKCornerLayout'))
        self.assertIn('sCornerReuseDepth && sCornerReuseCell == cell', body('WCKCornerReuse'))
        self.assertIn('hooks.target-present', model)
        self.assertIn('abi.no-frame-hook', model)

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
