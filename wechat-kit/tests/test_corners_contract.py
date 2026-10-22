#!/usr/bin/env python3
"""Static contracts for global corner rounding. NOT UIKit execution."""
import argparse,re,unittest
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('--root',type=Path);a,rest=p.parse_known_args()
root=(a.root or Path(__file__).resolve().parents[1])
corners=(root/'src/WCKCorners.m').read_text()
settings=(root/'src/WCKSettings.m').read_text()
page=(root/'src/WCKSettingsViewController.m').read_text()
detail=(root/'src/WCKFeatureDetailViewController.m').read_text()

class CornersContract(unittest.TestCase):
 def test_installed_and_gated(self):
  self.assertIn('void WCKInstallCorners(void)',corners)
  self.assertIn('WCKEnabled(@"corners")',corners)
  self.assertIn('WCKSetModuleStatus(@"corners"',corners)
  self.assertIn('WCKInstallCorners();',(root/'src/WCKBootstrap.m').read_text())

 def test_radius_is_bounded(self):
  self.assertIn('MIN(24.0, MAX(0.0, radius))',corners)
  self.assertIn('MIN(24.0, MAX(0.0, radius))',settings)
  self.assertIn('@12.0',settings)

 def test_scope_has_two_modes(self):
  self.assertIn('isEqualToString:@"all"',corners)   # list is the default path
  self.assertIn('@"cornersScope": @"list"',settings)
  self.assertIn('cornersScope',settings)
  self.assertIn('isEqualToString:@"all"',corners)

 def test_excludes_content_and_keyboard(self):
  for name in ['UIImageView','UILabel','UIScrollView','UITableView','UIWindow','UIInputSetContainerView','UIVisualEffectView']:
   self.assertIn(name,corners)
  self.assertIn('WCKCornerClassExcluded',corners)

 def test_only_clips_when_it_paints(self):
  # masksToBounds must follow an actual background, not be forced on every view.
  self.assertIn('layer.masksToBounds = WCKPaintsBackground(view);',corners)
  self.assertNotIn('masksToBounds = YES',corners.replace('layer.masksToBounds = NO',''))

 def test_refresh_is_bounded(self):
  self.assertIn('visited < 4000',corners)
  self.assertIn('WCKRefreshCorners',corners)
  self.assertIn('WCKSettingsDidChangeNotification',corners)

 def test_card_layout_parameters(self):
  for key in ['cornersMargin','cornersSpacing','cornersStrokeWidth','cornersFill','cornersStrokeColor']:
   self.assertIn(key,(root/'src/WCKSettings.m').read_text())
   self.assertIn(key,page)
  self.assertIn('WCKApplyCardLayout',corners)
  self.assertIn('CGRectInset(bounds, margin, spacing / 2.0)',corners)
  self.assertIn('WCKInstallHook(UITableViewCell.class, @selector(layoutSubviews)',corners)
  # Every slider must carry its row, otherwise it writes the first row.
  self.assertIn('slider.tag = path.row;',detail)
  self.assertIn('extraRowAtRow:sender.tag',detail)

 def test_page_exposes_slider_and_choice(self):
  self.assertIn('@"type": @"slider"',page)
  self.assertIn('@"type": @"choice"',page)
  self.assertIn('@"cornersRadius"',page)
  self.assertIn('@"cornersScope"',page)
  self.assertIn('@"key": @"corners"',page)
  self.assertIn('- (void)sliderCommitted:(UISlider *)sender',detail)
  self.assertIn('- (void)presentChoiceForRow:',detail)

if __name__=='__main__':unittest.main(argv=[__file__]+rest,verbosity=2)
