#!/usr/bin/env bash
set -eo pipefail

JID=202156
TARGET=/data1/home/sunyiq/kalmannet_tukf06_20260809/retry2
OUTPUT="$TARGET/results/tukf06_full_diagonal_search_head_to_head_v1"
STDOUT="$TARGET/logs/evaluation-${JID}.out"
STDERR="$TARGET/logs/evaluation-${JID}.err"

echo "=== TUKF06 EVALUATION QUEUE ==="
squeue -j "$JID" -o '%.18i %.20j %.10T %.12M %.12l %.12R' || true
echo "=== TUKF06 EVALUATION ACCOUNTING ==="
sacct -j "$JID" --format=JobID%18,JobName%20,Partition%10,NodeList%12,State%18,ExitCode%8,Elapsed%10,TotalCPU%12,MaxRSS%12

state=$(sacct -j "$JID" -X -n -o State | awk 'NF {print $1; exit}')
exit_code=$(sacct -j "$JID" -X -n -o ExitCode | awk 'NF {print $1; exit}')
echo "evaluation_state=$state"
echo "evaluation_exit_code=$exit_code"

if [[ -f "$STDOUT" ]]; then
  echo "evaluation_stdout_bytes=$(wc -c < "$STDOUT")"
  echo "=== EVALUATION STDOUT TAIL ==="
  tail -n 30 "$STDOUT"
else
  echo "evaluation_stdout_absent=true"
fi
if [[ -f "$STDERR" ]]; then
  echo "evaluation_stderr_bytes=$(wc -c < "$STDERR")"
  if [[ -s "$STDERR" ]]; then
    echo "=== EVALUATION STDERR TAIL ==="
    tail -n 30 "$STDERR"
  fi
else
  echo "evaluation_stderr_absent=true"
fi

case "$state" in
  PENDING|RUNNING|CONFIGURING|COMPLETING)
    echo "TUKF06_EVALUATION_ACTIVE job_id=$JID state=$state"
    ;;
  COMPLETED)
    if [[ "$exit_code" != "0:0" ]]; then
      echo "completed evaluation has nonzero exit code: $exit_code" >&2
      exit 111
    fi
    test -f "$STDOUT" -a -f "$STDERR"
    if [[ -s "$STDERR" ]]; then
      echo "completed evaluation stderr is nonempty" >&2
      exit 112
    fi
    test -f "$OUTPUT/evaluation_summary.json"
    test -f "$OUTPUT/evaluation_manifest.sha256.json"
    test -d "$OUTPUT/evaluation"
    count=$(find "$OUTPUT/evaluation" -maxdepth 1 -type f -name 'basin_*' | wc -l)
    echo "evaluation_basin_file_count=$count"
    echo "evaluation_summary_sha256=$(sha256sum "$OUTPUT/evaluation_summary.json" | awk '{print $1}')"
    echo "evaluation_manifest_sha256=$(sha256sum "$OUTPUT/evaluation_manifest.sha256.json" | awk '{print $1}')"
    echo "TUKF06_EVALUATION_COMPLETED_READY_FOR_DEEP_AUDIT job_id=$JID"
    ;;
  *)
    echo "TUKF06_EVALUATION_TERMINAL_FAILURE job_id=$JID state=$state exit_code=$exit_code" >&2
    exit 113
    ;;
esac
