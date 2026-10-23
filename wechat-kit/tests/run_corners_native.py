#!/usr/bin/env python3
"""Run real WCKCorners source against isolated Foundation fake-UIKit fixtures.
This is behavioral model execution, NOT real UIKit or WeChat. On non-Darwin,
--object-only --sdk ... --arch ... performs compile-only and exits truthfully.
"""
import argparse,hashlib,json,os,re,subprocess,sys,tempfile
from pathlib import Path
CASES=['geometry','isolation','restore','refresh','lifetime','abi']
VARIANTS=['baseline','baseline-overrides','disabled-feature','refresh-noop','strong-registry']
def main():
 p=argparse.ArgumentParser(description=__doc__)
 p.add_argument('--object-only',action='store_true');p.add_argument('--sdk',type=Path);p.add_argument('--arch',choices=['arm64','arm64e'],default='arm64')
 p.add_argument('--source',type=Path);p.add_argument('--output',type=Path);p.add_argument('--variant',choices=VARIANTS)
 a=p.parse_args();root=Path(__file__).resolve().parents[1];source_path=(a.source or root/'src/WCKCorners.m').resolve()
 report={'level':'objects only; NOT executed' if a.object_only else 'Foundation fake UIKit; NOT UIKit/WeChat','arch':a.arch if a.object_only else 'native host','source':str(source_path),'results':[],'status':'pending'}
 def save():
  if a.output:a.output.parent.mkdir(parents=True,exist_ok=True);a.output.write_text(json.dumps(report,indent=2)+'\n')
 def fail(status,msg,code=1):report.update(status=status,detail=msg);save();print(status+': '+msg,file=sys.stderr);return code
 if a.object_only and (not a.sdk or not a.sdk.is_dir()):p.error('--object-only requires an existing --sdk')
 if a.sdk and not a.object_only:p.error('--sdk is compile-only')
 if not a.object_only and sys.platform!='darwin':return fail('UNSUPPORTED_ENV','macOS Foundation required; no behavior executed',77)
 try:source=source_path.read_text()
 except OSError as e:return fail('SOURCE_UNAVAILABLE',str(e))
 report['source_sha256']=hashlib.sha256(source.encode()).hexdigest()
 report['fixture_sha256']={str(x.relative_to(root)):hashlib.sha256(x.read_bytes()).hexdigest() for x in [root/'tests/WCKCornersModel.m',root/'tests/fake-corners/UIKit/UIKit.h']}
 def variant(name):
  if name in ('baseline','baseline-overrides'):return source,None,None
  if name=='disabled-feature':
   body='#define WCKEnabled WCKCornersDisabledFeature\n'+source+'\nBOOL WCKCornersDisabledFeature(NSString *k){(void)k;return NO;}\n'
   return body,'geometry','geometry.frame'
  if name=='refresh-noop':
   body,n=re.subn(r'\bvoid\s+WCKRefreshCorners\s*\(\s*void\s*\)\s*\{','void WCKCornersDiscardedRefresh(void) {',source,count=1)
   if n!=1:raise ValueError('WCKRefreshCorners definition missing')
   return body+'\nvoid WCKRefreshCorners(void){}\n','refresh','refresh.registered'
  if name=='strong-registry':
   if 'weakObjectsHashTable' in source:body=source.replace('weakObjectsHashTable','hashTableWithOptions:NSPointerFunctionsStrongMemory')
   elif 'NSPointerFunctionsWeakMemory' in source:body=source.replace('NSPointerFunctionsWeakMemory','NSPointerFunctionsStrongMemory')
   else:raise ValueError('weak registry marker missing')
   return body,'lifetime','lifetime.weak'
  raise ValueError(name)
 names=[a.variant] if a.variant else VARIANTS
 try:
  with tempfile.TemporaryDirectory(prefix='wck-corners-') as tmp:
   td=Path(tmp);common=['clang','-Wall','-Wextra','-Werror','-Wno-unused-parameter',
                      '-I'+str(root/'tests/fake-corners'),'-I'+str(root/'src'),'-fno-modules']
   if a.object_only:common+=['-target',a.arch+'-apple-ios15.0','-isysroot',str(a.sdk),'-Wno-incompatible-sysroot']
   def compile_unit(unit,obj,flags=()):
    cmd=common+list(flags)
    if unit.suffix=='.m':cmd+=['-fobjc-arc','-fblocks']
    cmd+=['-c',str(unit),'-o',str(obj)];x=subprocess.run(cmd,capture_output=True,text=True,timeout=90)
    report.setdefault('compilations',[]).append({'unit':str(unit),'command':cmd,'exit':x.returncode,'stderr':x.stderr});save()
    if x.returncode:raise RuntimeError('COMPILE_FAILURE '+str(unit)+'\n'+x.stderr)
   dependency_obj=[]
   for unit in [root/'src/WCKPolicy.c',root/'src/WCKSettings.m',root/'src/WCKSVGPalette.m']:
    obj=td/(unit.name+'.o');compile_unit(unit,obj);dependency_obj.append(obj)
   variants={}
   for name in names:
    body,target,marker=variant(name);f=td/(name+'.m');f.write_text(body);exe=td/name
    model_flags=['-DWCK_CORNERS_HOST_OVERRIDE=1'] if name=='baseline-overrides' else []
    model_obj=td/(name+'-model.o')
    compile_unit(root/'tests/WCKCornersModel.m',model_obj,model_flags)
    cmd=common+['-fobjc-arc','-fblocks']
    cmd += ['-target',a.arch+'-apple-ios15.0','-isysroot',str(a.sdk),'-Wno-incompatible-sysroot'] if a.object_only else []
    if a.object_only:
     cmd += [str(f),'-c','-o',str(exe)+'.o']
    else:
     cmd += [str(f),str(model_obj)]+[str(x) for x in dependency_obj]+['-framework','Foundation','-framework','CoreGraphics','-o',str(exe)]
    c=subprocess.run(cmd,capture_output=True,text=True,timeout=120)
    report['results'].append({'variant':name,'compiled':c.returncode==0,'cases':[],'executed':False});save()
    if c.returncode:raise RuntimeError('COMPILE_FAILURE (not a caught mutant) '+name+'\n'+c.stderr)
    row=report['results'][-1]
    if not a.object_only:
     for case in ([target] if target else CASES):
      home=td/(name+'-'+case);home.mkdir();env=dict(os.environ,HOME=str(home))
      x=subprocess.run([str(exe),case],capture_output=True,text=True,timeout=30,env=env)
      good=(x.returncode==86 and marker in x.stderr) if marker else (x.returncode==0 and 'CORNERS CASE '+case+' PASS' in x.stdout)
      row['cases'].append({'case':case,'exit':x.returncode,'expected':good,'stdout':x.stdout,'stderr':x.stderr})
      save();print(name,case,'PASS' if good else 'FAIL',flush=True)
      if not good:raise RuntimeError('ASSERTION_MISMATCH '+name+'/'+case+'\n'+x.stdout+'\n'+x.stderr)
     row['executed']=True;save()
   if not a.object_only and names==VARIANTS:
    totals={r['variant']:r['executed'] and all(c['expected'] for c in r['cases']) for r in report['results']}
    if not all(totals.values()):raise RuntimeError('INCOMPLETE_VARIANTS')
   report['status']='PASS_OBJECTS_ONLY' if a.object_only else 'PASS_FOUNDATION_MODEL_NOT_UIKIT';report['complete']=True;save()
 except subprocess.TimeoutExpired as e:return fail('TIMEOUT',str(e),124)
 except RuntimeError as e:return fail('FAILED',str(e),1)
 print(report['status']);return 0
if __name__=='__main__':raise SystemExit(main())
