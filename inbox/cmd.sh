#!/bin/bash
# seq=7 — 按 HPC_AGENT_GUIDE.md 的标准流程实跑一遍，验证手册准确性。
# 顺带补齐手册第 4 节里还没实测的几个事实。全部只读。

echo "=== A GUIDE CLAIM: paths exist ==="
for p in ~/neuralhydrology ~/hpc_mailbox ~/hpc_mailbox/inbox/node_test.slurm; do
    [ -e "$p" ] && echo "OK   $p" || echo "MISS $p"
done

echo; echo "=== B GUIDE CLAIM: git 1.8.3.1 syntax limits ==="
echo -n "git version: "; git --version
echo -n "git -C     : "; git -C ~/neuralhydrology status >/dev/null 2>&1 && echo "SUPPORTED(unexpected)" || echo "NOT SUPPORTED (as documented)"
echo -n "--show-current: "; git rev-parse --abbrev-ref HEAD >/dev/null 2>&1 && \
    (cd ~/neuralhydrology && git branch --show-current >/dev/null 2>&1 && echo "SUPPORTED(unexpected)" || echo "NOT SUPPORTED (as documented)")

echo; echo "=== C GUIDE CLAIM: remote is SSH ==="
cd ~/neuralhydrology && git remote -v | head -2

echo; echo "=== D GUIDE CLAIM: network ==="
echo -n "github:22   "; timeout 8 bash -c '</dev/tcp/20.205.243.166/22' 2>/dev/null && echo OK || echo FAIL
echo -n "github:443  "; timeout 8 bash -c '</dev/tcp/20.205.243.166/443' 2>/dev/null && echo OK || echo FAIL
echo -n "pypi:443    "; timeout 8 bash -c '</dev/tcp/151.101.128.223/443' 2>/dev/null && echo OK || echo FAIL

echo; echo "=== E GUIDE CLAIM: nh_final content ==="
source /data1/home/$USER/miniconda3/etc/profile.d/conda.sh 2>/dev/null
conda activate nh_final 2>/dev/null && \
  python -c "import sys,torch;print('python',sys.version.split()[0],'| torch',torch.__version__)" 2>&1

echo; echo "=== F 531 RESULTS (real user question) ==="
R=~/neuralhydrology/results/10_global_conceptual_model_benchmark
if [ -d "$R" ]; then
    ls "$R" 2>&1 | head -6
    echo "--- repro_v01 summary ---"
    ls -la "$R/camels_us_531_repro_v01/summary/" 2>&1 | head -12
else
    echo "results dir not found: $R"
fi

echo; echo "=== G RUNNER HEALTH ==="
pgrep -af "bash runner.sh" || echo "NO RUNNER (impossible if you are reading this)"
echo "uptime: $(uptime | sed 's/.*up //;s/,.*users.*//')"

echo; echo "=== H DISK ==="
df -h "$HOME" 2>&1 | tail -1
