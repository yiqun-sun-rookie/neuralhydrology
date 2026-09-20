#!/bin/bash
# seq=88 READ-ONLY: status of the R1 jobs (226558-226561) and, if all three syn_ln018 arms are COMPLETED with test
# metrics, pack them (config + output.log + epoch-30 test_metrics + gate marker + filtered slurm logs) as base64 tar.gz.
# Nothing is written into the landing dir (tar built in a temp dir). No backslash literals.
set -o pipefail
date "+wallclock %F %T %z"
date "+epoch %s"
ROOT=/data1/home/sunyiq/precip_swap3_daily_2026_09
cd "$ROOT" || { echo "ROOT MISSING"; exit 1; }
echo "=== A. sacct R1 ==="
sacct -j 226558,226559,226560,226561 -X --format=JobID,JobName%28,State%12,Elapsed,Start,End,ExitCode,NodeList%10 2>&1
echo "=== B. queue ==="
squeue -u "$USER" -o '%.10i %.36j %.9T %.10M %.9P %R' 2>&1 | grep -Ei 'pswap3|JOBID'
echo "=== C. markers / runs ==="
[ -f logs/gate_syn_ln018.txt ] && echo "  $(cat logs/gate_syn_ln018.txt)" || echo "  gate_syn_ln018.txt: MISSING"
tail -n 2 logs/budget_ledger.txt | sed 's/^/  /'
n=0
for d in runs/pswap3_syn_ln018_s*_ep30; do
  [ -d "$d" ] || continue
  f="$d/test/model_epoch030/test_metrics.csv"
  if [ -f "$f" ]; then n=$((n+1)); echo "  $(basename $d): $(wc -l < $f) rows"; else echo "  $(basename $d): no test_metrics yet"; fi
done
echo "  arms with metrics: $n/3"
if [ "$n" -ne 3 ]; then echo "=== NOT READY: no pack ==="; echo "=== DONE (read-only) ==="; exit 0; fi
echo "=== D. PACK (R1 arms only) ==="
TMP=$(mktemp -d)
P="$TMP/pswap3_r1_results"
mkdir -p "$P/slurm_logs"
for d in runs/pswap3_syn_ln018_s*_ep30; do
  a=$(basename "$d")
  mkdir -p "$P/$a/test/model_epoch030"
  cp "$d/config.yml" "$P/$a/" 2>/dev/null
  cp "$d/output.log" "$P/$a/" 2>/dev/null
  cp "$d/test/model_epoch030/test_metrics.csv" "$P/$a/test/model_epoch030/" 2>/dev/null
done
cp logs/gate_syn_ln018.txt logs/build_syn_ln018.json logs/budget_ledger.txt logs/jobs.txt logs/configs_manifest_before_r1.json "$P/" 2>/dev/null
cp configs/configs_manifest.json "$P/configs_manifest_after_r1.json" 2>/dev/null
for f in logs/slurm_pswap3_gate_syn_ln018_*.out logs/slurm_pswap3_gate_syn_ln018_*.err logs/slurm_pswap3_syn_ln018_*.out logs/slurm_pswap3_syn_ln018_*.err; do
  [ -f "$f" ] && grep -v -E '%[|]' "$f" > "$P/slurm_logs/$(basename "$f")"
done
echo "  metrics packed: $(find "$P" -name test_metrics.csv | wc -l) (expect 3)"
( cd "$P" && find . -type f | LC_ALL=C sort | xargs sha256sum ) > "$P/MANIFEST.sha256"
( cd "$TMP" && tar --mtime='2026-01-01 00:00:00' --owner=0 --group=0 --numeric-owner -czf pswap3_r1_results.tar.gz pswap3_r1_results )
echo "tar bytes=$(stat -c%s "$TMP/pswap3_r1_results.tar.gz") sha256=$(sha256sum "$TMP/pswap3_r1_results.tar.gz" | cut -c1-16) files=$(wc -l < "$P/MANIFEST.sha256")"
echo "=== E. BASE64 (between the markers) ==="
echo "-----BEGIN TARGZ B64-----"
base64 -w 0 "$TMP/pswap3_r1_results.tar.gz"; echo
echo "-----END TARGZ B64-----"
rm -rf "$TMP"
echo "=== DONE ==="
