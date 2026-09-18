#!/bin/bash
# Stage-3 RETRIEVE part 1 of 2 (PREREG_20260916 section 11.0 + stop condition 5, 18.1 item 7): ONLY the reference-family
# files -- the 3 ref_daymet ep60 runs (epoch 30 and 60 metrics) and the 8 reference COPIES in runs_s2_copy/ (epoch 10 and
# 20 metrics) -- plus gate/guard/build/E4-manifest/P7 logs. No era5l ep60 run, no E1/E2/shift1 arm and no candidate
# copy is touched; they come in part 2 after the ep60/ep10/ep20 noise floors are registered locally.
# Read-only on the landing dir (tar built in a temp dir). No backslash literals anywhere in this file.
set -o pipefail
ROOT=/data1/home/sunyiq/precip_swap3_daily_2026_09
date "+wallclock %F %T %z"
cd "$ROOT" || { echo "ROOT MISSING"; exit 1; }
echo "=== A. COMPLETENESS (reference family) ==="
for d in runs/pswap3_ep60_ref_daymet_s*_ep60; do
  for ep in 030 060; do f="$d/test/model_epoch$ep/test_metrics.csv"; if [ -f "$f" ]; then echo "  $(basename $d) ep$ep: $(wc -l < $f) rows"; else echo "  $(basename $d) ep$ep: MISSING"; fi; done
done
for d in runs_s2_copy/ref_daymet_s*; do
  for ep in 010 020; do f="$d/test/model_epoch$ep/test_metrics.csv"; if [ -f "$f" ]; then echo "  copy $(basename $d) ep$ep: $(wc -l < $f) rows"; else echo "  copy $(basename $d) ep$ep: MISSING"; fi; done
done
echo "=== B. PACK (reference family only) ==="
TMP=$(mktemp -d)
P="$TMP/pswap3_ref_results"
mkdir -p "$P/slurm_logs"
for d in runs/pswap3_ep60_ref_daymet_s*_ep60; do
  [ -d "$d" ] || continue
  a=$(basename "$d")
  mkdir -p "$P/$a/test/model_epoch030" "$P/$a/test/model_epoch060"
  cp "$d/config.yml" "$P/$a/" 2>/dev/null
  cp "$d/output.log" "$P/$a/" 2>/dev/null
  cp "$d/test/model_epoch030/test_metrics.csv" "$P/$a/test/model_epoch030/" 2>/dev/null
  cp "$d/test/model_epoch060/test_metrics.csv" "$P/$a/test/model_epoch060/" 2>/dev/null
done
for d in runs_s2_copy/ref_daymet_s*; do
  [ -d "$d" ] || continue
  a=$(basename "$d")
  mkdir -p "$P/runs_s2_copy/$a/test/model_epoch010" "$P/runs_s2_copy/$a/test/model_epoch020"
  cp "$d/config.yml" "$P/runs_s2_copy/$a/" 2>/dev/null
  cp "$d/test/model_epoch010/test_metrics.csv" "$P/runs_s2_copy/$a/test/model_epoch010/" 2>/dev/null
  cp "$d/test/model_epoch020/test_metrics.csv" "$P/runs_s2_copy/$a/test/model_epoch020/" 2>/dev/null
done
cp logs/gate_*.txt logs/build_*.json logs/guard_T16.json logs/guard_T16_PASS.txt logs/e4_copy_manifest.json logs/e4_done.txt logs/e4_ref_done.txt logs/p7_hydro_year.json logs/v9_streamflow.json logs/jobs.txt logs/budget_ledger.txt "$P/" 2>/dev/null
for f in logs/slurm_pswap3_gate_*.out logs/slurm_pswap3_gate_*.err logs/slurm_pswap3_guard_T16_*.out logs/slurm_pswap3_guard_T16_*.err logs/slurm_pswap3_p7_*.out logs/slurm_pswap3_p7_*.err logs/slurm_pswap3_eval_ckpt_*.out logs/slurm_pswap3_eval_ckpt_*.err logs/slurm_pswap3_ep60_ref_daymet_*.out logs/slurm_pswap3_ep60_ref_daymet_*.err; do
  [ -f "$f" ] && grep -v -E '%[|]' "$f" > "$P/slurm_logs/$(basename "$f")"
done
echo "  candidate files included: $(find "$P" -path '*era5l*' -o -path '*pswap3_win_*' -o -path '*pswap3_syn_*' -o -path '*pswap3_shift1*' -o -path '*pswap2_armP*' | wc -l) (must be 0)"
echo "  ref ep60 metrics: $(find "$P" -path '*pswap3_ep60_ref_daymet*test_metrics.csv' | wc -l) (expect 6); ref copy metrics: $(find "$P" -path '*runs_s2_copy*test_metrics.csv' | wc -l) (expect 16)"
( cd "$P" && find . -type f | LC_ALL=C sort | xargs sha256sum ) > "$P/MANIFEST.sha256"
( cd "$TMP" && tar --mtime='2026-01-01 00:00:00' --owner=0 --group=0 --numeric-owner -czf pswap3_ref_results.tar.gz pswap3_ref_results )
echo "tar bytes=$(stat -c%s "$TMP/pswap3_ref_results.tar.gz") sha256=$(sha256sum "$TMP/pswap3_ref_results.tar.gz" | cut -c1-16) files=$(wc -l < "$P/MANIFEST.sha256")"
echo "=== C. BASE64 (between the markers) ==="
echo "-----BEGIN TARGZ B64-----"
base64 -w 0 "$TMP/pswap3_ref_results.tar.gz"; echo
echo "-----END TARGZ B64-----"
rm -rf "$TMP"
echo "=== DONE ==="
