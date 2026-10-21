#!/usr/bin/env python3
"""Run the actual C policy; prove tests reject compiling defective variants."""
import json, subprocess, tempfile
from pathlib import Path
root=Path(__file__).resolve().parents[1]
source=(root/'src/WCKPolicy.c').read_text()
variants={
 'baseline':source,
 'mutant-version-bypass':source.replace('strcmp(version, "8.0.69") == 0 && strcmp(build, "8.0.69.33") == 0','true'),
 'mutant-empty-list-no-tint':source.replace('(!restricted || WCKNameInCSV(name, include)) && !WCKNameInCSV(name, exclude)','((void)restricted, WCKNameInCSV(name, include)) && !WCKNameInCSV(name, exclude)'),
 'mutant-ignore-exclusion':source.replace('&& !WCKNameInCSV(name, exclude)','&& ((void)exclude, true)'),
 'mutant-block-as-object':source.replace('return strcmp(actual, "@") == 0 ||','return actual[0] == \'@\' ||'),
}
results=[]
with tempfile.TemporaryDirectory(prefix='wck-policy-') as td:
    td=Path(td)
    for name,content in variants.items():
        src=td/(name+'.c');src.write_text(content);exe=td/name
        cmd=['clang','-std=c11','-Wall','-Wextra','-Werror','-I'+str(root/'src'),str(src),str(root/'tests/policy_test.c'),'-o',str(exe)]
        c=subprocess.run(cmd,capture_output=True,text=True,timeout=35)
        if c.returncode:raise RuntimeError(name+' failed to compile:\n'+c.stderr)
        r=subprocess.run([str(exe)],capture_output=True,text=True,timeout=20)
        expected=(r.returncode==0) if name=='baseline' else (r.returncode!=0)
        results.append(dict(name=name,compiled=True,returncode=r.returncode,expected=expected,
            output=r.stdout.strip() if name=='baseline' else 'defect rejected' if expected else 'DEFECT MISSED'))
        print(name,results[-1]['output'],flush=True)
        if not expected:raise RuntimeError('unexpected result: '+name)
(root/'evidence').mkdir(parents=True,exist_ok=True)
(root/'evidence/host-policy-tests.json').write_text(json.dumps(results,indent=2))
