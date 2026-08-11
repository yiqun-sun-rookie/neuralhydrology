#!/bin/bash
# ID29 seq=266: early read-only matrix health audit to reassess job 202214 restart projection.
set -eo pipefail

if false; then

ROOT='/data1/home/sunyiq/nearing2022_da'
JOB_ID=202214
INCIDENT_DIR="$ROOT/closure_20260810/recovery/job202214_cuda_stall_seq262"
OUTPUT_PARENT="$ROOT/closure_20260810/time_split/autoregression"

echo '=== POST-RELEASE VERIFICATION START ==='
date --iso-8601=seconds
job_record="$(scontrol show job -o "$JOB_ID")"
printf '%s\n' "$job_record"
[[ " $job_record " == *' Requeue=1 '* ]]
[[ " $job_record " == *' Restarts=1 '* ]]
[[ " $job_record " != *' Reason=JobHeldUser '* ]]
[[ " $job_record " != *' Reason=job_requeued_in_held_state '* ]]
excluded_hostlist="$(printf '%s\n' "$job_record" | tr ' ' '\n' | sed -n 's/^ExcNodeList=//p' | head -n 1)"
mapfile -t excluded_nodes < <(scontrol show hostnames "$excluded_hostlist")
printf 'excluded_node=%s\n' "${excluded_nodes[@]}"
printf '%s\n' "${excluded_nodes[@]}" | grep -Fxq 'ngu002'
printf '%s\n' "${excluded_nodes[@]}" | grep -Fxq 'ngu104'
if [[ " $job_record " == *' JobState=RUNNING '* ]]; then
  [[ " $job_record " != *' NodeList=ngu104 '* ]]
fi

echo '=== INCIDENT MANIFEST RECHECK ==='
[[ "$(sha256sum "$INCIDENT_DIR/MANIFEST.sha256" | awk '{print $1}')" == \
   '59f929d602d9e96948e9f049ee217f64c6c5fc0dfb72cc944ee985ec35d9bcfd' ]]
(
  cd "$INCIDENT_DIR"
  sha256sum -c MANIFEST.sha256
)

echo '=== SOURCE CANDIDATES ==='
while IFS= read -r candidate_dir; do
  if [[ -f "$candidate_dir/model_epoch030.pt" ]]; then
    checkpoint030=yes
  else
    checkpoint030=no
  fi
  printf '%s|checkpoint030=%s\n' "$candidate_dir" "$checkpoint030"
done < <(find "$OUTPUT_PARENT" -mindepth 1 -maxdepth 1 -type d \
  -name 'nearing2022_full_time_autoregression_lead1_holdout0.5_seed0_*_ep30' -print | sort)

echo '=== ACTIVE SLURM LOGS ==='
for log_path in "$ROOT/closure_20260810/logs/N22-train_202214.out" \
  "$ROOT/closure_20260810/logs/N22-train_202214.err"; do
  if [[ -f "$log_path" ]]; then
    stat -c '%n|bytes=%s|mtime=%y|inode=%i' "$log_path"
    tail -c 16384 "$log_path" | tr '\r' '\n' | tail -n 40
  else
    echo "missing=$log_path"
  fi
done

echo '=== POST-RELEASE VERIFICATION END ==='
date --iso-8601=seconds
echo 'read_only=true'
exit 0

ROOT='/data1/home/sunyiq/nearing2022_da'
JOB_ID=202214
INCIDENT_DIR="$ROOT/closure_20260810/recovery/job202214_cuda_stall_seq262"

echo '=== RECOVERY ATTEMPT 1 RESUME START ==='
date --iso-8601=seconds
held_record="$(scontrol show job -o "$JOB_ID")"
printf '%s\n' "$held_record"
[[ " $held_record " == *' JobState=PENDING '* ]]
[[ " $held_record " == *' Requeue=1 '* ]]
[[ " $held_record " == *' Restarts=1 '* ]]
[[ " $held_record " == *' Reason=job_requeued_in_held_state '* || \
   " $held_record " == *' Reason=JobHeldUser '* ]]
[[ "$(sha256sum "$INCIDENT_DIR/MANIFEST.sha256" | awk '{print $1}')" == \
   '59f929d602d9e96948e9f049ee217f64c6c5fc0dfb72cc944ee985ec35d9bcfd' ]]
(
  cd "$INCIDENT_DIR"
  sha256sum -c MANIFEST.sha256
)

echo '=== EXCLUDE FAILED NODE ==='
scontrol update JobId="$JOB_ID" ExcNodeList=ngu002,ngu104
excluded_record="$(scontrol show job -o "$JOB_ID")"
printf '%s\n' "$excluded_record"
excluded_hostlist="$(printf '%s\n' "$excluded_record" | tr ' ' '\n' | sed -n 's/^ExcNodeList=//p' | head -n 1)"
mapfile -t excluded_nodes < <(scontrol show hostnames "$excluded_hostlist")
printf 'excluded_node=%s\n' "${excluded_nodes[@]}"
printf '%s\n' "${excluded_nodes[@]}" | grep -Fxq 'ngu002'
printf '%s\n' "${excluded_nodes[@]}" | grep -Fxq 'ngu104'

echo '=== RELEASE REQUEUED JOB ==='
scontrol release "$JOB_ID"
released=false
for _ in $(seq 1 60); do
  released_record="$(scontrol show job -o "$JOB_ID")"
  if [[ " $released_record " == *' JobState=PENDING '* || " $released_record " == *' JobState=RUNNING '* ]]; then
    if [[ " $released_record " != *' Reason=JobHeldUser '* && \
         " $released_record " != *' Reason=job_requeued_in_held_state '* ]]; then
      released=true
      break
    fi
  fi
  sleep 2
done
printf '%s\n' "$released_record"
[[ "$released" == true ]]
[[ " $released_record " == *' Requeue=1 '* ]]
[[ " $released_record " == *' Restarts=1 '* ]]
if [[ " $released_record " == *' JobState=RUNNING '* ]]; then
  [[ " $released_record " != *' NodeList=ngu104 '* ]]
fi

echo '=== RECOVERY ATTEMPT 1 RESUME END ==='
date --iso-8601=seconds
echo 'failure_evidence_reverified=true'
echo 'failed_node_excluded=true'
echo 'registered_job_id_preserved=true'
exit 0

ROOT='/data1/home/sunyiq/nearing2022_da'
JOB_ID=202214
RUN_DIR="$ROOT/closure_20260810/time_split/autoregression/nearing2022_full_time_autoregression_lead1_holdout0.5_seed0_2026_0810_1200_ep30"
LOG_DIR="$ROOT/closure_20260810/logs"
INCIDENT_DIR="$ROOT/closure_20260810/recovery/job202214_cuda_stall_seq262"

echo '=== RECOVERY ATTEMPT 1 START ==='
date --iso-8601=seconds

job_before="$(scontrol show job -o "$JOB_ID")"
printf '%s\n' "$job_before"
[[ " $job_before " == *' JobState=RUNNING '* ]]
[[ " $job_before " == *' NodeList=ngu104 '* ]]
[[ " $job_before " == *' Requeue=0 '* ]]
[[ ! -e "$RUN_DIR/model_epoch030.pt" ]]
[[ ! -e "$INCIDENT_DIR" ]]

mkdir -p "$ROOT/closure_20260810/recovery"
mkdir "$INCIDENT_DIR"

copy_and_verify() {
  local source_path="$1"
  local target_name="$2"
  local expected_sha256="${3:-}"
  local source_sha256
  local target_sha256
  [[ -f "$source_path" ]]
  source_sha256="$(sha256sum "$source_path" | awk '{print $1}')"
  if [[ -n "$expected_sha256" ]]; then
    [[ "$source_sha256" == "$expected_sha256" ]]
  fi
  cp --reflink=auto --preserve=mode,timestamps -- "$source_path" "$INCIDENT_DIR/$target_name"
  cmp -s -- "$source_path" "$INCIDENT_DIR/$target_name"
  target_sha256="$(sha256sum "$INCIDENT_DIR/$target_name" | awk '{print $1}')"
  [[ "$source_sha256" == "$target_sha256" ]]
  printf '%s  %s\n' "$target_sha256" "$target_name"
}

echo '=== INCIDENT COPY HASHES ==='
copy_and_verify "$LOG_DIR/N22-train_202214.out" 'slurm_stdout.out'
copy_and_verify "$LOG_DIR/N22-train_202214.err" 'slurm_stderr.err'
copy_and_verify "$RUN_DIR/config.yml" 'run_config.yml' \
  'df3b834bc27d939d69731019c32a71eb02c386e3d7a2c50a1ad32186043b6e9e'
copy_and_verify "$RUN_DIR/train_data/train_data_scaler.yml" 'train_data_scaler.yml' \
  '97cb80f9f9b7b08f3cf627293a81a912bbe39b6bb65ea1c484bf51c10a8558bc'
copy_and_verify "$RUN_DIR/model_epoch029.pt" 'model_epoch029.pt' \
  '4ccbca0040f969749807081984ebf5d3cc5f9cc1d9b62b04c7d34a8b9ccfc975'
copy_and_verify "$RUN_DIR/optimizer_state_epoch029.pt" 'optimizer_state_epoch029.pt' \
  '1f6fb09b6bb9c03d332b6b047d996a66e44f98c838a335a22c2ccb567ff9e0c4'
copy_and_verify "$RUN_DIR/output.log" 'run_output.log' \
  'cec12be5cbf08ecd654bf75b93026ecd08dd6899f7b87cd338772759a7df1b58'

(
  cd "$INCIDENT_DIR"
  sha256sum model_epoch029.pt optimizer_state_epoch029.pt run_config.yml run_output.log \
    slurm_stderr.err slurm_stdout.out train_data_scaler.yml > MANIFEST.sha256.tmp
  mv MANIFEST.sha256.tmp MANIFEST.sha256
  sha256sum -c MANIFEST.sha256
)
chmod a-w "$INCIDENT_DIR"/*
chmod a-w "$INCIDENT_DIR"
echo "incident_dir=$INCIDENT_DIR"
sha256sum "$INCIDENT_DIR/MANIFEST.sha256"

echo '=== ENABLE MANUAL REQUEUE ==='
scontrol update JobId="$JOB_ID" Requeue=1
job_requeue_enabled="$(scontrol show job -o "$JOB_ID")"
printf '%s\n' "$job_requeue_enabled"
[[ " $job_requeue_enabled " == *' Requeue=1 '* ]]

echo '=== REQUEUE AND HOLD ==='
scontrol requeuehold "$JOB_ID"
held=false
for _ in $(seq 1 60); do
  held_record="$(scontrol show job -o "$JOB_ID")"
  if [[ " $held_record " == *' JobState=PENDING '* && " $held_record " == *' Reason=JobHeldUser '* ]]; then
    held=true
    break
  fi
  sleep 2
done
printf '%s\n' "$held_record"
[[ "$held" == true ]]

echo '=== EXCLUDE FAILED NODE ==='
scontrol update JobId="$JOB_ID" ExcNodeList=ngu002,ngu104
excluded_record="$(scontrol show job -o "$JOB_ID")"
printf '%s\n' "$excluded_record"
excluded_hostlist="$(printf '%s\n' "$excluded_record" | tr ' ' '\n' | sed -n 's/^ExcNodeList=//p' | head -n 1)"
mapfile -t excluded_nodes < <(scontrol show hostnames "$excluded_hostlist")
printf 'excluded_node=%s\n' "${excluded_nodes[@]}"
printf '%s\n' "${excluded_nodes[@]}" | grep -Fxq 'ngu002'
printf '%s\n' "${excluded_nodes[@]}" | grep -Fxq 'ngu104'

echo '=== RELEASE REQUEUED JOB ==='
scontrol release "$JOB_ID"
released=false
for _ in $(seq 1 60); do
  released_record="$(scontrol show job -o "$JOB_ID")"
  if [[ " $released_record " == *' JobState=PENDING '* || " $released_record " == *' JobState=RUNNING '* ]]; then
    if [[ " $released_record " != *' Reason=JobHeldUser '* ]]; then
      released=true
      break
    fi
  fi
  sleep 2
done
printf '%s\n' "$released_record"
[[ "$released" == true ]]
[[ " $released_record " == *' Requeue=1 '* ]]
if [[ " $released_record " == *' JobState=RUNNING '* ]]; then
  [[ " $released_record " != *' NodeList=ngu104 '* ]]
fi

echo '=== RECOVERY ATTEMPT 1 END ==='
date --iso-8601=seconds
echo 'failure_evidence_preserved=true'
echo 'original_config_full_restart=true'
echo 'registered_job_id_preserved=true'
exit 0

export LC_ALL=C
JOB_ID=202214

echo '=== DIAGNOSTIC SNAPSHOT START ==='
date --iso-8601=seconds

echo '=== SCONTROL JOB RECORD ==='
job_record="$(scontrol show job -o "$JOB_ID")"
printf '%s\n' "$job_record"

stdout_path="$(printf '%s\n' "$job_record" | tr ' ' '\n' | sed -n 's/^StdOut=//p' | head -n 1)"
stderr_path="$(printf '%s\n' "$job_record" | tr ' ' '\n' | sed -n 's/^StdErr=//p' | head -n 1)"
batch_host="$(printf '%s\n' "$job_record" | tr ' ' '\n' | sed -n 's/^BatchHost=//p' | head -n 1)"

echo '=== SQUEUE JOB RECORD ==='
squeue -h -j "$JOB_ID" -o '%i|%T|%M|%l|%N|%R|%C|%m|%b|%j'

echo '=== SACCT JOB AND STEP RECORDS ==='
sacct -j "$JOB_ID" -n -P \
  --format=JobIDRaw,JobName,State,ExitCode,Elapsed,Timelimit,Start,End,NodeList,AllocCPUS,ReqMem,AllocTRES

echo '=== SSTAT SNAPSHOT 1 ==='
sstat -a -j "$JOB_ID" -n -P \
  --format=JobID,AveCPU,AveRSS,MaxRSS,MaxVMSize,MaxDiskRead,MaxDiskWrite,NTasks || true

echo '=== NODE RECORD ==='
if [[ -n "$batch_host" && "$batch_host" != '(null)' ]]; then
  scontrol show node -o "$batch_host" || true
fi

echo '=== COMPUTE-NODE PROCESS AND GPU RECORDS ==='
if [[ -n "$batch_host" && "$batch_host" != '(null)' ]]; then
  if ! timeout 30 ssh -o BatchMode=yes -o ConnectTimeout=10 "$batch_host" bash -s -- "$JOB_ID" <<'REMOTE_DIAGNOSTIC'
set -uo pipefail
job_id="$1"
echo '--- listpids ---'
scontrol listpids "$job_id" || true
echo '--- user process table ---'
ps -u "$USER" -o pid=,ppid=,lstart=,etime=,state=,pcpu=,pmem=,wchan:32=,args= --sort=pid || true
echo '--- gpu devices ---'
nvidia-smi \
  --query-gpu=index,uuid,utilization.gpu,utilization.memory,memory.used,memory.total,pstate,temperature.gpu \
  --format=csv,noheader,nounits || true
echo '--- gpu compute processes ---'
nvidia-smi --query-compute-apps=gpu_uuid,pid,process_name,used_gpu_memory \
  --format=csv,noheader,nounits || true
echo '--- target main process ---'
main_pid=''
while read -r candidate_pid; do
  [[ -n "$candidate_pid" ]] || continue
  candidate_cmd="$(tr '\0' ' ' < "/proc/$candidate_pid/cmdline" 2>/dev/null || true)"
  if [[ "$candidate_cmd" == *'/time_split/autoregression/lead_1_holdout_0.5_seed_0.yml'* ]]; then
    main_pid="$candidate_pid"
    break
  fi
done < <(nvidia-smi --query-compute-apps=pid --format=csv,noheader,nounits 2>/dev/null || true)
echo "main_pid=$main_pid"
if [[ -n "$main_pid" && -d "/proc/$main_pid" ]]; then
  echo '--- main process status ---'
  cat "/proc/$main_pid/status" || true
  echo '--- main process io ---'
  cat "/proc/$main_pid/io" || true
  echo '--- main process kernel wait channel ---'
  cat "/proc/$main_pid/wchan" || true
  echo
  echo '--- main process threads ---'
  ps -L -p "$main_pid" -o pid=,tid=,psr=,stat=,pcpu=,wchan:32=,comm= --sort=-pcpu | head -n 80 || true
  echo '--- python stack sampler availability ---'
  command -v py-spy || true
  echo '--- native diagnostic tool availability ---'
  for tool in gdb pstack eu-stack strace perf; do
    tool_path="$(command -v "$tool" 2>/dev/null || true)"
    echo "$tool=$tool_path"
  done
  echo '--- main process kernel stack availability ---'
  cat "/proc/$main_pid/stack" || true
  echo '--- bounded native stack trace ---'
  timeout -k 5 30 gdb -nx -batch -q -p "$main_pid" \
    -ex 'set pagination off' \
    -ex 'set confirm off' \
    -ex 'thread apply all bt 24' \
    -ex 'detach' || echo "gdb_stack_exit=$?"
fi
echo '--- gpu process monitor ---'
nvidia-smi pmon -i 1 -s um -d 1 -c 8 || true
echo '--- gpu 1 full health record ---'
nvidia-smi -i 1 -q || true
echo '--- recent kernel NVIDIA records ---'
dmesg 2>/dev/null | grep -Ei 'NVRM|Xid|GPU' | tail -n 80 || true
REMOTE_DIAGNOSTIC
  then
    echo "compute_node_probe_failed=$batch_host"
  fi
fi

echo '=== RUN-DIRECTORY CHECKPOINT RECORDS ==='
run_dir='/data1/home/sunyiq/nearing2022_da/closure_20260810/time_split/autoregression/nearing2022_full_time_autoregression_lead1_holdout0.5_seed0_2026_0810_1200_ep30'
if [[ -d "$run_dir" ]]; then
  find "$run_dir" -maxdepth 2 -type f -printf '%T@|%s|%p\n' | sort -n | tail -n 80
  echo '--- recovery input sha256 ---'
  sha256sum \
    "$run_dir/config.yml" \
    "$run_dir/train_data/train_data_scaler.yml" \
    "$run_dir/model_epoch029.pt" \
    "$run_dir/optimizer_state_epoch029.pt" \
    "$run_dir/output.log"
else
  echo "run_dir_missing=$run_dir"
fi

echo '=== LOG METADATA SNAPSHOT 1 ==='
if [[ -f "$stdout_path" ]]; then
  stat -c 'stdout|%n|bytes=%s|mtime=%y|mtime_epoch=%Y|inode=%i' "$stdout_path"
  stdout_size_before="$(stat -c '%s' "$stdout_path")"
  stdout_mtime_before="$(stat -c '%Y' "$stdout_path")"
else
  echo "stdout_missing=$stdout_path"
  stdout_size_before=-1
  stdout_mtime_before=-1
fi
if [[ -f "$stderr_path" ]]; then
  stat -c 'stderr|%n|bytes=%s|mtime=%y|mtime_epoch=%Y|inode=%i' "$stderr_path"
else
  echo "stderr_missing=$stderr_path"
fi

sleep 15

echo '=== SSTAT SNAPSHOT 2 ==='
sstat -a -j "$JOB_ID" -n -P \
  --format=JobID,AveCPU,AveRSS,MaxRSS,MaxVMSize,MaxDiskRead,MaxDiskWrite,NTasks || true

echo '=== LOG METADATA SNAPSHOT 2 ==='
if [[ -f "$stdout_path" ]]; then
  stat -c 'stdout|%n|bytes=%s|mtime=%y|mtime_epoch=%Y|inode=%i' "$stdout_path"
  stdout_size_after="$(stat -c '%s' "$stdout_path")"
  stdout_mtime_after="$(stat -c '%Y' "$stdout_path")"
  echo "stdout_size_delta_15s=$((stdout_size_after - stdout_size_before))"
  echo "stdout_mtime_delta_15s=$((stdout_mtime_after - stdout_mtime_before))"
  echo '=== STDOUT TAIL ==='
  tail -c 65536 "$stdout_path" | tr '\r' '\n' | tail -n 120
fi
if [[ -f "$stderr_path" ]]; then
  stat -c 'stderr|%n|bytes=%s|mtime=%y|mtime_epoch=%Y|inode=%i' "$stderr_path"
  echo '=== STDERR TAIL ==='
  tail -n 120 "$stderr_path"
fi

echo '=== DIAGNOSTIC SNAPSHOT END ==='
date --iso-8601=seconds
echo 'read_only=true'
exit 0

fi
ROOT=/data1/home/sunyiq/nearing2022_da
IDEA="$ROOT/src/29_nearing2022_da_ar"
REGISTRY="$IDEA/registry"
AGGREGATION="$ROOT/closure_20260810/aggregation"
DIAGNOSTICS="$ROOT/results/29_nearing2022_da_ar/formal_closure/diagnostics"
MAIN_JOBS=202214,202215,202216,202222,202226,202227,202228,202229,202230,202238,202293,202294,202315

echo "=== SNAPSHOT TIME ==="
date --iso-8601=seconds

source ~/miniconda3/etc/profile.d/conda.sh
conda activate nh_final
cd "$ROOT"
export PYTHONPATH="$ROOT${PYTHONPATH:+:$PYTHONPATH}"

echo "=== REGISTERED COMPLETE-ROLE COUNTS ==="
python - "$ROOT" "$IDEA" "$REGISTRY" "$AGGREGATION" <<'PY'
from collections import Counter
import json
from pathlib import Path
import sys

import pandas as pd

root = Path(sys.argv[1]).resolve()
idea = Path(sys.argv[2]).resolve()
registry = Path(sys.argv[3]).resolve()
aggregation = Path(sys.argv[4]).resolve()
sys.path.insert(0, str(idea / 'scripts'))

from verify_registered_closure import audit_registered_closure

training = pd.read_csv(registry / 'experiment_registry.csv', keep_default_na=False, dtype=str)
evaluations = pd.read_csv(registry / 'evaluation_registry.csv', keep_default_na=False, dtype=str)
hyperparameters = pd.read_csv(
    registry / 'assimilation_hyperparameter_registry.csv', keep_default_na=False, dtype=str,
)
closure = audit_registered_closure(
    root,
    registry / 'experiment_registry.csv',
    registry / 'evaluation_registry.csv',
    registry / 'assimilation_hyperparameter_registry.csv',
    aggregation / 'evaluations',
    aggregation / 'hyperparameters',
)
missing = {
    coordinate_type: {
        row['coordinate_id'] for row in closure['missing']
        if row['coordinate_type'] == coordinate_type
    }
    for coordinate_type in ('training', 'evaluation', 'hyperparameter')
}


def family_counts(frame, identifier, coordinate_type):
    return dict(sorted(Counter(
        row['family'] for _, row in frame.iterrows()
        if row[identifier] not in missing[coordinate_type]
    ).items()))


print(json.dumps({
    'training_complete': len(training) - len(missing['training']),
    'training_total': len(training),
    'training_by_family': family_counts(training, 'exp_id', 'training'),
    'evaluation_complete': len(evaluations) - len(missing['evaluation']),
    'evaluation_total': len(evaluations),
    'evaluation_by_family': family_counts(evaluations, 'eval_id', 'evaluation'),
    'hyperparameter_complete': len(hyperparameters) - len(missing['hyperparameter']),
    'hyperparameter_total': len(hyperparameters),
    'hyperparameter_by_family': family_counts(hyperparameters, 'eval_id', 'hyperparameter'),
    'missing_roles_total': len(closure['missing']),
    'registered_matrix_complete': closure['complete'],
}, sort_keys=True))
PY

echo "=== EVALUATION ARRAY TASK RECORDS ==="
sacct -n -P -j 202222 --format=JobID,State,ExitCode,ElapsedRaw,Elapsed,Start,End

echo "=== PLANNING ESTIMATE ==="
python - <<'PY'
from datetime import datetime, timedelta
import json
import math
from pathlib import Path
import re
import statistics
import subprocess

records = subprocess.run(
    [
        'sacct', '-n', '-P', '-j', '202222',
        '--format=JobID,State,ExitCode,ElapsedRaw,Elapsed,Start,End',
    ],
    check=True, capture_output=True, text=True,
).stdout.splitlines()
task_pattern = re.compile(r'^202222_(\d+)$')
tasks = {}
for line in records:
    fields = line.split('|')
    if len(fields) < 7:
        continue
    match = task_pattern.fullmatch(fields[0])
    if not match:
        continue
    task = int(match.group(1))
    tasks[task] = {
        'state': fields[1],
        'exit_code': fields[2],
        'elapsed_seconds': int(fields[3] or 0),
        'elapsed': fields[4],
        'start': fields[5],
        'end': fields[6],
    }

completed = sorted(task for task, row in tasks.items() if row['state'] == 'COMPLETED')
running = sorted(task for task, row in tasks.items() if row['state'] == 'RUNNING')
pending = sorted(set(range(30)) - set(completed) - set(running))
failed = sorted(
    task for task, row in tasks.items()
    if row['state'] in {
        'FAILED', 'TIMEOUT', 'OUT_OF_MEMORY', 'NODE_FAIL', 'PREEMPTED',
        'BOOT_FAIL', 'DEADLINE',
    }
)
long_durations = sorted(
    tasks[task]['elapsed_seconds'] for task in completed
    if tasks[task]['elapsed_seconds'] >= 3600
)
if not long_durations:
    raise ValueError('No completed long evaluation tasks are available for planning')

ansi = re.compile(r'\x1b\[[0-9;]*[A-Za-z]')
progress_pattern = re.compile(r'(?<!Epoch\s)(\d+)%\|.*?\|\s*(\d+)/(\d+)')
running_estimates = []
for task in running:
    job = f'202222_{task}'
    record = subprocess.run(
        ['scontrol', 'show', 'job', '-o', job], check=True, capture_output=True, text=True,
    ).stdout.strip()
    fields = dict(token.split('=', 1) for token in record.split() if '=' in token)
    stdout = Path(fields['StdOut'])
    payload = {'task': task, 'job': job, 'runtime': fields['RunTime']}
    if stdout.is_file():
        size = stdout.stat().st_size
        with stdout.open('rb') as handle:
            handle.seek(max(0, size - 4 * 1024 * 1024))
            tail = ansi.sub('', handle.read().decode('utf-8', errors='replace')).replace('\r', '\n')
        matches = list(progress_pattern.finditer(tail))
        if matches:
            percent, step, total = map(int, matches[-1].groups())
            fraction = step / total
            elapsed = tasks[task]['elapsed_seconds']
            total_seconds = elapsed / fraction
            remaining_seconds = max(0.0, total_seconds - elapsed)
            payload.update({
                'reported_percent': percent,
                'completed_basins': step,
                'total_basins': total,
                'projected_total_hours': round(total_seconds / 3600, 2),
                'projected_remaining_hours': round(remaining_seconds / 3600, 2),
            })
    running_estimates.append(payload)

if not running_estimates or any('projected_remaining_hours' not in row for row in running_estimates):
    raise ValueError('Every running task must have a progress-based projection')

current_wave_remaining = max(row['projected_remaining_hours'] for row in running_estimates)
future_waves = math.ceil(len(pending) / 2)
duration_hours = {
    'lower': min(long_durations) / 3600,
    'median': statistics.median(long_durations) / 3600,
    'upper': max(long_durations) / 3600,
}
now = datetime.now().astimezone()
finish = {
    key: now + timedelta(hours=current_wave_remaining + future_waves * value)
    for key, value in duration_hours.items()
}
print(json.dumps({
    'schema': 'nearing2022-evaluation-array-planning-estimate-v1',
    'array_job_id': '202222',
    'array_tasks_total': 30,
    'array_concurrency': 2,
    'completed_tasks': completed,
    'running_tasks': running,
    'pending_tasks': pending,
    'failed_tasks': failed,
    'completed_long_task_count': len(long_durations),
    'completed_long_duration_hours': [round(value / 3600, 3) for value in long_durations],
    'completed_long_duration_summary_hours': {
        key: round(value, 3) for key, value in duration_hours.items()
    },
    'running_task_estimates': running_estimates,
    'future_waves_after_current': future_waves,
    'projected_dependency_release': {
        key: value.isoformat(timespec='seconds') for key, value in finish.items()
    },
    'replacement_job_202510_can_start_only_after_parent_terminal': True,
    'planning_only': True,
    'registered_matrix_modified': False,
}, indent=2, sort_keys=True))
PY

echo "=== LIVE RUNNING PROGRESS AND WALLTIME PROJECTION ==="
python - "$MAIN_JOBS" <<'PY'
import json
from pathlib import Path
import re
import subprocess
import sys

parents = sys.argv[1]
running = subprocess.run(
    ['squeue', '-h', '-j', parents, '-t', 'RUNNING', '-o', '%i'],
    check=True, capture_output=True, text=True,
).stdout.split()
ansi = re.compile(r'\x1b\[[0-9;]*[A-Za-z]')
epoch_pattern = re.compile(r'# Epoch\s+(\d+):\s*(\d+)%\|.*?\|\s*(\d+)/(\d+)')
generic_pattern = re.compile(r'(?<!Epoch\s)(\d+)%\|.*?\|\s*(\d+)/(\d+)')


def seconds(value):
    days = 0
    if '-' in value:
        day_text, value = value.split('-', 1)
        days = int(day_text)
    fields = [int(item) for item in value.split(':')]
    if len(fields) == 3:
        hours, minutes, secs = fields
    else:
        hours, minutes, secs = 0, fields[0], fields[1]
    return days * 86400 + hours * 3600 + minutes * 60 + secs


risk_jobs = []
for job in sorted(running):
    record = subprocess.run(
        ['scontrol', 'show', 'job', '-o', job], check=True, capture_output=True, text=True,
    ).stdout.strip()
    fields = dict(token.split('=', 1) for token in record.split() if '=' in token)
    stdout = Path(fields['StdOut'])
    payload = {
        'job': job,
        'name': fields['JobName'],
        'runtime': fields['RunTime'],
        'time_limit': fields['TimeLimit'],
        'stdout_exists': stdout.is_file(),
    }
    if stdout.is_file():
        size = stdout.stat().st_size
        with stdout.open('rb') as handle:
            handle.seek(max(0, size - 4 * 1024 * 1024))
            tail = ansi.sub('', handle.read().decode('utf-8', errors='replace')).replace('\r', '\n')
        epochs = list(epoch_pattern.finditer(tail))
        generic = list(generic_pattern.finditer(tail))
        payload['stdout_bytes'] = size
        if epochs:
            epoch, _, step, total = map(int, epochs[-1].groups())
            fraction = ((epoch - 1) + step / total) / 30
            projected = seconds(fields['RunTime']) / fraction if fraction > 0 else None
            limit = seconds(fields['TimeLimit'])
            risk = projected > limit
            payload.update({
                'epoch': epoch,
                'epoch_step': step,
                'epoch_total_steps': total,
                'thirty_epoch_fraction': round(fraction, 6),
                'projected_total_hours': round(projected / 3600, 2),
                'projected_slack_hours': round((limit - projected) / 3600, 2),
                'time_limit_risk': risk,
            })
            if risk:
                risk_jobs.append(job)
        elif generic:
            percent, step, total = map(int, generic[-1].groups())
            payload.update({'percent': percent, 'step': step, 'total': total})
    print(json.dumps(payload, sort_keys=True))
print(json.dumps({'time_limit_risk_jobs': sorted(risk_jobs), 'running_jobs': len(running)}, sort_keys=True))
PY

echo "=== MAIN JOB STATES AND FAILURE GATE ==="
squeue -h -j "$MAIN_JOBS" -o '%i|%T|%M|%l|%R|%j' | sort
sacct -n -X -P -j "$MAIN_JOBS" --format=JobIDRaw,JobName,State,ExitCode,Elapsed,Start,End,NodeList
MAIN_FAILURES=$(sacct -n -X -P -j "$MAIN_JOBS" --format=JobIDRaw,JobName,State,ExitCode | \
  awk -F'|' '$3 ~ /^(FAILED|TIMEOUT|OUT_OF_MEMORY|NODE_FAIL|PREEMPTED|BOOT_FAIL|DEADLINE)/')
printf '%s\n' "$MAIN_FAILURES"
test -z "$MAIN_FAILURES"

echo "=== REPLACEMENT AND FROZEN STATES ==="
sacct -n -X -P -j 202510,202511 --format=JobIDRaw,JobName,State,ExitCode,Elapsed,Reason
squeue -h -j 202510,202511 -o '%i|%j|%T|%M|%R|%E' | sort
find "$DIAGNOSTICS" -maxdepth 1 -mindepth 1 \
  \( -name 'author_v13_training_data_port_all531_v2*' \
  -o -name 'author_v13_warmup_isolation_all531_v2*' \
  -o -name 'warmup_target_replacement_verification_v1*' \) -printf '%f|%y\n' | sort

PAIR_PRESENT=0
for relative in \
  src/29_nearing2022_da_ar/scripts/prepare_warmup_target_pair.py \
  src/29_nearing2022_da_ar/scripts/analyze_warmup_target_pair.py \
  src/29_nearing2022_da_ar/hpc/run_warmup_target_pair.slurm \
  src/29_nearing2022_da_ar/hpc/analyze_warmup_target_pair.slurm \
  test/test_nearing2022_warmup_pair.py; do
  if test -e "$ROOT/$relative"; then PAIR_PRESENT=$((PAIR_PRESENT + 1)); fi
done
echo "paired_training_payload_present=$PAIR_PRESENT"
test "$PAIR_PRESENT" -eq 0
PAIR_QUEUE=$(squeue -h -n N22-repl-verify,N22-warm-pair,N22-warm-analysis -o '%i|%j|%T|%M|%R')
printf '%s\n' "$PAIR_QUEUE"
test -z "$PAIR_QUEUE"
test "$(squeue -h -j 202293 -o '%i|%T|%r|%j')" = '202293|PENDING|JobHeldUser|N22-manifest'
test ! -e "$ROOT/closure_20260810/aggregation/final_reproduction_gate.json"
test ! -e "$ROOT/closure_20260810/aggregation/final_reproduction_differences.csv"
echo "verification_job_submitted=false"
echo "pair_training_submitted=false"
echo "registered_matrix_modified=false"
