#!/bin/bash
# Stage-2 RETRIEVE part 2 of 2: the 18 candidate arms (noise floor registered locally 2026-09-13 16:03, sha 00b16c3dbfd9401e).
# Read-only on the landing dir (tar built in a temp dir). No backslash literals anywhere in this file.
set -o pipefail
ROOT=/data1/home/sunyiq/precip_swap2_daily_2026_09
date "+wallclock %F %T %z"
cd "$ROOT" || { echo "ROOT MISSING"; exit 1; }
echo "=== A. COMPLETENESS (candidate arms: test_metrics.csv present) ==="
n=0; for d in runs/pswap2_armP_*; do f="$d/test/model_epoch030/test_metrics.csv"; if [ -f "$f" ]; then n=$((n+1)); echo "  $(basename $d): $(wc -l < $f) rows"; else echo "  $(basename $d): MISSING"; fi; done
echo "candidate arms evaluated: $n/18"
echo "=== B. PACK (candidates only) ==="
TMP=$(mktemp -d)
P="$TMP/pswap2_cand_results"
mkdir -p "$P/slurm_logs"
for d in runs/pswap2_armP_*; do
  [ -d "$d" ] || continue
  a=$(basename "$d")
  mkdir -p "$P/$a/test/model_epoch030"
  cp "$d/config.yml" "$P/$a/" 2>/dev/null
  cp "$d/test/model_epoch030/test_metrics.csv" "$P/$a/test/model_epoch030/" 2>/dev/null
  cp "$d/output.log" "$P/$a/" 2>/dev/null
done
for f in logs/slurm_pswap2_armP_*.out logs/slurm_pswap2_armP_*.err; do
  [ -f "$f" ] && grep -v -E '%[|]' "$f" > "$P/slurm_logs/$(basename "$f")"
done
echo "  public_median files for candidates: $(ls logs/pswap2_armP_*.public_median.txt 2>/dev/null | wc -l) (must be 0, stop condition 5)"
( cd "$P" && find . -type f | LC_ALL=C sort | xargs sha256sum ) > "$P/MANIFEST.sha256"
( cd "$TMP" && tar --mtime='2026-01-01 00:00:00' --owner=0 --group=0 --numeric-owner -czf pswap2_cand_results.tar.gz pswap2_cand_results )
echo "tar bytes=$(stat -c%s "$TMP/pswap2_cand_results.tar.gz") sha256=$(sha256sum "$TMP/pswap2_cand_results.tar.gz" | cut -c1-16) files=$(wc -l < "$P/MANIFEST.sha256")"
echo "=== C. BASE64 (between the markers) ==="
echo "-----BEGIN TARGZ B64-----"
base64 -w 0 "$TMP/pswap2_cand_results.tar.gz"; echo
echo "-----END TARGZ B64-----"
rm -rf "$TMP"
echo "=== DONE ==="
