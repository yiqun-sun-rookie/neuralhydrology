#!/usr/bin/env bash
set -euo pipefail
export PYTHONNOUSERSITE=1 PYTHONDONTWRITEBYTECODE=1

phase='/data1/home/sunyiq/kalmannet_tukf09_scaled_noise_rehearsal_20260922/timing_probe_01142500_20260929_attempt1'
old='/data1/home/sunyiq/kalmannet_tukf09_scaled_noise_rehearsal_20260922/full_budget_01142500_20260928_attempt1/bundle'
control="$phase/basin_01142500/control"
python='/data1/home/sunyiq/miniconda3/envs/knet_clean/bin/python'
printf 'TIMING_PROBE_STAGED_PREFLIGHT_BEGIN basin=01142500 read_only=true\n'
date -u '+UTC=%Y-%m-%dT%H:%M:%SZ'
[[ "$(id -un)" == sunyiq ]] || { printf 'WRONG_ACCOUNT\n'; exit 1; }
for path in "$phase" "$control" "$phase/logs" "$phase/cache" "$phase/tmp" "$old"; do
    [[ -d "$path" && ! -L "$path" ]] || { printf 'MISSING_OR_LINKED_DIRECTORY %s\n' "$path"; exit 1; }
done
[[ ! -e "$phase/basin_01142500/run" && ! -L "$phase/basin_01142500/run" ]] || { printf 'DIAGNOSTIC_RUN_ALREADY_EXISTS\n'; exit 1; }
[[ ! -e "$control/submission_attempt.json" && ! -L "$control/submission_attempt.json" ]] || { printf 'SUBMISSION_ATTEMPT_ALREADY_CONSUMED\n'; exit 1; }
[[ ! -e "$control/submission.json" && ! -L "$control/submission.json" ]] || { printf 'SUBMISSION_ALREADY_RECORDED\n'; exit 1; }
[[ "$(sha256sum "$phase/payload_manifest.json" | awk '{print $1}')" == '1d0b611435939b3290cd6ab843472479b7fb0f209791e650e0f017f39cc51e98' ]] || { printf 'DIAGNOSTIC_MANIFEST_CHANGED\n'; exit 1; }
[[ "$(sha256sum "$phase/tukf09_timing_probe_01142500_20260929.py" | awk '{print $1}')" == 'dbb2cef831d7b75ca45e46fc876d2bb9a60da21f95ed2fd0b1259c4106525051' ]] || { printf 'DIAGNOSTIC_WRAPPER_CHANGED\n'; exit 1; }
[[ "$(sha256sum "$phase/timing_probe_01142500_20260929.slurm" | awk '{print $1}')" == '4f42af818c796bb24e095596e4ad50c756a01a7606f8979f937c58a84292da29' ]] || { printf 'DIAGNOSTIC_JOB_SCRIPT_CHANGED\n'; exit 1; }
[[ "$(sha256sum "$old/hpc/tukf09_455_scaled_noise_common_v1.py" | awk '{print $1}')" == 'b4b70d97e4fdeca92ef1a7a8a6335a41d45acead5b40db5bdf1ab92ff70a3a5e' ]] || { printf 'FROZEN_SCIENCE_CHANGED\n'; exit 1; }
[[ "$("$python" --version)" == 'Python 3.11.13' ]] || { printf 'PYTHON_CHANGED\n'; exit 1; }
"$python" -B - "$control/deployment.json" <<'PY'
import json
from pathlib import Path
import sys
record = json.loads(Path(sys.argv[1]).read_text(encoding='utf-8'))
assert record == {
    'status': 'ONE_TIMING_DIAGNOSTIC_STAGED_NOT_SUBMITTED',
    'basin_id': '01142500',
    'archive_sha256': '8737f4fd58dea66d26551462b15536c97d0fbdde8d7a2598df92438a3c431e40',
    'manifest_sha256': '1d0b611435939b3290cd6ab843472479b7fb0f209791e650e0f017f39cc51e98',
    'old_bundle_manifest_sha256': '4ebee2dcbd215e9751c86ca9895b84090956e7857d84b524fc87d60a3ea6afa1',
    'scheduler_submission_performed': False,
}
print('STAGED_DEPLOYMENT_RECORD_VERIFIED')
PY
partition="$(scontrol show partition hcpu48y -o)"
printf 'PARTITION %s\n' "$partition"
[[ "$partition" == *' State=UP '* && "$partition" == *' OverSubscribe=NO '* ]] || { printf 'PARTITION_CHANGED\n'; exit 1; }
queue="$(squeue -u sunyiq -h -o '%i|%j|%T|%P|%R')"
printf 'OWN_QUEUE_BEGIN\n%s\nOWN_QUEUE_END\n' "$queue"
if printf '%s\n' "$queue" | awk -F '|' '$2 ~ /^tukf09-noise-/ { found=1 } END { exit !found }'; then
    printf 'COMPETING_NOISE_JOB\n'; exit 1
fi
printf 'ACCOUNTING_229133 '
sacct -X -j 229133 -P -n --format=JobID,JobName,Partition,AllocCPUS,ReqCPUS,AllocTRES,ReqTRES,ElapsedRaw,State,ExitCode
printf 'TIMING_PROBE_STAGED_PREFLIGHT_END result=PASS read_only=true\n'
