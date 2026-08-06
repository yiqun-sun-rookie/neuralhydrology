#!/bin/bash
# probe seq=7 — 停机公告应对：确认节点校区归属 + 现有环境的升级风险
cd ~/hpc_mailbox || exit 1

echo "=== 1. WHICH CAMPUS ARE THE COMPUTE NODES? (IP tells the campus) ==="
echo "  江宁 = 11.11.1.x / 11.11.4.x ; 常州 = 11.11.6.x  (per the official manual)"
for N in ngu001 ngu201 ngu101 icn201; do
    A=$(scontrol show node $N 2>/dev/null | tr ' ' '\n' | grep "^NodeAddr=" | cut -d= -f2)
    R=$(getent hosts "$A" 2>/dev/null | awk '{print $1}')
    printf "  %-8s NodeAddr=%-14s resolved=%s\n" "$N" "${A:-?}" "${R:-n/a}"
done
echo "  --- login node I am on ---"
hostname; hostname -i 2>/dev/null; ip -4 addr 2>/dev/null | grep -o "inet 11\.11\.[0-9.]*" | head -3

echo "  --- slurm controller ---"
scontrol show config 2>/dev/null | grep -E "^SlurmctldHost" | sed 's/^/  /'

echo; echo "=== 2. CURRENT OS / GLIBC / TOOLCHAIN (baseline before upgrade) ==="
cat /etc/redhat-release 2>/dev/null
ldd --version 2>&1 | head -1
echo "bash $BASH_VERSION"
git --version
python3 --version 2>&1

echo; echo "=== 3. nh_final BINARY LINKAGE RISK ==="
P=/data1/home/$USER/miniconda3/envs/nh_final/bin/python
$P -c "import sys,torch;print('  python',sys.version.split()[0],'torch',torch.__version__)" 2>&1
echo "  --- torch links against which glibc symbols ---"
TL=$($P -c "import torch,os;print(os.path.dirname(torch.__file__))" 2>/dev/null)
if [ -n "$TL" ] && [ -f "$TL/lib/libtorch_cpu.so" ]; then
    objdump -T "$TL/lib/libtorch_cpu.so" 2>/dev/null | grep -o "GLIBC_[0-9.]*" | sort -uV | tail -3 | sed 's/^/    /'
else
    echo "    (libtorch_cpu.so not found, skipping)"
fi
echo "  conda env size: $(du -sh /data1/home/$USER/miniconda3/envs/nh_final 2>/dev/null | cut -f1)"

echo; echo "=== 4. ANYTHING OF MINE STILL QUEUED/RUNNING? ==="
squeue -u "$USER" 2>&1
echo "  (must be empty before 2026-08-11 noon)"

echo; echo "=== 5. WHAT WOULD I LOSE? results/ size on HPC ==="
du -sh ~/neuralhydrology/results 2>/dev/null
du -sh ~/adv531 2>/dev/null
echo "  --- uncommitted work in the repo ---"
cd ~/neuralhydrology && git status --porcelain 2>/dev/null | wc -l
