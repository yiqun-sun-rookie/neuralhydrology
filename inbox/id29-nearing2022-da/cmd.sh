#!/bin/bash
# ID29 seq=8: the slurm logs look empty (stdout buffering). Read neuralhydrology's own output.log instead.
ROOT=/data1/home/sunyiq/nearing2022_da
RES=$ROOT/results/29_nearing2022_da_ar

echo "=== A: queue ==="
squeue -u "$USER" -o "%.10i %.12j %.8T %.12M %R" 2>&1

echo "=== B: run directories created? ==="
ls -1dt $RES/*/ 2>/dev/null | head -5

echo "=== C: neuralhydrology output.log per run ==="
for d in $(ls -1dt $RES/*/ 2>/dev/null | head -2); do
  echo "---- $(basename $d)"
  if [ -f "$d/output.log" ]; then
    grep -E "Loading basin data|Calculating target|Create lookup|Epoch [0-9]+ average|Median validation|Setting|device" "$d/output.log" 2>/dev/null | tail -8
    echo "   (last line): $(tail -1 "$d/output.log" | cut -c1-140)"
    echo "   (log size): $(wc -c < "$d/output.log") bytes, mtime $(date -r "$d/output.log" +%H:%M:%S)"
  else
    echo "   no output.log yet; dir contents:"; ls "$d" | head -6
  fi
done

echo "=== D: are the processes actually burning cpu? ==="
ssh -o BatchMode=yes -o ConnectTimeout=10 ngu104 "ps -u sunyiq -o pid,etime,time,%cpu,%mem,cmd --sort=-time | grep -E 'nh_run|PID' | head -5" 2>&1 | tail -5

echo "=== E: slurm log sizes (confirm buffering vs nothing) ==="
ls -la $ROOT/logs/ 2>/dev/null | tail -6
