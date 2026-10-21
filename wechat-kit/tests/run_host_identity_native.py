#!/usr/bin/env python3
"""Real production host gate + registry in a Foundation fixture, not real WeChat."""
from pathlib import Path
import json,subprocess,sys,tempfile
root=Path(__file__).resolve().parents[1]
if sys.platform!='darwin':
    print('SKIP: requires macOS Foundation runtime; NOT a passed test');raise SystemExit(77)
cases=['normal','display_default','display_wrong','wrong_build','wrong_version','wrong_identifier',
 'runtime_identifier_mismatch','wrong_executable_name','wrong_executable_path','non_file_url',
 'missing_then_ready','corrupt_then_ready','scalar_plist','numeric_version','missing_field','oversized','concurrent']
names=['WCKHostIdentity.m','WCKRuntime.m','WCKEntryRegistry.m','WCKSettings.m','WCKPolicy.c']
source={n:(root/'src'/n).read_text() for n in names}
variants={
 'baseline':{},
 'mutant-memory-version':{'WCKHostIdentity.m':('NSDictionary *identity = parsed;','NSDictionary *identity = bundle.infoDictionary;')},
 'mutant-unknown-build':{'WCKPolicy.c':('strcmp(version, "8.0.69") == 0 && strcmp(build, "8.0.69.33") == 0','(version && build)')},
 'mutant-cache-io-failure':{'WCKRuntime.m':('cached = readable;','cached = YES;')},
}
results=[]
with tempfile.TemporaryDirectory(prefix='wck-host-native-') as td:
    td=Path(td)
    for variant,changes in variants.items():
        folder=td/variant;folder.mkdir();paths=[]
        for name,body in source.items():
            if name in changes:
                old,new=changes[name];assert body.count(old)==1;body=body.replace(old,new)
            dest=folder/name;dest.write_text(body);paths.append(str(dest))
        exe=folder/'run'
        cmd=['xcrun','clang','-fobjc-arc','-fblocks','-Wall','-Wextra','-Werror','-Wno-unused-parameter',
             '-I'+str(root/'src'),*paths,str(root/'tests/WCKHostIdentityRegression.m'),'-framework','Foundation','-o',str(exe)]
        c=subprocess.run(cmd,capture_output=True,text=True,timeout=90)
        if c.returncode:raise RuntimeError(variant+' COMPILE FAILED:\n'+c.stderr)
        rows=[]
        for case in cases:
            r=subprocess.run([str(exe),case],capture_output=True,text=True,timeout=20)
            rows.append(dict(case=case,exit=r.returncode,stdout=r.stdout.strip(),stderr=r.stderr[:1500]))
        results.append(dict(variant=variant,compiled=True,cases=rows))
        (root/'evidence').mkdir(exist_ok=True)
        (root/'evidence/native-host-identity-tests.json').write_text(json.dumps(results,indent=2))
        if variant=='baseline':
            assert all(r['exit']==0 for r in rows),rows
            print('native real host gate + registry:',len(rows),'cases PASS',flush=True)
        else:
            assert any(r['exit']!=0 for r in rows),'mutant missed: '+variant
            print(variant,'COMPILED, runtime defect caught',flush=True)
