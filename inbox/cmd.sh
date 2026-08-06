#!/bin/bash
# seq=1 — 首轮验证：把之前手动跑不完的八项 + 网络/环境实况一次性拿全。
# 全部只读，不提交任何作业，不改任何文件。
# 注意 HPC git=1.8.3.1，不支持 `git -C` 和 `branch --show-current`。

echo "=== 1 IDENTITY ==="
hostname; whoami; date -Iseconds

echo; echo "=== 2 SINFO SUMMARY ==="
sinfo -s 2>&1

echo; echo "=== 3 PARTITION DETAIL ==="
sinfo -o "%20P %6a %12l %6D %24N %12G" 2>&1

echo; echo "=== 4 NGU NODES (suspected bad) ==="
sinfo -N -l 2>&1 | grep -i ngu | head -12 || echo "no ngu nodes listed"

echo; echo "=== 5 OFFICIAL ALIASES ==="
type si 2>&1 | head -3
type sq 2>&1 | head -3

echo; echo "=== 6 CONDA ENVS ==="
conda env list 2>&1

echo; echo "=== 6b nh_final CONTENT ==="
if conda env list 2>/dev/null | grep -q nh_final; then
    source /data1/home/$USER/miniconda3/etc/profile.d/conda.sh 2>/dev/null
    conda activate nh_final 2>/dev/null && \
        python -c "import sys,torch;print('python',sys.version.split()[0]);print('torch',torch.__version__);print('cuda_avail',torch.cuda.is_available())" 2>&1
else
    echo "nh_final NOT FOUND"
fi

echo; echo "=== 7 REPO STATE ==="
cd ~/neuralhydrology 2>/dev/null && {
    git rev-parse --abbrev-ref HEAD 2>&1
    git log --oneline -1 2>&1
    git remote -v 2>&1
    echo "--- dirty files (count) ---"
    git status --porcelain 2>/dev/null | wc -l
} || echo "~/neuralhydrology not found"

echo; echo "=== 8 ACCOUNTING / BILLING ==="
sacct -S 2026-03-01 -X --format=JobID%10,Partition%10,AllocCPUS%5,AllocTRES%34,Elapsed%11,State%11 2>&1 | head -25

echo; echo "=== 9 MY QUEUE NOW ==="
squeue -u "$USER" 2>&1 | head -10

echo; echo "=== 10 DATA PRESENCE ==="
for d in ~/neuralhydrology/data/camels_us ~/neuralhydrology/data/CAMELS_US ~/neuralhydrology/data; do
    [ -d "$d" ] && echo "FOUND $d" && ls "$d" 2>/dev/null | head -6
done

echo; echo "=== 11 QUOTA / DISK ==="
df -h "$HOME" 2>&1 | tail -2
