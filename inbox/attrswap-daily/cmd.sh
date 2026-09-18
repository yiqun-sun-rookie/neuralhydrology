#!/bin/bash
# Stage-3 RETRIEVE part 2 of 2: the candidate families, after the ep60 / ep10 / ep20 noise floors were registered locally
# (2026-09-18 16:2x, noise_floor_ep60 c9952cbe705a4232 / ep10 e9820be33f1c575d / ep20 e81174f734a1285b):
# 3 era5l ep60 runs (epoch 30 + 60), the 24 thirty-epoch arms (E1 windows, E2 noise tiers, shift1; epoch 30), the 18
# candidate copies in runs_s2_copy/ (epoch 10 + 20), plus the filtered slurm logs of those arms.
# Read-only on the landing dir (tar built in a temp dir). No backslash literals anywhere in this file.
set -o pipefail
ROOT=/data1/home/sunyiq/precip_swap3_daily_2026_09
date "+wallclock %F %T %z"
cd "$ROOT" || { echo "ROOT MISSING"; exit 1; }
echo "=== A. COMPLETENESS (candidate families) ==="
n=0
for d in runs/pswap3_ep60_era5l_refday_s*_ep60; do for ep in 030 060; do f="$d/test/model_epoch$ep/test_metrics.csv"; if [ -f "$f" ]; then n=$((n+1)); else echo "  MISSING $d ep$ep"; fi; done; done
echo "  era5l ep60 metrics: $n/6"
n=0
for d in runs/pswap3_win_* runs/pswap3_syn_* runs/pswap3_shift1_*; do f="$d/test/model_epoch030/test_metrics.csv"; if [ -f "$f" ]; then n=$((n+1)); else echo "  MISSING $d"; fi; done
echo "  30-epoch arm metrics: $n/24"
n=0
for d in runs_s2_copy/pswap2_armP_*; do for ep in 010 020; do f="$d/test/model_epoch$ep/test_metrics.csv"; if [ -f "$f" ]; then n=$((n+1)); else echo "  MISSING $d ep$ep"; fi; done; done
echo "  candidate copy metrics: $n/36"
echo "=== B. PACK (candidate families) ==="
TMP=$(mktemp -d)
P="$TMP/pswap3_cand_results"
mkdir -p "$P/slurm_logs"
for d in runs/pswap3_ep60_era5l_refday_s*_ep60; do
  [ -d "$d" ] || continue
  a=$(basename "$d")
  mkdir -p "$P/$a/test/model_epoch030" "$P/$a/test/model_epoch060"
  cp "$d/config.yml" "$P/$a/" 2>/dev/null
  cp "$d/output.log" "$P/$a/" 2>/dev/null
  cp "$d/test/model_epoch030/test_metrics.csv" "$P/$a/test/model_epoch030/" 2>/dev/null
  cp "$d/test/model_epoch060/test_metrics.csv" "$P/$a/test/model_epoch060/" 2>/dev/null
done
for d in runs/pswap3_win_* runs/pswap3_syn_* runs/pswap3_shift1_*; do
  [ -d "$d" ] || continue
  a=$(basename "$d")
  mkdir -p "$P/$a/test/model_epoch030"
  cp "$d/config.yml" "$P/$a/" 2>/dev/null
  cp "$d/output.log" "$P/$a/" 2>/dev/null
  cp "$d/test/model_epoch030/test_metrics.csv" "$P/$a/test/model_epoch030/" 2>/dev/null
done
for d in runs_s2_copy/pswap2_armP_*; do
  [ -d "$d" ] || continue
  a=$(basename "$d")
  mkdir -p "$P/runs_s2_copy/$a/test/model_epoch010" "$P/runs_s2_copy/$a/test/model_epoch020"
  cp "$d/config.yml" "$P/runs_s2_copy/$a/" 2>/dev/null
  cp "$d/test/model_epoch010/test_metrics.csv" "$P/runs_s2_copy/$a/test/model_epoch010/" 2>/dev/null
  cp "$d/test/model_epoch020/test_metrics.csv" "$P/runs_s2_copy/$a/test/model_epoch020/" 2>/dev/null
done
for f in logs/slurm_pswap3_ep60_era5l_refday_*.out logs/slurm_pswap3_ep60_era5l_refday_*.err logs/slurm_pswap3_win_*.out logs/slurm_pswap3_win_*.err logs/slurm_pswap3_syn_*.out logs/slurm_pswap3_syn_*.err logs/slurm_pswap3_shift1_*.out logs/slurm_pswap3_shift1_*.err; do
  [ -f "$f" ] && grep -v -E '%[|]' "$f" > "$P/slurm_logs/$(basename "$f")"
done
echo "  public_median files for candidates: $(ls logs/pswap3_win_*.public_median.txt logs/pswap3_syn_*.public_median.txt logs/pswap3_shift1_*.public_median.txt logs/pswap3_ep60_era5l_*.public_median.txt 2>/dev/null | wc -l) (must be 0, stop condition 5)"
echo "  metrics packed: $(find "$P" -name test_metrics.csv | wc -l) (expect 6 + 24 + 36 = 66)"
( cd "$P" && find . -type f | LC_ALL=C sort | xargs sha256sum ) > "$P/MANIFEST.sha256"
( cd "$TMP" && tar --mtime='2026-01-01 00:00:00' --owner=0 --group=0 --numeric-owner -czf pswap3_cand_results.tar.gz pswap3_cand_results )
echo "tar bytes=$(stat -c%s "$TMP/pswap3_cand_results.tar.gz") sha256=$(sha256sum "$TMP/pswap3_cand_results.tar.gz" | cut -c1-16) files=$(wc -l < "$P/MANIFEST.sha256")"
echo "=== C. BASE64 (between the markers) ==="
echo "-----BEGIN TARGZ B64-----"
base64 -w 0 "$TMP/pswap3_cand_results.tar.gz"; echo
echo "-----END TARGZ B64-----"
rm -rf "$TMP"
echo "=== DONE ==="
