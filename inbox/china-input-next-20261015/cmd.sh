#!/bin/bash
set -eo pipefail
ROOT=/data1/home/sunyiq/china_input_completion_hpc_20261015_001/soil_topography_sources_v1
EXPECTED=242943
test ! -L "$ROOT"
test "$(cat "$ROOT/OWN_C1_JOB_ID")" = "$EXPECTED"
printf 'OWN_C1_QUERY_JOB_ID=%s\n' "$EXPECTED"
date -u '+OWN_C1_SERVER_QUERY_UTC=%Y-%m-%dT%H:%M:%SZ'
set +e
timeout 12s squeue -h -j "$EXPECTED" -o '%i|%T|%N|%C|%M'
printf 'OWN_C1_SQUEUE_EXIT=%s\n' "$?"
timeout 12s sacct -j "$EXPECTED" --format=JobID,State,ExitCode,Elapsed,AllocCPUS,AllocTRES,MaxRSS --parsable2 --noheader
printf 'OWN_C1_SACCT_EXIT=%s\n' "$?"
set -e
for file in "$ROOT/logs/c1-$EXPECTED.out" "$ROOT/logs/c1-$EXPECTED.err"; do
 printf 'OWN_C1_LOG=%s\n' "$file"
 if test -f "$file"; then head -c 8192 "$file"; printf '\n'; fi
done
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -B - <<'PY_READ'
import base64,hashlib,pathlib
root=pathlib.Path('/data1/home/sunyiq/china_input_completion_hpc_20261015_001/soil_topography_sources_v1')
for name in ['C1_RESULT.json','C1_FAILURE.json','C1_REPORTS.zip']:
 path=root/name
 if not path.exists():
  print('OWN_C1_MISSING='+name);continue
 assert not path.is_symlink() and path.is_file() and path.stat().st_size<=4194304
 raw=path.read_bytes()
 print('OWN_C1_FILE='+name)
 print('OWN_C1_BYTES='+str(len(raw)))
 print('OWN_C1_SHA256='+hashlib.sha256(raw).hexdigest())
 print('OWN_C1_BASE64_BEGIN')
 print(base64.b64encode(raw).decode())
 print('OWN_C1_BASE64_END')
for name in ['sources/SOURCE_RESULT.json','sources/DEM_HEADER.json','headers/HEADER_RESULT.json',
 'catalog/FUTURE_SOURCE_MANIFEST.json','soil_main/SUMMARY.json','soil_independent/INDEPENDENT_RESULT.json',
 'terrain_main/SUMMARY.json','terrain_independent/INDEPENDENT_RESULT.json']:
 print('OWN_C1_PATH_EXISTS='+name+'|'+str((root/name).exists()))
PY_READ
printf 'OWN_C1_READ_DONE\n'
