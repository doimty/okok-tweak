#!/usr/bin/env python3
"""Actual production + Foundation fake UIKit; never a pixel or device test.
macOS: compile and execute each case; mutants must fail an assertion, not compilation.
Alpine: --object-only --sdk PATH --arch arm64|arm64e compiles only, exit77 without it.
"""
import argparse,hashlib,json,os,subprocess,sys,tempfile
from pathlib import Path
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--object-only',action='store_true');p.add_argument('--sdk',type=Path)
p.add_argument('--arch',choices=['arm64','arm64e'],default='arm64');p.add_argument('--output',type=Path)
p.add_argument('--variant',help='one variant only, to keep local checks bounded')
a=p.parse_args();r=Path(__file__).resolve().parents[1]
if not a.object_only and sys.platform!='darwin':
 print('requires macOS Foundation; SVG parameter model NOT executed');raise SystemExit(77)
if a.object_only and not a.sdk:p.error('--object-only requires --sdk')
source=(r/'src/WCKSVG.m').read_text();variants={'baseline':(source,None)}
def mutation(name,old,new,case,all_matches=False):
 assert old in source and (all_matches or source.count(old)==1),(name,'anchor missing or ambiguous')
 variants[name]=(source.replace(old,new),case)
mutation('missing-theme','NSClassFromString(@"MMThemeManager")','NSClassFromString(@"WCKAbsentTheme")','parameters')
mutation('missing-vm','NSClassFromString(@"WeSVGVM")','NSClassFromString(@"WCKAbsentVM")','parameters')
mutation('missing-engine','NSClassFromString(@"WeSVGEngine")','NSClassFromString(@"WCKAbsentEngine")','parameters')
mutation('drop-name-scope','sScopeName = (__bridge void *)held;','sScopeName = NULL; (void)held;','routes')
mutation('engine-scale','payload, size, scale, rotation, opacity, color);','payload, size, 1, rotation, opacity, color);','parameters')
mutation('theme-angle','payload, size, color, opacity, angle, ignore);','payload, size, color, opacity, 0, ignore);','parameters')
mutation('no-settings-refresh','for (UIView *view in sSVGViews.allObjects) WCKRefreshSVGView(view);','for (UIView *view in sSVGViews.allObjects) (void)view;','refresh')
mutation('wrong-carrier-traits','[view traitCollection]','UITraitCollection.currentTraitCollection','refresh',True)
mutation('no-transform-provenance','if (input && !input.ambiguous) {','if (NO && input && !input.ambiguous) {','refresh')
mutation('bypass-image-subclass','case WCKSVGAlignOp: return [image imageWithAlignmentRectInsets:step.insets];','case WCKSVGAlignOp: return sOriginalAlign ? sOriginalAlign(image, @selector(imageWithAlignmentRectInsets:), step.insets) : nil;','subclasses')
mutation('bypass-view-subclass','else [(UIImageView *)view setImage:next];','else sOriginalImage(view, @selector(setImage:), next);','subclasses')
mutation('no-self-dedup','if (result == image && last && last.operation == operation && last.mode == mode &&','if (NO && result == image && last && last.operation == operation && last.mode == mode &&','self-intent')
mutation('skip-first-self-transform','WCKSVGStep *last = input.steps.lastObject;','if (result == image) return result; WCKSVGStep *last = input.steps.lastObject;','self-intent')
mutation('alias-last-wins','BOOL same = old && WCKSVGSameStamp(old, stamp);','BOOL same = (old && WCKSVGSameStamp(old, stamp), YES);','lifetime')
mutation('alias-reclaim','[sConflictedImages addObject:image];','(void)image;','lifetime')
mutation('strong-quarantine','sConflictedImages = [NSHashTable hashTableWithOptions:\n            NSPointerFunctionsWeakMemory','sConflictedImages = [NSHashTable hashTableWithOptions:\n            NSPointerFunctionsStrongMemory','lifetime')
mutation('no-reentry-guard','if (superseded || scope.superseded) {','if (NO && (superseded || scope.superseded)) {','reentry')
mutation('no-aba-marker','sAssignmentScope->superseded = YES;','(void)sAssignmentScope;','reentry')
mutation('wrong-incoming-guard','WCKSVGCurrent(view, kind, state) != entryImage','((void)entryImage, WCKSVGCurrent(view, kind, state) != image)','reentry')
# A compiler failure cannot count as a caught semantic mutation.
if a.variant:
 assert a.variant in variants,a.variant
 variants={a.variant:variants[a.variant]}
output=a.output or r/'evidence'/('svg-parameter-objects-'+a.arch+'.json' if a.object_only else 'native-svg-model-tests.json')
output.parent.mkdir(parents=True,exist_ok=True);rows=[]
units=['src/WCKPolicy.c','src/WCKSettings.m','src/WCKSVGSelection.m','src/WCKSVGPalette.m','tests/WCKSVGParameterModel.m']
with tempfile.TemporaryDirectory(prefix='wck-svg-param-') as tmp:
 td=Path(tmp);common=['clang','-Wall','-Wextra','-Werror','-Wno-unused-parameter','-I'+str(r/'tests/fake-svg-parameter'),'-I'+str(r/'src')]
 if a.object_only:common+=['-target',a.arch+'-apple-ios15.0','-isysroot',str(a.sdk),'-Wno-incompatible-sysroot']
 common+=['-fmodules','-fmodules-cache-path='+str(td/'modules')]
 if a.object_only:
  for unit in units:
   flags=['-fobjc-arc','-fblocks'] if unit.endswith('.m') else []
   print('compile fixture unit',unit,a.arch,flush=True)
   c=subprocess.run(common+flags+['-c',str(r/unit),'-o',str(td/(Path(unit).name+'.o'))],capture_output=True,text=True,timeout=90)
   assert c.returncode==0,(unit,'compile failed, not execution',c.stderr)
 for name,(body,target) in variants.items():
  f=td/(name+'.m');f.write_text(body);exe=td/name
  cmd=common+['-fobjc-arc','-fblocks',str(f)]
  cmd+=['-c','-o',str(exe)+'.o'] if a.object_only else ['-framework','Foundation','-framework','CoreGraphics']+[str(r/u) for u in units]+['-o',str(exe)]
  print('compile production variant',name,a.arch,flush=True)
  c=subprocess.run(cmd,capture_output=True,text=True,timeout=90)
  assert c.returncode==0,(name,'COMPILE FAILURE IS NOT A CAUGHT MUTANT',c.stderr)
  row={'variant':name,'compiled':True,'executed':False,'cases':[]}
  if not a.object_only:
   for case in ([target] if target else ['parameters','routes','refresh','self-intent','lifetime','subclasses','reentry','failures']):
    home=td/(name+'-'+case);home.mkdir();env=dict(os.environ,HOME=str(home))
    x=subprocess.run([str(exe),case],env=env,capture_output=True,text=True,timeout=25)
    ok=(x.returncode!=0 and 'SVG PARAM CHECK failed' in x.stderr) if target else (x.returncode==0 and 'checks PASS' in x.stdout)
    row['cases'].append({'name':case,'exit':x.returncode,'expected':ok,'stdout':x.stdout,'stderr':x.stderr})
    assert ok,(name,case,x.returncode,x.stdout,x.stderr)
   row['executed']=True
  rows.append(row)
  output.write_text(json.dumps({'level':'objects only; NOT executed' if a.object_only else 'Foundation model; NOT UIKit/WeChat','source_sha256':hashlib.sha256(source.encode()).hexdigest(),'results':rows},indent=2))
  print(name,'compiled, NOT executed' if a.object_only else 'baseline cases PASS' if not target else 'specified runtime CHECK caught mutation',flush=True)
