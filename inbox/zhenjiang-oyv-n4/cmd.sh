#!/bin/bash
set -o pipefail
ROOT=/data1/home/sunyiq/zhenjiang_oyv_v1
N4=$(ls -1 "$ROOT/n4_tasks" 2>/dev/null | wc -l)
PC=$(ls -1 "$ROOT/platform_control_a800" 2>/dev/null | wc -l)
echo "PROGRESS n4=${N4}/1440 platform_control=${PC}/160"
sacct -j 213141 -X -n -P -o State 2>/dev/null | sort | uniq -c | tr '\n' ' ' | sed 's/^/CONTROL_STATES /'
echo
for j in 212932 212933; do
  echo -n "ARRAY $j "
  sacct -j "$j" -X -n -P -o State 2>/dev/null | sort | uniq -c | tr '\n' ' '
  echo
done
FAILS=$(sacct -X -n -P -S 2026-08-26 -o JobID,JobName,State 2>/dev/null | grep -E '\|(FAILED|TIMEOUT|NODE_FAIL|OUT_OF_MEMORY)' | grep -E 'zj_oyv_n4|zj_pfctl' | head -5)
[ -n "$FAILS" ] && { echo "TROUBLE:"; echo "$FAILS"; } || echo "TROUBLE none"
if [ "$PC" -ge 160 ]; then
  echo "CONTROL_COMPLETE running the cost comparison"
  cd "$ROOT/repo" || exit 1
  source /data1/home/${USER}/miniconda3/etc/profile.d/conda.sh 2>/dev/null || source $HOME/miniconda3/etc/profile.d/conda.sh
  conda activate nh_final 2>/dev/null
  export PYTHONPATH="$ROOT/pysite:${PYTHONPATH:-}"
  python -u scripts/analysis/platform_control_ladder_v1.py --mode compare \
    --reference-root "$ROOT/ladder_tasks" --scratch-root "$ROOT/platform_control_a800" 2>&1 | head -60
fi
echo "=== DONE ==="
