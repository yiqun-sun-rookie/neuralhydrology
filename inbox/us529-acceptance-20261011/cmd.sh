#!/bin/bash
set -euo pipefail
export PYTHONDONTWRITEBYTECODE=1
test "$(id -un)" = sunyiq
task_root='/data1/home/sunyiq/us_nonnegative_repair_execution_20261010_001/posthoc_clip_cpu_v1'
task_expected_job='241259'
test -f "$task_root/OWN_CLIP_JOB_ID.txt"
test ! -L "$task_root/OWN_CLIP_JOB_ID.txt"
test "$(stat -c %s "$task_root/OWN_CLIP_JOB_ID.txt")" -le 32
task_job=$(cat "$task_root/OWN_CLIP_JOB_ID.txt")
[[ "$task_job" =~ ^[0-9]+$ ]]
test "$task_job" = "$task_expected_job"
printf 'OWN_CLIP_QUERY_JOB_ID=%s\n' "$task_job"
date -u '+OWN_CLIP_QUERY_UTC=%Y-%m-%dT%H:%M:%SZ'
set +e
timeout 8s squeue -j "$task_job" -h -o '%i|%j|%T|%R'
printf 'OWN_CLIP_SQUEUE_EXIT=%s\n' "$?"
timeout 8s sacct -j "$task_job" --noheader --parsable2 --format=JobIDRaw,JobName,State,ExitCode,Elapsed,NCPUS,NodeList,AllocTRES
printf 'OWN_CLIP_SACCT_EXIT=%s\n' "$?"
set -e
python -B -X utf8 - "$task_job" <<'OWN_CLIP_READ_PY'
from pathlib import Path
import hashlib,os,stat,sys
root=Path('/data1/home/sunyiq/us_nonnegative_repair_execution_20261010_001/posthoc_clip_cpu_v1')
assert root.resolve()==root and not root.is_symlink()
job=sys.argv[1];assert job.isascii() and job.isdigit()
def read(name,limit,optional=False):
 p=root/name
 assert p.resolve()==p
 if optional and not p.exists():
  print('OWN_CLIP_MISSING='+name);return None
 a=p.lstat();assert stat.S_ISREG(a.st_mode) and a.st_nlink==1 and a.st_size<=limit
 with p.open('rb') as f:
  b=os.fstat(f.fileno());raw=f.read(limit+1);c=os.fstat(f.fileno())
 d=p.lstat();key=lambda x:(x.st_dev,x.st_ino,x.st_size,x.st_mtime_ns,x.st_ctime_ns,x.st_nlink)
 assert key(a)==key(b)==key(c)==key(d) and len(raw)==a.st_size<=limit
 print('OWN_CLIP_FILE='+name+' bytes='+str(len(raw))+' sha256='+hashlib.sha256(raw).hexdigest())
 return raw
assert read('OWN_CLIP_JOB_ID.txt',32)==(job+'\n').encode()
raw=read('logs/clip-'+job+'.out',950000,True)
err=read('logs/clip-'+job+'.err',8192,True)
if err:
 print('OWN_CLIP_STDERR_BEGIN');sys.stdout.flush();sys.stdout.buffer.write(err);sys.stdout.buffer.flush();print('\nOWN_CLIP_STDERR_END')
if raw is None or b'OWN_CLIP_DONE\n' not in raw:
 if raw:
  lines=[x for x in raw.splitlines() if not x.startswith(b'OWN_CLIP_GZIP_BASE64=')][-30:]
  print('OWN_CLIP_INCOMPLETE_LOG_BEGIN');sys.stdout.flush();sys.stdout.buffer.write(b'\n'.join(lines)+b'\n');sys.stdout.buffer.flush()
 print('OWN_CLIP_REPORT_NOT_YET_COMPLETE');sys.exit(0)
assert raw.count(b'OWN_CLIP_DONE\n')==1 and raw.count(b'OWN_CLIP_META=')==1 and raw.count(b'OWN_CLIP_GZIP_BASE64=')==1
assert b'OWN_CLIP_CPU_FINISHED_UTC=' in raw and raw.decode('utf-8')
print('OWN_CLIP_STDOUT_BEGIN');sys.stdout.flush();sys.stdout.buffer.write(raw);sys.stdout.buffer.flush();print('OWN_CLIP_STDOUT_END')
print('OWN_CLIP_COLLECTION_DONE')
OWN_CLIP_READ_PY
