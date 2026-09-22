#!/usr/bin/env bash
set -eo pipefail
date -u '+%Y-%m-%dT%H:%M:%SZ'
printf 'OLD_PRIVATE_RUNTIME_METADATA_ONLY\n'
runtime='/data1/home/sunyiq/kalmannet_tukf09_455_basin_zero_validation_target_variance_revision_v1_a800_exclusive_v2r14_20260909/runtime_v2r14'
find "$runtime/pysite" -maxdepth 1 -type d \( -name 'numpy-*.dist-info' -o -name 'torch-*.dist-info' -o -name 'psutil-*.dist-info' \) -printf '%f\n'
find "$runtime/evidence" -maxdepth 1 -type f -printf '%f\n'
printf 'MEMORY_ENFORCEMENT_CONFIGURATION\n'
cgconfig='/usr/local/globle/softs/slurm/19.05.4.1/etc/cgroup.conf'
if [ -r "$cgconfig" ]; then
    awk '/^[[:space:]]*(CgroupAutomount|ConstrainCores|ConstrainRAMSpace|AllowedRAMSpace|ConstrainSwapSpace|AllowedSwapSpace|MaxRAMPercent|MinRAMSpace)/ {print}' "$cgconfig"
else
    printf 'CGROUP_CONFIGURATION_NOT_READABLE\n'
fi
printf 'RESERVE_NEW_ROOT_EXCLUSIVELY\n'
candidate='/data1/home/sunyiq/kalmannet_tukf09_scaled_noise_rehearsal_20260922'
if [ -e "$candidate" ] || [ -L "$candidate" ]; then
    printf 'REFUSE_EXISTING_ROOT %s\n' "$candidate"
    exit 1
fi
mkdir -m 750 "$candidate"
mkdir -m 750 "$candidate/control" "$candidate/logs"
cp -n "$0" "$candidate/control/root_creation_command.sh"
sha256sum "$candidate/control/root_creation_command.sh"
stat -c '%F|%U|%a|%n' "$candidate" "$candidate/control" "$candidate/logs"
printf 'NO_COMPUTE_SUBMISSION_PERFORMED\n'
printf 'CURRENT_USER_JOBS\n'
squeue -u sunyiq -h -o '%i|%j|%T|%P|%C|%D|%R|%Z'
printf 'ROOT_RESERVED_NO_EXISTING_EXPERIMENT_MODIFIED\n'
