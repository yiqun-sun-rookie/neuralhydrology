#!/bin/bash
set -euo pipefail
export PYTHONDONTWRITEBYTECODE=1
export OMP_NUM_THREADS=1
export OPENBLAS_NUM_THREADS=1
export MKL_NUM_THREADS=1
test "$(id -un)" = "sunyiq"
task_root='/data1/home/sunyiq/us_nonnegative_repair_execution_20261010_001/audit_cpu_v2'
task_job='241228'
printf 'OWN_SIX_CPU_AUDIT_QUERY_UTC='
date -u '+%Y-%m-%dT%H:%M:%SZ'
printf 'OWN_SIX_CPU_AUDIT_QUERY_JOB_ID=%s\n' "$task_job"
set +e
timeout 8s squeue -j "$task_job" -h -o '%i|%j|%T|%R'
printf 'OWN_SIX_CPU_AUDIT_SQUEUE_EXIT=%s\n' "$?"
timeout 8s sacct -j "$task_job" --noheader --parsable2 --format=JobIDRaw,JobName,State,ExitCode,Elapsed,NCPUS,NodeList,AllocTRES
printf 'OWN_SIX_CPU_AUDIT_SACCT_EXIT=%s\n' "$?"
set -e
python -B -X utf8 - <<'OWN_CPU_AUDIT_READ_ONLY_PY'
from pathlib import Path
import hashlib,os,stat,sys
root=Path('/data1/home/sunyiq/us_nonnegative_repair_execution_20261010_001/audit_cpu_v2')
assert root.resolve()==root and root.is_dir() and not root.is_symlink()
def read(name,limit,optional=False):
 p=root/name
 assert p.resolve()==p
 if optional and not p.exists():
  print('OWN_SIX_CPU_AUDIT_MISSING='+name)
  return None
 a=p.lstat()
 assert stat.S_ISREG(a.st_mode) and a.st_nlink==1 and a.st_size<=limit
 with p.open('rb') as f:
  b=os.fstat(f.fileno()); raw=f.read(limit+1); c=os.fstat(f.fileno())
 d=p.lstat()
 key=lambda x:(x.st_dev,x.st_ino,x.st_size,x.st_mtime_ns,x.st_nlink)
 assert key(a)==key(b)==key(c)==key(d) and len(raw)==a.st_size<=limit
 print('OWN_SIX_CPU_AUDIT_FILE='+name+' bytes='+str(len(raw))+' sha256='+hashlib.sha256(raw).hexdigest())
 return raw
assert read('OWN_INDEPENDENT_CPU_JOB_ID.txt',32)==b'241228\n'
raw=read('logs/audit-241228.out',1179648,True)
err=read('logs/audit-241228.err',8192,True)
if err:
 print('OWN_SIX_CPU_AUDIT_STDERR_BEGIN');sys.stdout.flush();sys.stdout.buffer.write(err);sys.stdout.buffer.flush();print('\nOWN_SIX_CPU_AUDIT_STDERR_END')
if raw is None or b'OWN_SIX_INDEPENDENT_RESCORE_DONE\n' not in raw:
 if raw:
  # No partial encoded line is forwarded.
  lines=[line for line in raw.splitlines() if not line.startswith(b'OWN_SIX_INDEPENDENT_RESCORE_GZIP_BASE64=')][-30:]
  print('OWN_SIX_CPU_AUDIT_INCOMPLETE_LOG_BEGIN');sys.stdout.flush();sys.stdout.buffer.write(b'\n'.join(lines)+b'\n');sys.stdout.buffer.flush()
 print('OWN_SIX_CPU_AUDIT_REPORT_NOT_YET_COMPLETE')
 sys.exit(0)
assert raw.count(b'OWN_SIX_INDEPENDENT_RESCORE_DONE\n')==1 and raw.count(b'OWN_SIX_INDEPENDENT_RESCORE_META=')==1
assert raw.count(b'OWN_SIX_INDEPENDENT_RESCORE_GZIP_BASE64=')==1
assert b'OWN_SIX_AUDIT_CPU_FINISHED_UTC=' in raw
assert raw.decode('utf-8')
print('OWN_SIX_CPU_AUDIT_STDOUT_BEGIN');sys.stdout.flush();sys.stdout.buffer.write(raw);sys.stdout.buffer.flush();print('OWN_SIX_CPU_AUDIT_STDOUT_END')
print('OWN_SIX_CPU_AUDIT_COLLECTION_DONE')
OWN_CPU_AUDIT_READ_ONLY_PY
