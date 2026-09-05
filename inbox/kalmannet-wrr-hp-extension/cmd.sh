#!/bin/bash
set -o pipefail
EXP=/data1/home/sunyiq/kalmannet_wrr_hp_extension_20260902/repo/experiments/optimize_hyper_parameters/wrr_hp_extension_20260902
cd "$EXP" || exit 1
echo "=== FILES ==="
find runs -path '*idx001[7-9]_*' -o -path '*idx002[0-5]_*' | grep -E 'cell_metrics.json|epoch_log.jsonl|FAILED|error.txt' | sort
echo "=== TARBALL_B64 ==="
tar -czf /tmp/wrrhp_ladder_$$.tar.gz $(find runs \( -path '*idx001[7-9]_*' -o -path '*idx002[0-5]_*' \) \( -name cell_metrics.json -o -name epoch_log.jsonl -o -name FAILED -o -name error.txt \) | sort) combos.jsonl registry.csv 2>/dev/null
echo "bytes=$(stat -c %s /tmp/wrrhp_ladder_$$.tar.gz) sha256=$(sha256sum /tmp/wrrhp_ladder_$$.tar.gz | awk '{print $1}')"
base64 -w 120 /tmp/wrrhp_ladder_$$.tar.gz; rm -f /tmp/wrrhp_ladder_$$.tar.gz
echo "=== END_B64 ==="
