#!/usr/bin/env python3
"""Source-only feature wiring contracts. Not a UIKit/WeChat behavioral test."""
from pathlib import Path
import unittest, plistlib
root=Path(__file__).resolve().parents[1]
class FeatureContracts(unittest.TestCase):
    def test_exact_host_bundle(self):
        p=plistlib.loads((root/'WeChatKit.plist').read_bytes())
        self.assertEqual(p['Filter']['Bundles'],['com.tencent.xin'])
    def test_enable_snapshot_and_state(self):
        src=(root/'src/WCKRuntime.m').read_text()
        body=src.split('BOOL WCKEnabled(',1)[1].split('BOOL WCKMethodMatches(',1)[0]
        for phrase in ['WCKHostIsSupported()', 'WCKRuntimeStatuses()[feature]', 'isEqualToString:@"ready"',
                       'snapshot[@"enabled"]', 'snapshot[feature]']:
            self.assertIn(phrase,body)
    def test_hook_fail_original(self):
        src=(root/'src/WCKRuntime.m').read_text()
        self.assertLess(src.index('*original = fallback;'),src.index('hook(cls, selector, replacement, original);'))
        self.assertIn('if (!*original) { *original = fallback; return NO; }',src)
        self.assertIn('method_getNumberOfArguments(method) != count + 2',src)
    def test_original_chat_scroll_keyboard(self):
        src=(root/'src/WCKKeyboard.m').read_text()
        for s in ['NSClassFromString(@"BaseMsgContentViewController")',
                  'scrollViewWillEndDragging:withVelocity:targetContentOffset:',
                  '@encode(CGPoint)', '@encode(CGPoint *)', 'content - 10.0', 'velocity.y > 0.15',
                  '30 * NSEC_PER_MSEC', 'CGFloat stop = target ? target->y : offset;',
                  'NSSelectorFromString(@"textView")',
                  '[currentText becomeFirstResponder]', 'epoch != sKeyboardEpoch',
                  'currentText != weakText']:
            self.assertIn(s,src)
        self.assertEqual(src.count('sOriginalKeyboardDrag(vc, cmd, scroll, velocity, target);'),1)
        self.assertLess(src.index('sOriginalKeyboardDrag(vc, cmd, scroll, velocity, target);'),
                        src.index('WCKKeyboardVisible(vc, scroll)'))
        for forbidden in ['setValue:', 'UISwipeGestureRecognizer', 'addGestureRecognizer:']:
            self.assertNotIn(forbidden,src)
    def test_svg_global_source_and_no_caller_mutation(self):
        src=(root/'src/WCKSVG.m').read_text()
        policy=(root/'src/WCKPolicy.c').read_text()
        self.assertIn('!restricted || WCKNameInCSV(name, include)',policy)
        for s in ['WCKSVGSelectPacked(WCKSettings.shared.snapshot, request.name,',
                  'NSMapTable mapTableWithKeyOptions:', 'WCKSVGNameScope',
                  'WCKSVGReplayStep', 'sFactoryDepth++ == 0']:
            self.assertIn(s,src)
        for s in ['setTintColor:', 'imageConfigWithTintColor:', 'NSURLSession',
                  'initWithCGImage:', 'imageWithTintColor:']:
            self.assertNotIn(s,src)
    def test_unread_only_action_and_bounded(self):
        src=(root/'src/WCKReadAll.m').read_text()
        for s in ['UIGestureRecognizerStateBegan','self.busy','[raw count] > 5000',
                  'MIN(index + 16, names.count)','ClearUnRead:FromID:ToID:',
                  '(manager, clearSelector, name, 0, UINT32_MAX)',
                  'WCKServiceCenter() != center','tabBarItemViews','tabs.selectedIndex != 0',
                  'if (!after) ++cleared']:
            self.assertIn(s,src)
        for s in ['DeleteSession','DeleteMsgButKeepSession','RemoveMessages','NSLog(']:
            self.assertNotIn(s,src)
    def test_unread_native_entry_before_binding(self):
        src=(root/'src/WCKReadAll.m').read_text()
        install=src.split('void WCKInstallReadAll(void)',1)[1]
        center=src.split('static id WCKServiceCenter(void)',1)[1].split('static id WCKService(',1)[0]
        self.assertIn('Class center = WCKReadContextEntry(&entry);',install)
        self.assertIn('WCKMethodMatches(object_getClass(center), entry,',install)
        self.assertIn('Class cls = WCKReadContextEntry(&selector);',center)
        self.assertNotIn('objc_msgSend',install)
        self.assertIn('NSSelectorFromString(@"currentContext")',src)
    def test_no_phony_unimplemented(self):
        src=(root/'src/WCKVerifiedFeatures.m').read_text()
        self.assertIn('WCKInstallReadAll()',src)
        self.assertNotIn('@"ready"',src)
        self.assertIn('WCKInstallAlbumSheet()',src)
        self.assertIn('WCKInstallMomentsTime()',src)
        self.assertIn('noHotUpdate',src)
    def test_preserves_settings_bar(self):
        src=(root/'src/WCKEntryUI.m').read_text()
        self.assertNotIn('rightBarButton',src)
        self.assertNotIn('UIBarButtonItem',src)
        self.assertIn('WCKAddSettingsRow(host, driver)',src)
        self.assertIn('sLoadReady || sWillReady || sDidReady || sReloadReady',src)
        self.assertNotIn('loaded && appeared',src)
        bootstrap=(root/'src/WCKBootstrap.m').read_text()
        self.assertIn('if (!WCKHostIsSupported()) return;',bootstrap)
        self.assertLess(bootstrap.index('WCKInstallEntryPoints();'),bootstrap.index('WCKInstallKeyboard();'))
    def test_independent_runtime(self):
        src='\n'.join(p.read_text() for p in (root/'src').glob('*') if p.suffix in ('.h','.c','.m'))
        for forbidden in ['WCRefine','WCPulse','WeX','https://','NSURLConnection',
                          'NSURLSession','dlopen(', 'frida','system(', 'sbreload']:
            self.assertNotIn(forbidden,src)
if __name__=='__main__':unittest.main(verbosity=2)
