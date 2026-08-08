#!/bin/bash
# Read-only audit: did anything I did leave the machine worse for other work?
echo "=== 1. conda envs: did the 3 failed creates leave debris? ==="
source /data1/home/${USER}/miniconda3/etc/profile.d/conda.sh 2>/dev/null
conda env list 2>&1
echo "--- partial env dirs? ---"
ls -la ~/miniconda3/envs/ 2>&1 | tail -8
ls -la ~/.conda/envs/ 2>&1 | tail -8

echo "=== 2. is .condarc untouched? ==="
ls -l ~/.condarc 2>&1; echo "--- content ---"; cat ~/.condarc 2>&1 | head -15

echo "=== 3. nh_final still works and unchanged? ==="
conda activate nh_final 2>&1 && python -c "import numpy,pandas,pyarrow,torch;print('nh_final OK:',numpy.__version__,pandas.__version__,pyarrow.__version__,'torch',torch.__version__)" 2>&1 | tail -2

echo "=== 4. your repo untouched? (HEAD + dirty count should match the earlier probe) ==="
cd ~/neuralhydrology 2>/dev/null && git rev-parse --abbrev-ref HEAD 2>&1 && git log -1 --format="%h %s" 2>&1 && echo "dirty files: $(git status --porcelain 2>/dev/null | wc -l)  (earlier probe said 78)"

echo "=== 5. adv531 untouched? ==="
ls -ld ~/adv531 2>&1 | head -2
find ~/adv531 -maxdepth 1 -newermt "2026-08-08 14:00" 2>/dev/null | head -5
echo "(nothing listed above = nothing of mine touched it today)"

echo "=== 6. disk footprint I added ==="
du -sh ~/autoresearch64 2>&1
du -sh ~/.cache/pip 2>&1
df -h /data1 2>&1 | tail -1

echo "=== 7. queue clean? no stray jobs of mine ==="
squeue -u "$USER" -o "%.10i %.14j %.10T %.10M" 2>&1 | head -8
sacct -S 2026-08-08 -X --format=JobID%10,JobName%14,State%12,Elapsed%10 2>&1 | tail -8

echo "=== 8. mailbox runner healthy for other channels? ==="
pgrep -af "hpc_runner_active" 2>&1 | head -3
ls -1 ~/hpc_mailbox/outbox/*/ 2>/dev/null | wc -l
echo "leftover slurm logs in outbox (should be 0):"; ls ~/hpc_mailbox/outbox/slurm_* 2>/dev/null | wc -l
