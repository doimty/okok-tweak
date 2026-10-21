#!/usr/bin/env python3
"""Production unread driver + fake services; no real unread mutation or UIKit."""
import json,subprocess,sys,tempfile
from pathlib import Path
r=Path(__file__).resolve().parents[1]
if sys.platform!='darwin':
 print('requires macOS Foundation; unread model NOT executed');raise SystemExit(77)
source=(r/'src/WCKReadAll.m').read_text()
variants={'baseline':source,
 'mutant-no-layout-bind':source.replace('WCKBindReadBar(bar); // MMTabBar only;', '(void)bar; // MMTabBar only;'),
 'mutant-no-size-bound':source.replace('[raw count] > 5000','[raw count] > 500000'),
 'mutant-no-account-check':source.replace('WCKService(center, @"CMessageMgr") != manager','NO'),
 'mutant-no-readback':source.replace('unsigned int after = ((unsigned int (*)(id,SEL,id))objc_msgSend)(manager, countSelector, name);','unsigned int after = 0;'),
}
cases=['normal','duplicate','replacement','layout_first','legacy','wrong_abi','nil_name','wrong_name','long_name','disabled','nonfirst','wrong_page','hidden','readback','switch_service','cancel','toggle','busy','large','no_begin']
rows=[]
with tempfile.TemporaryDirectory(prefix='wck-unread-') as td:
 td=Path(td)
 for name,body in variants.items():
  assert name=='baseline' or body!=source,'unchanged mutant'
  sp=td/(name+'.m');sp.write_text(body);exe=td/name
  cmd=['clang','-fobjc-arc','-fblocks','-framework','Foundation','-framework','CoreGraphics','-Wall','-Wextra','-Werror','-Wno-unused-parameter','-I'+str(r/'tests/fake-readall'),'-I'+str(r/'src'),str(sp),str(r/'src/WCKPolicy.c'),str(r/'tests/WCKReadAllModel.m'),'-o',str(exe)]
  c=subprocess.run(cmd,capture_output=True,text=True,timeout=90)
  assert c.returncode==0,(name,'COMPILE FAILED',c.stderr)
  runs=[]
  for case in cases:
   p=subprocess.run([str(exe),case],capture_output=True,text=True,timeout=15)
   runs.append(dict(case=case,exit=p.returncode,stdout=p.stdout,stderr=p.stderr))
  ok=all(x['exit']==0 for x in runs) if name=='baseline' else any(x['exit']!=0 for x in runs)
  rows.append(dict(variant=name,compiled=True,expected=ok,cases=runs,level='Foundation + fake services, not actual unread'))
  (r/'evidence').mkdir(exist_ok=True)
  (r/'evidence/native-readall-tests.json').write_text(json.dumps(rows,indent=2))
  print(name,str(len(runs))+' cases PASS' if name=='baseline' and ok else 'runtime defect caught' if ok else 'FAIL',flush=True)
  assert ok,(name,[x for x in runs if x['exit']!=0])
