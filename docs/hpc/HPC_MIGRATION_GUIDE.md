# NeuralHydrology HPC Migration Guide (Ultimate Edition)

这份文档记录了将 NeuralHydrology 项目完整迁移至高性能计算集群（HPC）的最佳实践。特别针对 **老旧 Linux 系统 (CentOS 7 / GLIBC 2.17)** 和 **严格防火墙/动态OTP** 环境进行了适配。

## 1. 核心挑战与解决方案

在本次迁移中，我们解决了以下致命问题：

| 问题现象 | 原因分析 | **最终解决方案** |
| :--- | :--- | :--- |
| `ImportError: /lib64/libm.so.6: version 'GLIBC_2.27' not found` | HPC 系统太老 (CentOS 7)，不支持标准 pip 安装的 PyTorch | **使用 Conda 官方源安装 PyTorch 2.4** (自带兼容库)，严禁使用 `pip install torch`。 |
| `sbatch` 提交后无数次秒退 (ExitCode 127) | Windows 本地编辑脚本导致换行符 (`CRLF`) 问题 | 必须运行 `sed -i 's/\r$//' script.slurm` 修复格式。 |
| 频繁断网/必须重新输入 OTP | 校园网防火墙策略严格 | 使用 `tmux` 保持会话；使用 **WinSCP 自动同步**替代 SFTP 插件。 |
| `pandas` 安装失败 (GCC error) | HPC 的 GCC 编译器版本过低 (4.8.5) | 使用 `conda install pandas -c conda-forge` 安装预编译包，**不要由 pip 编译**。 |
| 找不到 `nh_run.py` 模块 | 复杂的目录嵌套结构 | 使用 `python -m neuralhydrology.nh_run` 模块化调用，并设置 `PYTHONPATH`。 |

---

## 2. 环境配置 (The "Golden" Environment)

经过验证，唯一稳定可用的环境配置命名为 **`nh_final`**。请严格按照以下步骤创建，**不要随意修改安装顺序**。

### 步骤 2.1：克隆/创建基础环境
我们发现官方 Conda 频道的 PyTorch 2.4.0 对老系统有极好的兼容性。

```bash
# 方案 A: 如果集群上有现成的 knet_clean 环境 (推荐)
conda create --name nh_final --clone knet_clean

# 方案 B: 从头创建 (如果之前的环境不可用)
conda create -n nh_final python=3.11 -y
conda activate nh_final
# 关键：只从 pytorch 和 nvidia 频道安装，严禁使用 pip
conda install pytorch==2.4.0 torchvision==0.19.0 torchaudio==2.4.0 pytorch-cuda=12.1 -c pytorch -c nvidia -y
```

### 步骤 2.2：补全科学计算库
**注意**：在老机器上，核心计算库必须用 Conda 装，否则 pip 会试图编译源码导致失败。

```bash
conda activate nh_final
conda install pandas numpy matplotlib scipy pyyaml scikit-learn h5py tqdm -c conda-forge -y
```

### 步骤 2.3：安装项目代码
```bash
cd ~/neuralhydrology  # 进入项目根目录
pip install -e .      # 以开发模式安装项目
```

---

## 3. 标准化作业提交脚本

不要再手动修改脚本，请使用这个模板。它解决了路径、环境激活和文件格式的所有潜在问题。

**保存为：** `src/caravan_global/hpc/submit_caravan.slurm`

```bash
#!/usr/bin/env bash
#SBATCH -J nh_caravan
#SBATCH -p hgpu8                   # 根据实际可用分区修改 (推荐 mix 状态的分区)
#SBATCH --gres=gpu:1
#SBATCH --cpus-per-task=8
#SBATCH -t 72:00:00                # 72小时通常是安全上限
#SBATCH -o logs/slurm-%j.out
#SBATCH -e logs/slurm-%j.err

set -eo pipefail

echo "[INFO] Job started on $(hostname) at $(date)"

# 1. 激活环境 (兼容多种 Miniconda 路径)
source /data1/home/sunyiq/miniconda3/etc/profile.d/conda.sh || source $HOME/miniconda3/etc/profile.d/conda.sh || source $HOME/anaconda3/etc/profile.d/conda.sh
conda activate nh_final || { echo "[ERROR] Failed to activate nh_final"; exit 1; }

# 2. 准备目录
cd ${SLURM_SUBMIT_DIR}
mkdir -p logs
mkdir -p runs

echo "[INFO] Python: $(which python)"
# 简单验证环境
python -c "import torch; print(f'Torch: {torch.__version__}, Device: {torch.cuda.get_device_name(0) if torch.cuda.is_available() else None}')"

# 3. 运行训练 (关键：使用 -m 模块调用方式)
export PYTHONPATH=$(pwd):$PYTHONPATH
# 注意：不要用 python neuralhydrology/nh_run.py，这会导致模块引用错误
srun python -m neuralhydrology.nh_run train --config src/caravan_global/configs/caravan_hpc.yml

echo "[INFO] Job finished at $(date)"
```

---

## 4. 推荐工作流 (Best Practices)

为了避免断网和文件由于，推荐使用 **"本地编辑 + 自动同步 + 远程托管"** 的模式。

1.  **代码编辑**：在本地 (Windows) 使用 VS Code / PyCharm 编辑代码和 Config 文件。
2.  **文件同步**：使用 **WinSCP** 打开 "Keep remote directory up to date" (Ctrl+U)。
    *   *优势*：修改本地文件，自动上传，且 WinSCP 会维持心跳防断线。
3.  **任务管理**：
    *   登录 Xshell。
    *   输入 `tmux` 进入虚拟会话 (防断网神器)。
    *   **每次提交前必做**：`sed -i 's/\r$//' src/caravan_global/hpc/submit_caravan.slurm` (修复 Windows 换行符)。
    *   提交：`sbatch src/caravan_global/hpc/submit_caravan.slurm`。
4.  **监控**：
    *   看状态：`squeue -u <user_name>`
    *   看日志：`tail -f logs/slurm-XXXXXX.out`

---

## 5. 常见报错速查

*   **GLIBC_2.27 not found**: 环境里混入了 pip 安装的包，或者使用了此时不兼容的 pytorch-cuda 包。**解决**：重做环境，严格遵循 conda 优先原则。
*   **Job 状态一直 PD**: 资源满了，使用 `sinfo` 找一个状态为 `mix` 的分区（如 hgpu8）。
*   **No module named 'pandas'**: 在 HPC 上 pip install pandas 失败。**解决**：`conda install pandas`。
*   **sbatch 提交后无日志且直接消失**: 脚本里有 Windows 换行符。**解决**：使用 `sed` 或 `dos2unix` 修复。

---
*Document created on 2026-01-24 based on successful deployment experience.*

