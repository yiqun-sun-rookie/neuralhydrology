#!/bin/bash
# sequence=1
# Read-only resource and existing-job inventory; no computation or submission.
set -eo pipefail
date -u '+SNAPSHOT_UTC=%Y-%m-%dT%H:%M:%SZ'
hostname
printf '%s\n' OWN_JOBS
squeue -u sunyiq -h -o '%i|%j|%P|%T|%M|%l|%D|%C|%R'
printf '%s\n' GPU_RESOURCES
sinfo -p hgpu2p,hgpu2,hgpu4,hgpu8 -N -O nodelist,partition,statelong,gres:14,gresused:24,cpusstate
printf '%s\n' OWN_JOB_PATHS
for jid in $(squeue -u sunyiq -h -o '%i'); do
    scontrol -o show job "$jid"
done
printf '%s\n' STORAGE
df -Pk /data1/home/sunyiq
printf '%s\n' NEW_ROOT
root=/data1/home/sunyiq/kalmannet_hamid_weights_20260923_v1
if [ -e "$root" ]; then
    printf '%s\n' ROOT_ALREADY_EXISTS
    exit 3
fi
printf '%s\n' ROOT_AVAILABLE
printf '%s\n' KNOWN_INPUT_LOCATIONS
for candidate in /data1/home/sunyiq/kalmannet_wrr_hp_extension_20260902/repo/data/processed/high_flow_aug /data1/home/sunyiq/knet_project/data/processed/high_flow_aug; do
    for name in train_win800_19990101_01-20070527_03.pt val_win800_20070527_04-20090314_13.pt; do
        if [ -f "$candidate/$name" ]; then
            stat -c '%n|%s|%y' "$candidate/$name"
        fi
    done
done
printf '%s\n' WRR_RECENT_JOB_STATES
sacct -X -S 2026-09-14 -u sunyiq -n -P --format=JobID,JobName%60,State,ExitCode,Elapsed,Start,End,Partition | awk -F'|' 'tolower($2) ~ /wrr|hamid|horizon/ {print}'
printf '%s\n' READ_ONLY_PREFLIGHT_COMPLETE
