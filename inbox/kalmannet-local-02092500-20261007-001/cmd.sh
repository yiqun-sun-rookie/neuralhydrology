#!/usr/bin/env bash
# sequence=1
set -e -o pipefail
export PYTHONDONTWRITEBYTECODE=1
timeout 420 /data1/home/sunyiq/miniconda3/envs/nh_final/bin/python3.11 - <<'LOCAL_CHECKPOINT_TRANSFER'
"""Transfer the one fixed checkpoint; no remote model execution."""
import hashlib,json,os,re,subprocess,time
from pathlib import Path
CHANNEL='kalmannet-local-02092500-20261007-001'
SOURCE=Path('/data1/home/sunyiq/kalmannet_daily_camels_per_basin_21_development_20260908_v3_aligned_rematch_20260916/runs/DAILY_CAMELS_KNET_ALIGNED_REMATCH_V3_20260916_KNET_BASIN_02092500_SEED_20260922/checkpoints/epoch_121.pt')
EXPECTED='0f18bf4e514d3ea07580e8d37bbcd8c7d08992e7c5fd5bbd19a256ac246f94ba'
def clean(s):
 s=re.sub(r'https?://[^\s/@]+@','https://[redacted]@',s)
 return re.sub(r'(?:gh[pousr]_[A-Za-z0-9_]+|github_pat_[A-Za-z0-9_]+)','[redacted]',s)[:4000]
def main():
 if any(p.is_symlink() for p in (SOURCE,*SOURCE.parents)) or SOURCE.resolve()!=SOURCE:raise ValueError('checkpoint path differs')
 with SOURCE.open('rb') as f:
  before=os.fstat(f.fileno())
  if not 0<before.st_size<=64*1024**2:raise ValueError('checkpoint outside transfer byte limit')
  raw=f.read();after=os.fstat(f.fileno())
 if (before.st_size,before.st_mtime_ns)!=(after.st_size,after.st_mtime_ns):raise ValueError('checkpoint changed')
 digest=hashlib.sha256(raw).hexdigest()
 if digest!=EXPECTED:raise ValueError('checkpoint digest differs')
 repo=Path.home()/'hpc_mailbox';stage=Path.home()/'.hpc_mailbox_staging'/CHANNEL
 stage.mkdir(parents=True,exist_ok=True);index=stage/'checkpoint_transfer.index'
 if index.exists():raise ValueError('transfer index already exists')
 env=dict(os.environ,GIT_INDEX_FILE=str(index),GIT_TERMINAL_PROMPT='0')
 lock=Path.home()/'.hpc_mailbox_pushlock';obtained=False
 for _ in range(120):
  try:lock.mkdir();obtained=True;break
  except FileExistsError:time.sleep(.5)
 if not obtained:raise TimeoutError('mailbox push lock unavailable')
 def git(args,input_bytes=None,timeout=90):
  r=subprocess.run(['git']+args,cwd=str(repo),env=env,input=input_bytes,stdout=subprocess.PIPE,stderr=subprocess.PIPE,timeout=timeout)
  if r.returncode:raise RuntimeError('git '+args[0]+' failed: '+clean(r.stderr.decode('utf-8','replace')))
  return r.stdout.decode('ascii').strip()
 try:
  ref='refs/local-trial-transfer/'+CHANNEL;git(['fetch','-q','origin','hpc-mailbox:'+ref]);parent=git(['rev-parse',ref])
  target='outbox/'+CHANNEL+'/checkpoint.pt'
  if git(['ls-tree',parent,'--',target]):raise ValueError('checkpoint output already exists')
  blob=git(['hash-object','-w','--stdin'],raw)
  if blob!=hashlib.sha1(b'blob '+str(len(raw)).encode()+b'\0'+raw).hexdigest():raise ValueError('git object differs')
  git(['read-tree',parent]);git(['update-index','--add','--cacheinfo','100644',blob,target]);tree=git(['write-tree'])
  commit=git(['commit-tree',tree,'-p',parent,'-m','Local model trial: exact checkpoint transfer '+CHANNEL])
  git(['push','-q','origin',commit+':refs/heads/hpc-mailbox'],timeout=180)
  print(json.dumps({'status':'CHECKPOINT_TRANSFERRED','channel':CHANNEL,'path':target,'bytes':len(raw),'sha256':digest,'blob_sha':blob,'commit':commit,'parent':parent},sort_keys=True))
 finally:
  if index.exists():index.unlink()
  lock.rmdir()
if __name__=='__main__':
 try:main()
 except Exception as e:
  print(json.dumps({'status':'TRANSFER_ERROR','type':type(e).__name__,'message':clean(str(e))},sort_keys=True));raise SystemExit(1)

LOCAL_CHECKPOINT_TRANSFER
