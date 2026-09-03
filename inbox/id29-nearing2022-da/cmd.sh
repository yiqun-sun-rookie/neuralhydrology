set -o pipefail
ROOT=/data1/home/sunyiq/nearing2022_da
echo "=== SLURM SCRIPT LOG PATHS ==="
grep -nE 'output|error' "$ROOT/src/29_nearing2022_da_ar/hpc/run_warmup_target_pair.slurm" 2>/dev/null | head -20 || echo 'slurm file not found by that name'
ls -1 "$ROOT/src/29_nearing2022_da_ar/hpc/" 2>/dev/null | grep -i warm || true
echo "=== CANDIDATE LOGS ==="
find "$ROOT/logs" -name '*219423*' -newermt '2026-09-03' 2>/dev/null | head -20 || true
echo "=== ERR TAILS ==="
for F in $(find "$ROOT" -maxdepth 4 -name '*219423*' 2>/dev/null | head -10); do
  echo "--- $F"; tail -40 "$F" 2>/dev/null || true
done
exit 0
