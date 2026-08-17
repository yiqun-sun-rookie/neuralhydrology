#!/bin/bash
# probe seq=8 — 核实第二条公告：CPU 平台是否已升级 Rocky 9.5？端口是否已改？
cd ~/hpc_mailbox || exit 1

echo "=== 1. WHAT OS IS THIS LOGIN NODE RIGHT NOW ==="
cat /etc/redhat-release 2>/dev/null || cat /etc/os-release 2>/dev/null | head -3
echo "kernel: $(uname -r)"
echo "glibc:  $(ldd --version 2>&1 | head -1)"
echo "date:   $(date -Iseconds)"
echo "uptime: $(uptime -p 2>/dev/null || uptime)"

echo; echo "=== 2. DOES /data0/software EXIST (the announced new paths)? ==="
for d in /data0/software /data0/software/Intel /data0/software/AMD /data0/software/rocky9.5; do
    if [ -d "$d" ]; then echo "  EXISTS  $d"; ls "$d" 2>/dev/null | head -5 | sed 's/^/            /'
    else echo "  MISSING $d"; fi
done

echo; echo "=== 3. SSHD PORT ON THIS HOST ==="
grep -E "^Port|^#Port" /etc/ssh/sshd_config 2>/dev/null | sed 's/^/  /' || echo "  (cannot read sshd_config)"
ss -tlnp 2>/dev/null | grep -E ":22 |:8262 " | sed 's/^/  /' || netstat -tln 2>/dev/null | grep -E ":22 |:8262 " | sed 's/^/  /' || echo "  (cannot list ports)"

echo; echo "=== 4. COMPUTE NODE OS — are icn (CPU) nodes already on Rocky 9? ==="
sinfo -o "%12P %10T %6D %30N" 2>&1 | head -12
echo "  --- try to read OS reported by slurm per node ---"
for N in icn201 icn202 ngu001 ngu201; do
    O=$(scontrol show node $N 2>/dev/null | grep -o "OS=[^=]*" | head -1)
    S=$(scontrol show node $N 2>/dev/null | tr ' ' '\n' | grep "^State=" | head -1)
    printf "  %-8s %-12s %s\n" "$N" "${S:-?}" "${O:-?}"
done

echo; echo "=== 5. SLURM VERSION (a Rocky 9 rebuild would likely bump it) ==="
scontrol show config 2>/dev/null | grep -E "SLURM_VERSION" | sed 's/^/  /'
sinfo --version 2>&1 | sed 's/^/  /'

echo; echo "=== 6. IS MY ENV STILL FUNCTIONAL RIGHT NOW ==="
/data1/home/$USER/miniconda3/envs/nh_final/bin/python -c "import torch;print('  torch',torch.__version__,'ok')" 2>&1 | tail -2
