#!/bin/bash
set -eo pipefail
ROOT=/data1/home/sunyiq/china_input_completion_hpc_20261015_001/preflight_v1
EXPECTED=242773
test ! -L "$ROOT"
test "$(cat "$ROOT/OWN_INPUT_JOB_ID")" = "$EXPECTED"
printf 'OWN_INPUT_QUERY_JOB_ID=%s\n' "$EXPECTED"
date -u '+OWN_INPUT_SERVER_QUERY_UTC=%Y-%m-%dT%H:%M:%SZ'
set +e
timeout 12s squeue -h -j "$EXPECTED" -o '%i|%T|%N|%C|%M'
printf 'OWN_INPUT_SQUEUE_EXIT=%s\n' "$?"
timeout 12s sacct -j "$EXPECTED" --format=JobID,State,ExitCode,Elapsed,AllocCPUS,AllocTRES,MaxRSS --parsable2 --noheader
printf 'OWN_INPUT_SACCT_EXIT=%s\n' "$?"
set -e
for file in "$ROOT/logs/preflight-$EXPECTED.out" "$ROOT/logs/preflight-$EXPECTED.err"; do
 printf 'OWN_INPUT_LOG=%s\n' "$file"
 if test -f "$file"; then head -c 16384 "$file"; printf '\n'; fi
done
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -B - <<'PY_READ'
import base64,hashlib,pathlib
root=pathlib.Path('/data1/home/sunyiq/china_input_completion_hpc_20261015_001/preflight_v1')
for name in ['RESULT.json','FAILURE.json','REPORTS.zip']:
 p=root/name
 if not p.exists():
  print('OWN_INPUT_MISSING='+name)
  continue
 assert p.is_file() and not p.is_symlink() and p.stat().st_size<=1048576
 raw=p.read_bytes()
 print('OWN_INPUT_FILE='+name)
 print('OWN_INPUT_BYTES='+str(len(raw)))
 print('OWN_INPUT_SHA256='+hashlib.sha256(raw).hexdigest())
 print('OWN_INPUT_BASE64_BEGIN')
 print(base64.b64encode(raw).decode())
 print('OWN_INPUT_BASE64_END')
PY_READ
printf 'OWN_INPUT_READ_DONE\n'
