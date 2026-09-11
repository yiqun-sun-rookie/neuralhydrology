#!/bin/bash
# kalmannet-daily-perbasin sequence=98: READ-ONLY observation of verification job 225184;
# when the job is terminal, return the small audit files (base64) and the hashes of the large ones.
set -o pipefail
echo "channel=kalmannet-daily-perbasin sequence=98 purpose=read-only-observe-and-collect-job225184"
ROOT=/data1/home/sunyiq/kalmannet_daily_camels_per_basin_21_development_20260908
REQ=$ROOT/runtime/verify_224875_verifier_repair_seq97
DEP=$ROOT/deployment_A40_verifier_repair_20260911_SEQ97
JOB=225184
echo "QUERY_ACCOUNTING_BEGIN"
timeout 20s sacct -X -n -P -j "$JOB" --format=JobIDRaw,JobName,State,ExitCode,ElapsedRaw,AllocCPUS,ReqTRES,AllocTRES,NodeList,Submit,Start,End
echo "QUERY_ACCOUNTING_EXIT=$?"
echo "QUERY_QUEUE_BEGIN"
timeout 20s squeue -j "$JOB" -h -o '%i|%T|%P|%R|%S|%C' 2>&1
echo "QUERY_QUEUE_EXIT=$?"
STATE=$(timeout 20s sacct -X -n -P -j "$JOB" --format=State | head -n 1)
echo "STATE=$STATE"
emit_file() {
  f="$1"
  if [ -f "$f" ]; then
    echo "FILE_BEGIN path=$f bytes=$(stat -c %s "$f") sha256=$(sha256sum "$f" | cut -c1-64)"
    base64 "$f"
    echo "FILE_END path=$f"
  else
    echo "FILE_ABSENT path=$f"
  fi
}
hash_file() {
  f="$1"
  if [ -f "$f" ]; then
    echo "FILE_HASH path=$f bytes=$(stat -c %s "$f") sha256=$(sha256sum "$f" | cut -c1-64)"
  else
    echo "FILE_ABSENT path=$f"
  fi
}
case "$STATE" in
  COMPLETED|FAILED|TIMEOUT|NODE_FAIL|OUT_OF_MEMORY|CANCELLED*)
    echo "TERMINAL=1"
    emit_file "$REQ/slurm-$JOB.stdout"
    emit_file "$REQ/slurm-$JOB.stderr"
    emit_file "$REQ/audit/verifier_process.json"
    emit_file "$REQ/audit/verifier_stderr.bin"
    emit_file "$REQ/audit/independent_verification_report.json"
    emit_file "$REQ/submission_seq97.receipt.json"
    emit_file "$DEP/verifier_repair_identity.json"
    hash_file "$REQ/audit/verifier_stdout.bin"
    hash_file "$REQ/audit/run_directory_snapshot_before.json"
    hash_file "$REQ/audit/run_directory_snapshot_after.json"
    hash_file "$DEP/workspace/scripts/verify_daily_camels_knet_per_basin_pilot.py"
    hash_file "$DEP/workspace/bundle_manifest.json"
    ;;
  *)
    echo "TERMINAL=0"
    hash_file "$REQ/slurm-$JOB.stdout"
    ;;
esac
echo "READ_ONLY_OBSERVE_COMPLETE submissions=0 cancellations=0 modifications=0"
