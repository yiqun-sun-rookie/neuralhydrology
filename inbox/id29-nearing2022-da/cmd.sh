#!/bin/bash
# ID29 seq=289: locate the actual run dirs / epoch-30 checkpoints for the rerun coordinates.
set -o pipefail
ROOT=/data1/home/sunyiq/nearing2022_da
AR="$ROOT/closure_20260810/time_split/autoregression"

echo "=== TIME ==="; date --iso-8601=seconds
echo "=== AR PARENT LISTING ==="
ls -1 "$AR" 2>/dev/null | head -30 || echo "AR dir missing: $AR"
echo "  (count=$(ls -1 "$AR" 2>/dev/null | wc -l))"

echo "=== EPOCH-30 CHECKPOINTS UNDER AR (newest 8) ==="
find "$AR" -name 'model_epoch030.pt' -printf '%T@|%p|%s\n' 2>/dev/null | sort -rn | head -8 | \
  while IFS='|' read -r t p s; do printf '  %s  %10s bytes  %s\n' "$(date -d @${t%.*} '+%m-%d %H:%M')" "$s" "${p#$AR/}"; done

echo "=== TARGET COORDINATES ==="
for C in lead_2_holdout_0.75_seed_0 lead_2_holdout_1.0_seed_0 lead_1_holdout_0.5_seed_0; do
  D="$AR/$C"
  if [ -d "$D" ]; then
    printf -- '--- %s ---\n' "$C"
    ls -1 "$D" 2>/dev/null | head -6
    find "$D" -name 'model_epoch0*.pt' 2>/dev/null | sed 's|.*/||' | sort | tail -3 | sed 's/^/    /'
  else
    printf -- '--- %s : parent dir ABSENT ---\n' "$C"
  fi
done

echo "=== RERUN JOB STATES ==="
sacct -X -n -P -j 204860,204861,206430 --format=JobID,JobName,State,Elapsed,End,NodeList 2>/dev/null || true
echo "=== RERUN STDOUT TAILS ==="
for J in 204860 204861; do
  L=$(ls -t "$ROOT/closure_20260810/logs/"*"${J}"*.out 2>/dev/null | head -1)
  [ -n "$L" ] && { printf -- '--- %s ---\n' "$(basename "$L")"; tail -c 4000 "$L" | tr '\r' '\n' | grep -vE '^# Epoch' | tail -8; }
done

echo "=== END seq=289 ==="; date --iso-8601=seconds
exit 0
