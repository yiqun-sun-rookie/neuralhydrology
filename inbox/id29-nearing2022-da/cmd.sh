set -o pipefail
ROOT=/data1/home/sunyiq/nearing2022_da
for J in 219423_0 219423_1 220487; do
  echo "=== JOB $J ==="
  for F in $(sacct -j "$J" -X -n -P --format=JobID 2>/dev/null); do :; done
  SO=$(scontrol show job "$J" 2>/dev/null | tr ' ' '\n' | sed -n 's/^StdErr=//p' | head -1)
  echo "  (scontrol stderr: ${SO:-unavailable})"
done
echo "=== LOG FILES MATCHING warmpair/replv2 IN logs dir ==="
find "$ROOT/logs" -maxdepth 3 -newermt '2026-09-02' \( -name '*219423*' -o -name '*220487*' \) 2>/dev/null | head -20 || true
echo "=== TAILS ==="
for L in $(find "$ROOT/logs" -maxdepth 3 -newermt '2026-09-02' \( -name '*219423*' -o -name '*220487*' \) 2>/dev/null | head -20); do
  echo "--- $L ($(stat -c %s "$L") bytes)"
  tail -30 "$L" 2>/dev/null || true
done
echo "=== ALSO SEARCH ROOT FOR SLURM OUT ==="
find "$ROOT" -maxdepth 2 -newermt '2026-09-02' -name 'slurm-*' 2>/dev/null | head -20 || true
exit 0
