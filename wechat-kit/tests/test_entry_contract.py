#!/usr/bin/env python3
"""Entry wiring contracts only; native registry behavior is tested separately."""
import unittest
from pathlib import Path
root=Path(__file__).resolve().parents[1]
ui=(root/'src/WCKEntryUI.m').read_text()
registry=(root/'src/WCKEntryRegistry.m').read_text()
bootstrap=(root/'src/WCKBootstrap.m').read_text()
class EntryContracts(unittest.TestCase):
    def test_registration_has_no_master_dependency(self):
        for src in [ui,registry,bootstrap]:
            self.assertNotIn('WCKEnabled(',src)
            self.assertNotIn('boolForKey:',src)
        self.assertIn('WCPluginsMgr',registry)
        self.assertIn('registerControllerWithTitle:version:controller:',registry)
        self.assertIn('"v", args, 3',registry)
    def test_no_linked_lifecycle_gate(self):
        self.assertIn('sLoadReady || sWillReady || sDidReady || sReloadReady',ui)
        self.assertNotIn('sSettingsHookReady',ui+bootstrap)
        for ready in ['sLoadReady','sWillReady','sDidReady','sReloadReady','sHubReady']:
            self.assertIn('if (!'+ready+')',ui)
    def test_snapshot_order(self):
        body=ui.split('static void WCKHubLoaded(',1)[1].split('void WCKInstallEntryPoints',1)[0]
        self.assertLess(body.index('WCKRegisterPluginEntry();'),body.index('sHubLoad(host, selector)'))
    def test_bounded_retry(self):
        self.assertIn('@[@0.25, @1.0, @3.0]',bootstrap)
        self.assertIn('UIApplicationDidBecomeActiveNotification',bootstrap)
        self.assertIn('__weak UIViewController *weakHost',ui)
        self.assertNotIn('NSTimer',bootstrap+ui)
    def test_row_and_navigation_are_independent(self):
        self.assertIn('WCKAddNavigationEntry(host, driver);',ui)
        self.assertIn('WCKAddSettingsRow(host, driver);',ui)
        self.assertIn('[sections containsObject:driver.section]',ui)
        self.assertIn('driver.updating',ui)
        self.assertNotIn('setValue:',ui)
        self.assertIn('ivar_getTypeEncoding',ui)
        self.assertIn('class_getInstanceVariable',ui)
    def test_registration_readback_and_reentry(self):
        self.assertIn('NSArray *before = WCKReadHubPlugins(hub);',registry)
        self.assertIn('NSArray *after = WCKReadHubPlugins(hub);',registry)
        self.assertIn('@finally { sRegistrationInProgress = NO; }',registry)
        self.assertIn('[value count] > 2048',registry)
    def test_build_metadata_and_native_test(self):
        self.assertIn('Version: 0.1.0-alpha4',(root/'control').read_text())
        self.assertIn('src/WCKEntryRegistry.m src/WCKEntryUI.m',(root/'Makefile').read_text())
        self.assertIn('"0.1.0-alpha4"',registry)
        native=(root/'tests/run_entry_native.py').read_text()
        for x in ['COMPILE FAILED','wrong_abi','absent_then_late','mutant-no-registration','mutant-no-dedupe']:
            self.assertIn(x,native)
if __name__=='__main__':unittest.main(verbosity=2)
