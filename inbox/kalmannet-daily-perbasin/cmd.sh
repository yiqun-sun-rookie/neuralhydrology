#!/usr/bin/env bash
set -euo pipefail
sequence=33
echo "channel=kalmannet-daily-perbasin sequence=${sequence} purpose=v2-task6-readonly-current-queue"
date --iso-8601=seconds
hostname
echo 'training_submissions=0 optimizer_steps=0 formal_evaluation_access=0 signals_sent=0 task_file_writes=0'
ROOT=/data1/home/sunyiq/kalmannet_daily_camels_per_basin_pilots_20260901
[[ -d "$ROOT" && ! -L "$ROOT" ]] || { echo 'REGISTERED_ROOT_MISSING_OR_LINK'; exit 91; }
queue="$(squeue -h -u "$(id -un)" -o '%i|%200j|%T|%N')"
printf '%s\n' '=== CURRENT USER JOBS ===' "$queue"
related="$(printf '%s\n' "$queue" | awk -F'|' '$2 ~ /(kdpp|DAILY_CAMELS_KNET_PER_BASIN|daily.camels.*per.basin|kalmannet.daily.perbasin)/ {n++} END {print n+0}')"
echo "related_active_job_count=$related"
echo '=== TARGET NODE SCHEDULER STATE ==='
sinfo -N -n ngu202 -o '%N|%P|%T|%G|%C|%m'
echo '=== EXISTING DEPLOYMENT DIRECTORIES (METADATA ONLY) ==='
find "$ROOT/deployments" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort
echo '=== EXISTING LOCK PATHS (METADATA ONLY) ==='
if [[ -d "$ROOT/status/locks" ]]; then find "$ROOT/status/locks" -mindepth 1 -maxdepth 2 -printf '%y|%P\n' | sort; fi
echo "next_stage_allowed_by_related_queue=$([[ "$related" == 0 ]] && echo true || echo false)"
[[ "$related" == 0 ]] || exit 92
echo 'TASK6_QUEUE_GATE=PASS'
