# Implementation Status

本文档记录计划实施的状态和已完成的工作。

---

## 🚀 对话交接摘要（用于开启新对话）

> 本节为**权威最新状态**，优先于下文历史清单。

### 1) 本对话的目的（Why）

- 在 `CAMELS-H` 小时尺度大样本数据上完成 `Mamba vs LSTM` 对比，建立可发表论文的证据链。
- 核心研究问题：
  - Mamba 在小时数据（尤其长序列）上是否优于 LSTM？
  - 当 `seq_length=3000+`（超长输入）时，Mamba 是否体现稳定性/效率优势？
- 最终定位：形成高水平论文（方法 + 大样本实验 + 统计分析 + 复现实验资产）。

### 2) 最新进度（What is done）

- **任务隔离已完成**：
  - 代码/配置统一在 `src/mamba_camelsh/`
  - 结果统一在 `results/03_mamba_camelsh/`
  - 日志统一在 `logs/03_mamba_camelsh/`
  - 隔离规则文档：`src/mamba_camelsh/TASK_ISOLATION.md`
- **LSTM baseline 已隔离**（已统一使用 `src/mamba_camelsh/...`）：
  - 新增 `src/mamba_camelsh/configs/camelsh_lstm_mini.yml`
  - `submit_lstm_mini.slurm` 已切到该配置
- **HPC 提交链路已打通**：
  - Mini 作业已成功提交并运行：`JobID=156071`
  - 使用真实 sbatch：`/usr/local/globle/softs/slurm/19.05.4.1/bin/sbatch`
- **关键坑位已解决并文档化**：
  - `sbatch` 被 alias 到 `xbatch`（包装器行为不一致）
  - `DOS line breaks (\r\n)` 导致提交失败
  - `--mem` 导致 “Memory specification can not be satisfied”
  - 问题节点排除：`ngu001,ngu201,ngu202`

### 3) 当前阻塞与注意事项（Risks）

- HPC 上必须优先执行：
  - `sed -i 's/\r$//' src/mamba_camelsh/hpc/*.slurm`
  - 用真实 sbatch 路径提交（不要依赖 alias）
- 结果尚未完成收集，统计分析与论文结论仍待实验输出支撑。

### 4) 下一步计划（Next actions）

1. **Mini 完成后立即收集结果**（Mamba mini + LSTM mini）。
2. 运行 `scripts/analyze_results.py` 生成对比表和图。
3. 若 Mini 结果正常，提交：
   - `submit_full.slurm`（全量）
   - `submit_longseq.slurm`（`seq_length=3000`）
4. 将关键结果填入 `paper/RESULTS_TEMPLATE.md`。
5. 进行统计显著性检验（paired tests）并撰写论文结果段落。

### 5) 新对话可直接复制的启动信息（Bootstrap prompt）

```text
我们继续 neuralhydrology 的 CAMELS-H Mamba 任务。请以 src/mamba_camelsh/IMPLEMENTATION_STATUS.md 的“对话交接摘要（用于开启新对话）”为准。
当前目标：完成 Mamba vs LSTM 的 Mini/Full/Longseq 实验并输出可发表结果。
已知：HPC 需要用 /usr/local/globle/softs/slurm/19.05.4.1/bin/sbatch，提交前需 sed -i 's/\r$//' src/mamba_camelsh/hpc/*.slurm。
请先帮我检查 Job 156071 的日志状态，然后给我下一步最短执行清单。
```

### 6) 最终目标（Final objective）

- 形成一篇可投的、可复现的论文工作流：
  - **科学结论**：Mamba 在 CAMELS-H 小时大样本和超长序列场景的性能与效率证据
  - **工程资产**：隔离的代码、配置、HPC 脚本、分析脚本、结果模板
  - **可复现性**：明确路径、命名规范、提交流程、踩坑修复手册

---

## ✅ 已完成的工作

### 1. HPC 部署准备

#### 1.1 目录结构和配置文件
- ✅ 创建 `src/mamba_camelsh/` 标准目录结构
- ✅ 创建四个配置文件：
  - `configs/camelsh_mini.yml` (50 basins, 10 epochs, seq=168)
  - `configs/camelsh_full.yml` (all basins, 30 epochs, seq=336)
  - `configs/camelsh_longseq.yml` (50 basins, 10 epochs, seq=3000)
  - `configs/camelsh_lstm_mini.yml` (50 basins, 10 epochs, seq=168, isolated baseline)
- ✅ 创建 basin list 文件：`data/test_50_basins.txt`

#### 1.2 SLURM 提交脚本
- ✅ `hpc/submit_mini.slurm` - Mini benchmark 作业脚本
- ✅ `hpc/submit_full.slurm` - Full training 作业脚本
- ✅ `hpc/submit_longseq.slurm` - Long sequence test 作业脚本
- ✅ `hpc/submit_lstm_mini.slurm` - LSTM baseline 作业脚本

#### 1.3 文档和检查清单
- ✅ `README.md` - HPC 部署使用指南
- ✅ `HPC_DEPLOYMENT_CHECKLIST.md` - 逐步检查清单

### 2. 结果分析工具

#### 2.1 分析脚本
- ✅ `scripts/analyze_results.py` - Mamba vs LSTM 性能对比分析脚本
- ✅ `scripts/README.md` - 脚本使用说明

**功能**:
- 加载和比较实验结果
- 生成对比表格
- 创建可视化图表（散点图、箱线图）
- 统计显著性检验

### 3. 论文撰写准备

#### 3.1 论文大纲和模板
- ✅ `paper/PAPER_OUTLINE.md` - 完整论文大纲
  - 包含所有章节结构
  - 关键信息点
  - 目标期刊建议
  - 写作提示

- ✅ `paper/RESULTS_TEMPLATE.md` - 结果记录模板
  - Mini benchmark 结果模板
  - Full training 结果模板
  - Long sequence 结果模板
  - 对比分析模板

---

## ⏳ 需要用户执行的任务

### 阶段一：HPC 环境准备

#### 任务 1.1: 数据验证
**状态**: ⏳ 待执行  
**操作**: SSH 登录 HPC，检查 CAMELS-H 数据是否存在

```bash
ls -la ~/neuralhydrology/data/camelsh/
ls -la /data1/home/$USER/neuralhydrology/data/camelsh/
```

**检查清单**: 参见 `HPC_DEPLOYMENT_CHECKLIST.md` 步骤 1.1-1.3

#### 任务 1.2: 文件同步
**状态**: ⏳ 待执行  
**操作**: 使用 WinSCP 同步 `src/mamba_camelsh/` 到 HPC

**检查清单**: 参见 `HPC_DEPLOYMENT_CHECKLIST.md` 步骤 2.1-2.2

#### 任务 1.3: 环境检查与修复
**状态**: ⏳ 待执行  
**操作**: 在 HPC 上修复脚本格式并验证环境

```bash
cd ~/neuralhydrology
sed -i 's/\r$//' src/mamba_camelsh/hpc/*.slurm
mkdir -p logs/03_mamba_camelsh results/03_mamba_camelsh
conda activate nh_final
python -c "import torch; print(torch.cuda.is_available())"
```

**检查清单**: 参见 `HPC_DEPLOYMENT_CHECKLIST.md` 步骤 3.1-3.4

#### 任务 1.4: 可选加速安装
**状态**: ⏳ 待执行（可选但强烈推荐）  
**操作**: 安装 mamba-ssm CUDA 加速

```bash
module load cuda/11.8
bash hpc/install_mamba_ssm.sh
```

**检查清单**: 参见 `HPC_DEPLOYMENT_CHECKLIST.md` 步骤 4.1

### 阶段二：实验执行

#### 任务 2.1: Mini Benchmark
**状态**: ⏳ 待执行  
**操作**: 提交 Mini benchmark 作业

```bash
/usr/local/globle/softs/slurm/19.05.4.1/bin/sbatch src/mamba_camelsh/hpc/submit_mini.slurm
```

**监控**:
```bash
squeue -u $USER
tail -f logs/03_mamba_camelsh/<JOBID>.out
```

#### 任务 2.2: LSTM Baseline
**状态**: ⏳ 待执行  
**操作**: 提交 LSTM mini benchmark 作业

```bash
/usr/local/globle/softs/slurm/19.05.4.1/bin/sbatch src/mamba_camelsh/hpc/submit_lstm_mini.slurm
```

#### 任务 2.3: Full Training
**状态**: ⏳ 待执行（Mini 成功后）  
**操作**: 提交 Full training 作业

```bash
/usr/local/globle/softs/slurm/19.05.4.1/bin/sbatch src/mamba_camelsh/hpc/submit_full.slurm
```

#### 任务 2.4: Long Sequence Test
**状态**: ⏳ 待执行  
**操作**: 提交 Long sequence test 作业

```bash
/usr/local/globle/softs/slurm/19.05.4.1/bin/sbatch src/mamba_camelsh/hpc/submit_longseq.slurm
```

### 阶段三：结果分析

#### 任务 3.1: 收集结果
**状态**: ⏳ 待执行（实验完成后）  
**操作**: 从 HPC 下载实验结果到本地

**结果位置**:
- Mamba: `results/03_mamba_camelsh/`
- LSTM: `results/03_mamba_camelsh/camelsh_lstm_mini_benchmark_*`

#### 任务 3.2: 运行分析脚本
**状态**: ⏳ 待执行  
**操作**: 使用分析脚本生成对比结果

```bash
python src/mamba_camelsh/scripts/analyze_results.py \
    --mamba_results results/03_mamba_camelsh/camelsh_mamba_mini_benchmark \
    --lstm_results results/03_mamba_camelsh/camelsh_lstm_mini_benchmark_* \
    --output_dir results/03_mamba_camelsh/analysis
```

#### 任务 3.3: 记录结果
**状态**: ⏳ 待执行  
**操作**: 在 `paper/RESULTS_TEMPLATE.md` 中填写实验结果

### 阶段四：论文撰写

#### 任务 4.1: 撰写论文初稿
**状态**: ⏳ 待执行  
**参考**: `paper/PAPER_OUTLINE.md`

#### 任务 4.2: 代码清理
**状态**: ⏳ 待执行  
**操作**: 
- 清理调试代码
- 添加详细注释
- 准备示例脚本

#### 任务 4.3: GitHub 仓库准备
**状态**: ⏳ 待执行  
**操作**: 
- 创建 GitHub 仓库
- 上传代码和文档
- 准备 README 和 LICENSE

---

## 📁 文件结构总结

```
src/mamba_camelsh/
├── __init__.py
├── README.md                          # HPC 部署指南
├── HPC_DEPLOYMENT_CHECKLIST.md        # 检查清单
├── IMPLEMENTATION_STATUS.md           # 本文档
│
├── configs/
│   ├── camelsh_mini.yml               # Mini benchmark 配置
│   ├── camelsh_full.yml               # Full training 配置
│   ├── camelsh_longseq.yml            # Long sequence 配置
│   └── camelsh_lstm_mini.yml          # LSTM mini baseline 配置（隔离）
│
├── data/
│   └── test_50_basins.txt             # 50 个流域列表
│
├── hpc/
│   ├── submit_mini.slurm              # Mamba mini 作业脚本
│   ├── submit_full.slurm              # Mamba full 作业脚本
│   ├── submit_longseq.slurm           # Mamba longseq 作业脚本
│   └── submit_lstm_mini.slurm         # LSTM mini 作业脚本
│
├── scripts/
│   ├── README.md                      # 脚本说明
│   └── analyze_results.py             # 结果分析脚本
│
└── paper/
    ├── PAPER_OUTLINE.md               # 论文大纲
    └── RESULTS_TEMPLATE.md            # 结果记录模板
```

---

## 🎯 下一步行动

1. **立即执行**: 按照 `HPC_DEPLOYMENT_CHECKLIST.md` 完成阶段一（HPC 环境准备）
2. **提交作业**: Mini benchmark 和 LSTM baseline 可以并行提交
3. **持续监控**: 使用 `squeue` 和 `tail -f` 监控作业状态
4. **记录进展**: 在 `paper/RESULTS_TEMPLATE.md` 中记录结果

---

## 📝 注意事项

1. **Windows 换行符**: 上传到 HPC 后必须执行 `sed -i 's/\r$//'` 修复
2. **数据路径**: 确认 HPC 上数据路径正确（Linux 区分大小写）
3. **环境变量**: 确保 Conda 环境正确激活
4. **日志监控**: 定期检查日志文件，及时发现问题
5. **结果备份**: 实验完成后及时下载结果到本地

---

**最后更新**: 2026-01-21  
**状态**: 已在 HPC 成功提交 Mini 作业（JobID: 156071），进入运行与结果收集阶段
