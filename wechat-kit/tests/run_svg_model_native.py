#!/usr/bin/env python3
"""Execute production SVG code with a deterministic fake UIKit, NOT pixel/UI tests."""
import json,os,subprocess,sys,tempfile
from pathlib import Path
if sys.platform!='darwin':
 print('requires macOS Foundation; model NOT executed');raise SystemExit(77)
r=Path(__file__).resolve().parents[1];source=(r/'src/WCKSVG.m').read_text()
variants={
 'baseline':source,
 'mutant-drop-provenance':source.replace('(void)factory;', 'if (!tint && !factory) return source;'),
 'mutant-no-settings-refresh':source.replace('for (UIView *view in sSVGViews.allObjects) WCKRefreshSVGView(view);','for (UIView *view in sSVGViews.allObjects) (void)view;'),
 'mutant-ignore-carrier-dark':source.replace('view.traitCollection','UITraitCollection.currentTraitCollection'),
 'mutant-no-transform-provenance':source.replace('return WCKSVGRecord(result, descriptor.name)', 'return result'),
 'mutant-no-short-factory':source.replace('BOOL simple = WCKInstallHook','BOOL simple = NO && WCKInstallHook')}
results=[]
with tempfile.TemporaryDirectory(prefix='wck-svg-model-') as td:
 td=Path(td)
 for name,src in variants.items():
  assert name=='baseline' or src!=source,'mutation unchanged'
  sp=td/'svg.m';sp.write_text(src);exe=td/name
  cmd=['clang','-fobjc-arc','-fblocks','-framework','Foundation','-framework','CoreGraphics','-Wall','-Wextra','-Werror','-Wno-unused-parameter','-I'+str(r/'tests/fake-uikit'),'-I'+str(r/'src'),str(sp)]
  cmd += [str(r/p) for p in ['src/WCKPolicy.c','src/WCKSettings.m','src/WCKSVGSelection.m','tests/WCKSVGModel.m']]
  cmd += ['-o',str(exe)]
  c=subprocess.run(cmd,capture_output=True,text=True,timeout=120)
  assert c.returncode==0,(name,c.stderr)
  home=td/(name+'-home')
  home.mkdir();env=dict(os.environ,HOME=str(home))
  p=subprocess.run([str(exe)],env=env,capture_output=True,text=True,timeout=30)
  ok=p.returncode==0 if name=='baseline' else p.returncode!=0
  results.append(dict(variant=name,compiled=True,exit=p.returncode,expected=ok,stdout=p.stdout,stderr=p.stderr,level='Foundation + test-only UIKit model, not pixels'))
  print(name,p.stdout.strip() if name=='baseline' else 'runtime defect caught' if ok else 'MISSED',flush=True)
  assert ok,(name,p.stdout,p.stderr)
(r/'evidence').mkdir(exist_ok=True)
(r/'evidence/native-svg-model-tests.json').write_text(json.dumps(results,indent=2))
