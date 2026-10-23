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
        for forbidden in ['WCKInstallHook(UIView.class', 'WCKInstallHook(UITableViewCell.class',
                          'sOriginalSetBackgroundColor', 'WCKInstallHook(UIButton.class',
                          'heightForHeaderInSection']:
            self.assertNotIn(forbidden, source)

    def test_supported_page_scope_is_fail_closed(self):
        for name in ['NewMainFrameViewController', 'ContactsViewController',
                     'FindFriendEntryViewController', 'MoreViewController',
                     'ContactInfoViewController']:
            self.assertIn('@"' + name + '"', source)
        # One switch per page, not one shared scope value.
        for key in ['cornersHome', 'cornersContacts', 'cornersDiscover',
                    'cornersMe', 'cornersProfile']:
            self.assertIn('@"' + key + '"', source)
            self.assertIn('@"' + key + '"', page)
            self.assertIn('@"' + key + '"', settings)
        enabled = body('WCKCornerPageEnabled')
        self.assertIn('key != nil && [snapshot[key] boolValue]', enabled)
        self.assertNotIn('cornersScope', source)
        self.assertNotIn('cornersScope', page)

    def test_horizontal_geometry_changes_only_cell_frame(self):
        frame = body('WCKCornerFrame')
        for token in ['CGRect bounds = table.bounds', 'convertRect:bounds toView:parent',
                      'state.superview == parent', 'state.hostFrame', 'state.appliedFrame',
                      'CGRectGetMinX(visible)', 'CGRectGetMaxX(visible)']:
            self.assertIn(token, frame)
        self.assertIn('state.superview == parent', frame)
        self.assertIn('convertRect:state.appliedFrame toView:parent', frame)
        self.assertIn('CGRectEqualToRect(incoming, appliedInParent)', frame)
        self.assertNotIn('state.table == table && state.superview == parent', frame)
        self.assertIn('state.superview convertRect:state.hostFrame toView:parent', frame)
        self.assertNotIn('contentView.frame =', source)
        self.assertNotIn('CGRectInset', source)
        layout = body('WCKCornerLayout')
        self.assertIn('original(cell, cmd);', layout)
        self.assertIn('geometry.wrapper-coordinate-conversion', model)
        self.assertIn('geometry.migration-no-double-inset', model)
        self.assertIn('geometry.same-parent-table-change-restores-host', model)
        self.assertIn('geometry.offset-parent-change-restores-host', model)
        self.assertIn('geometry.spacing', model)
        frame_geometry = body('WCKCornerFrame')
        self.assertIn('CGRectGetMinY(host) + spacing / 2.0', frame_geometry)
        self.assertIn('desired.size.height = CGRectGetHeight(host) - spacing', frame_geometry)

    def test_disable_and_reuse_restore_only_owned_values(self):
        restore = body('WCKCornerRestoreStyle')
        for token in ['layer.cornerRadius == saved.lastRadius',
                      'layer.maskedCorners == saved.lastMask',
                      'layer.borderWidth == saved.lastWidth',
                      'layer.borderWidth = saved.width',
                      'state.appliedFill', 'state.hostFill']:
            self.assertIn(token, restore)
        reuse = body('WCKCornerReuse')
        for token in ['state.ownsFrame', 'state.hostFrame', 'state.appliedFrame',
                      'CGRectEqualToRect(cell.frame, state.appliedFrame)',
                      'original(cell, cmd);']:
            self.assertIn(token, reuse)
        self.assertIn('convertRect:state.appliedFrame toView:cell.superview', reuse)
        self.assertIn('cell.window == nil && state.ownsFrame', reuse)
        self.assertIn('reuse.detached-restores-host', model)
        self.assertIn('reuse.table-change-restores-host', model)
        self.assertIn('restore.reuse-drops-state', model)

    def test_row_masks_and_spacing_scope_not_overclaimed(self):
        layout = body('WCKCornerLayout')
        # Every row is its own card; row-index masks left middle rows square.
        self.assertNotIn('path.row == 0', layout)
        self.assertNotIn('path.row == rows - 1', layout)
        self.assertIn('kCALayerMinXMaxYCorner | kCALayerMaxXMaxYCorner', layout)
        self.assertIn('if (radius <= 0) mask = 0;', layout)
        self.assertNotIn('heightForHeaderInSection', source)
        self.assertNotIn('cornersSpacingUnified', settings)
        self.assertNotIn('cornersPinnedTopSpacing', settings)
        self.assertNotIn('置顶会话顶部间距', page)
        self.assertIn('([key isEqualToString:@"cornersMargin"] ? 30.0 : 24.0)', settings)
        # Spacing is a real card gap on the cell frame, not a fake header hook.
        self.assertIn('@"cornersSpacing": @8.0', settings)
        self.assertIn('cornersSpacing', page)

    def test_host_clipping_and_button_background_are_untouched(self):
        self.assertNotRegex(source, r'\.masksToBounds\s*=')
        self.assertIn('layer.borderColor = border.CGColor', source)
        self.assertNotIn('WCKInstallHook(UIButton.class', source)
        self.assertIn('restore.border-applied', model)

    def test_per_cell_reentrancy_and_hook_abi_model(self):
        self.assertIn('sCornerLayoutDepth && sCornerLayoutCell == cell', body('WCKCornerLayout'))
        self.assertIn('sCornerFrameDepth && sCornerFrameCell == cell', body('WCKCornerSetFrame'))
        self.assertIn('sCornerReuseDepth && sCornerReuseCell == cell', body('WCKCornerReuse'))
        install = body('WCKInstallCorners')
        for token in ['@encode(CGRect)', '@selector(setFrame:)', '@selector(layoutSubviews)',
                      '@selector(prepareForReuse)']:
            self.assertIn(token, install)
        self.assertIn('abi.frame', model)
        self.assertIn('hooks.allowed-target', model)

    def test_settings_keys_and_controls_match(self):
        for key in ['corners', 'cornersRadius', 'cornersMargin', 'cornersSpacing',
                    'cornersHome', 'cornersContacts', 'cornersDiscover', 'cornersMe',
                    'cornersProfile', 'cornersFill', 'cornersStrokeWidth', 'cornersStrokeColor']:
            self.assertIn('@"' + key + '"', settings)
            self.assertIn('@"' + key + '"', page)
        self.assertIn('slider.tag = path.row;', detail)
        self.assertIn('extraRowAtRow:sender.tag', detail)

    def test_refresh_is_bounded_weak_and_cell_local(self):
        refresh = body('WCKRefreshCorners')
        self.assertIn('if (sCornerRefreshQueued) return;', refresh)
        self.assertIn('WCKCornerRefreshLimit', refresh)
        self.assertIn('NSHashTable weakObjectsHashTable', source)
        self.assertIn('[cell setNeedsLayout];', refresh)
        self.assertNotIn('layoutIfNeeded', refresh)
        self.assertNotIn('beginUpdates', refresh)
        self.assertNotIn('connectedScenes', source)
        self.assertIn('refresh.registered', model)


if __name__ == '__main__':
    unittest.main(argv=[__file__] + rest, verbosity=2)
