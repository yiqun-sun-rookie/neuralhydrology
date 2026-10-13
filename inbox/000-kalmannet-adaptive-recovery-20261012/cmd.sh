#!/bin/bash
sequence=12
umask 077
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -I -S -B - <<'CPU_READ_ONLY'
from pathlib import Path
import os,json,hashlib,subprocess,datetime,stat
assert os.getuid()==os.geteuid()==2272 and not os.environ.get('SLURM_JOB_ID')
R=Path('/data1/home/sunyiq/kalmannet_cpu_remaining_fifteen_full_validation_20261012_001');assert R.resolve()==R
r=dict(schema='cpu_full15_small_progress_and_collector_projection_v1',read_only=True,job_id='241342',observed_utc=datetime.datetime.now(datetime.timezone.utc).isoformat(),scientific_submissions=0,other_jobs_modified=False,queries=[],formal_results=[],external_collectors=[])
for a in [['scontrol','show','job','241342','--oneliner'],['squeue','--noheader','--jobs','241342','--format=%i|%T|%N'],['sacct','-j','241342','--parsable2','--noheader','--format=JobIDRaw,JobName,User,UID,Partition,Submit,Start,End,ElapsedRaw,AllocCPUS,AllocTRES,ReqTRES,State,ExitCode,NodeList,WorkDir,TimelimitRaw,Comment,CPUTimeRAW,TotalCPU']]:
 q=subprocess.run(a,capture_output=True,stdin=subprocess.DEVNULL,timeout=20,env={**os.environ,'TZ':'UTC','LC_ALL':'C'});r['queries'].append(dict(argv=a,returncode=q.returncode,stdout=q.stdout.decode(),stderr=q.stderr.decode()))
def read(p,limit):
 if not p.exists():return None,None
 st=p.lstat();assert stat.S_ISREG(st.st_mode) and not p.is_symlink() and st.st_uid==2272 and p.resolve().is_relative_to(R) and st.st_size<=limit
 b=p.read_bytes();return json.loads(b),dict(path=str(p),bytes=len(b),sha256=hashlib.sha256(b).hexdigest())
x,p=read(R/'source_manifest.json',64*1024);r['source_manifest_identity']=p
x,p=read(R/'metadata/root_admission.json',256*1024);r['root_admission_identity']=p
c,p=read(R/'output/task_internal_candidate.json',32*1024**2);r['candidate_identity']=p
if c is not None:r['candidate']={k:c.get(k) for k in ['actual_job_id','source_manifest_sha256','admission_sha256','state','error_type','error','cleanup_verified','all_fifteen_full_technical_complete','entry_monotonic','finished_monotonic','actual_job_deadline_exceeded','exit_code_intent']};r['candidate']['completed_case_indices']=[x['case_index'] for x in c.get('cases',[])]
for p in sorted((R/'root_receipts').glob('*_collect/external_receipt.json')):
 x,pin=read(p,32*1024**2);r['external_collectors'].append(dict(identity=pin,fields={k:x.get(k) for k in ['schema','job_id','source_manifest_sha256','task_external','job_terminal_verified','native_terminal','all_own_rows','task_internal_cleanup_verified','technical_opportunity_completed','full_configuration_increment','all_fifteen_full_complete','actual_native_seconds','actual_allocated_cpu_seconds','test_completed_count','error','terminal_verified']},case_indices=[y['case_index'] for y in x.get('cases',[]) or []]))
for i in [1,2,3,4,5,6,7,12,13,14,15,25,26,27,28]:
 x,p=read(R/f'output/case_{i:03d}/formal/result.json',3*1024**2)
 if x is not None:r['formal_results'].append(dict(case_index=i,identity=p,fields={k:x.get(k) for k in ['case','state','execution_complete','windows_traversed','own_statistics_reconstructed','reconstruction_report_consumer_verification']}))
stag=Path('/data1/home/sunyiq/.hpc_mailbox_staging/kalmannet-joint-adaptive-20261007')
r['own_main_staging_files']=[]
if stag.is_dir() and not stag.is_symlink():
 for p in sorted(stag.iterdir()):
  if p.is_file() and not p.is_symlink():s=p.stat();r['own_main_staging_files'].append(dict(name=p.name,bytes=s.st_size,mtime=s.st_mtime))
print(json.dumps(r,sort_keys=True))
CPU_READ_ONLY
