#!/usr/bin/env bash
set -euo pipefail
python3 - <<'PY'
"""Adjust only the existing pending replay's reservation; never submit jobs."""
import datetime,hashlib,json,os,pathlib,re,shutil,subprocess
root=pathlib.Path('/data1/home/sunyiq/zhenjiang_training_covariance_failure_006_20261016_001')
job='244010';source_job='243692'
def now():return datetime.datetime.now(datetime.timezone(datetime.timedelta(hours=8))).isoformat()
def read(p):return json.loads(p.read_bytes())
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def run(c):
 p=subprocess.run(c,capture_output=True,text=True,timeout=30)
 return {'command':c,'returncode':p.returncode,'stdout':p.stdout,'stderr':p.stderr}
def fields(q):
 assert q['returncode']==0,q
 return dict(re.findall(r'(\w+)=([^\s]+)',q['stdout']))
def seconds(v):
 days,_,tail=v.rpartition('-');bits=[int(x) for x in tail.split(':')]
 assert len(bits) in (2,3)
 return (int(days)*86400 if days else 0)+sum(x*y for x,y in zip(reversed(bits),(1,60,3600)))
def save(p,value):
 with p.open('x',encoding='utf-8') as f:
  json.dump(value,f,sort_keys=True,indent=2,allow_nan=False);f.write('\n');f.flush();os.fsync(f.fileno())
record={'status':'existing_replay_partition_route_preflight','checked_at_beijing':now(),'job_id':job,
 'source_failed_job':source_job,'diagnostic_root':str(root),'new_time_limit_minutes':30,'minimum_backfill_minutes':15,
 'new_jobs_submitted':0,'maximum_gpu_count':1,'formal_training_restarted':False,'formal_epochs_added':0,
 'scientific_rules_changed':False,'evaluation_values_read':False,'other_jobs_modified':False,
 'priority_or_qos_change_requested':False,
 'evidence_basis':{'preceding_member47_checkpoint':'2026-10-16T17:26:28+08:00',
  'broadcast_failure_written':'2026-10-16T17:28:52+08:00','critical_training_segment_upper_bound_seconds':144,
  'prior_same_dimension_cpu_reference_seconds':41,'duration_is_evidence_not_a_completion_guarantee':True},
 'user_instruction':'Resolve the existing244010 queue delay, run its original failure replay and resume authorized formal training.'}
attempt=root/'records/existing244010_exact_device_route_20261016.attempt.json'
response=root/'records/existing244010_exact_device_route_20261016.response.json'
try:
 assert read(root/'records/scheduler_jobs.json')=={'covariance_diagnostic':job}
 spec=read(root/'diagnostic_spec.json');manifest=read(root/'package_manifest.json')
 assert spec['source_job']==source_job and spec['expected_saved_epoch']==46 and spec['replayed_epoch']==47
 assert spec['formal_checkpoint_write_allowed'] is False and not spec['scientific_rules_changed']
 assert sha(root/'package_manifest.json')=='b51ee5585f9d8d208e943a6e6c4b8824c7ff453a77cdaff7a0ad0ca6ef4f32c6'
 for name,identity in manifest['files'].items():assert sha(root/name)==identity['sha256']
 source=pathlib.Path(spec['source_root']);assert read(source/'records/scheduler_jobs.json')[spec['case']]==source_job
 assert sha(source/'runs'/spec['run_id']/'continuation.pt')=='5eb115db35cd71a3d2cb8dc64d262935875c0c0aa593e2acc2c809173d4c79d3'
 for name,digest in spec['source_code_file_hashes'].items():assert sha(source/name)==digest
 control=shutil.which('scontrol')
 candidates=[pathlib.Path('/usr/local/globle/softs/slurm/19.05.4.1/bin/scontrol')]
 if shutil.which('squeue'):candidates.insert(0,pathlib.Path(shutil.which('squeue')).resolve().with_name('scontrol'))
 if not control:control=next((str(p) for p in candidates if p.is_file() and os.access(p,os.X_OK)),None)
 assert control,'actual login-node scontrol executable unavailable; no mutation attempted'
 record['controller_executable']={'path':control,'sha256':sha(pathlib.Path(control).resolve())}
 record['before']=run([control,'show','job','-o',job]);b=fields(record['before'])
 expected={'JobId':job,'JobName':spec['job_name'],'UserId':'sunyiq(2272)','Partition':'hgpu2p',
  'NumCPUs':'4','NumTasks':'1','TresPerNode':'gpu:1','ExcNodeList':'ngu[002,011]',
  'WorkDir':str(root),'Command':str(root/'hpc/covariance_diagnostic.slurm')}
 assert all(b.get(k)==v for k,v in expected.items()),b
 record['source_accounting']=run(['sacct','-n','-X','-j',source_job,'--format=JobID,State,ExitCode,Start,End','-P'])
 assert record['source_accounting']['returncode']==0
 assert record['source_accounting']['stdout'].strip().split('|')[:5]==[source_job,'FAILED','1:0','2026-10-16T15:56:08','2026-10-16T17:30:44']
 record['duplicate_guard']=run(['squeue','-h','-u','sunyiq','-o','%i|%j|%T|%Z'])
 assert record['duplicate_guard']['returncode']==0
 rows=[line.split('|') for line in record['duplicate_guard']['stdout'].splitlines() if line.strip()]
 assert sum(row[0]==job for row in rows)==sum(row[1]==spec['job_name'] for row in rows)==1
 assert not any(row[0]==source_job or row[3]==str(source) for row in rows)
 record['other_three_before']=run(['squeue','-h','-j','236706,236707,237928','-o','%i|%T|%Z|%l|%C|%b'])


 # Only original RTX3090 nodes of hgpu2 are candidates. DeviceTotalMem is
 # queried through the CUDA driver without creating a CUDA context or kernels.
 record['partition_query']=run([control,'show','partition','-o'])
 record['association_query']=run(['sacctmgr','-n','-P','show','association','where','user=sunyiq','format=Cluster,Account,User,Partition,QOS,DefaultQOS'])
 assert record['association_query']['returncode']==0 and 'hhuhpc_jt|g_sunyiq|sunyiq||qos_sunyiq|' in record['association_query']['stdout'].splitlines()
 part=next(dict(re.findall(r'(\w+)=([^\s]+)',line)) for line in record['partition_query']['stdout'].splitlines() if line.startswith('PartitionName=hgpu2 '))
 assert part['State']=='UP' and part['AllowAccounts']==part['AllowGroups']==part['AllowQos']=='ALL' and part['PriorityTier']=='1'
 assert part['Nodes']=='ngu[003,009]'
 record['inventory']=[];matched={};excluded=['ngu002','ngu011'];valid=[]
 metadata_code="import ctypes,json; c=ctypes.CDLL('libcuda.so.1'); assert c.cuInit(0)==0; n=ctypes.c_int(); assert c.cuDeviceGetCount(ctypes.byref(n))==0; out=[]\nfor i in range(n.value):\n d=ctypes.c_int(); assert c.cuDeviceGet(ctypes.byref(d),i)==0; name=ctypes.create_string_buffer(256); assert c.cuDeviceGetName(name,256,d)==0; mem=ctypes.c_size_t(); assert c.cuDeviceTotalMem_v2(ctypes.byref(mem),d)==0; major=ctypes.c_int();minor=ctypes.c_int(); assert c.cuDeviceComputeCapability(ctypes.byref(major),ctypes.byref(minor),d)==0; out.append(dict(name=name.value.decode(),total_memory_bytes=mem.value,capability=[major.value,minor.value]))\nprint(json.dumps(dict(devices=out,contexts_created=0,gpu_kernels_launched=0)))"
 import base64
 remote='python3 -c "import base64;exec(base64.b64decode(\''+base64.b64encode(metadata_code.encode()).decode()+'\'))"'
 for node in ['ngu003','ngu009']:
  nq=run([control,'show','node','-o',node]);nf=fields(nq);assert nf['NodeName']==node and nf['Partitions']=='hgpu2'
  item={'node':node,'partition':'hgpu2','scheduler_node':nq,'same_frozen_gpu':False,'exact_source_memory_matched':False}
  if any(x in nf['State'] for x in ['DOWN','DRAIN','FAIL']):item['inventory_skipped']='scheduler_unavailable'
  else:
   keyfile=root/('records/node_'+node+'_first_connection_554_known_hosts')
   if not keyfile.exists():
    scan=run(['ssh-keyscan','-T','5','-t','ecdsa',node]);assert scan['returncode']==0 and scan['stdout'].strip()
    keys=[line for line in scan['stdout'].splitlines() if line.startswith(node+' ')]
    assert len(keys)==1
    keyfile.open('x').write(keys[0]+'\n')
   item['project_scoped_host_key_file']={'path':str(keyfile),'sha256':sha(keyfile),'global_ssh_configuration_changed':False}
   inv=run(['ssh','-T','-o','BatchMode=yes','-o','StrictHostKeyChecking=yes','-o','UserKnownHostsFile='+str(keyfile),'-o','ConnectTimeout=5','-o','ConnectionAttempts=1',node,remote])
   item['device_identity_read']=inv
   if inv['returncode']==0:
    data=json.loads(inv['stdout']);item['actual_device_metadata']=data
    assert data['contexts_created']==data['gpu_kernels_launched']==0
    item['same_frozen_gpu']=bool(data['devices']) and all(d['name']=='NVIDIA GeForce RTX 3090' and d['capability']==[8,6] for d in data['devices'])
    item['exact_source_memory_matched']=item['same_frozen_gpu'] and all(d['total_memory_bytes']==25296044032 for d in data['devices'])
  record['inventory'].append(item)
  if item['exact_source_memory_matched']:valid.append(node)
  else:excluded.append(node)
 if valid:matched['hgpu2']=valid
 record['admitted_matching_nodes']=matched;record['desired_partition_list']=['hgpu2p']+sorted(matched)
 record['no_priority_or_qos_change']=True
 if attempt.exists():
  record.update(status='prior_exclusive_partition_attempt_preserved_no_retry',prior_attempt=read(attempt))
  if response.exists():record['prior_response']=read(response)
 elif b['JobState']!='PENDING':record.update(status='replay_already_started_no_partition_change',actual_state=b['JobState'])
 elif not matched:record.update(status='no_matching_alternate_gpu_route_proven',actual_state=b['JobState'])
 else:
  assert b['RunTime']=='00:00:00' and b['NodeList']=='(null)' and b['Reason']=='Priority'
  assert seconds(b['TimeLimit'])==1800 and seconds(b['TimeMin'])==900
  record['before_fields']=b;save(attempt,record)
  record['update']=run([control,'update','JobId='+job,'Partition='+','.join(record['desired_partition_list']),'ExcNodeList='+','.join(sorted(set(excluded)))])
  record['after']=run([control,'show','job','-o',job]);a=fields(record['after']);record['after_fields']=a
  assert all(a.get(k)==v for k,v in expected.items() if k not in ['Partition','ExcNodeList']),a
  assert all(a[k]==b[k] for k in ['SubmitTime','EligibleTime','Account','QOS','Nice'])
  assert all(sha(root/name)==identity['sha256'] for name,identity in manifest['files'].items())
  assert sha(source/'runs'/spec['run_id']/'continuation.pt')==spec['source_run_files']['continuation.pt']['sha256']
  verified=record['update']['returncode']==0 and set(a['Partition'].split(','))==set(record['desired_partition_list'])
  record.update(status='existing_replay_matching_partition_route_verified' if verified else 'partition_update_unconfirmed_read_only_reconciliation_required',job_id_and_queue_age_retained=True,script_package_and_complete_source_unchanged=True,actual_state=a['JobState'])
  record['other_three_after']=run(['squeue','-h','-j','236706,236707,237928','-o','%i|%T|%Z|%l|%C|%b'])
  record['finished_at_beijing']=now();save(response,record)
except Exception as error:
 import traceback
 record.update(status='partition_action_error_preserved_no_retry',error_type=type(error).__name__,error=str(error),traceback=traceback.format_exc(),mutation_may_have_executed=attempt.exists())
 if attempt.exists() and not response.exists():save(response,record)
record['finished_at_beijing']=now()
print(json.dumps(record,sort_keys=True,allow_nan=False),flush=True)
PY
set +u
source /data1/home/sunyiq/miniconda3/etc/profile.d/conda.sh
conda activate nh_final
set -u
export PYTHONDONTWRITEBYTECODE=1
python -B /data1/home/sunyiq/zhenjiang_training_covariance_failure_006_20261016_001/hpc/probe_covariance_diagnostic.py
