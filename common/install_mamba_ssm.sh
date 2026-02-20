#!/bin/bash
# 在 HPC 上安装 mamba-ssm CUDA kernel（加速训练 10-50 倍）
# 使用方法: bash common/install_mamba_ssm.sh

set -e

echo "=========================================="
echo "Installing mamba-ssm CUDA kernel"
echo "This will significantly speed up Mamba training"
echo "=========================================="

# 1. Check CUDA availability
echo "[1/5] Checking CUDA..."
if ! command -v nvcc &> /dev/null; then
    echo "[ERROR] nvcc not found. Please load CUDA module first:"
    echo "  module load cuda/11.8  # or your CUDA version"
    exit 1
fi

nvcc --version
echo "[OK] CUDA found"

# 2. Check Python environment
echo "[2/5] Checking Python environment..."
if ! command -v python &> /dev/null; then
    echo "[ERROR] Python not found"
    exit 1
fi

python --version
echo "[OK] Python found"

# 3. Install causal-conv1d (dependency)
echo "[3/5] Installing causal-conv1d..."
pip install causal-conv1d>=1.1.0 || {
    echo "[WARNING] Failed to install causal-conv1d via pip, trying from source..."
    # If pip install fails, try building from source
    git clone https://github.com/Dao-AILab/causal-conv1d.git /tmp/causal-conv1d
    cd /tmp/causal-conv1d
    pip install .
    cd -
}

# 4. Install mamba-ssm
echo "[4/5] Installing mamba-ssm..."
echo "This may take 10-30 minutes as it needs to compile CUDA kernels..."

# Try pip install first
pip install mamba-ssm || {
    echo "[INFO] pip install failed, trying from source..."
    
    # Clone repository
    if [ ! -d "/tmp/mamba-ssm" ]; then
        git clone https://github.com/state-spaces/mamba.git /tmp/mamba-ssm
    fi
    
    cd /tmp/mamba-ssm
    
    # Install
    pip install -e . || {
        echo "[ERROR] Failed to install mamba-ssm from source"
        echo "You may need to check CUDA compatibility and compilation environment"
        exit 1
    }
    
    cd -
}

# 5. Verify installation
echo "[5/5] Verifying installation..."
python -c "
try:
    from mamba_ssm import Mamba
    print('[SUCCESS] mamba_ssm installed successfully!')
    print('[INFO] You can now use the fast CUDA kernel backend')
except ImportError as e:
    print(f'[ERROR] Import failed: {e}')
    exit(1)
"

echo "=========================================="
echo "Installation completed!"
echo "Mamba training should now be 10-50x faster"
echo "=========================================="
