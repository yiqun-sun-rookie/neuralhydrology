#!/bin/bash
# a02 seq=18 : progress check after ~5h.
export LC_ALL=C
PKG=/data1/home/$USER/nature_1st_a02

echo "=== A A02 QUEUE ==="
squeue -u "$USER" -o "%.10i %.16j %.9P %.8T %.10M %.14R" 2>&1 | grep -E "a02_|JOBID"
echo "  running=$(squeue -u "$USER" -h -t R -o '%j' | grep -c '^a02_')  pending=$(squeue -u "$USER" -h -t PD -o '%j' | grep -c '^a02_')"

echo "=== B ACCOUNTING ==="
sacct -S 2026-08-07 -u "$USER" -X --format=JobID%9,JobName%13,NodeList%8,State%11,ExitCode%7,Elapsed%9 2>&1 | grep -E "a02_(pre|sam)|JobID|----" | head -18

echo "=== C TRAINING PROGRESS ==="
for f in $PKG/logs/a02_pre_s*.out $PKG/logs/a02_sam_s*.out; do
  [ -f "$f" ] || continue
  n=$(grep -c "^Epoch" "$f" 2>/dev/null)
  last=$(grep "^Epoch" "$f" 2>/dev/null | tail -1 | cut -c1-72)
  printf "  %-28s ep=%-3s %s\n" "$(basename $f .out)" "$n" "$last"
done

echo "=== C2 ANY ERRORS ==="
grep -ilE "traceback|CUDA error|out of memory|Killed" $PKG/logs/a02_*.out $PKG/logs/a02_*.err 2>/dev/null | head -8 || true
for f in $PKG/logs/a02_*.err; do
  [ -s "$f" ] || continue
  echo "  -- $(basename $f):"; tail -3 "$f" | sed 's/^/     /'
done

echo "=== D RESULT TARBALLS ==="
ls -la /data1/home/$USER/hpc_mailbox/outbox/a02_*.tar.gz 2>/dev/null | awk '{print "  ",$9,$5}' | head -14 || echo "  none yet"

echo "=== E CLUSTER ==="
squeue -u "$USER" -h -t R -O "JobID:9,Name:16,NodeList:9,TimeUsed:9,TimeLimit:10" 2>&1 | grep -v a02_ | head -6
sinfo -p hgpu2p,hgpu2,hgpu4,hgpu8 -N -h -O "NodeHost:9,StateLong:8,GresUsed:13" 2>&1 | head -12
