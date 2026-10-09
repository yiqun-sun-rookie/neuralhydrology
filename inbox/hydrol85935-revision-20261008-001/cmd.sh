#!/usr/bin/env bash
set -eo pipefail
ROOT=/data1/home/sunyiq/hydrol85935_revision_20261008_001
test "$(readlink -f "$ROOT")" = "$ROOT"
test "$(cat "$ROOT/OWNER")" = hydrol85935_revision_20261008_001
date -Is
squeue -u "$USER" -o '%.18i %.14P %.35j %.10T %.12M %.8C %.20b %.30R'
sacct -j 237696,237883,237904,237936,238679,238886 -n -P -o JobID,State,ExitCode,Elapsed,MaxRSS,NodeList
for name in control/continuation_v003/status.json control/runtime_setup_20261009_001/supervisor_exit_code control/runtime_setup_20261009_001/job_id runtime_torch271cu118/DOWNLOAD_COMPLETE.json runtime_torch271cu118/INSTALL_COMPLETE.json diagnostics/matched_runtime_20261009/summary.json diagnostics/path_trace_20261009_001/summary.json control/full_v003/jobs.json; do
  printf '\nFILE %s\n' "$name"
  if [ -f "$ROOT/$name" ]; then stat -c '%y %s bytes' "$ROOT/$name"; cat "$ROOT/$name"; else printf 'NOT_CREATED\n'; fi
done
printf '\nCONTINUATION_PROCESS\n'
pid=$(cat "$ROOT/control/continuation_v003/coordinator_pid")
ps -p "$pid" -o pid,etimes,args || true
printf '\nCONTINUATION_EVENTS\n'
tail -n 5 "$ROOT/control/continuation_v003/events.jsonl"
printf '\nSTAGE_LOGS\n'
find "$ROOT/logs" -maxdepth 1 -type f -printf '%f %s bytes %TY-%Tm-%TdT%TH:%TM:%TS\n' | sort
printf '\nEXECUTION_COMPLETION_MARKERS\n'
if [ -d "$ROOT/execution" ]; then find "$ROOT/execution" -name complete.json -type f -print | wc -l; else printf '0 execution directory absent\n'; fi
printf '\nNONSECRET_NUMERIC_RUNTIME_ENVIRONMENT\n'
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python - <<'PY'
import json,os
names=('NVIDIA_TF32_OVERRIDE','TORCH_ALLOW_TF32_CUBLAS_OVERRIDE','CUBLAS_WORKSPACE_CONFIG','CUDA_MODULE_LOADING','CUDNN_LOGLEVEL_DBG','CUDNN_LOGDEST_DBG','CUDNN_LOGINFO_DBG')
print(json.dumps({name:os.environ.get(name) for name in names}))
PY
