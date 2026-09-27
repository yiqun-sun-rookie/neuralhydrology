#!/usr/bin/env bash
set -euo pipefail

phase='/data1/home/sunyiq/kalmannet_tukf09_scaled_noise_rehearsal_20260922/full_budget_recovery_v2r8_20260927'
job='228129'

printf '=== EXACT FIRST-BASIN JOB STATUS ===\n'
date -u '+UTC=%Y-%m-%dT%H:%M:%SZ'
accounting="$(sacct -X -j "$job" -P -n --format=JobID,JobName,Partition,AllocCPUS,ReqCPUS,AllocTRES,ReqTRES,ElapsedRaw,State,ExitCode)"
if [[ -n "$accounting" ]]; then printf '%s\n' "$accounting"; else printf 'NO_ACCOUNTING_ROW\n'; fi
queue="$(squeue -j "$job" -h -o '%i|%j|%T|%P|%R')"
if [[ -n "$queue" ]]; then printf '%s\n' "$queue"; else printf 'NOT_IN_ACTIVE_QUEUE\n'; fi

printf '=== EXCLUSIVE NEW PHASE ===\n'
if [[ -d "$phase" && ! -L "$phase" && "$(realpath -e "$phase")" == "$phase" ]]; then
  printf 'NEW_PHASE_DIRECTORY_PRESENT\n'
else
  printf 'NEW_PHASE_DIRECTORY_ABSENT_OR_LINKED\n'
fi
if [[ -e "$phase/basin_01142500" || -L "$phase/basin_01142500" ]]; then
  printf 'SECOND_BASIN_PATH_PRESENT\n'
else
  printf 'SECOND_BASIN_PATH_ABSENT\n'
fi
for relative in \
  control/deployed.json \
  basin_01047000/control/submission_attempt.json \
  basin_01047000/control/submission.json \
  basin_01047000/control/job_gate.json \
  basin_01047000/run/supervisor.json \
  basin_01047000/run/model/started.json \
  basin_01047000/run/model/manifest.final.sha256.json; do
  target="$phase/$relative"
  if [[ -f "$target" && ! -L "$target" ]]; then
    printf 'FILE %s\n' "$relative"
    sha256sum "$target"
    case "$relative" in
      basin_01047000/control/submission.json|basin_01047000/control/job_gate.json|basin_01047000/run/supervisor.json|basin_01047000/run/model/started.json)
        /data1/home/sunyiq/miniconda3/envs/knet_clean/bin/python -B - "$relative" "$target" <<'PY'
import json
from pathlib import Path
import sys

relative, path = sys.argv[1:]
record = json.loads(Path(path).read_text(encoding='utf-8'))
if relative.endswith('/submission.json'):
    print('SUBMISSION_JOB_ID_LINE=' + str(record.get('stdout', '')).strip())
    print('SUBMISSION_RETURNCODE=' + str(record.get('returncode')))
elif relative.endswith('/job_gate.json'):
    print('JOB_GATE_STATUS=' + str(record.get('status')))
    for key in ('original_linux_protection_tests', 'final_output_guard_regressions',
                'new_standard_library_gate_tests', 'synthetic_tensor_loop_tests'):
        print(key.upper() + '=' + json.dumps(record.get(key), sort_keys=True))
elif relative.endswith('/supervisor.json'):
    print('SUPERVISOR_SUCCESS=' + str(record.get('success')))
    print('SUPERVISOR_REASON=' + str(record.get('reason')))
    print('SUPERVISOR_EXIT_CODE=' + str(record.get('exit_code')))
else:
    print('MODEL_STARTED_RECORD=' + json.dumps(record, sort_keys=True))
PY
        ;;
    esac
  else
    printf 'MISSING %s\n' "$relative"
  fi
done

printf '=== EXACT JOB LOG TAILS ===\n'
for suffix in out err; do
  target="$phase/logs/job-$job.$suffix"
  if [[ -f "$target" && ! -L "$target" ]]; then
    printf 'LOG %s\n' "$suffix"
    tail -n 30 "$target"
  else
    printf 'MISSING job-%s.%s\n' "$job" "$suffix"
  fi
done
printf 'READ_ONLY_EXACT_JOB_STATUS_COMPLETE\n'
