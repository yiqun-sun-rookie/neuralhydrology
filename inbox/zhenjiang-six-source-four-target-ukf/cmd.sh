#!/usr/bin/env bash
set -euo pipefail
python3 - <<'PY'
import base64,datetime,gzip,hashlib,io,json,pathlib,subprocess,tarfile
S=pathlib.Path('/data1/home/sunyiq/zhenjiang_complete_comparison_20261006_recovery_001')
D=pathlib.Path('/data1/home/sunyiq/zhenjiang_gradient_diagnostic_20261011_001')
E=pathlib.Path('/data1/home/sunyiq/zhenjiang_gradient_export_20261012_001')
spec=json.loads((D/'diagnostic_spec.json').read_text()); run=spec['run_id']; case=spec['case']
job=str(json.loads((S/'records/scheduler_jobs.json').read_text())[case])
q=subprocess.run(['squeue','-h','-u','sunyiq','-o','%i|%T'],capture_output=True,text=True,timeout=30)
assert q.returncode==0 and not any(line.split('|')[0]==job for line in q.stdout.splitlines()),(q.returncode,q.stdout,q.stderr)
a=subprocess.run(['sacct','-n','-X','-j',job,'--format=JobID,State,ExitCode','-P'],capture_output=True,text=True,timeout=30)
assert a.returncode==0 and job+'|FAILED|1:0' in a.stdout,a.stdout
E.mkdir(exist_ok=False)
files={}; identities={}
def add(path,name,expected=None):
 raw=path.read_bytes(); h=hashlib.sha256(raw).hexdigest()
 assert expected is None or h==expected,(str(path),h)
 assert name not in files and not name.startswith('/') and '..' not in pathlib.PurePosixPath(name).parts
 files[name]=raw; identities[name]={'remote_path':str(path),'bytes':len(raw),'sha256':h}
for name,identity in spec['source_run_files'].items():add(S/'runs'/run/name,'source/runs/'+run+'/'+name,identity['sha256'])
for name,h in spec['source_code_file_hashes'].items():add(S/name,'source/'+name,h)
for name in ['configs/protocol-v3.json','configs/registry-v3.json','records/authorization.json','records/data_preparation_complete.json','prepared/tuning/manifest.json','records/'+case+'/tune_foundation_group_outcome.json','records/'+case+'/tune_branch_group_configs.json']:
 add(S/name,'source/'+name)
config=json.loads(files['source/runs/'+run+'/config.json']); effective=config['effective_config']
parent=pathlib.Path(effective['parent_checkpoint']);add(parent,'parent/best.pt',effective['parent_hash'])
manifest=json.loads(files['source/prepared/tuning/manifest.json'])
assert manifest['status']=='admitted' and not manifest.get('evaluation_year_reads',False)
entries=[e for e in manifest['files'] if 'tuning_train' in e.get('phases',[])]
assert len(entries)>0
for i,e in enumerate(entries):
 assert set(e['years']).issubset({2017,2018,2019,2020}) and e['role'] in ('realtime_inputs','qc_labels','astronomical_tide')
 p=pathlib.Path(e['path']);assert any(p.resolve()==pathlib.Path(r).resolve() or pathlib.Path(r).resolve() in p.resolve().parents for r in manifest['approved_roots'])
 assert not any(p.resolve()==pathlib.Path(r).resolve() or pathlib.Path(r).resolve() in p.resolve().parents for r in manifest.get('forbidden_roots',[]))
 add(p,'training/'+str(i)+'_'+p.name,e['sha256'])
add(D/'diagnostic_spec.json','diagnostic_spec.json')
meta={'schema':'read_only_training_only_diagnostic_export_v1','at':datetime.datetime.now().astimezone().isoformat(),'source_root':str(S),'run_id':run,'source_job':job,'files':identities,'training_years_only':[2017,2018,2019,2020],'evaluation_values_read':False,'formal_training_outputs_allowed':False,'purpose':'local auxiliary gradient diagnosis; different hardware cannot prove formal recovery','scheduler':{'squeue':q.stdout,'sacct':a.stdout}}
files['export_manifest.json']=(json.dumps(meta,sort_keys=True,indent=2)+'\n').encode()
buf=io.BytesIO()
with gzip.GzipFile(fileobj=buf,mode='wb',compresslevel=6,mtime=0) as gz:
 with tarfile.open(fileobj=gz,mode='w|') as t:
  for name,raw in sorted(files.items()):
   info=tarfile.TarInfo(name);info.size=len(raw);info.mtime=0;t.addfile(info,io.BytesIO(raw))
raw=buf.getvalue(); bundle=E/'training_diagnostic.tar.gz'
with bundle.open('xb') as f:f.write(raw)
for name,d in identities.items():assert hashlib.sha256(pathlib.Path(d['remote_path']).read_bytes()).hexdigest()==d['sha256'],name
report={'status':'diagnostic_export_ready','bundle_path':str(bundle),'bundle_bytes':len(raw),'bundle_sha256':hashlib.sha256(raw).hexdigest(),'source_files_unchanged':True,'file_count':len(files),'evaluation_values_read':False,'offset':0,'chunk_bytes':min(len(raw),8000000),'base64':base64.b64encode(raw[:8000000]).decode()}
with (E/'export_receipt.json').open('x') as f:json.dump({k:v for k,v in report.items() if k!='base64'},f,indent=2)
print(json.dumps(report,sort_keys=True))
PY
