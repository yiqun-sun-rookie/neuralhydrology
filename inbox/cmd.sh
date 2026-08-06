#!/bin/bash
# seq=6 — 全 GPU 节点健康普查。sinfo 的 idle 不代表 CUDA 可用（ngu002 已证明），
# 只能逐个真跑。每节点约 20-40s，成本很小。

cd ~/hpc_mailbox || exit 1
mkdir -p outbox

# hgpu2p 全部 9 节点 + hgpu2 的 2 个 + hgpu8 的 3 个（ngu103 已 down，跳过）
P2P="ngu001 ngu002 ngu004 ngu005 ngu006 ngu007 ngu008 ngu010 ngu011"
P2="ngu003 ngu009"
P8="ngu201 ngu202 ngu203"
P4="ngu101 ngu102 ngu104"

echo "=== SUBMIT ==="
JOBIDS=""
submit () {  # $1=node $2=partition
    JID=$(sbatch --parsable -p "$2" --nodelist=$1 --job-name=nt_$1 \
          -t 00:04:00 inbox/node_test.slurm 2>&1)
    case "$JID" in
        [0-9]*) echo "$1 ($2) -> $JID"; JOBIDS="$JOBIDS $JID:$1" ;;
        *)      echo "$1 ($2) -> SUBMIT_REJECTED: $JID" ;;
    esac
}
for N in $P2P; do submit $N hgpu2p; done
for N in $P2;  do submit $N hgpu2;  done
for N in $P8;  do submit $N hgpu8;  done
for N in $P4;  do submit $N hgpu4;  done

echo; echo "=== WAIT (max 10 min) ==="
for i in $(seq 1 60); do
    LEFT=$(squeue -u "$USER" -h -o "%i" 2>/dev/null | wc -l)
    [ $((i % 3)) -eq 0 ] && echo "t=${i}0s left=$LEFT"
    [ "$LEFT" -eq 0 ] && break
    sleep 10
done

echo; echo "=== VERDICT TABLE ==="
printf "%-9s %-9s %-14s %-8s %-6s %s\n" NODE JOB STATE EXIT GPUS VERDICT
for JN in $JOBIDS; do
    J=${JN%%:*}; N=${JN##*:}
    ST=$(sacct -j "$J" -X -n --format=State%14 2>/dev/null | head -1 | tr -d ' ')
    EC=$(sacct -j "$J" -X -n --format=ExitCode%8 2>/dev/null | head -1 | tr -d ' ')
    F="outbox/nodetest_${J}.out"
    NG=$(grep -c "GeForce\|NVIDIA" "$F" 2>/dev/null)
    V=$(grep -o "VERDICT: .*" "$F" 2>/dev/null | head -1)
    [ -z "$V" ] && V="(no verdict)"
    printf "%-9s %-9s %-14s %-8s %-6s %s\n" "$N" "$J" "$ST" "$EC" "$NG" "$V"
done

echo; echo "=== FAILING NODES DETAIL ==="
for JN in $JOBIDS; do
    J=${JN%%:*}; N=${JN##*:}
    F="outbox/nodetest_${J}.out"
    if ! grep -q "NODE_HEALTHY" "$F" 2>/dev/null; then
        echo "----- $N (job $J) -----"
        cat "$F" 2>/dev/null | tail -18
        [ -s "outbox/nodetest_${J}.err" ] && { echo "-- stderr --"; head -8 "outbox/nodetest_${J}.err"; }
    fi
done

echo; echo "=== SINFO CROSS-CHECK (what SLURM thinks) ==="
sinfo -N -o "%12N %10P %10T %30E" 2>&1 | grep -E "NODELIST|ngu"

rm -f outbox/nodetest_*.out outbox/nodetest_*.err
echo; echo "cleanup done"
