#!/usr/bin/env bash
set -eo pipefail
root=/data1/home/sunyiq/kalmannet_wrr_counter_diagnosis_20260928_v1
job=228714
echo '=== FINAL SCHEDULER STATE ==='
sacct -n -P -j "$job" -o JobID,JobName,State,ExitCode,Elapsed,NodeList | sed -n '1,8p'
echo '=== FULL COMPARISON ==='
cat "$root/comparison.json"
echo '=== COUNTER COVERAGE ==='
cat "$root/runs/counted_a/counter_coverage.json"
cat "$root/runs/counted_b/counter_coverage.json"
echo '=== EACH PHASE CLAIMS ==='
for phase in plain_a counted_a counted_b plain_b; do
  echo "PHASE=$phase"
  grep -E '"(state|case_id|model_inference_calls|training_calls|test_tensor_reads|time_mapping_passed|inputs_unchanged|parameters_unchanged|duration_seconds)"' "$root/runs/$phase/completion.json"
done
echo '=== ENVIRONMENT AND SMALL EVIDENCE HASHES ==='
cat "$root/runs/plain_a/environment.json"
sha256sum "$root/comparison.json" "$root/runs/plain_a/completion.json" "$root/runs/counted_a/completion.json" "$root/runs/counted_b/completion.json" "$root/runs/plain_b/completion.json"
echo '=== ARTIFACT COUNTS AND FAILURE FILES ==='
find "$root/runs" -maxdepth 2 -type f -name '*.npy' -printf '%p|%s\n' | sort
find "$root/runs" -maxdepth 2 -type f -name failure.json -print
