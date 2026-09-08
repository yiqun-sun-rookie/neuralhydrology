set -o pipefail
ROOT=/data1/home/sunyiq/nearing2022_da
date --iso-8601=seconds
for J in 219423_0 219423_1 220487; do
  echo "=== $J ==="
  for K in StdErr StdOut; do
    F=$(sacct -j "$J" -X -n -P --format=JobID 2>/dev/null | head -1)
  done
  SE=$(scontrol show job "$J" 2>/dev/null | tr ' ' '\n' | sed -n 's/^StdErr=//p' | head -1)
  echo "  scontrol StdErr=$SE"
done
echo "=== LOG FILES MATCHING (logs dir) ==="
for D in "$ROOT/logs" "$ROOT/logs/29_nearing2022_da_ar" /data1/home/sunyiq/nearing2022_da/slurm_logs; do
  [ -d "$D" ] && find "$D" -maxdepth 2 -name '*21942*' -o -maxdepth 2 -name '*22048*' 2>/dev/null | head -20
done
echo "=== GLOBAL FIND (bounded) ==="
find "$ROOT" -maxdepth 4 \( -name '*219423*' -o -name '*220487*' \) 2>/dev/null | head -20
