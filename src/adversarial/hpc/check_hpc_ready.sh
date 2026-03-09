#!/bin/bash
# HPC 环境检查脚本 — 在 HPC 上运行，确认对抗实验所有依赖就位
# 用法: ssh sunyiq@hpcbh.hhu.edu.cn "bash -s" < src/adversarial/hpc/check_hpc_ready.sh

echo "=== 1. CAMELS_US 数据 ==="
for CANDIDATE in \
    ~/neuralhydrology/data/CAMELS_US \
    ~/data/CAMELS_US \
    /data1/home/sunyiq/neuralhydrology/data/CAMELS_US \
    /data1/home/sunyiq/data/CAMELS_US; do
    if [ -d "$CANDIDATE" ]; then
        echo "  FOUND: $CANDIDATE"
        ls "$CANDIDATE/" 2>/dev/null | head -5
        # Check for daymet forcing
        DAYMET=$(find "$CANDIDATE" -name "*daymet*" -type d 2>/dev/null | head -1)
        if [ -n "$DAYMET" ]; then
            echo "  daymet forcing dir: $DAYMET"
            ls "$DAYMET/" 2>/dev/null | head -3
        else
            echo "  WARNING: no daymet forcing found"
        fi
        echo "  Basin count: $(find "$CANDIDATE" -name "*.txt" -path "*/streamflow*" 2>/dev/null | wc -l)"
        break
    fi
done
echo ""

echo "=== 2. 模型权重 ==="
MODEL_DIR=~/neuralhydrology/results/05_full_531_basins/full_training_nse_2025_1025_1821_ep50
if [ -d "$MODEL_DIR" ]; then
    echo "  FOUND: $MODEL_DIR"
    ls -lh "$MODEL_DIR"/model_epoch050.pt "$MODEL_DIR"/config.yml "$MODEL_DIR"/train_data/train_data_scaler.yml 2>/dev/null
else
    echo "  NOT FOUND: $MODEL_DIR"
    # Check backup
    BACKUP=~/neuralhydrology_backup_20260304
    if [ -d "$BACKUP" ]; then
        echo "  Checking backup: $BACKUP"
        find "$BACKUP" -name "model_epoch050.pt" 2>/dev/null | head -3
    fi
fi
echo ""

echo "=== 3. Conda 环境 ==="
source /data1/home/sunyiq/miniconda3/etc/profile.d/conda.sh 2>/dev/null
conda activate nh_final 2>/dev/null
if [ $? -eq 0 ]; then
    echo "  nh_final activated OK"
    python -c "import torch; print(f'  PyTorch {torch.__version__}, CUDA: {torch.cuda.is_available()}')" 2>/dev/null
    python -c "import neuralhydrology; print(f'  neuralhydrology OK')" 2>/dev/null
    python -c "import yaml, scipy, numpy; print('  yaml/scipy/numpy OK')" 2>/dev/null
else
    echo "  FAILED to activate nh_final"
fi
echo ""

echo "=== 4. Git 状态 ==="
cd ~/neuralhydrology 2>/dev/null
if [ $? -eq 0 ]; then
    echo "  Branch: $(git branch --show-current 2>/dev/null)"
    echo "  Latest: $(git log --oneline -1 2>/dev/null)"
    echo "  Remote: $(git remote get-url origin 2>/dev/null)"
else
    echo "  ~/neuralhydrology not found"
fi
echo ""

echo "=== 5. GPU 状态 ==="
nvidia-smi --query-gpu=name,memory.total --format=csv,noheader 2>/dev/null || echo "  nvidia-smi not available (run on compute node)"
echo ""

echo "=== 6. src/adversarial 代码 ==="
if [ -d ~/neuralhydrology/src/adversarial ]; then
    echo "  FOUND"
    ls ~/neuralhydrology/src/adversarial/scripts/ 2>/dev/null
    ls ~/neuralhydrology/src/adversarial/configs/ 2>/dev/null
    ls ~/neuralhydrology/src/adversarial/data/ 2>/dev/null
else
    echo "  NOT FOUND — need git pull"
fi
echo ""

echo "=== Done ==="
