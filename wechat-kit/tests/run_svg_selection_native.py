#!/usr/bin/env python3
"""macOS Foundation execution of real SVG selection+settings; no UIKit/device claims."""
import json,subprocess,tempfile,sys
from pathlib import Path
if sys.platform!='darwin':
    print('requires macOS Foundation; not executed on this Linux host');raise SystemExit(77)
r=Path(__file__).resolve().parents[1];selection=(r/'src/WCKSVGSelection.m').read_text();policy=(r/'src/WCKPolicy.c').read_text()
variants={
 'baseline':(selection,policy),
 'mutant-master-bypass':(selection.replace('![master boolValue]','NO'),policy),
 'mutant-light-used-in-dark':(selection.replace('dark ? @"svgTintDark" : @"svgTintLight"','dark ? @"svgTintLight" : @"svgTintLight"'),policy),
 'mutant-old-empty-list':(selection,policy.replace('(!restricted || WCKNameInCSV(name, include))','((void)restricted, WCKNameInCSV(name, include))')),
 'mutant-palette-fixed-slot':(selection.replace('NSUInteger slot = WCKPaletteIndexForName(name, palette.count);','NSUInteger slot = 0; (void)name;'),policy),
 'mutant-alpha-ignored':(selection.replace('alpha = WCKSVGRandomAlpha(settings);','alpha = (WCKSVGRandomAlpha(settings), 1.0);'),policy),
 'mutant-palette-no-default':(selection.replace('return palette.count ? palette : WCKDefaultSVGPalette();','return palette;'),policy),
 'mutant-fixed-flag-ignored':(selection.replace('BOOL fixed = ![fixedFlag isKindOfClass:NSNumber.class] || [fixedFlag boolValue];','BOOL fixed = YES; (void)fixedFlag;'),policy)}
results=[]
with tempfile.TemporaryDirectory(prefix='wck-svg-native-') as td:
 td=Path(td)
 for name,(s,p) in variants.items():
  if name!='baseline':assert (s,p)!=(selection,policy),'mutation did not modify source'
  sp=td/'selection.m';pp=td/'policy.c';sp.write_text(s);pp.write_text(p);exe=td/name
  c=subprocess.run(['clang','-fobjc-arc','-fblocks','-framework','Foundation','-Wall','-Wextra','-Werror','-Wno-unused-parameter','-I'+str(r/'src'),str(sp),str(pp),str(r/'src/WCKSettings.m'),str(r/'src/WCKSVGPalette.m'),str(r/'tests/WCKSVGSelectionTests.m'),'-o',str(exe)],capture_output=True,text=True,timeout=120)
  assert c.returncode==0,(name,c.stderr)
  t=subprocess.run([str(exe)],capture_output=True,text=True,timeout=25)
  ok=(t.returncode==0) if name=='baseline' else t.returncode!=0
  results.append(dict(variant=name,compiled=True,exit=t.returncode,expected=ok,stdout=t.stdout,stderr=t.stderr))
  print(name,t.stdout.strip() if name=='baseline' else 'runtime defect caught' if ok else 'MISSED',flush=True)
  assert ok,(name,t.stdout,t.stderr)
(r/'evidence').mkdir(exist_ok=True)
(r/'evidence/native-svg-selection-tests.json').write_text(json.dumps(results,indent=2))
