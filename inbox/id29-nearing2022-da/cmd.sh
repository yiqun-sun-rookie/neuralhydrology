set -o pipefail
ROOT=/data1/home/sunyiq/nearing2022_da
cd "$ROOT"
for J in 219423_0 219423_1 220487; do
  echo "===== $J ====="
  for F in $(sacct -j "$J" -X -n -P --format=JobID 2>/dev/null); do :; done
  SO=$(scontrol show job "$J" 2>/dev/null | tr ' ' '\n' | sed -n 's/^StdErr=//p' | head -1)
  echo "  scontrol stderr: ${SO:-unavailable}"
done
echo "===== candidate log files ====="
find "$ROOT/logs" "$ROOT" -maxdepth 3 -name '*219423*' -o -maxdepth 3 -name '*220487*' 2>/dev/null | head -40 || true
