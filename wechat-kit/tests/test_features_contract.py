#!/usr/bin/env python3
"""Source-only feature wiring contracts. Not a UIKit/WeChat behavioral test."""
from pathlib import Path
import unittest, plistlib, re
root=Path(__file__).resolve().parents[1]

def function_body(source, name):
    # Locate a real balanced function, not a historical comment delimiter.
    # Mask literals/comments without changing offsets so braces in them do not count.
    masked=re.sub(r'/\*.*?\*/|//[^\n]*|"(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\'',
                  lambda m: ''.join('\n' if c=='\n' else ' ' for c in m.group()),
                  source, flags=re.S)
    match=re.search(r'\b'+re.escape(name)+r'\s*\([^;{}]*\)\s*\{',masked)
    if not match:raise AssertionError('missing function '+name)
    start=match.end();depth=1
    for i in range(start,len(masked)):
        depth+=(masked[i]=='{')-(masked[i]=='}')
        if not depth:return source[start:i]
    raise AssertionError('unterminated function '+name)

class FeatureContracts(unittest.TestCase):
    def test_exact_host_bundle(self):
        p=plistlib.loads((root/'WeChatKit.plist').read_bytes())
        self.assertEqual(p['Filter']['Bundles'],['com.tencent.xin'])
    def test_enable_snapshot_and_state(self):
        src=(root/'src/WCKRuntime.m').read_text(encoding='utf-8')
        body=function_body(src,'WCKEnabled')
        self.assertIn('snapshot[@"enabled"]',body)
        self.assertIn('snapshot[feature]',body)
        self.assertNotIn('WCKHostIsSupported()',body)
        self.assertNotIn('WCKRuntimeStatuses()',body)
        self.assertNotIn('isEqualToString:@"ready"',body)
    def test_hook_checks_each_signature_field(self):
        src=(root/'src/WCKRuntime.m').read_text(encoding='utf-8')
        matcher=function_body(src,'WCKMethodMatches')
        self.assertIn('class_getInstanceMethod',matcher)
        self.assertIn('WCKSignatureMatches',matcher)
        signature=function_body(src,'WCKSignatureMatches')
        for call in ['method_getNumberOfArguments', 'method_copyReturnType',
                     'method_copyArgumentType', 'WCKTypeMatches']:
            self.assertIn(call,signature)
        self.assertNotIn('(void)returnType; (void)arguments; (void)count;',matcher+signature)
    def test_hook_void_api_and_honest_installation_status(self):
        src=(root/'src/WCKRuntime.m').read_text(encoding='utf-8')
        installer=function_body(src,'WCKInstallHook')
        self.assertNotIn('WCKHostIsSupported()',installer)
        self.assertIn('WCKMethodMatches(',installer)
        self.assertIn('dlsym(RTLD_DEFAULT, "MSHookMessageEx")',installer)
        self.assertRegex(src,r'typedef\s+void\s*\(\s*\*\s*WCKHookFunction\s*\)\s*\(Class,\s*SEL,\s*IMP,\s*IMP\s*\*\s*\);')
        for state in ['install_failed.signature_mismatch', 'hook_api_missing',
                      'attempted_unverified.postcondition_failed',
                      'attempted_unverified.original_imp_null',
                      'attempted_unverified.original_imp_recursive']:
            self.assertIn(state,installer)
        self.assertNotIn('method_setImplementation(',installer)
        self.assertNotIn('class_replaceMethod(',installer)
    def test_native_installer_executes_actual_runtime(self):
        runner=(root/'tests/run_runtime_installer_native.py').read_text(encoding='utf-8')
        fixture=(root/'tests/WCKRuntimeInstallerRegression.m').read_text(encoding='utf-8')
        for item in ['src/WCKRuntime.m', 'WCKPolicy.c', 'WCKRuntimeInstallerRegression.m',
                     '-Ddlsym=WCKRuntimeTestDlsym', 'UNSUPPORTED_ENV', 'RUNTIME ASSERT[']:
            self.assertIn(item,runner)
        self.assertNotIn('BOOL WCKMethodMatches(',fixture)
        self.assertNotIn('BOOL WCKInstallHook(',fixture)
    def test_original_chat_scroll_keyboard(self):
        src=(root/'src/WCKKeyboard.m').read_text(encoding='utf-8')
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
        src=(root/'src/WCKSVG.m').read_text(encoding='utf-8')
        policy=(root/'src/WCKPolicy.c').read_text(encoding='utf-8')
        self.assertIn('!restricted || WCKNameInCSV(name, include)',policy)
        for s in ['WCKSVGSelectPacked(WCKSettings.shared.snapshot, request.name,',
                  'NSMapTable mapTableWithKeyOptions:', 'WCKSVGNameScope',
                  'WCKSVGReplayStep', 'sFactoryDepth++ == 0']:
            self.assertIn(s,src)
        for s in ['setTintColor:', 'imageConfigWithTintColor:', 'NSURLSession',
                  'initWithCGImage:', 'imageWithTintColor:']:
            self.assertNotIn(s,src)
    def test_unread_only_action_and_bounded(self):
        src=(root/'src/WCKReadAll.m').read_text(encoding='utf-8')
        for s in ['UIGestureRecognizerStateBegan','self.busy','[raw count] > 5000',
                  'MIN(index + 16, names.count)','ClearUnRead:FromID:ToID:',
                  '(manager, clearSelector, name, 0, UINT32_MAX)',
                  'WCKServiceCenter() != center','tabBarItemViews','tabs.selectedIndex != 0',
                  'if (!after) ++cleared']:
            self.assertIn(s,src)
        for s in ['DeleteSession','DeleteMsgButKeepSession','RemoveMessages','NSLog(']:
            self.assertNotIn(s,src)
    def test_unread_native_entry_before_binding(self):
        src=(root/'src/WCKReadAll.m').read_text(encoding='utf-8')
        install=src.split('void WCKInstallReadAll(void)',1)[1]
        center=src.split('static id WCKServiceCenter(void)',1)[1].split('static id WCKService(',1)[0]
        self.assertIn('Class center = WCKReadContextEntry(&entry);',install)
        self.assertIn('WCKMethodMatches(object_getClass(center), entry,',install)
        self.assertIn('Class cls = WCKReadContextEntry(&selector);',center)
        self.assertNotIn('objc_msgSend',install)
        self.assertIn('NSSelectorFromString(@"currentContext")',src)
    def test_no_phony_unimplemented(self):
        src=(root/'src/WCKVerifiedFeatures.m').read_text(encoding='utf-8')
        self.assertIn('WCKInstallReadAll()',src)
        self.assertNotIn('@"ready"',src)
        self.assertIn('WCKInstallAlbumSheet()',src)
        self.assertIn('WCKInstallMomentsTime()',src)
        self.assertIn('noHotUpdate',src)
    def test_preserves_settings_bar(self):
        src=(root/'src/WCKEntryUI.m').read_text(encoding='utf-8')
        self.assertNotIn('rightBarButton',src)
        self.assertNotIn('UIBarButtonItem',src)
        self.assertIn('WCKAddSettingsRow(host, driver)',src)
        self.assertIn('sLoadReady || sWillReady || sDidReady || sReloadReady',src)
        self.assertNotIn('loaded && appeared',src)
        self.assertNotIn('WCKHostIsSupported()',src)
        bootstrap=(root/'src/WCKBootstrap.m').read_text(encoding='utf-8')
        self.assertNotIn('if (!WCKHostIsSupported()) return;',bootstrap)
        self.assertLess(bootstrap.index('WCKInstallEntryPoints();'),bootstrap.index('WCKInstallKeyboard();'))
    def test_independent_runtime(self):
        src='\n'.join(p.read_text(encoding='utf-8') for p in (root/'src').glob('*') if p.suffix in ('.h','.c','.m'))
        for forbidden in ['WCRefine','WCPulse','WeX','https://','NSURLConnection',
                          'NSURLSession','dlopen(', 'frida','system(', 'sbreload']:
            self.assertNotIn(forbidden,src)
if __name__=='__main__':unittest.main(verbosity=2)
