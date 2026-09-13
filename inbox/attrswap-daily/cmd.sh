#!/bin/bash
# Stage-2 RETRIEVE part 1 of 2 (PREREG_20260911 stop condition 5): ONLY the 8 ref_daymet arms + gate/build/V9 logs.
# Candidate arms are NOT touched here; they are retrieved in a later receipt after the noise floor is registered.
# Read-only on the landing dir (tar built in a temp dir). No backslash literals anywhere in this file.
set -o pipefail
ROOT=/data1/home/sunyiq/precip_swap2_daily_2026_09
date "+wallclock %F %T %z"
cd "$ROOT" || { echo "ROOT MISSING"; exit 1; }
echo "=== A. COMPLETENESS (reference arms) ==="
n=0; for s in 100 200 300 400 500 600 700 800; do
  f="logs/ref_daymet_s$s.public_median.txt"; if [ -f "$f" ]; then echo "  ref_daymet_s$s: $(cat "$f")"; n=$((n+1)); else echo "  ref_daymet_s$s: MISSING"; fi
done
echo "reference arms with medians: $n/8"
echo "=== B. PACK (reference only) ==="
TMP=$(mktemp -d)
P="$TMP/pswap2_ref_results"
mkdir -p "$P/slurm_logs"
for d in runs/ref_daymet_s*; do
  [ -d "$d" ] || continue
  a=$(basename "$d")
  mkdir -p "$P/$a/test/model_epoch030"
  cp "$d/config.yml" "$P/$a/" 2>/dev/null
  cp "$d/test/model_epoch030/test_metrics.csv" "$P/$a/test/model_epoch030/" 2>/dev/null
  cp "$d/output.log" "$P/$a/" 2>/dev/null
done
cp logs/ref_daymet_s*.public_median.txt logs/gate_*.txt logs/build_*.json logs/v9_streamflow.json logs/jobs.txt "$P/" 2>/dev/null
for f in logs/slurm_pswap2_gate_*.out logs/slurm_pswap2_gate_*.err logs/slurm_ref_daymet_*.out logs/slurm_ref_daymet_*.err; do
  [ -f "$f" ] && grep -v -E '%[|]' "$f" > "$P/slurm_logs/$(basename "$f")"
done
echo "  candidate arm files included: $(find "$P" -path '*pswap2_armP*' | wc -l) (must be 0)"
( cd "$P" && find . -type f | LC_ALL=C sort | xargs sha256sum ) > "$P/MANIFEST.sha256"
( cd "$TMP" && tar --mtime='2026-01-01 00:00:00' --owner=0 --group=0 --numeric-owner -czf pswap2_ref_results.tar.gz pswap2_ref_results )
echo "tar bytes=$(stat -c%s "$TMP/pswap2_ref_results.tar.gz") sha256=$(sha256sum "$TMP/pswap2_ref_results.tar.gz" | cut -c1-16) files=$(wc -l < "$P/MANIFEST.sha256")"
echo "=== C. BASE64 (between the markers) ==="
echo "-----BEGIN TARGZ B64-----"
base64 -w 0 "$TMP/pswap2_ref_results.tar.gz"; echo
echo "-----END TARGZ B64-----"
rm -rf "$TMP"
echo "=== DONE ==="
