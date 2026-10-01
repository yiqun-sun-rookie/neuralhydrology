#!/usr/bin/env bash
# This file is finalized with the immutable payload digest before publication.
set -eo pipefail
task_base="$HOME/precip_dynamic_filter_20260930"
task_run="$task_base/run_20261001_211612_19f6cfd5"
task_data="$HOME/neuralhydrology/data/camels_us"
task_payload="$HOME/hpc_mailbox/inbox/precip-dynamic-filter-v03/payload/dynamic_filter_run_20261001_211612_19f6cfd5_v2.tgz"
test -d "$task_data"
if [ -e "$task_base" ]; then echo ROOT_COLLISION; exit 21; fi
test -f "$task_payload"
task_actual=$(sha256sum "$task_payload")
task_actual=${task_actual%% *}
test "$task_actual" = "2a80f85adb10841736c586843e750f0482f164bedf0b1feb630f5dd61bcd9d08"
mkdir "$task_base"
mkdir "$task_run"
task_resolved=$(readlink -f "$task_run")
case "$task_resolved" in "$HOME/precip_dynamic_filter_20260930/"*) ;; *) exit 22 ;; esac
tar -xzf "$task_payload" -C "$task_resolved"
mkdir "$task_resolved/logs"
test ! -e "$task_resolved/submission_receipt.txt"
task_reply=$(sbatch --parsable --chdir="$task_resolved/code" --export="ALL,DYNAMIC_RUN_ROOT=$task_resolved,DYNAMIC_DATA_DIR=$task_data" --output="$task_resolved/logs/pilot-%j.out" --error="$task_resolved/logs/pilot-%j.err" "$task_resolved/code/src/precip_input_assimilation/hpc/dynamic_filter_pilot_v03.slurm")
task_job=${task_reply%%;*}
[[ "$task_job" =~ ^[0-9]+$ ]]
printf '%s\n' "$task_reply" > "$task_resolved/submission_receipt.txt"
printf 'JOB_ID=%s\nRUN_ROOT=%s\nPAYLOAD_SHA256=%s\n' "$task_job" "$task_resolved" "$task_actual"
scontrol show job "$task_job"
