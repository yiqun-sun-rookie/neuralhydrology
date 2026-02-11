# HPC Deployment Guide

This directory contains all scripts for deploying NeuralHydrology to Hohai University HPC.

## 文件结构

| 文件 | 用途 |
|------|------|
| **核心脚本** ||
| `submit.sh` | 智能作业提交脚本（自动管理日志目录） |
| `logs.sh` | 日志管理脚本（查看、清理日志） |
| **训练作业** ||
| `submit_caravan.slurm` | Caravan 全球日模型训练 |
| `submit_mamba_camels_us.slurm` | Mamba CAMELS-US 全量训练 (531 basins) |
| `submit_mamba_quick.slurm` | Mamba CAMELS-US 快速验证 (100 basins) |
| **配置文件** ||
| `caravan_hpc.yml` | Caravan HPC 优化配置 |
| **环境设置** ||
| `setup_hpc_env.sh` | Conda 环境初始化 |
| `install_mamba_ssm.sh` | 安装 Mamba CUDA kernel |
| `download_caravan.sh` | 下载 Caravan 数据集 |

## 快速开始

### 1. 提交作业（推荐方式）

使用智能提交脚本，自动创建按任务分类的日志目录：

```bash
cd ~/neuralhydrology

# 查看可用任务
./hpc/submit.sh

# 提交作业
./hpc/submit.sh caravan              # Caravan 训练
./hpc/submit.sh mamba_quick          # Mamba 快速验证
./hpc/submit.sh mamba_camels_us      # Mamba 全量训练

# 自定义脚本
./hpc/submit.sh my_task hpc/custom.slurm
```

### 2. 日志管理

日志自动按任务分类存放：

```
logs/
├── caravan/
│   ├── 12345.out
│   └── 12345.err
├── mamba_quick/
│   └── ...
└── mamba_camels_us/
    └── ...
```

使用日志管理脚本：

```bash
# 查看所有任务日志概览
./hpc/logs.sh

# 查看指定任务的日志列表
./hpc/logs.sh caravan

# 查看指定作业的详细日志
./hpc/logs.sh caravan 12345

# 实时查看最新日志
./hpc/logs.sh tail mamba_quick

# 清理旧日志（保留最近 5 个）
./hpc/logs.sh clean caravan
./hpc/logs.sh clean all
```

### 3. 直接提交作业

也可以直接使用 sbatch：

```bash
sbatch hpc/submit_caravan.slurm
sbatch hpc/submit_mamba_quick.slurm
sbatch hpc/submit_mamba_camels_us.slurm
```

## 监控作业

```bash
# 查看队列状态
squeue -u $USER

# 实时日志
./hpc/logs.sh tail <task>
# 或
tail -f logs/<task>/<job_id>.out

# 取消作业
scancel <job_id>
```

## 环境配置

### 首次登录

```bash
ssh sunyiq@hpcbh.hhu.edu.cn
bash hpc/setup_hpc_env.sh
```

### 安装 Mamba CUDA Kernel（加速 10-50 倍）

```bash
module load cuda/11.8  # 根据 HPC 调整版本
conda activate nh_clean
bash hpc/install_mamba_ssm.sh
```

## 数据上传

### 本地 PowerShell:
```powershell
cd G:\github\pycharm\projects\neuralhydrology\data
tar -czvf Caravan.tar.gz Caravan/
scp Caravan.tar.gz sunyiq@hpcbh.hhu.edu.cn:/data1/home/sunyiq/data/
```

### HPC 端:
```bash
cd ~/data
tar -xzvf Caravan.tar.gz
rm Caravan.tar.gz
```

## 注意事项

1. **不要在登录节点运行计算任务** - 使用 `sbatch` 提交
2. **内存需求**: Caravan (~128GB), CAMELS-US 531 (~64GB)
3. **环境变量**: 可通过 `CONDA_ENV` 指定 conda 环境
   ```bash
   CONDA_ENV=my_env ./hpc/submit.sh caravan
   ```

## 技术支持

- Email: hpc@hhu.edu.cn
- Phone: 025-83787629
