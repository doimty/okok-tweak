#!/usr/bin/env python3
"""Source-only SVG regressions, not a UIKit/WeChat runtime test.

Run: python3 tests/test_svg_contract.py
Optional --source PATH checks an older source or isolated mutation.
"""
from pathlib import Path
import argparse
import re
import unittest

parser = argparse.ArgumentParser()
parser.add_argument('--source', type=Path)
args, remaining = parser.parse_known_args()
root = Path(__file__).resolve().parents[1]
source = (args.source or root / 'src/WCKSVG.m').read_text()


def body(name):
    match = re.search(r'\b' + re.escape(name) + r'\([^;]*?\)\s*\{', source)
    if not match:
        raise AssertionError('missing function: ' + name)
    start = match.end()
    depth = 1
    for pos in range(start, len(source)):
        depth += (source[pos] == '{') - (source[pos] == '}')
        if not depth:
            return source[start:pos]
    raise AssertionError('unterminated function: ' + name)


class SVGContracts(unittest.TestCase):
    def test_independent_actual_abi_factories(self):
        install = body('WCKInstallSVG')
        for selector, hook in [
            ('imageNamed:size:color:alpha:rotate:', 'WCKSVGNamed'),
            ('imageWithContentsOfFile:size:color:alpha:rotate:', 'WCKSVGFile'),
            ('imageNamed:fromConfig:', 'WCKSVGConfig'),
            ('adaptedWeSVGImageWithName:data:config:', 'WCKSVGAdapted'),
            ('imageData:fromConfig:', 'WCKSVGData'),
        ]:
            self.assertIn('@"' + selector + '"', install)
            self.assertIn('(IMP)' + hook, install)
        self.assertIn('named || file || config || adapted || data', install)
        self.assertNotIn('named && config', install)
        self.assertIn('@encode(CGSize)', install)
        self.assertIn('@encode(UIControlState)', install)
        self.assertIn('"@", "d", "d"', install)
        self.assertIn('"@", "@", "@"', install)

    def test_original_parameters_and_depth_finally(self):
        self.assertIn('static _Thread_local NSUInteger sFactoryDepth', source)
        expected = {
            'Named': 'name, size, color, alpha, rotate',
            'File': 'file, size, color, alpha, rotate',
            'Config': 'name, config',
            'Adapted': 'name, data, config',
            'Data': 'data, config',
        }
        for suffix, arguments in expected.items():
            code = body('WCKSVG' + suffix)
            self.assertIn('sFactoryDepth++ == 0', code)
            self.assertIn('sOriginal' + suffix + '(cls, cmd, ' + arguments + ')', code)
            self.assertIn('@finally { --sFactoryDepth; }', code)
            self.assertIn('return top ? WCKSVGRecord', code)
            self.assertNotIn('@catch', code)
        self.assertNotIn('setTintColor:', source)
        self.assertNotIn('imageConfigWithTintColor:', source)

    def test_only_tagged_independent_bitmap_and_no_source_cycle(self):
        record = body('WCKSVGRecord')
        self.assertIn('isKindOfClass:UIImage.class', record)
        self.assertIn('!source.CGImage || source.images.count', record)
        self.assertIn('existing ? existing.source : result', record)
        self.assertIn('descriptor.source = source', record)
        self.assertIn('@"<svg-data>"', record)
        self.assertNotIn('WCKEnabled', record)
        self.assertIn('NSThread.isMainThread', record)
        self.assertIn('initWithCGImage:source.CGImage', body('WCKSVGCopy'))
        self.assertIn('scale:source.scale orientation:source.imageOrientation', body('WCKSVGCopy'))
        for member in ['capInsets', 'resizingMode', 'alignmentRectInsets', 'renderingMode']:
            self.assertIn('source.' + member, body('WCKSVGCopy'))
        render = body('WCKSVGRender')
        self.assertIn('Keep provenance even when disabled', render)
        self.assertIn('imageWithTintColor:color renderingMode:UIImageRenderingModeAlwaysOriginal', render)
        self.assertIn('objc_setAssociatedObject(image, &sDescriptorKey, descriptor', render)
        self.assertNotIn('objc_setAssociatedObject(source', source)
        self.assertIn('@catch', render)

    def test_real_permission_and_view_trait_selection(self):
        render = body('WCKSVGRender')
        self.assertIn('WCKEnabled(@"svgTint")', render)
        self.assertIn('WCKSVGSelectRGB(WCKSettings.shared.snapshot, descriptor.name,', render)
        self.assertIn('traits.userInterfaceStyle == UIUserInterfaceStyleDark', render)
        self.assertIn('view.traitCollection', body('WCKPrepareImage'))
        self.assertIn('view.traitCollection', body('WCKRefreshSVGView'))
        self.assertNotIn('setObject:', source)

    def test_weak_bounded_reversible_views(self):
        self.assertIn('@property(nonatomic, weak) UIView *host', source)
        self.assertIn('[NSHashTable weakObjectsHashTable]', source)
        self.assertIn('WCKSVGMaximumButtonStates = 32', source)
        prepare = body('WCKPrepareImage')
        self.assertIn('WCKDescriptor(image)', prepare)
        self.assertIn('if (!driver) return image', prepare)
        self.assertIn('return descriptor.source', prepare)
        self.assertIn('[driver.states removeObjectForKey:key]', prepare)
        self.assertIn('objc_setAssociatedObject(view, &sDriverKey, nil', body('WCKTrack'))
        install = body('WCKInstallSVG')
        for selector in ['setImage:', 'setHighlightedImage:', 'setImage:forState:', 'traitCollectionDidChange:']:
            self.assertIn('@selector(' + selector + ')', install)
        self.assertIn('WCKSettingsDidChangeNotification', install)
        self.assertIn('queue:NSOperationQueue.mainQueue', install)
        self.assertIn('sSVGViews.allObjects', install)
        self.assertIn('可重新打开页面', install)
        for forbidden in ['layoutSubviews', 'subviews', 'NSURLSession', 'NSLog(', 'setTintColor:']:
            self.assertNotIn(forbidden, source)
        for hook, original in [('SetImage', 'Image'), ('SetHighlighted', 'Highlighted'), ('SetButton', 'Button')]:
            code = body('WCKSVG' + hook)
            self.assertIn('sOriginal' + original + '(view, cmd, next', code)
            self.assertIn('@finally { --sViewDepth; }', code)
        for suffix in ['Image', 'Button']:
            code = body('WCKSVG' + suffix + 'Trait')
            self.assertLess(code.index('sOriginal' + suffix + 'Trait'), code.index('WCKRefreshSVGView'))


if __name__ == '__main__':
    unittest.main(argv=['test_svg_contract.py'] + remaining, verbosity=2)
