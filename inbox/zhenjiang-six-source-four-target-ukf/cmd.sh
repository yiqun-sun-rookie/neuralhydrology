#!/usr/bin/env bash
set -euo pipefail
python3 - <<'PY'
import pathlib,json,tarfile,io,hashlib,subprocess,re
root=pathlib.Path('/data1/home/sunyiq/zhenjiang_complete_comparison_20261006_002')
inbox=pathlib.Path('inbox/zhenjiang-six-source-four-target-ukf')
seq=int((inbox/'seq').read_text());payload=inbox/('payload_complete_comparison_20261006_'+str(seq)+'.tar.gz');raw=payload.read_bytes()
if hashlib.sha256(raw).hexdigest()!='8b846c4228326955e0dd24212b1861c9137cbb2dcc397929b4c5180d9ad6cbb4':raise ValueError('diagnostic package differs')
with tarfile.open(fileobj=io.BytesIO(raw),mode='r:gz') as t:
 members=t.getmembers();expected=['hpc/diagnostic_tools/py-spy-0.4.2', 'hpc/diagnostic_tools/LICENSE', 'hpc/diagnostic_tools/tool_manifest.json']
 if {m.name for m in members}!=set(expected) or len(members)!=len(expected):raise ValueError('diagnostic package allow-list differs')
 for m in members:
  p=pathlib.PurePosixPath(m.name)
  if not m.isfile() or p.is_absolute() or '..' in p.parts:raise ValueError('unsafe diagnostic file')
 content={m.name:t.extractfile(m).read() for m in members}
 for n,b in content.items():
  if n in {'hpc/diagnostic_tools/py-spy-0.4.2': {'sha256': '9b4d1f39b2a47ae44f4c6a46f615dcc0287d7755beba5065f32391951e07d594', 'bytes': 8079336}, 'hpc/diagnostic_tools/LICENSE': {'sha256': '80bbb8731db59cd835f59fcd06f127953804bb511c8487fd265d96c7c702cd00', 'bytes': 1088}} and hashlib.sha256(b).hexdigest()!={'hpc/diagnostic_tools/py-spy-0.4.2': {'sha256': '9b4d1f39b2a47ae44f4c6a46f615dcc0287d7755beba5065f32391951e07d594', 'bytes': 8079336}, 'hpc/diagnostic_tools/LICENSE': {'sha256': '80bbb8731db59cd835f59fcd06f127953804bb511c8487fd265d96c7c702cd00', 'bytes': 1088}}[n]['sha256']:raise ValueError('tool file differs')
 tool=root/'hpc/diagnostic_tools';tool.mkdir(exist_ok=False)
 for n,b in content.items():
  p=root/n;p.write_bytes(b);p.chmod(0o755 if p.name=='py-spy-0.4.2' else 0o644)
job=str(json.loads((root/'records/scheduler_jobs.json').read_text())['legacy_lstm__small'])
r=subprocess.run(['scontrol','show','job','-o',job],capture_output=True,text=True,timeout=15);report={'package_sha256':'8b846c4228326955e0dd24212b1861c9137cbb2dcc397929b4c5180d9ad6cbb4','registered_job':job,'scheduler':{'returncode':r.returncode,'stdout':r.stdout,'stderr':r.stderr}}
match=re.search(r'(?:^| )NodeList=([a-zA-Z0-9_-]+)(?: |$)',r.stdout)
if match and 'JobState=RUNNING' in r.stdout and ('WorkDir='+str(root)+' ') in r.stdout:
 command='python3 -c '+repr("import base64;exec(compile(base64.b64decode('aW1wb3J0IGpzb24scGF0aGxpYixkYXRldGltZSxzdWJwcm9jZXNzLHRpbWUKcm9vdD1wYXRobGliLlBhdGgoJy9kYXRhMS9ob21lL3N1bnlpcS96aGVuamlhbmdfY29tcGxldGVfY29tcGFyaXNvbl8yMDI2MTAwNl8wMDInKQpqb2I9c3RyKGpzb24ubG9hZHMoKHJvb3QvJ3JlY29yZHMvc2NoZWR1bGVyX2pvYnMuanNvbicpLnJlYWRfdGV4dCgpKVsnbGVnYWN5X2xzdG1fX3NtYWxsJ10pCnBpZHM9W10KZm9yIHAgaW4gcGF0aGxpYi5QYXRoKCcvcHJvYycpLml0ZXJkaXIoKToKIGlmIG5vdCBwLm5hbWUuaXNkaWdpdCgpOmNvbnRpbnVlCiB0cnk6CiAgaWYgJ3NjcmlwdHMvdHJhaW5fc3VwZXJjb21wdXRlcl9jYXNlLnB5IC0tY2FzZSBsZWdhY3lfbHN0bV9fc21hbGwnIGluIChwLydjbWRsaW5lJykucmVhZF9ieXRlcygpLnJlcGxhY2UoYidcMCcsYicgJykuZGVjb2RlKCkgYW5kIChwLydjd2QnKS5yZXNvbHZlKCk9PXJvb3QgYW5kICgnam9iXycram9iKSBpbiAocC8nY2dyb3VwJykucmVhZF90ZXh0KCk6cGlkcy5hcHBlbmQoaW50KHAubmFtZSkpCiBleGNlcHQgT1NFcnJvcjpwYXNzCnJlcG9ydD17J2F0JzpkYXRldGltZS5kYXRldGltZS5ub3coKS5hc3RpbWV6b25lKCkuaXNvZm9ybWF0KCksJ2pvYic6am9iLCdvd25fcGlkcyc6cGlkcywnc3RhY2tfc2FtcGxlcyc6W119CmlmIGxlbihwaWRzKT09MToKIGV4ZT1yb290LydocGMvZGlhZ25vc3RpY190b29scy9weS1zcHktMC40LjInCiBmb3IgaSBpbiByYW5nZSgzKToKICBjbWQ9W3N0cihleGUpLCdkdW1wJywnLS1waWQnLHN0cihwaWRzWzBdKSwnLS1uYXRpdmUnXQogIHRyeToKICAgcj1zdWJwcm9jZXNzLnJ1bihjbWQsY2FwdHVyZV9vdXRwdXQ9VHJ1ZSx0ZXh0PVRydWUsdGltZW91dD0xNSk7cmVwb3J0WydzdGFja19zYW1wbGVzJ10uYXBwZW5kKHsnYXQnOmRhdGV0aW1lLmRhdGV0aW1lLm5vdygpLmFzdGltZXpvbmUoKS5pc29mb3JtYXQoKSwncmV0dXJuY29kZSc6ci5yZXR1cm5jb2RlLCdzdGRvdXQnOnIuc3Rkb3V0Wy0zMDAwMDpdLCdzdGRlcnInOnIuc3RkZXJyWy0zMDAwOl19KQogIGV4Y2VwdCBFeGNlcHRpb24gYXMgZTpyZXBvcnRbJ3N0YWNrX3NhbXBsZXMnXS5hcHBlbmQoeydlcnJvcic6c3RyKGUpfSkKICBpZiBpPDI6dGltZS5zbGVlcCgzKQplbHNlOnJlcG9ydFsnbm90X3NhbXBsZWQnXT0nb3duIHRyYWluaW5nIFBJRCBub3QgdW5pcXVlJwpwcmludChqc29uLmR1bXBzKHJlcG9ydCxlbnN1cmVfYXNjaWk9VHJ1ZSkpCg=='),'own_stack','exec'))")
 r=subprocess.run(['ssh','-o','BatchMode=yes','-o','ConnectTimeout=10',match.group(1),command],capture_output=True,text=True,timeout=60);report['node_stack']={'returncode':r.returncode,'stdout':r.stdout,'stderr':r.stderr}
print(json.dumps(report,ensure_ascii=True))
PY
