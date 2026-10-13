#!/bin/bash
set -eo pipefail
ROOT='/data1/home/sunyiq/china_radiation_16_hpc_20261012_001/execution_v1/raw_recovery_attempt1/coordinate_repair_attempt2'
task_job=241654
test "$(cat "$ROOT/OWN_NUMERICAL_JOB_ID.txt")" = "$task_job"
printf 'OWN_REQUEST_BUILD_QUERY_JOB_ID=%s\nOWN_NUMERICAL_QUERY_JOB_ID=%s\n' "$task_job" "$task_job"
set +e
timeout 12s squeue -j "$task_job" -h -o '%i|%j|%T|%R'
task_sq=$?
timeout 12s sacct -j "$task_job" --noheader --parsable2 --format=JobID,JobName,State,ExitCode,Elapsed,AllocCPUS,NodeList,AllocTRES
task_sa=$?
set -e
printf 'OWN_SQUEUE_EXIT=%s\nOWN_SACCT_EXIT=%s\n' "$task_sq" "$task_sa"
for task_kind in out err; do
    printf 'OWN_NUMERICAL_LOG_%s_BEGIN\n' "$task_kind"
    if test -f "$ROOT/logs/numerical-$task_job.$task_kind"; then
        head -c 32768 "$ROOT/logs/numerical-$task_job.$task_kind"
    else printf 'MISSING\n'; fi
    printf '\nOWN_NUMERICAL_LOG_%s_END\n' "$task_kind"
done
if test -f "$ROOT/NUMERICAL_RESULT.json"; then
    test "$(stat -c %s "$ROOT/NUMERICAL_RESULT.json")" -le 1048576
    printf 'OWN_NUMERICAL_REPORT_BEGIN\n'
    cat "$ROOT/NUMERICAL_RESULT.json"
    printf 'OWN_NUMERICAL_REPORT_END\n'
    /data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -B - <<'PY'
import base64,gzip,hashlib,io,tarfile
from pathlib import Path
root=Path('/data1/home/sunyiq/china_radiation_16_hpc_20261012_001/execution_v1/raw_recovery_attempt1/coordinate_repair_attempt2')
files=sorted((root/'numerical_v1').glob('*.json'))+[root/'NUMERICAL_RESULT.json']
assert len(files)==33 and len({p.name for p in files})==33
stream=io.BytesIO()
with tarfile.open(fileobj=stream,mode='w') as archive:
    for path in files:
        data=path.read_bytes();assert len(data)<=8*1024**2
        item=tarfile.TarInfo(path.name);item.size=len(data);item.mtime=0
        archive.addfile(item,io.BytesIO(data))
assert len(stream.getvalue())<=64*1024**2
packet=gzip.compress(stream.getvalue(),mtime=0);assert len(packet)<=4*1024**2
print('OWN_NUMERICAL_BYTE_PACKET_SHA256='+hashlib.sha256(packet).hexdigest())
print('OWN_NUMERICAL_BYTE_PACKET_BASE64_BEGIN')
print(base64.b64encode(packet).decode())
print('OWN_NUMERICAL_BYTE_PACKET_BASE64_END')
PY
else printf 'OWN_NUMERICAL_REPORT_MISSING\n'; fi
printf 'OWN_NUMERICAL_READ_DONE\n'
