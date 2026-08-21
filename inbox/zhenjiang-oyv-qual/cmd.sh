#!/usr/bin/env bash
# Read-only extraction of the complete paper-facing gauge-failure evidence ledger.
set -o pipefail
ROOT=/data1/home/sunyiq/zhenjiang_oyv_v1
SUMMARY="$ROOT/ladder_impact/ladder_cost_summary.csv"
RANKING="$ROOT/ladder_impact/station_ranking.csv"

echo "=== A. IDENTITIES ==="
test -f "$SUMMARY" || { echo "MISSING_SUMMARY"; exit 1; }
test -f "$RANKING" || { echo "MISSING_RANKING"; exit 1; }
sha256sum "$SUMMARY" "$RANKING"

echo "=== B. HEADER ==="
head -n 1 "$SUMMARY"

echo "=== C. TARGET-GAUGE FAILURE COSTS, ALL REPORTED HORIZONS ==="
grep -E '^complete_observation,(zhenjiang|jiangyin),hidden_target,(1|3|6|12|24),' "$SUMMARY"

echo "=== D. SINGLE ADDITIONAL STATION LOSSES, ALL REPORTED HORIZONS ==="
grep -E '^hidden_target,(zhenjiang|jiangyin),hidden_target_minus_[a-z]+,(1|3|6|12|24),' "$SUMMARY"

echo "=== E. MULTI-STATION LOSSES, ALL REPORTED HORIZONS ==="
grep -E '^hidden_target,(zhenjiang|jiangyin),(hidden_target_both_nearest|endpoints_only),(1|3|6|12|24),' "$SUMMARY"

echo "=== F. PREREGISTERED ONE- AND SIX-HOUR RANKINGS ==="
cat "$RANKING"
echo "=== END ==="
