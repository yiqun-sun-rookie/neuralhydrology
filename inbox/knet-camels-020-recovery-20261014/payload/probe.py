"""Login-node metadata only; no submission, science or shared-state changes."""
import os,sys,json,subprocess,hashlib,base64,datetime,re
from pathlib import Path
base=Path('/data1/home/sunyiq/knet_camels_hpc_20261012_001/attempts/020_snow_training_20261014_001')
channel='knet-camels-hpc-20261012-001'
def command(argv):
    result=subprocess.run(argv,capture_output=True,text=True,timeout=30)
    return dict(exit_code=result.returncode,stdout=result.stdout,stderr=result.stderr)
def read(path,maxbytes=100000):
    if not path.is_file():return None
    assert not path.is_symlink() and path.stat().st_size<=maxbytes
    return path.read_text(encoding='utf-8',errors='replace')
record=dict(checked_utc=datetime.datetime.now(datetime.timezone.utc).isoformat(),host=os.uname().nodename,
    submission=read(base/'submission.json'),submission_started=read(base/'submission_started.json'),
    submission_stdout=read(base/'submission_stdout.txt'),root_exists=base.exists())
ps=command(['ps','-eo','pid,ppid,etimes,args'])
record['relevant_processes']=[re.sub(r'https?://[^ /@]+@','https://REDACTED@',x) for x in ps['stdout'].splitlines()
    if any(k in x for k in ['hpc_runner_active','cmd_29.sh','020_snow_training','git fetch','git push','git pull','git reset','git pack-objects'])]
stage=Path.home()/'.hpc_mailbox_staging'/channel/'result_29.txt'
raw=None if not stage.is_file() else stage.read_bytes()
record['staged_receipt']=None if raw is None else dict(bytes=len(raw),sha256=hashlib.sha256(raw).hexdigest(),
    complete=b'### exit_code=' in raw,tail=raw.decode(errors='replace').splitlines()[-12:])
staged_command=Path.home()/'.hpc_mailbox_staging'/channel/'cmd_29.sh'
record['staged_command_sha256']=None if not staged_command.is_file() else hashlib.sha256(staged_command.read_bytes()).hexdigest()
mailbox=Path.home()/'hpc_mailbox'
record['runner_log_tail']=command(['tail','-n','55',str(mailbox/'runner2.log')])
record['mailbox_head']=command(['git','--git-dir='+str(mailbox/'.git'),'rev-parse','HEAD'])
q=command(['squeue','-u','sunyiq','-h','-o','%i|%j|%T|%M|%R'])
record['matching_queue_rows']=[x for x in q['stdout'].splitlines() if '|knet020_train_snow|' in x]
record['queue_query_exit_code']=q['exit_code']
if record['submission']:
    job=json.loads(record['submission'])['job_id'];assert job.isdigit()
    record['job_details']=command(['scontrol','show','job',job])
    log=base/'logs'/('diagnostic-'+job+'.out');err=base/'logs'/('diagnostic-'+job+'.err')
    record['training_log_tail']=command(['tail','-n','18',str(log)]) if log.is_file() else None
    record['training_error']=read(err)
print('RECOVERY_PROBE_JSON='+json.dumps(record))
if raw is not None and b'### exit_code=' in raw:
    print('ORIGINAL_RECEIPT_BASE64='+base64.b64encode(raw).decode())
