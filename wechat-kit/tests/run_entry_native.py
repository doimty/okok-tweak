#!/usr/bin/env python3
"""Native Foundation tests of production registry; fake host, NOT real WeChat/UIKit."""
import json,subprocess,sys,tempfile
from pathlib import Path
root=Path(__file__).resolve().parents[1]
if sys.platform!='darwin':
    print('SKIP: native Foundation runtime requires macOS; not counted as passed')
    raise SystemExit(77)
cases=['normal','duplicate','preserve_neighbor','existing','absent_then_late','nil_then_ready',
       'invalid_list','unreadable_model','readback_failure','partial_throw','unsupported','background','wrong_abi']
source=(root/'src/WCKEntryRegistry.m').read_text()
call='((void (*)(id, SEL, id, id, id))objc_msgSend)(hub, registration,\n            @"WeChatKit", @"0.1.0-alpha6", WCKControllerName);'
assert source.count(call)==1
variants={
 'baseline':source,
 'mutant-no-registration':source.replace(call,'(void)registration;'),
 'mutant-no-dedupe':source.replace('if (WCKHubContainsController(before, &readable)) {','if (WCKHubContainsController(before, &readable) && NO) {'),
 'mutant-Class-not-NSString':source.replace('0.1.0-alpha6", WCKControllerName);','0.1.0-alpha6", (id)NSClassFromString(WCKControllerName));'),
}
results=[]
with tempfile.TemporaryDirectory(prefix='wck-native-entry-') as td:
    td=Path(td)
    for name,body in variants.items():
        src=td/(name+'.m');src.write_text(body);exe=td/name
        cmd=['xcrun','clang','-fobjc-arc','-fblocks','-Wall','-Wextra','-Werror','-Wno-unused-parameter',
            '-I'+str(root/'src'),str(src),str(root/'src/WCKPolicy.c'),
            str(root/'tests/WCKEntryRegistryRegression.m'),'-framework','Foundation','-o',str(exe)]
        c=subprocess.run(cmd,capture_output=True,text=True,timeout=90)
        if c.returncode:raise RuntimeError(name+' COMPILE FAILED: '+c.stderr)
        runs=[]
        for case in cases:
            r=subprocess.run([str(exe),case],capture_output=True,text=True,timeout=15)
            runs.append(dict(case=case,exit=r.returncode,stdout=r.stdout.strip(),stderr=r.stderr[:1200]))
        if name=='baseline':
            assert all(x['exit']==0 for x in runs),runs
            print('native Foundation registry:',len(runs),'cases PASS',flush=True)
        else:
            assert any(x['exit']!=0 for x in runs),'mutant missed: '+name
            print(name,'COMPILED, runtime defect caught',flush=True)
        results.append(dict(variant=name,compiled=True,cases=runs))
(root/'evidence').mkdir(exist_ok=True)
(root/'evidence/native-entry-tests.json').write_text(json.dumps(results,indent=2))
