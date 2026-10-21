#!/usr/bin/env python3
"""Build real iOS objects with the available SDK; NOT a link/install test."""
import argparse, json, subprocess, time, shutil
from pathlib import Path
p=argparse.ArgumentParser()
p.add_argument('--sdk',type=Path,required=True)
p.add_argument('--arch',choices=['arm64','arm64e'],required=True)
a=p.parse_args(); root=Path(__file__).resolve().parents[1]
settings=json.loads((a.sdk/'SDKSettings.json').read_text())
version=settings.get('Version','unknown'); clang=shutil.which('clang')
if not clang:raise SystemExit('clang missing')
build=root/'evidence'/('cross-'+a.arch);build.mkdir(parents=True,exist_ok=True)
ccversion=subprocess.run([clang,'--version'],capture_output=True,text=True,timeout=20).stdout
sources=sorted((root/'src').glob('*.m'))+sorted((root/'src').glob('*.c'))
rows=[]; failed=False
for src in sources:
    cmd=[clang,'-target',a.arch+'-apple-ios15.0','-isysroot',str(a.sdk),'-I'+str(root/'src'),'-Wall','-Wextra','-Werror','-Wno-unused-parameter','-Wno-deprecated-declarations','-Wno-incompatible-sysroot']
    if src.suffix=='.m':cmd+=['-fobjc-arc','-fblocks','-fmodules','-fmodules-cache-path='+str(build/'modules')]
    cmd+=['-c',str(src),'-o',str(build/(src.stem+'.o'))]
    start=time.monotonic();r=subprocess.run(cmd,capture_output=True,text=True,timeout=90)
    (build/(src.name+'.log')).write_text(r.stdout+r.stderr)
    rows.append(dict(file=src.name,exit=r.returncode,seconds=round(time.monotonic()-start,3)))
    print(a.arch,src.name,'PASS' if r.returncode==0 else 'FAIL',flush=True)
    if r.returncode:
        print(r.stderr[:6000],flush=True);failed=True;break
out=dict(arch=a.arch,sdk_version=version,sdk_path=str(a.sdk),compiler=ccversion,
         evidence_level='actual Apple SDK object compilation; no linking/native execution',results=rows,
         all_sources_compiled=not failed and len(rows)==len(sources))
(build/'results.json').write_text(json.dumps(out,indent=2))
raise SystemExit(1 if failed else 0)
