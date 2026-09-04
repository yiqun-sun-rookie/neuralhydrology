#!/bin/bash
set -o pipefail
ROOT=/data1/home/sunyiq/kalmannet_wrr_hp_extension_20260902
EXP="$ROOT/repo/experiments/optimize_hyper_parameters/wrr_hp_extension_20260902"
cd "$EXP" || exit 1
echo "=== FILE_LIST ==="
find runs -name cell_metrics.json -o -name epoch_log.jsonl -o -name FAILED -o -name error.txt | sort
echo "=== TARBALL_B64 (cell_metrics + failed-cell diagnostics + epoch logs) ==="
tar -czf /tmp/wrrhp_results_$$.tar.gz \
  $(find runs -name cell_metrics.json | sort) \
  $(find runs -name epoch_log.jsonl | sort) \
  $(find runs -name FAILED -o -name error.txt | sort) \
  registry.csv combos.jsonl source_manifest.json 2>/dev/null
echo "bytes=$(stat -c %s /tmp/wrrhp_results_$$.tar.gz) sha256=$(sha256sum /tmp/wrrhp_results_$$.tar.gz | awk '{print $1}')"
base64 -w 120 /tmp/wrrhp_results_$$.tar.gz
rm -f /tmp/wrrhp_results_$$.tar.gz
echo "=== END_B64 ==="
