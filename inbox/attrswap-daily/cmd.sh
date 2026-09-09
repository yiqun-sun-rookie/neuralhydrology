#!/bin/bash
# forcing-swap RETRIEVE -- pack the 9 per-basin metric tables + medians + gate + run configs + slurm logs
# into a tar.gz and print it base64 inside the receipt (decode locally: base64 -d > pswap_hpc_results.tar.gz).
set -o pipefail
ROOT=/data1/home/sunyiq/precip_swap_daily_2026_09
date "+wallclock %F %T %z"
cd "$ROOT" || { echo "ROOT MISSING"; exit 1; }
echo "=== A. COMPLETENESS ==="
n=0; for a in pswap_armP_chirps_s100 pswap_armP_chirps_s200 pswap_armP_chirps_s300 pswap_armP_era5l_s100 pswap_armP_era5l_s200 pswap_armP_era5l_s300; do
  f="logs/$a.public_median.txt"; if [ -f "$f" ]; then echo "  $a: $(cat "$f")"; n=$((n+1)); else echo "  $a: MISSING"; fi
done
echo "arms with medians: $n/6"
echo "=== B. PACK ==="
TMP=$(mktemp -d)
mkdir -p "$TMP/pswap_hpc_results"
for d in runs/pswap_*; do
  [ -d "$d" ] || continue
  a=$(basename "$d")
  mkdir -p "$TMP/pswap_hpc_results/$a/test/model_epoch030"
  cp "$d/config.yml" "$TMP/pswap_hpc_results/$a/" 2>/dev/null
  cp "$d/test/model_epoch030/test_metrics.csv" "$TMP/pswap_hpc_results/$a/test/model_epoch030/" 2>/dev/null
  cp "$d/output.log" "$TMP/pswap_hpc_results/$a/" 2>/dev/null
done
cp logs/*.public_median.txt logs/gate.txt logs/rebuild_era5l.txt logs/build_*.json logs/job_ids*.txt "$TMP/pswap_hpc_results/" 2>/dev/null
mkdir -p "$TMP/pswap_hpc_results/slurm_logs"
for f in logs/slurm_pswap_*.out logs/slurm_pswap_*.err; do  # drop tqdm progress-bar lines (2+ MB per job), keep everything else
  [ -f "$f" ] && grep -v -E '%\|' "$f" > "$TMP/pswap_hpc_results/slurm_logs/$(basename "$f")"
done
( cd "$TMP/pswap_hpc_results" && find . -type f | LC_ALL=C sort | xargs sha256sum ) > "$TMP/pswap_hpc_results/MANIFEST.sha256"
( cd "$TMP" && tar --mtime='2026-01-01 00:00:00' --owner=0 --group=0 --numeric-owner -czf pswap_hpc_results.tar.gz pswap_hpc_results )
echo "tar bytes=$(stat -c%s "$TMP/pswap_hpc_results.tar.gz") sha256=$(sha256sum "$TMP/pswap_hpc_results.tar.gz" | cut -c1-16) files=$(wc -l < "$TMP/pswap_hpc_results/MANIFEST.sha256")"
echo "=== C. BASE64 (between the markers) ==="
echo "-----BEGIN TARGZ B64-----"
base64 -w 0 "$TMP/pswap_hpc_results.tar.gz"; echo
echo "-----END TARGZ B64-----"
rm -rf "$TMP"
echo "=== DONE ==="
