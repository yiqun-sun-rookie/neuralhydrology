#!/usr/bin/env bash
set -euo pipefail

phase='/data1/home/sunyiq/kalmannet_tukf09_scaled_noise_rehearsal_20260922/full_budget_recovery_v2r8_20260927'
payload='/data1/home/sunyiq/hpc_mailbox/inbox/kalmannet-tukf09-noise-20260922/payload/full_budget_recovery_v2r8_20260927.zip'
python='/data1/home/sunyiq/miniconda3/envs/knet_clean/bin/python'

printf '=== FIRST-BASIN OUTPUT-GUARD RELEASE READ-ONLY PREFLIGHT ===\n'
date -u '+UTC=%Y-%m-%dT%H:%M:%SZ'
if [[ "$(id -un)" != 'sunyiq' ]]; then
    printf 'WRONG_ACCOUNT\n'
    exit 1
fi
if [[ -e "$phase" || -L "$phase" ]]; then
    printf 'NEW_PHASE_OCCUPIED\n'
    exit 1
fi
if [[ ! -d "$(dirname "$phase")" || -L "$(dirname "$phase")" ]]; then
    printf 'NEW_PHASE_PARENT_INVALID\n'
    exit 1
fi
printf 'NEW_PHASE_ABSENT\n'
if [[ -e "$payload" || -L "$payload" ]]; then
    printf 'NEW_PAYLOAD_OCCUPIED\n'
    exit 1
fi
printf 'NEW_PAYLOAD_ABSENT\n'
if [[ ! -x "$python" ]]; then
    printf 'FROZEN_PYTHON_MISSING\n'
    exit 1
fi
python_version="$("$python" --version)"
if [[ "$python_version" != 'Python 3.11.13' ]]; then
    printf 'FROZEN_PYTHON_VERSION_CHANGED %s\n' "$python_version"
    exit 1
fi
printf 'FROZEN_PYTHON_PRESENT %s\n' "$python_version"
partition="$(scontrol show partition hcpu48y -o)"
printf '%s\n' "$partition"
if [[ "$partition" != *' State=UP '* || "$partition" != *' OverSubscribe=NO '* ]]; then
    printf 'FROZEN_PARTITION_NOT_READY\n'
    exit 1
fi
printf 'OWN_QUEUE\n'
queue="$(squeue -u sunyiq -h -o '%i|%j|%T|%P|%R')"
printf '%s\n' "$queue"
if printf '%s\n' "$queue" | awk -F '|' '$2 ~ /^tukf09-noise-/ { found=1 } END { exit !found }'; then
    printf 'COMPETING_NOISE_RECOVERY_JOB_IN_QUEUE\n'
    exit 1
fi
printf 'READ_ONLY_PREFLIGHT_PASS\n'
