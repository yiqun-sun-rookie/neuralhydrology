#!/usr/bin/env bash
set -euo pipefail

phase='/data1/home/sunyiq/kalmannet_tukf09_scaled_noise_rehearsal_20260922/full_budget_integrated_release_20260927_attempt1'
payload='/data1/home/sunyiq/hpc_mailbox/inbox/kalmannet-tukf09-noise-20260922/payload/full_budget_integrated_release_20260927_attempt1.zip'
python='/data1/home/sunyiq/miniconda3/envs/knet_clean/bin/python'
private='/data1/home/sunyiq/kalmannet_tukf09_455_basin_zero_validation_target_variance_revision_v1_a800_exclusive_v2r14_20260909/runtime_v2r14/pysite'

printf '=== FIRST-BASIN INTEGRATED RELEASE READ-ONLY PREFLIGHT ===\n'
date -u '+UTC=%Y-%m-%dT%H:%M:%SZ'
[[ "$(id -un)" == sunyiq ]] || { printf 'WRONG_ACCOUNT\n'; exit 1; }
[[ ! -e "$phase" && ! -L "$phase" ]] || { printf 'NEW_PHASE_OCCUPIED\n'; exit 1; }
[[ -d "$(dirname "$phase")" && ! -L "$(dirname "$phase")" ]] || { printf 'NEW_PHASE_PARENT_INVALID\n'; exit 1; }
printf 'NEW_PHASE_ABSENT\n'
[[ ! -e "$payload" && ! -L "$payload" ]] || { printf 'NEW_PAYLOAD_OCCUPIED\n'; exit 1; }
printf 'NEW_PAYLOAD_ABSENT\n'
[[ -x "$python" && -d "$private" ]] || { printf 'FROZEN_RUNTIME_ABSENT\n'; exit 1; }
[[ "$("$python" --version)" == 'Python 3.11.13' ]] || { printf 'FROZEN_PYTHON_CHANGED\n'; exit 1; }
partition="$(scontrol show partition hcpu48y -o)"
printf '%s\n' "$partition"
[[ "$partition" == *' State=UP '* && "$partition" == *' OverSubscribe=NO '* ]] || { printf 'PARTITION_CHANGED\n'; exit 1; }
queue="$(squeue -u sunyiq -h -o '%i|%j|%T|%P|%R')"
printf '=== OWN_QUEUE ===\n%s\n' "$queue"
if printf '%s\n' "$queue" | awk -F '|' '$2 ~ /^tukf09-noise-/ { found=1 } END { exit !found }'; then
    printf 'COMPETING_NOISE_JOB\n'
    exit 1
fi
accounting="$(sacct -X -j 228129 -P -n --format=JobID,JobName,Partition,State,ExitCode)"
printf '=== FAILED_PREDECESSOR ===\n%s\n' "$accounting"
[[ "$(printf '%s\n' "$accounting" | wc -l)" -eq 1 && "$accounting" == '228129|tukf09-noise-recover-v2r8-0927|hcpu48y|FAILED|1:0' ]] || {
    printf 'PREDECESSOR_IDENTITY_CHANGED\n'
    exit 1
}
PYTHONNOUSERSITE=1 PYTHONDONTWRITEBYTECODE=1 PYTHONPATH="$private" \
OMP_NUM_THREADS=1 MKL_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 NUMEXPR_NUM_THREADS=1 \
"$python" -B -c 'import json,numpy,torch,sys;from pathlib import Path;p=Path(sys.argv[1]).resolve();assert sys.version.startswith("3.11.13") and numpy.__version__=="1.26.4" and torch.__version__.startswith("2.2.2");assert Path(numpy.__file__).resolve().is_relative_to(p) and Path(torch.__file__).resolve().is_relative_to(p);print(json.dumps({"python":sys.version,"numpy":numpy.__version__,"torch":torch.__version__,"numpy_path":numpy.__file__,"torch_path":torch.__file__},sort_keys=True))' "$private"
printf 'READ_ONLY_INTEGRATED_PREFLIGHT_PASS\n'
