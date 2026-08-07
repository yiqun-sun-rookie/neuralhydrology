#!/bin/bash
# a02 seq=10 : progress probe -- how many started, any early failures, GPU contention.
export LC_ALL=C
PKG=/data1/home/$USER/nature_1st_a02

echo "=== A A02 QUEUE ==="
squeue -u "$USER" -o "%.10i %.18j %.8T %.10M %.20R" 2>&1 | grep -E "a02_|JOBID"
echo "  running: $(squeue -u "$USER" -h -t R -o '%j' 2>/dev/null | grep -c '^a02_')  pending: $(squeue -u "$USER" -h -t PD -o '%j' 2>/dev/null | grep -c '^a02_')"

echo "=== B OTHER JOBS (contention, not touched) ==="
squeue -u "$USER" -h -o "%.10i %.18j %.8T" 2>&1 | grep -v "^ *[0-9]* *a02_" | head -8

echo "=== C ANY A02 FINISHED OR FAILED YET ==="
sacct -S today -u "$USER" -X --name=a02_pre_s42,a02_sam_s42,a02_pre_s43,a02_sam_s43,a02_pre_s44,a02_sam_s44,a02_pre_s45,a02_sam_s45,a02_pre_s46,a02_sam_s46,a02_pre_s47,a02_sam_s47 \
  --format=JobID%9,JobName%13,NodeList%9,State%11,ExitCode%7,Elapsed%9 2>&1 | head -18

echo "=== D TRAINING PROGRESS (epoch lines per run) ==="
for f in $PKG/logs/a02_*.out; do
  [ -f "$f" ] || continue
  n=$(grep -c "^Epoch" "$f" 2>/dev/null)
  last=$(grep "^Epoch" "$f" 2>/dev/null | tail -1 | cut -c1-72)
  printf "  %-34s epochs=%-3s %s\n" "$(basename $f)" "$n" "$last"
done

echo "=== E RESULT TARBALLS SO FAR ==="
ls -la /data1/home/$USER/hpc_mailbox/outbox/a02_*.tar.gz 2>/dev/null | head -14 || echo "  none yet"

echo "=== F GPU NODES ==="
sinfo -p hgpu2p -o "  %12P %6D %26N %8t" 2>&1 | head -5
