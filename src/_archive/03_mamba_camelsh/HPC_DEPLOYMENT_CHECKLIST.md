# HPC 部署检查清单

本文档提供逐步检查清单，确保 HPC 部署顺利进行。

## 阶段一：数据验证

### 步骤 1.1: SSH 登录 HPC
- [ ] 成功 SSH 登录到 HPC
- [ ] 确认当前用户和主目录

### 步骤 1.2: 检查 CAMELS-H 数据
```bash
# 执行以下命令检查数据
ls -la ~/neuralhydrology/data/camelsh/
ls -la /data1/home/$USER/neuralhydrology/data/camelsh/
```

- [ ] 数据目录存在
- [ ] 至少包含 455 个流域的数据文件
- [ ] `available_basins.txt` 文件存在
- [ ] 数据文件大小合理（总大小约 50GB+）

### 步骤 1.3: 数据上传（如需要）
如果数据不存在：
- [ ] 使用 WinSCP 或 rsync 上传数据
- [ ] 验证上传完整性
- [ ] 检查文件权限

**记录数据路径**: _________________________

---

## 阶段二：文件同步

### 步骤 2.1: WinSCP 同步
- [ ] 打开 WinSCP
- [ ] 连接到 HPC
- [ ] 同步 `src/mamba_camelsh/` 目录
  - 本地: `src/mamba_camelsh/`
  - HPC: `~/neuralhydrology/src/mamba_camelsh/`

### 步骤 2.2: 验证同步完整性
在 HPC 终端执行：
```bash
cd ~/neuralhydrology
ls -R src/mamba_camelsh/
```

- [ ] `configs/` 目录存在（4 个 YAML 文件，含 LSTM mini baseline）
- [ ] `hpc/` 目录存在（4 个 SLURM 脚本）
- [ ] `data/test_50_basins.txt` 存在
- [ ] `README.md` 存在

---

## 阶段三：环境检查与修复

### 步骤 3.1: 修复 Windows 换行符
```bash
cd ~/neuralhydrology
sed -i 's/\r$//' src/mamba_camelsh/hpc/*.slurm
```

- [ ] 命令执行成功
- [ ] 无错误信息

### 步骤 3.2: 创建日志目录
```bash
mkdir -p logs/03_mamba_camelsh results/03_mamba_camelsh
```

- [ ] 目录创建成功
- [ ] 验证目录存在：`ls -d logs/03_mamba_camelsh results/03_mamba_camelsh`

### 步骤 3.3: 验证 Conda 环境
```bash
conda activate nh_final
python --version
python -c "import torch; print(torch.cuda.is_available())"
```

- [ ] Conda 环境激活成功
- [ ] Python 版本正确
- [ ] CUDA 可用（输出 True）

### 步骤 3.4: 检查 Mamba 后端
```bash
python -c "
try:
    from transformers import MambaModel
    print('✓ transformers backend available')
except ImportError:
    print('✗ transformers not available')
    exit(1)
"
```

- [ ] transformers 后端可用
- [ ] 如果不可用，需要安装：`pip install transformers>=4.39`

---

## 阶段四：可选加速安装

### 步骤 4.1: 安装 mamba-ssm（强烈推荐）
```bash
# 加载 CUDA 模块（根据 HPC 调整版本）
module load cuda/11.8

# 运行安装脚本
bash hpc/install_mamba_ssm.sh
```

- [ ] CUDA 模块加载成功
- [ ] 安装脚本执行成功
- [ ] 验证安装：
  ```bash
  python -c "from mamba_ssm import Mamba; print('✓ mamba_ssm installed')"
  ```

**预期效果**: 训练速度提升 10-50 倍

---

## 阶段五：提交作业

### 步骤 5.1: Mini Benchmark
```bash
/usr/local/globle/softs/slurm/19.05.4.1/bin/sbatch src/mamba_camelsh/hpc/submit_mini.slurm
```

- [ ] 作业提交成功
- [ ] 记录作业 ID: _________________________
- [ ] 检查作业状态：`squeue -u $USER`

### 步骤 5.2: 监控作业
```bash
# 查看实时日志（替换 JOBID）
tail -f logs/03_mamba_camelsh/<JOBID>.out
```

- [ ] 日志正常输出
- [ ] 无错误信息
- [ ] 训练正常进行

### 步骤 5.3: 后续作业（Mini 成功后）
- [ ] Full Training: `/usr/local/globle/softs/slurm/19.05.4.1/bin/sbatch src/mamba_camelsh/hpc/submit_full.slurm`
- [ ] Long Sequence: `/usr/local/globle/softs/slurm/19.05.4.1/bin/sbatch src/mamba_camelsh/hpc/submit_longseq.slurm`

---

## 常见问题检查

### 问题 1: 作业秒挂（无日志）
- [ ] 已执行 `sed -i 's/\r$//'` 修复换行符
- [ ] 日志目录已创建
- [ ] 检查错误日志：`cat logs/03_mamba_camelsh/<JOBID>.err`

### 问题 2: FileNotFoundError
- [ ] 数据路径正确（`data/camelsh`）
- [ ] 路径大小写正确（Linux 区分大小写）
- [ ] basin list 文件路径正确

### 问题 3: OOM (内存不足)
- [ ] 检查 GPU 内存：`nvidia-smi`
- [ ] 降低 batch_size（在配置文件中）
- [ ] 检查 seq_length 是否过大

### 问题 4: MKL 错误
- [ ] SLURM 脚本中已包含 `export MKL_THREADING_LAYER=GNU`
- [ ] 检查环境变量设置

---

## 完成确认

- [ ] 所有检查项完成
- [ ] Mini Benchmark 作业运行中或已完成
- [ ] 结果目录中有输出文件
- [ ] 准备提交后续作业

**部署日期**: _________________________  
**部署人员**: _________________________  
**备注**: _________________________
