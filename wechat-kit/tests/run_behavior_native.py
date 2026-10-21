#!/usr/bin/env python3
"""Run actual production keyboard/time/album in Foundation models, never a device."""
import json,os,subprocess,sys,tempfile
from pathlib import Path
r=Path(__file__).resolve().parents[1]
if sys.platform!='darwin':
 print('requires macOS Foundation; behavior model NOT executed');raise SystemExit(77)
original={n:(r/'src'/n).read_text() for n in ['WCKKeyboard.m','WCKMomentsTime.m','WCKAlbumSheet.m']}
variants={'baseline':{},
 'mutant-keyboard-controller':{'WCKKeyboard.m':original['WCKKeyboard.m'].replace('![controller isKindOfClass:chat]', 'NO')},
 'mutant-keyboard-no-layout':{'WCKKeyboard.m':original['WCKKeyboard.m'].replace('WCKBindKeyboard(host); // MMInputToolView only.', '(void)host; // MMInputToolView only.')},
 'mutant-time-no-restore':{'WCKMomentsTime.m':original['WCKMomentsTime.m'].replace('state.label.text = state.originalText;', '(void)state.originalText;')},
 'mutant-album-all-keys':{'WCKAlbumSheet.m':original['WCKAlbumSheet.m'].replace('[key isEqualToString:@"clicfg_chat_album_pagesheet_mode"]', 'YES')},
}
rows=[]
with tempfile.TemporaryDirectory(prefix='wck-behavior-') as td:
 td=Path(td)
 for name,changes in variants.items():
  d=td/name;d.mkdir()
  for n,body in original.items():
   text=changes.get(n,body)
   if n in changes:assert text!=body,'unchanged mutation'
   (d/n).write_text(text)
  exe=d/'behavior'
  cmd=['clang','-fobjc-arc','-fblocks','-framework','Foundation','-framework','CoreGraphics','-Wall','-Wextra','-Werror','-Wno-unused-parameter','-I'+str(r/'tests/fake-behavior'),'-I'+str(d),'-I'+str(r/'src'),str(r/'tests/WCKBehaviorModel.m'),str(r/'src/WCKPolicy.c'),str(r/'src/WCKSettings.m'),'-o',str(exe)]
  c=subprocess.run(cmd,capture_output=True,text=True,timeout=90)
  assert c.returncode==0,(name,'COMPILE FAILED',c.stderr)
  runs=[]
  for mode in (['normal','missing_adjust'] if name=='baseline' else ['normal']):
   home=d/mode;home.mkdir();env=dict(os.environ,HOME=str(home))
   p=subprocess.run([str(exe),mode],env=env,capture_output=True,text=True,timeout=20)
   runs.append(dict(case=mode,exit=p.returncode,stdout=p.stdout,stderr=p.stderr))
  ok=all(x['exit']==0 for x in runs) if name=='baseline' else any(x['exit']!=0 for x in runs)
  rows.append(dict(variant=name,compiled=True,expected=ok,cases=runs,level='Foundation/model, NOT UIKit/device'))
  (r/'evidence').mkdir(exist_ok=True)
  (r/'evidence/native-behavior-tests.json').write_text(json.dumps(rows,indent=2))
  print(name,'PASS' if name=='baseline' and ok else 'runtime defect caught' if ok else 'FAIL',flush=True)
  assert ok,(name,runs)
