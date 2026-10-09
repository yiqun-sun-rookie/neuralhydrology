#!/usr/bin/env bash
set -eo pipefail
ROOT=/data1/home/sunyiq/hydrol85935_revision_20261008_001
DIR="$ROOT/diagnostics/path_trace_20261009_001"
CONTROL="$ROOT/control/path_trace_20261009_001"
test "$(readlink -f "$ROOT")" = "$ROOT"
test "$(cat "$ROOT/OWNER")" = hydrol85935_revision_20261008_001
date -Is
job=$(cat "$CONTROL/job_id")
test "$job" = 238886
sacct -j "$job" -n -P -o JobID,State,ExitCode,Elapsed,MaxRSS,NodeList
squeue -u "$USER" -o '%.18i %.14P %.35j %.10T %.12M %.8C %.20b %.30R'
for name in runtime.json summary.json comparisons.json default_stage.json deterministic_stage.json; do
  printf '\nFILE %s\n' "$name"
  if [ -f "$DIR/$name" ]; then cat "$DIR/$name"; else printf 'NOT_CREATED\n'; fi
done
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python - <<'PY'
import json
from pathlib import Path
root=Path('/data1/home/sunyiq/hydrol85935_revision_20261008_001')
folder=root/'diagnostics/path_trace_20261009_001'
control=root/'control/path_trace_20261009_001'
for setting in ('default','deterministic'):
    remote=folder/(setting+'_stage.json')
    if remote.exists():
        actual=json.loads(remote.read_text())
        expected=json.loads((control/('local_'+setting+'_stage.json')).read_text())
        print(json.dumps(dict(setting=setting,stage_input_identity_equal=actual==expected,remote=actual,local=expected)))
if (folder/'kernels.json').exists():
    data=json.loads((folder/'kernels.json').read_text())
    for setting,kernels in data.items():
        print(json.dumps(dict(setting=setting,cuda_kernel_count=len(kernels),kernels=kernels[:25] if isinstance(kernels,list) else kernels)))
if (folder/'results.json').exists():
    data=json.loads((folder/'results.json').read_text())
    for row in data:
        print(json.dumps(row))
PY
printf '\nSTDOUT_TAIL\n'
tail -n 3 "$ROOT/logs/path-trace-$job.out" || true
printf '\nSTDERR_TAIL\n'
tail -n 16 "$ROOT/logs/path-trace-$job.err" || true
