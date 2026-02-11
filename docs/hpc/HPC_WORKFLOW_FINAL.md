# NeuralHydrology HPC 标准化工作流指南 (2026版)

本文档定义了在河海大学 HPC 平台上部署 NeuralHydrology 实验的标准流程。
任何新的 Idea 都必须严格遵循此流程，以确保环境兼容性和可维护性。

---

## 1. 核心原则 (Rules)

1.  **目录隔离**：每个 Idea 必须有独立的 `src/<idea>/`、`results/<idea>/` 和 `logs/<idea>/`。
2.  **脚本模板化**：禁止手写 SLURM 脚本，必须基于标准模板修改。
3.  **格式清洗**：上传到 HPC 后必须执行 `sed -i 's/\r$//'` 修复 Windows 换行符。
4.  **环境统一**：所有任务统一使用 `nh_final` Conda 环境。

---

## 2. 标准目录结构

```
neuralhydrology/
├── src/                        # 代码与配置
│   ├── templates/              # 标准模板 (禁止修改)
│   │   └── hpc/submit_template.slurm
│   ├── caravan_global/         # Idea 01
│   │   ├── configs/config.yml
│   │   └── hpc/submit.slurm
│   └── mamba_camels_us/        # Idea 02
│       ├── configs/config.yml
│       ├── data/               # 专用数据文件 (basin lists)
│       └── hpc/submit.slurm
│
├── results/                    # 训练结果 (HPC 自动生成)
│   ├── 01_caravan_global/
│   └── 02_mamba_camels_us/
│
├── logs/                       # SLURM 日志 (HPC 自动生成)
│   ├── 01_caravan_global/
│   └── 02_mamba_camels_us/
│
└── data/                       # 原始数据集 (只读)
    ├── Caravan/
    └── camels_us/              # 注意 Linux 大小写敏感！
```

---

## 3. 部署流程 (Step-by-Step)

### 第一步：本地准备
1.  在 `src/` 下创建新 Idea 目录。
2.  复制模板：`cp src/templates/hpc/submit_template.slurm src/<idea>/hpc/submit_<idea>.slurm`。
3.  **修改配置**：
    *   `config.yml`: 确保 `run_dir: results/<idea_name>`。
    *   `config.yml`: 确保数据路径大小写正确（如 `data/camels_us`）。
    *   `submit_<idea>.slurm`: 修改 `TASK_NAME` 和 `CONFIG_FILE` 变量。

### 第二步：同步 (WinSCP)
1.  使用 WinSCP 将 `src/<idea>` 目录同步到 HPC。
2.  **检查数据**：如果使用了新的 basin list，确保它也在 `src/<idea>/data/` 中被同步。

### 第三步：HPC 执行 (SSH Terminal)
在 HPC 终端执行以下“三连击”：

```bash
# 1. 进入项目目录
cd ~/neuralhydrology

# 2. 格式修复 (防止秒挂)
sed -i 's/\r$//' src/<idea>/hpc/submit_<idea>.slurm

# 3. 提交作业
sbatch src/<idea>/hpc/submit_<idea>.slurm
```

---

## 4. 故障排查速查表

| 现象 | 原因 | 解决方案 |
| :--- | :--- | :--- |
| **作业秒挂 (无日志)** | 脚本格式错误 (Windows换行) | 执行 `sed -i 's/\r$//' <script>` |
| **作业秒挂 (无日志)** | 日志目录不存在 | 手动执行 `mkdir -p logs/<idea_name>` |
| **Error: iJIT_NotifyEvent** | MKL 库冲突 | 脚本中添加 `export MKL_THREADING_LAYER=GNU` |
| **FileNotFoundError** | 路径大小写错误 | 检查 `config.yml`，Linux 区分大小写 (`CAMELS` vs `camels`) |
| **OOM (内存溢出)** | 数据集过大 | 在 config 中设置 `cache_validation_data: False`，并减小 `batch_size` |
| **Node Failure (ngu001)** | 节点故障 | 脚本中添加 `#SBATCH --exclude=ngu001` |

---

## 5. 常用命令

```bash
# 查看队列
squeue -u $USER

# 查看日志 (自动找最新)
./hpc/logs.sh tail <idea_name>

# 取消作业
scancel <job_id>
```
