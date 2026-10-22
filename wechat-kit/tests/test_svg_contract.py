#!/usr/bin/env python3
"""Static SVG parameter-route contracts. NOT Foundation/UIKit/WeChat execution."""
import argparse,re,unittest
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('--source',type=Path);a,rest=p.parse_known_args()
r=Path(__file__).resolve().parents[1];source=(a.source or r/'src/WCKSVG.m').read_text()
def body(name):
 m=re.search(r'\b'+re.escape(name)+r'\([^;]*?\)\s*\{',source)
 if not m:raise AssertionError('missing function '+name)
 start=m.end();depth=1
 for i in range(start,len(source)):
  depth+=(source[i]=='{')-(source[i]=='}')
  if not depth:return source[start:i]
 raise AssertionError('unterminated '+name)
class SVGParameterContract(unittest.TestCase):
 def test_canonical_abi_not_same_shape(self):
  for s in ['MMThemeManager','WeSVGVM','WeSVGEngine','svgImageNamed:size:color:alpha:angle:ignoreNotFound:','imageWithName:size:scale:rotation:opacity:color:','imageWithData:size:scale:rotation:opacity:color:']:
   self.assertIn('@"'+s+'"',source)
  self.assertIn('double, int, BOOL',source);self.assertIn('double, double, double, id',source)
 def test_no_image_rebuild_or_post_tint(self):
  code=re.sub(r'//[^\n]*','',source)
  for s in ['CGImage','imageWithTintColor:','initWithCGImage:','UIGraphics','setFrame:','setContentMode:','UIImageRenderingModeAlwaysTemplate','UIImageRenderingModeAlwaysOriginal']:
   self.assertNotIn(s,code)
 def test_factory_preserves_arguments_and_result(self):
  call=body('WCKSVGCall')
  self.assertIn('payload, size, color, opacity, angle, ignore',call)
  self.assertIn('payload, size, scale, rotation, opacity, color',call)
  factory=body('WCKSVGFactory');self.assertIn('sFactoryDepth++ == 0',factory);self.assertIn('@finally { --sFactoryDepth; }',factory)
  self.assertIn('return result;',factory);self.assertIn('if (!result && tinted)',factory)
  self.assertIn('NSThread.isMainThread && WCKSVGChoose',factory)
 def test_names_survive_data_route(self):
  for fn in ['WCKSVGConfig','WCKSVGFile','WCKSVGAdapted']:self.assertIn('WCKSVGNameScope',body(fn))
  scope=body('WCKSVGNameScope');self.assertIn('if (!previous)',scope);self.assertIn('@finally { sScopeName = previous; }',scope)
  self.assertIn('sScopeName = (__bridge void *)held;',scope)
 def test_weak_image_external_provenance(self):
  self.assertIn('NSPointerFunctionsWeakMemory | NSPointerFunctionsObjectPointerPersonality',source)
  self.assertIn('weak, readonly) id receiver',source);self.assertIn('weak) UIImage *last',source)
  self.assertIn('old.ambiguous',body('WCKSVGStore'))
  self.assertNotRegex(source,r'objc_setAssociatedObject\((?:image|source|result),')
 def test_only_actual_caller_transforms_replay(self):
  transform=body('WCKSVGTransform');self.assertIn('if (input && !input.ambiguous)',transform)
  self.assertNotIn('if (result == image) return result;',transform)
  self.assertIn('WCKSVGStep *last = input.steps.lastObject;',transform)
  self.assertIn('last.operation == operation && last.mode == mode',transform)
  self.assertIn('UIEdgeInsetsEqualToEdgeInsets(last.insets, insets)',transform)
  self.assertIn('!sFactoryDepth && !sTransformDepth',transform);self.assertIn('@finally { --sTransformDepth; }',transform)
  replay=body('WCKSVGReplayStep')
  for s in ['imageWithRenderingMode:','resizableImageWithCapInsets:','imageWithAlignmentRectInsets:']:self.assertIn(s,replay)
  self.assertNotIn('sOriginal',replay)
 def test_carrier_traits_and_external_replacement(self):
  self.assertIn('[view traitCollection]',source)
  self.assertIn('for (UIView *view in sSVGViews.allObjects) WCKRefreshSVGView(view);',source)
  self.assertIn('NSHashTable weakObjectsHashTable',source)
  self.assertIn('[(UIImageView *)view setImage:next]',source)
  self.assertIn('[(UIButton *)view setImage:next forState:state]',source)
  self.assertIn('slot.last',source)
 def test_bounded_publication_refuses_unknown_stamp(self):
  store=body('WCKSVGStore')
  self.assertIn('attempt = 0; attempt < 3; ++attempt',store)
  self.assertNotIn('for (;;)',store)
  self.assertIn('removeObjectForKey:image',store)
  self.assertIn('old.ambiguous || (!same && !compatible)',store)
  self.assertIn('WCKSVGStepsPrefix',body('WCKSVGStore'))
  self.assertIn('stamp.steps.count > old.steps.count ? stamp : old',store)
  self.assertIn('a == b || (a != a && b != b)',source)
  self.assertIn('sConflictedImages = [NSHashTable hashTableWithOptions:',source)
  self.assertIn('[sConflictedImages containsObject:image]',body('WCKSVGLookup'))
  self.assertIn('[sConflictedImages containsObject:image]',store)
  self.assertIn('[sConflictedImages addObject:image]',store)
  self.assertIn('WCKSVGDiagnostic(@"contention",',store)
  self.assertNotIn('initWithRequest:nil steps:@[]',store)
  self.assertNotIn('return WCKSVGLookup(image)',store)
 def test_initial_assignment_checks_entry_not_argument(self):
  setter=body('WCKSVGSet')
  self.assertIn('entryImage = WCKSVGCurrent(view, kind, state)',setter)
  self.assertIn('WCKSVGCurrent(view, kind, state) != entryImage',setter)
  self.assertIn('if (superseded || scope.superseded)',setter)
  self.assertIn('sAssignmentScope->superseded = YES;',setter)
  self.assertIn('sAssignmentScope = previousScope; --sViewDepth;',setter)
 def test_slot_replay_adopts_only_exact_prefix(self):
  owned=body('WCKSVGOwnedStamp')
  self.assertIn('current != slot.last',owned)
  self.assertIn('theirs.count < mine.count',owned)
  self.assertIn('UIEdgeInsetsEqualToEdgeInsets(x.insets, y.insets)',owned)
  self.assertIn('return observed;',owned)
  refresh=body('WCKSVGRefreshSlot')
  self.assertIn('WCKSVGOwnedStamp(current, slot)',refresh)
  self.assertIn('WCKSVGRender(owned, current',refresh)
  # A recipe appended during replay must abort the assignment instead of being
  # overwritten by the stale one, and a transient conflict must keep the slot.
  self.assertIn('WCKSVGStamp *latest = WCKSVGOwnedStamp(current, slot);',refresh)
  self.assertIn('latest != owned',refresh)
  self.assertIn('if (!current || current != slot.last) WCKSVGPutSlot',refresh)
  self.assertNotIn('WCKSVGStillOwned',source)
 def test_selection_remains_global_and_reversible(self):
  self.assertIn('WCKEnabled(@"svgTint")',source);self.assertIn('WCKSVGSelectRGB(WCKSettings.shared.snapshot, request.name,',source)
  self.assertIn('traits.userInterfaceStyle == UIUserInterfaceStyleDark',source)
  self.assertIn('id color = tinted ? WCKSVGColor(rgb) : r.color;',source)
if __name__=='__main__':unittest.main(argv=[__file__]+rest,verbosity=2)
