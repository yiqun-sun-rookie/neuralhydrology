#!/bin/bash
# probe seq=6 — 确认 GPU 是否被僵尸分配占死，然后取消排到 2027 的作业
cd ~/hpc_mailbox || exit 1

echo "=== 1. GresUsed (is the GPU actually held?) ==="
for N in ngu201 ngu202 ngu203 ngu001; do
    printf "%-8s " "$N"
    scontrol show node $N 2>/dev/null | tr ' ' '\n' | grep -E "^Gres=|^GresUsed=|^CPUAlloc=|^State=" | tr '\n' ' '
    echo
done

echo; echo "=== 2. Where did zhangjw's successful jobs actually run? ==="
sacct -a -S 2026-08-06 -X -r hgpu8 --format=JobID%9,User%9,NodeList%9,State%12,Elapsed%9,AllocTRES%28 2>&1 | tail -10

echo; echo "=== 3. CANCEL the two zombie-blocked jobs ==="
scancel 201433 201435 2>&1 && echo "cancelled 201433 201435 (ETA was 2027)"

echo; echo "=== 4. FINAL: test ngu202 only (the one that works) ==="
JID=$(sbatch --parsable -p hgpu8 --nodelist=ngu202 --job-name=nt_ngu202 -t 00:04:00 inbox/node_test.slurm 2>&1)
echo "  ngu202 -> $JID"
for i in $(seq 1 30); do
    ST=$(squeue -j "$JID" -h -o "%t" 2>/dev/null); [ -z "$ST" ] && break
    sleep 10
done
sacct -j "$JID" -X --format=JobID%9,NodeList%9,State%12,ExitCode%8,Elapsed%9 2>&1 | tail -2
grep -o "VERDICT: .*" outbox/nodetest_${JID}.out 2>/dev/null || echo "(no verdict file)"
grep -c "GeForce" outbox/nodetest_${JID}.out 2>/dev/null | sed 's/^/  gpus seen: /'
rm -f outbox/nodetest_*.out outbox/nodetest_*.err

echo; echo "=== 5. MY QUEUE (should be empty) ==="
squeue -u "$USER" 2>&1
