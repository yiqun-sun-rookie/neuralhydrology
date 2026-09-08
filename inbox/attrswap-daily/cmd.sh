#!/bin/bash
# forcing-swap RETRIEVE -- pack the 9 per-basin metric tables + medians + gate + run configs + slurm logs
# into a tar.gz and print it base64 inside the receipt (decode locally: base64 -d > fswap_hpc_results.tar.gz).
set -o pipefail
ROOT=/data1/home/sunyiq/forcing_swap_daily_2026_09
date "+wallclock %F %T %z"
cd "$ROOT" || { echo "ROOT MISSING"; exit 1; }
echo "=== A. COMPLETENESS ==="
n=0; for a in fswap_armE27_s100 fswap_armE27_s200 fswap_armE27_s300 fswap_armE23_s100 fswap_armE23_s200 fswap_armE23_s300 fswap_armEP_s100 fswap_armEP_s200 fswap_armEP_s300; do
  f="logs/$a.public_median.txt"; if [ -f "$f" ]; then echo "  $a: $(cat "$f")"; n=$((n+1)); else echo "  $a: MISSING"; fi
done
echo "arms with medians: $n/9"
echo "=== B. PACK ==="
TMP=$(mktemp -d)
mkdir -p "$TMP/fswap_hpc_results"
for d in runs/fswap_*; do
  [ -d "$d" ] || continue
  a=$(basename "$d")
  mkdir -p "$TMP/fswap_hpc_results/$a/test/model_epoch030"
  cp "$d/config.yml" "$TMP/fswap_hpc_results/$a/" 2>/dev/null
  cp "$d/test/model_epoch030/test_metrics.csv" "$TMP/fswap_hpc_results/$a/test/model_epoch030/" 2>/dev/null
  cp "$d/output.log" "$TMP/fswap_hpc_results/$a/" 2>/dev/null
done
cp logs/*.public_median.txt logs/gate.txt logs/convert_verify.json logs/job_ids.txt "$TMP/fswap_hpc_results/" 2>/dev/null
mkdir -p "$TMP/fswap_hpc_results/slurm_logs"
for f in logs/slurm_fswap_*.out logs/slurm_fswap_*.err; do  # drop tqdm progress-bar lines (2+ MB per job), keep everything else
  [ -f "$f" ] && grep -v -E '%\|' "$f" > "$TMP/fswap_hpc_results/slurm_logs/$(basename "$f")"
done
( cd "$TMP/fswap_hpc_results" && find . -type f | LC_ALL=C sort | xargs sha256sum ) > "$TMP/fswap_hpc_results/MANIFEST.sha256"
( cd "$TMP" && tar --mtime='2026-01-01 00:00:00' --owner=0 --group=0 --numeric-owner -czf fswap_hpc_results.tar.gz fswap_hpc_results )
echo "tar bytes=$(stat -c%s "$TMP/fswap_hpc_results.tar.gz") sha256=$(sha256sum "$TMP/fswap_hpc_results.tar.gz" | cut -c1-16) files=$(wc -l < "$TMP/fswap_hpc_results/MANIFEST.sha256")"
echo "=== C. BASE64 (between the markers) ==="
echo "-----BEGIN TARGZ B64-----"
base64 -w 0 "$TMP/fswap_hpc_results.tar.gz"; echo
echo "-----END TARGZ B64-----"
rm -rf "$TMP"
echo "=== DONE ==="
