set -o pipefail
ROOT=/data1/home/sunyiq/nearing2022_da
for J in 219423_0 219423_1 220487; do
  echo "=== $J ==="
  SO=$(sacct -j "$J" -X -n -P --format=JobName 2>/dev/null | head -1)
  echo "  name=$SO"
done
echo "=== LOG FILES (logs dir, N22 recent) ==="
ls -1t $ROOT/logs/*.err 2>/dev/null | head -20 || true
ls -1t $ROOT/logs/**/*.err 2>/dev/null | head -20 || true
find $ROOT/logs -name '*21942*' -o -name '*22048*' 2>/dev/null | head -20 || true
find $ROOT -maxdepth 3 -name 'slurm-21942*' -o -maxdepth 3 -name 'slurm-22048*' 2>/dev/null | head -20 || true
echo "=== TAILS ==="
for F in $(find $ROOT -maxdepth 4 \( -name '*21942*' -o -name '*22048*' \) -type f 2>/dev/null | head -8); do
  echo "--- $F"; tail -30 "$F" 2>/dev/null || true
done
exit 0
