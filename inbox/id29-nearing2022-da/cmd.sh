set -o pipefail
ROOT=/data1/home/sunyiq/nearing2022_da
echo "=== find warmpair logs ==="
find "$ROOT" -maxdepth 4 -name '*219423*' -newermt '2026-09-01' 2>/dev/null | head -20 || true
find "$ROOT" -maxdepth 4 -name '*220487*' 2>/dev/null | head -10 || true
echo "=== tails ==="
for F in $(find "$ROOT" -maxdepth 4 \( -name '*219423*' -o -name '*220487*' \) 2>/dev/null | head -20); do
  echo "--- $F"; tail -40 "$F" 2>/dev/null || true
done
echo "=== slurm scripts present? ==="
ls -l "$ROOT/src/29_nearing2022_da_ar/hpc/" 2>/dev/null | grep -E 'warm|repl' || echo none
exit 0
