#!/bin/bash
# probe seq=5 — 对比 hgpu8 vs hgpu2p 的 RealMemory / 僵尸分配，确认 hgpu8 是否配置损坏
cd ~/hpc_mailbox || exit 1

echo "=== 1. RealMemory / CPUAlloc / AllocTRES ACROSS ALL GPU NODES ==="
printf "%-8s %-8s %-10s %-9s %-9s %-22s %s\n" NODE STATE RealMem CPUAlloc CPUTot AllocTRES Boot
for N in ngu001 ngu002 ngu004 ngu008 ngu010 ngu003 ngu101 ngu102 ngu201 ngu202 ngu203; do
    D=$(scontrol show node $N 2>/dev/null)
    ST=$(echo "$D" | grep -o "State=[A-Z*+]*" | head -1 | cut -d= -f2)
    RM=$(echo "$D" | grep -o "RealMemory=[0-9]*" | cut -d= -f2)
    CA=$(echo "$D" | grep -o "CPUAlloc=[0-9]*" | cut -d= -f2)
    CT=$(echo "$D" | grep -o "CPUTot=[0-9]*" | cut -d= -f2)
    AT=$(echo "$D" | grep -o "AllocTRES=[^ ]*" | cut -d= -f2-)
    BT=$(echo "$D" | grep -o "BootTime=[^ ]*" | cut -d= -f2 | cut -c1-10)
    printf "%-8s %-8s %-10s %-9s %-9s %-22s %s\n" "$N" "$ST" "${RM:-?}" "${CA:-?}" "${CT:-?}" "${AT:-none}" "${BT:-?}"
done

echo; echo "=== 2. ORPHANED ALLOC? jobs actually on hgpu8 nodes ==="
echo "squeue -w ngu201,ngu202,ngu203 (all states, all users):"
squeue -w ngu201,ngu202,ngu203 -a -o "%8i %10u %8T %10M" 2>&1 | head
echo "-> if only a header shows, the CPUAlloc on those nodes has no owning job"

echo; echo "=== 3. DefMemPerCPU / DefMemPerNode ==="
for P in hgpu8 hgpu2p; do
    echo -n "  $P: "
    scontrol show partition $P 2>&1 | tr ' ' '\n' | grep -E "DefMemPerCPU|DefMemPerNode|MaxMemPerCPU|MaxMemPerNode|TRESBillingWeights" | tr '\n' ' '
    echo
done

echo; echo "=== 4. LAST SUCCESSFUL JOB ON hgpu8 (when did it last work?) ==="
sacct -a -S 2026-01-01 -X -r hgpu8 --format=JobID%10,User%10,State%12,Start%20,Elapsed%10 2>&1 | tail -12

echo; echo "=== 5. SLURM VERSION / SCHED CONFIG ==="
scontrol show config 2>/dev/null | grep -E "^SchedulerType|^SelectType |^SelectTypeParameters|^DefMemPerCPU|^SlurmctldHost|SLURM_VERSION" | sed 's/^/  /'
