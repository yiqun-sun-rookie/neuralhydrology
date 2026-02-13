# Mamba CAMELS-US HPC 运行指南

本指南说明如何在 HPC 上运行 Mamba CAMELS-US 日尺度实验。

## 📋 前置条件

1. **HPC 环境**: Linux 系统，支持 CUDA
2. **Conda 环境**: 已安装 `neuralhydrology_gpu` 环境
3. **数据准备**: CAMELS-US 数据已下载到 HPC

## 🚀 快速开始

### 步骤 1: 安装 mamba-ssm（强烈推荐）

mamba-ssm 的 CUDA kernel 可以加速训练 **10-50 倍**！

```bash
# 加载 CUDA 模块（根据你的 HPC 调整）
module load cuda/11.8

# 激活环境
conda activate neuralhydrology_gpu

# 运行安装脚本
bash hpc/install_mamba_ssm.sh
```

**注意**: 安装过程可能需要 10-30 分钟（需要编译 CUDA kernel）

### 步骤 2: 提交快速验证作业（推荐）

先运行快速验证，确认一切正常：

```bash
sbatch src/mamba_camels_us/hpc/submit_mamba_quick.slurm
```

**预计时间**: 1-2 天（100 流域，5 epochs）

### 步骤 3: 提交全量训练作业

快速验证成功后，提交全量训练：

```bash
sbatch src/mamba_camels_us/hpc/submit_mamba_camels_us.slurm
```

**预计时间**: 
- 使用 mamba-ssm: 约 7-10 天（30 epochs）
- 使用 Hugging Face: 约 120+ 天（不推荐）

## 📊 监控作业

```bash
# 查看作业状态
squeue -u $USER

# 查看实时日志
tail -f logs/mamba_camels_us_<job_id>.out

# 查看错误日志
tail -f logs/mamba_camels_us_<job_id>.err

# 取消作业
scancel <job_id>
```

## 🔍 验证安装

检查 mamba-ssm 是否安装成功：

```bash
python -c "
try:
    from mamba_ssm import Mamba
    print('✅ mamba_ssm (fast CUDA kernel) is available!')
except ImportError:
    print('⚠️  mamba_ssm not found, will use Hugging Face (slower)')
    from transformers import MambaModel
    print('✅ Hugging Face transformers backend available')
"
```

## ⚙️ 自定义配置

### 修改 SLURM 参数

编辑 `src/mamba_camels_us/hpc/submit_mamba_camels_us.slurm`:

```bash
#SBATCH -p hgpu8          # 修改为你的 GPU 分区
#SBATCH --gres=gpu:1      # GPU 数量
#SBATCH --mem=64G         # 内存大小
#SBATCH -t 168:00:00      # 时间限制
```

### 修改 Conda 环境路径

如果 conda 路径不同，修改脚本中的 conda 路径：

```bash
source /your/path/to/miniconda3/etc/profile.d/conda.sh
conda activate your_env_name
```

## 📝 常见问题

### Q: 安装 mamba-ssm 失败？

**A**: 检查以下几点：
1. CUDA 模块是否已加载：`module list`
2. CUDA 版本是否兼容（建议 11.8+）
3. 编译环境是否完整（gcc, nvcc）

### Q: 训练速度还是很慢？

**A**: 
1. 确认 mamba-ssm 已安装：运行验证脚本
2. 检查 GPU 利用率：`nvidia-smi`
3. 如果仍使用 Hugging Face backend，检查日志中的警告信息

### Q: 作业被取消？

**A**: 
1. 检查时间限制是否足够（`-t` 参数）
2. 检查内存是否足够（`--mem` 参数）
3. 查看错误日志：`cat logs/mamba_camels_us_<job_id>.err`

## 📚 相关文档

- 主实验文档: `docs/experiments/MAMBA_CAMELS_US_EXPERIMENT.md`
- HPC 部署指南: `docs/technical/HPC_DEPLOYMENT_GUIDE.md`
