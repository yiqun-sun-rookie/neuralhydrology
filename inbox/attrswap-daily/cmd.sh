#!/bin/bash
# READ-ONLY retrieval for the ADDENDUM (gsmap_uncal_refday, gate 228125, array 228126): if the 3 arms have epoch-30
# test metrics, pack config.yml + output.log + test_metrics.csv + gate/build logs as base64 tar.gz between markers.
# Built in a temp dir; the MANIFEST is written outside the packed dir first, then moved in (no self-entry).
# No sbatch, no scancel. No backslash literals.
set -o pipefail
date "+wallclock %F %T %z"
R=/data1/home/sunyiq/precip_swap4_gpm_daily_2026_09
cd "$R" || { echo "ROOT MISSING"; exit 1; }
echo "=== A. sacct ==="
sacct -j 228125,228126 -X -S 2026-09-27 -n -P --format=JobID,State,Elapsed,ExitCode,NodeList 2>&1 | sed 's/^/  /'
[ -f logs/gate_add_ok.txt ] && echo "  $(cat logs/gate_add_ok.txt)"
n=$(find runs -path '*gsmap_uncal_refday*/test/model_epoch030/test_metrics.csv' | wc -l)
echo "  addendum arms with epoch-30 metrics: $n/3"
if [ "$n" -ne 3 ]; then
  for f in logs/slurm_pswap4_gate_add_228125.out logs/slurm_pswap4_arm_add_228126_*.out; do [ -f "$f" ] && { echo "--- $f"; tail -4 "$f"; }; done
  echo "=== NOT READY: no pack ==="; exit 0
fi
TMP=$(mktemp -d)
P="$TMP/pswap4_add_results"
mkdir -p "$P/runs" "$P/logs"
for d in runs/pswap4_armG_gsmap_uncal_refday_*; do
  a=$(basename "$d")
  mkdir -p "$P/runs/$a/test/model_epoch030"
  cp "$d/config.yml" "$d/output.log" "$P/runs/$a/"
  cp "$d/test/model_epoch030/test_metrics.csv" "$P/runs/$a/test/model_epoch030/"
done
cp logs/gate_add_ok.txt logs/jobs_add.txt logs/build_gsmap_uncal_refday.json configs/arms_add.txt configs/configs_manifest_add.json "$P/logs/" 2>/dev/null
cp logs/slurm_pswap4_gate_add_228125.out "$P/logs/" 2>/dev/null
for f in logs/slurm_pswap4_arm_add_228126_*.out; do grep -v -E '%[|]' "$f" > "$P/logs/$(basename $f)"; done
( cd "$P" && find . -type f | LC_ALL=C sort | xargs sha256sum ) > "$TMP/MANIFEST.sha256"
mv "$TMP/MANIFEST.sha256" "$P/MANIFEST.sha256"
( cd "$TMP" && tar --mtime='2026-01-01 00:00:00' --owner=0 --group=0 --numeric-owner -czf pswap4_add_results.tar.gz pswap4_add_results )
echo "tar bytes=$(stat -c%s "$TMP/pswap4_add_results.tar.gz") sha256=$(sha256sum "$TMP/pswap4_add_results.tar.gz" | cut -c1-16) files=$(wc -l < "$P/MANIFEST.sha256")"
echo "-----BEGIN TARGZ B64-----"
base64 -w 0 "$TMP/pswap4_add_results.tar.gz"; echo
echo "-----END TARGZ B64-----"
rm -rf "$TMP"
echo "=== DONE ==="
