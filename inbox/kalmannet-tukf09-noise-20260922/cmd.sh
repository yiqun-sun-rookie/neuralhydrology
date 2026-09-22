#!/usr/bin/env bash
set -eo pipefail
date -u '+%Y-%m-%dT%H:%M:%SZ'
printf 'SHARED_CPU_PARTITION\n'
scontrol show partition hcpu48y
printf 'AVAILABLE_ENVIRONMENT_PACKAGE_IDENTITIES\n'
for envname in knet_clean neuralhydrology nh_clean nh_final; do
    envroot="/data1/home/sunyiq/miniconda3/envs/$envname"
    printf 'ENV %s\n' "$envroot"
    find "$envroot/conda-meta" -maxdepth 1 -type f \( -name 'python-*.json' -o -name 'pytorch-*.json' -o -name 'numpy-*.json' -o -name 'psutil-*.json' \) -printf '%f\n'
    for site in "$envroot"/lib/python*/site-packages; do
        if [ -d "$site" ]; then
            find "$site" -maxdepth 1 -type d \( -name 'numpy-*.dist-info' -o -name 'torch-*.dist-info' -o -name 'psutil-*.dist-info' \) -printf '%f\n'
        fi
    done
done
printf 'OLD_RELEVANT_RUNTIME_DIRECTORY_NAMES_ONLY\n'
oldroot='/data1/home/sunyiq/kalmannet_tukf09_455_basin_zero_validation_target_variance_revision_v1_a800_exclusive_v2r14_20260909'
find "$oldroot" -maxdepth 2 -type d -printf '%p\n'
printf 'SCHEDULER_CONFIGURATION_LOCATION\n'
scontrol show config | awk '/SLURM_CONF|SlurmctldHost|SlurmctldPort|SlurmUser/ {print}'
printf 'CURRENT_USER_JOBS\n'
squeue -u sunyiq -h -o '%i|%j|%T|%P|%C|%D|%R|%Z'
printf 'RUNTIME_INVENTORY_READ_ONLY_COMPLETE\n'
