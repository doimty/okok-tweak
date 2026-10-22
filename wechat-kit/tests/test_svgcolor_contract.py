#!/usr/bin/env python3
"""Static contracts for the SVG colour second-level UI. NOT UIKit execution."""
import argparse,re,unittest
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('--root',type=Path);a,rest=p.parse_known_args()
root=(a.root or Path(__file__).resolve().parents[1])
ui=(root/'src/WCKSVGColorViewController.m').read_text()
settings_page=(root/'src/WCKSettingsViewController.m').read_text()
palette=(root/'src/WCKSVGPalette.m').read_text()
selection=(root/'src/WCKSVGSelection.m').read_text()
settings=(root/'src/WCKSettings.m').read_text()

class SVGColorUIContract(unittest.TestCase):
 def test_second_level_page_exists(self):
  header=(root/'src/WCKSVGColorViewController.h').read_text()
  self.assertIn('@interface WCKSVGColorViewController : UITableViewController',header)
  self.assertIn('- (instancetype)initWithSettings:(WCKSettings *)settings',ui)
  # Fixed / palette switch plus per-icon stable palette selection.
  self.assertIn('@"固定颜色", @"随机色板"',ui)
  self.assertIn('svgUseFixedColor',ui)
  self.assertIn('svgPaletteHexes',ui)
  self.assertIn('svgRandomAlpha',ui)
  self.assertIn('UIColorPickerViewController',ui)

 def test_palette_editor_keeps_one_colour(self):
  self.assertIn('WCKSVGPaletteEditorViewController',ui)
  self.assertIn('self.colors.count <= 1',ui)
  self.assertIn('至少保留一个颜色',ui)
  self.assertIn('self.colors.count >= 32',ui)
  self.assertIn('WCKDefaultSVGPalette()',ui)

 def test_no_host_style_mutation(self):
  # Only per-item appearance; the host navigation bar must stay untouched.
  self.assertIn('self.navigationItem.standardAppearance = appearance',ui)
  self.assertNotIn('UINavigationBar.appearance',ui)
  self.assertNotIn('UIAppearance',ui)

 def test_settings_page_has_single_entry(self):
  self.assertIn("cell.textLabel.text = @\"配色与图标名单\"",settings_page)
  self.assertIn('WCKSVGColorViewController alloc] initWithSettings:self.settings',settings_page)
  # The four raw text rows must not remain on the first page.
  self.assertNotIn('@"浅色图标颜色"',settings_page)
  self.assertNotIn('@"深色图标颜色"',settings_page)

 def test_palette_is_deterministic(self):
  self.assertIn('2166136261u',palette)      # FNV-1a offset basis
  self.assertIn('16777619u',palette)
  self.assertNotIn('.hash',palette)

 def test_selection_keeps_gates_and_alpha(self):
  for s in ['svgRandomAlpha','WCKPaletteIndexForName','WCKSVGUnpack','MIN(1.0, MAX(0.2, alpha))']:
   self.assertIn(s,selection)
  self.assertIn('svgUseFixedColor',selection)

 def test_settings_validate_palette_and_alpha(self):
  self.assertIn('list.count == 0 || list.count > 32',settings)
  self.assertIn('CFBooleanGetTypeID',settings)
  self.assertIn('MIN(1.0, MAX(0.2, alpha))',settings)

if __name__=='__main__':unittest.main(argv=[__file__]+rest,verbosity=2)
