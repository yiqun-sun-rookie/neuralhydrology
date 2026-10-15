#!/bin/bash
set -eo pipefail
ROOT=/data1/home/sunyiq/china_input_completion_hpc_20261015_001/soil_pair_v1
EXPECTED=242833
test ! -L "$ROOT"
test "$(cat "$ROOT/OWN_SOIL_PAIR_JOB_ID")" = "$EXPECTED"
printf 'OWN_SOIL_PAIR_QUERY_JOB_ID=%s\n' "$EXPECTED"
date -u '+OWN_SOIL_PAIR_SERVER_QUERY_UTC=%Y-%m-%dT%H:%M:%SZ'
set +e
timeout 12s squeue -h -j "$EXPECTED" -o '%i|%T|%N|%C|%M'
printf 'OWN_SOIL_PAIR_SQUEUE_EXIT=%s\n' "$?"
timeout 12s sacct -j "$EXPECTED" --format=JobID,State,ExitCode,Elapsed,AllocCPUS,AllocTRES,MaxRSS --parsable2 --noheader
printf 'OWN_SOIL_PAIR_SACCT_EXIT=%s\n' "$?"
set -e
for file in "$ROOT/logs/soil-$EXPECTED.out" "$ROOT/logs/soil-$EXPECTED.err"; do
 printf 'OWN_SOIL_PAIR_LOG=%s\n' "$file"
 if test -f "$file"; then head -c 8192 "$file"; printf '\n'; fi
done
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -B - <<'PY_READ'
import base64,hashlib,pathlib
root=pathlib.Path('/data1/home/sunyiq/china_input_completion_hpc_20261015_001/soil_pair_v1')
for name in ['PAIR_RESULT.json','PAIR_FAILURE.json','SOIL_REPORTS.zip']:
 path=root/name
 if not path.exists():
  print('OWN_SOIL_PAIR_MISSING='+name);continue
 assert not path.is_symlink() and path.is_file() and path.stat().st_size<=4194304
 raw=path.read_bytes()
 print('OWN_SOIL_PAIR_FILE='+name)
 print('OWN_SOIL_PAIR_BYTES='+str(len(raw)))
 print('OWN_SOIL_PAIR_SHA256='+hashlib.sha256(raw).hexdigest())
 print('OWN_SOIL_PAIR_BASE64_BEGIN')
 print(base64.b64encode(raw).decode())
 print('OWN_SOIL_PAIR_BASE64_END')
for name in ['vegetation_probe/PROBE_RESULT.json','main.stdout','main/SUMMARY.json','independent.stdout','independent/INDEPENDENT_RESULT.json']:
 print('OWN_SOIL_PAIR_PATH_EXISTS='+name+'|'+str((root/name).exists()))
PY_READ
printf 'OWN_SOIL_PAIR_READ_DONE\n'
