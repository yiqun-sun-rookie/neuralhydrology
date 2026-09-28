#!/usr/bin/env bash
set -eo pipefail
task_root=/data1/home/sunyiq/kalmannet_wrr_closeout_20260928_v1
task_payload="$PWD/inbox/kalmannet-wrr-closeout-20260928/saved_stats_audit_001.tar"
test "$(sha256sum "$task_payload" | cut -d' ' -f1)" = e4628f679d19f7dccef0f28a25599374c1a175abc09b95b15b4f446c65ef9224
test ! -e "$task_root/saved_stats_audit_001"
test ! -L "$task_root/saved_stats_audit_001"
test ! -e "$task_root/saved_stats_diagnostic_001"
mkdir "$task_root/saved_stats_audit_001"
tar -xf "$task_payload" -C "$task_root/saved_stats_audit_001"
cd "$task_root/saved_stats_audit_001"
sha256sum --strict --check package_files.sha256
bash -n saved_statistics.slurm
echo SAVED_STATISTICS_DIAGNOSTIC_SUBMISSION_ONLY_NO_NEW_MODELS
sbatch --parsable saved_statistics.slurm
