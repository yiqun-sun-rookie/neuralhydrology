#!/usr/bin/env bash
set -euo pipefail
export PYTHONNOUSERSITE=1 PYTHONDONTWRITEBYTECODE=1

phase='/data1/home/sunyiq/kalmannet_tukf09_scaled_noise_rehearsal_20260922/timing_probe_01142500_20260929_attempt1'
previous='/data1/home/sunyiq/kalmannet_tukf09_scaled_noise_rehearsal_20260922/full_budget_01142500_20260928_attempt1'
bundle="$previous/bundle"
python='/data1/home/sunyiq/miniconda3/envs/knet_clean/bin/python'
private='/data1/home/sunyiq/kalmannet_tukf09_455_basin_zero_validation_target_variance_revision_v1_a800_exclusive_v2r14_20260909/runtime_v2r14/pysite'

printf 'TIMING_PROBE_PREFLIGHT_BEGIN basin=01142500 read_only=true\n'
date -u '+UTC=%Y-%m-%dT%H:%M:%SZ'
[[ "$(id -un)" == sunyiq ]] || { printf 'WRONG_ACCOUNT\n'; exit 1; }
[[ ! -e "$phase" && ! -L "$phase" ]] || { printf 'NEW_PHASE_OCCUPIED\n'; exit 1; }
[[ -d "$(dirname "$phase")" && ! -L "$(dirname "$phase")" ]] || { printf 'NEW_PHASE_PARENT_INVALID\n'; exit 1; }
printf 'NEW_PHASE_ABSENT\n'
[[ -d "$bundle" && ! -L "$bundle" && -f "$bundle/bundle_manifest.json" && ! -L "$bundle/bundle_manifest.json" ]] || { printf 'FROZEN_BUNDLE_MISSING_OR_LINKED\n'; exit 1; }
[[ "$(sha256sum "$bundle/bundle_manifest.json" | awk '{print $1}')" == '4ebee2dcbd215e9751c86ca9895b84090956e7857d84b524fc87d60a3ea6afa1' ]] || { printf 'FROZEN_MANIFEST_CHANGED\n'; exit 1; }
[[ "$(sha256sum "$bundle/hpc/tukf09_455_scaled_noise_common_v1.py" | awk '{print $1}')" == 'b4b70d97e4fdeca92ef1a7a8a6335a41d45acead5b40db5bdf1ab92ff70a3a5e' ]] || { printf 'FROZEN_SCIENCE_SOURCE_CHANGED\n'; exit 1; }
[[ "$(sha256sum "$bundle/hpc/tukf09_455_scaled_noise_local_transfer_contract_v1.json" | awk '{print $1}')" == '27239212680bd370bd76f40e53337b7d68d80cbe4dc01feac2164bab4917f8a1' ]] || { printf 'FROZEN_SCIENCE_CONTRACT_CHANGED\n'; exit 1; }
[[ -x "$python" && -d "$private" && ! -L "$private" ]] || { printf 'RUNTIME_MISSING_OR_LINKED\n'; exit 1; }
[[ "$("$python" --version)" == 'Python 3.11.13' ]] || { printf 'PYTHON_VERSION_CHANGED\n'; exit 1; }
printf 'FROZEN_INPUTS_AND_PYTHON_PRESENT\n'
partition="$(scontrol show partition hcpu48y -o)"
printf 'PARTITION %s\n' "$partition"
[[ "$partition" == *' State=UP '* && "$partition" == *' OverSubscribe=NO '* ]] || { printf 'PARTITION_CHANGED\n'; exit 1; }
queue="$(squeue -u sunyiq -h -o '%i|%j|%T|%P|%R')"
printf 'OWN_QUEUE_BEGIN\n%s\nOWN_QUEUE_END\n' "$queue"
if printf '%s\n' "$queue" | awk -F '|' '$2 ~ /^tukf09-noise-/ { found=1 } END { exit !found }'; then
    printf 'COMPETING_NOISE_JOB\n'; exit 1
fi
for job in 228327 229133; do
    printf 'ACCOUNTING_%s ' "$job"
    sacct -X -j "$job" -P -n --format=JobID,JobName,Partition,AllocCPUS,ReqCPUS,AllocTRES,ReqTRES,ElapsedRaw,State,ExitCode
done
printf 'FREE_KIB '
df -Pk "$(dirname "$phase")" | awk 'NR==2 {print $4}'
printf 'TIMING_PROBE_PREFLIGHT_END result=PASS read_only=true\n'
