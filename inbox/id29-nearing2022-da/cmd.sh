#!/bin/bash
# ID29 seq=9: runner is back. Find out (a) where the dependency job 201864 went, (b) how far training has got.
# No ssh into compute nodes, no wildcard log deletion.
ROOT=/data1/home/sunyiq/nearing2022_da
RES=$ROOT/results/29_nearing2022_da_ar

echo "=== A: full queue with reasons ==="
squeue -u "$USER" -o "%.10i %.12j %.10T %.12M %.12L %R" 2>&1

echo "=== B: what happened to the assimilation job(s) ==="
sacct -u "$USER" -X --starttime 2026-08-08T15:00 \
      --format=JobID%10,JobName%12,State%14,ExitCode%8,Elapsed%10,Submit%20,Reason%22 2>&1 | tail -15

echo "=== C: simulation 201858 progress (neuralhydrology's own log) ==="
D=$(ls -1dt $RES/nearing2022_simulation_seed0_*/ 2>/dev/null | head -1)
echo "run=$D"
if [ -n "$D" ] && [ -f "$D/output.log" ]; then
  grep -E "Epoch [0-9]+ average loss" "$D/output.log" | tail -4
  echo "  last line: $(tail -1 "$D/output.log" | cut -c1-130)"
  echo "  log mtime: $(date -r "$D/output.log" +%H:%M:%S)  size: $(wc -c < "$D/output.log")"
  ls "$D" | grep -c "model_epoch" | sed 's/^/  checkpoints saved: /'
else
  echo "  no output.log yet"; ls -la "$D" 2>/dev/null | head -8
fi

echo "=== D: autoregression 201859 progress ==="
D=$(ls -1dt $RES/nearing2022_autoregression_*/ 2>/dev/null | head -1)
echo "run=$D"
if [ -n "$D" ] && [ -f "$D/output.log" ]; then
  grep -E "Epoch [0-9]+ average loss" "$D/output.log" | tail -4
  echo "  last line: $(tail -1 "$D/output.log" | cut -c1-130)"
  echo "  log mtime: $(date -r "$D/output.log" +%H:%M:%S)"
  ls "$D" | grep -c "model_epoch" | sed 's/^/  checkpoints saved: /'
else
  echo "  no output.log yet"; ls -la "$D" 2>/dev/null | head -8
fi

echo "=== E: slurm logs ==="
ls -la "$ROOT/logs" 2>/dev/null | tail -8

echo "=== F: errors if any ==="
for f in "$ROOT"/logs/*.err; do
  n=$(grep -icE "traceback|error|out of memory" "$f" 2>/dev/null)
  echo "  $(basename $f): $n error-ish lines"
  [ "$n" -gt 0 ] && grep -iE "traceback|error|out of memory" "$f" | head -3
done
