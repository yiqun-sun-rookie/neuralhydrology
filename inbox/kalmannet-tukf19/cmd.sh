#!/usr/bin/env bash
set -o pipefail

TARGET=/data1/home/sunyiq/kalmannet_tukf19_20260823
JOB=209815

echo '=== TUKF19 SMOKE JOB ACCOUNTING ==='
sacct -j "$JOB" --format=JobID%14,JobName%24,Partition%12,State%16,ExitCode%10,Elapsed%12,AllocCPUS%10,NodeList%16,MaxRSS%14 2>&1 || true

echo '=== TUKF19 STATUS FILES ==='
ls -la "$TARGET/artifacts/tukf19_hpc_deployment_v1/status" 2>&1 || true
ls -la "$TARGET/artifacts/tukf19_hpc_deployment_v1/smoke" 2>&1 || true
ls -la "$TARGET/logs" 2>&1 || true

echo '=== TUKF19 SMOKE REPORT ==='
cat "$TARGET/artifacts/tukf19_hpc_deployment_v1/smoke/smoke_report.json" 2>&1 || true

echo '=== TUKF19 SMOKE STDOUT ==='
cat "$TARGET/logs/smoke-$JOB.out" 2>&1 || true

echo '=== TUKF19 SMOKE STDERR ==='
cat "$TARGET/logs/smoke-$JOB.err" 2>&1 || true

echo '=== TUKF19 FORMAL SUBMISSION ABSENCE ==='
if [[ -e "$TARGET/artifacts/tukf19_hpc_deployment_v1/status/formal_submission.json" ]]; then
  cat "$TARGET/artifacts/tukf19_hpc_deployment_v1/status/formal_submission.json" 2>&1 || true
else
  echo FORMAL_SUBMISSION_ABSENT
fi

echo TUKF19_SMOKE_FAILURE_DIAGNOSTIC_COMPLETE
exit 0
