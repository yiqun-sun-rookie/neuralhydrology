#!/bin/bash
# READ-ONLY retrieval for the GPM-era contract: if all 26 arms have epoch-30 test metrics, pack per run
# config.yml + output.log + test/model_epoch030/test_metrics.csv, plus the gate / build reports, jobs.txt and the
# budget ledger, as a deterministic tar.gz printed in base64 between markers. The tar is built in a temp dir
# (nothing is written into the landing dir). No sbatch, no scancel. No backslash literals.
set -o pipefail
date "+wallclock %F %T %z"
R=/data1/home/sunyiq/precip_swap4_gpm_daily_2026_09
cd "$R" || { echo "ROOT MISSING"; exit 1; }
echo "=== A. sacct ==="
sacct -j 228080,228081 -X -S 2026-09-27 -n -P --format=JobID,State,Elapsed,ExitCode,NodeList 2>&1 | sed 's/^/  /'
n=$(find runs -path '*/test/model_epoch030/test_metrics.csv' | wc -l)
echo "  arms with epoch-30 metrics: $n/26"
if [ "$n" -ne 26 ]; then echo "=== NOT READY: no pack ==="; exit 0; fi
echo "=== B. PACK ==="
TMP=$(mktemp -d)
P="$TMP/pswap4_results"
mkdir -p "$P/runs" "$P/logs"
for d in runs/pswap4_*; do
  a=$(basename "$d")
  mkdir -p "$P/runs/$a/test/model_epoch030"
  cp "$d/config.yml" "$d/output.log" "$P/runs/$a/"
  cp "$d/test/model_epoch030/test_metrics.csv" "$P/runs/$a/test/model_epoch030/"
done
cp logs/gate_ok.txt logs/jobs.txt logs/budget_ledger.txt logs/build_shadow4.json logs/build_*.json "$P/logs/" 2>/dev/null
cp configs/configs_manifest.json configs/arms.txt "$P/logs/" 2>/dev/null
cp logs/slurm_pswap4_gate_228080.out "$P/logs/" 2>/dev/null
for f in logs/slurm_pswap4_arm_228081_*.out; do grep -v -E '%[|]' "$f" > "$P/logs/$(basename $f)"; done
echo "  metrics packed: $(find "$P" -name test_metrics.csv | wc -l) (expect 26)"
( cd "$P" && find . -type f | LC_ALL=C sort | xargs sha256sum ) > "$P/MANIFEST.sha256"
( cd "$TMP" && tar --mtime='2026-01-01 00:00:00' --owner=0 --group=0 --numeric-owner -czf pswap4_results.tar.gz pswap4_results )
echo "tar bytes=$(stat -c%s "$TMP/pswap4_results.tar.gz") sha256=$(sha256sum "$TMP/pswap4_results.tar.gz" | cut -c1-16) files=$(wc -l < "$P/MANIFEST.sha256")"
echo "-----BEGIN TARGZ B64-----"
base64 -w 0 "$TMP/pswap4_results.tar.gz"; echo
echo "-----END TARGZ B64-----"
rm -rf "$TMP"
echo "=== DONE ==="
