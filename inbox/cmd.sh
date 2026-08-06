#!/bin/bash
# seq=5 — 实测所谓"坏节点"。提交小作业到 ngu001/ngu002（旧文档称坏）
# 和 ngu004（对照组），每个 4 核 5 分钟上限。会消耗少量机时，用户已授权。

cd ~/hpc_mailbox || exit 1
mkdir -p outbox

echo "=== SUBMIT ==="
JOBIDS=""
for N in ngu001 ngu002 ngu004; do
    JID=$(sbatch --parsable --nodelist=$N --job-name=nt_$N inbox/node_test.slurm 2>&1)
    echo "$N -> $JID"
    JOBIDS="$JOBIDS $JID"
done

echo; echo "=== WAIT (max 6 min) ==="
for i in $(seq 1 36); do
    PENDING=$(squeue -u "$USER" -h -o "%i" 2>/dev/null | wc -l)
    echo "t=${i}0s running/pending=$PENDING"
    [ "$PENDING" -eq 0 ] && break
    sleep 10
done

echo; echo "=== SACCT ==="
for J in $JOBIDS; do
    sacct -j "$J" -X --format=JobID%10,JobName%10,NodeList%9,State%14,ExitCode%8,Elapsed%9 2>&1 | tail -2
done

echo; echo "=== OUTPUT PER NODE ==="
for J in $JOBIDS; do
    echo "----- job $J -----"
    cat "outbox/nodetest_${J}.out" 2>/dev/null || echo "(no .out)"
    if [ -s "outbox/nodetest_${J}.err" ]; then
        echo "--- stderr ---"
        head -20 "outbox/nodetest_${J}.err"
    fi
done

echo; echo "=== CLEANUP (keep results out of git) ==="
rm -f outbox/nodetest_*.out outbox/nodetest_*.err
echo done
