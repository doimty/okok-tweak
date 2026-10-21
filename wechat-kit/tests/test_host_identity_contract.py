import unittest
from pathlib import Path
r=Path(__file__).resolve().parents[1]
class HostIdentityContract(unittest.TestCase):
    def test_no_display_metadata(self):
        s=(r/'src/WCKHostIdentity.m').read_text()
        self.assertNotIn('infoDictionary',s)
        self.assertNotIn('objectForInfoDictionaryKey',s)
        self.assertIn('NSPropertyListSerialization propertyListWithData:data',s)
        self.assertIn('WCKHostMatches(identifier.UTF8String, version.UTF8String, build.UTF8String)',s)
    def test_main_bundle_and_cache(self):
        s=(r/'src/WCKRuntime.m').read_text()
        self.assertIn('WCKHostMatchesBundle(NSBundle.mainBundle, &readable)',s)
        self.assertIn('cached = readable;',s)
        self.assertIn('[identityLock lock]',s)
        self.assertIn('@finally { [identityLock unlock]; }',s)
        self.assertIn('supported = NO; cached = NO;',s)
    def test_file_and_identity_boundaries(self):
        s=(r/'src/WCKHostIdentity.m').read_text()
        for x in ['base.isFileURL','executable.isFileURL','1024 * 1024',
                  'isKindOfClass:NSDictionary.class','isKindOfClass:NSString.class',
                  'bundle.bundleIdentifier','isEqualToString:@"WeChat"','URLByResolvingSymlinksInPath',
                  'expectedPath isEqualToString:actualPath']:
            self.assertIn(x,s)
    def test_no_weakened_exact_policy(self):
        s=(r/'src/WCKPolicy.c').read_text()
        for x in ['strcmp(bundle, "com.tencent.xin") == 0','strcmp(version, "8.0.69") == 0',
                  'strcmp(build, "8.0.69.33") == 0']:
            self.assertIn(x,s)
    def test_regression_end_to_end(self):
        s=(r/'tests/run_host_identity_native.py').read_text()
        for x in ['WCKRuntime.m','WCKHostIdentity.m','WCKEntryRegistry.m','WCKSettings.m',
                  'display_default','wrong_build','missing_then_ready','corrupt_then_ready',
                  'mutant-memory-version','mutant-unknown-build','mutant-cache-io-failure']:
            self.assertIn(x,s)
if __name__=='__main__':unittest.main(verbosity=2)
