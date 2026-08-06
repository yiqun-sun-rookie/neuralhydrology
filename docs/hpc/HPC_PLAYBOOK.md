# HPC 知识库（河海大学 hpcbh，NeuralHydrology）

> 📘 **要在 HPC 上执行命令？先看 [`HPC_AGENT_GUIDE.md`](HPC_AGENT_GUIDE.md)** ——
> 那是操作手册（Git 信箱怎么用、怎么提交作业、什么必须问用户）。
> 本文是知识库：分区、坑、规章、官方手册对照。

**整理日期**: 2026-08-06
**适用**: 本仓库 `neuralhydrology` 在河海大学 HPC 上的所有实验提交
**状态**: 本文件是**唯一权威**。以下旧文件已被本文覆盖，不要再照抄：
- `docs/hpc/HPC_WORKFLOW_FINAL.md`（流程仍可读，但同步方式、分区、环境名已过时）
- `docs/hpc/HPC_QUICK_START.md`（conda 环境名错，写的 `nh`，实际是 `nh_final`）
- `src/templates/hpc/submit_template.slurm`（分区/时间/exclude 已过时，仅骨架可用）
- `src/static_falsification/hpc/submit_film_poc.slurm`（**反面教材**，见第 9 节）

> **2026-08-06 更新**：本文已按当天在集群上的**实测结果**大幅修订。
> 第 2 节（分区/坏节点）、第 7 节（同步/网络/git 版本）、第 10 节（踩坑表）
> 中被推翻的旧结论已就地标出。新增第 12.5 节（Git 信箱自动化通道）。
> 详见文末第 14 节的实测清单。

本文来源（三条，互补）：
1. **官方手册**：`docs/hpc/reference/河海大学高性能计算平台用户手册V4.1.pdf`
   （文件名 V4.1，封面标 V4.0，2024 年 5 月，实验室与平台处分析测试中心编）
   — 平台的**规章与计费规则**以它为准，见第 13 节
2. 2026-03-30 整理的**实跑操作经验** — 分区、坑、同步方式
3. 仓库中最新且经过实跑的脚本 `src/xaj_global_pilot/hpc/submit_benchmark_531_repro.slurm`
   （2026-04-26）— 具体写法

**三者的分工要清楚**：官方手册只写了 CPU 队列（`hcpu40/48/64/128`、`hcore40`）的
用法和样例，**通篇没有 GPU 队列的样例，也没有出现 `hgpu2p` / `hgpu8`**，2.1 节的
硬件资源表实际是空的。我们用的分区、坏节点、`nh_final` 环境、`--mem` 报错这些，
**全部来自实跑经验，手册补不上**；反过来，登录节点禁令、计费规则、`si` / `scontrol`
这些**只有手册有**。缺任何一条都不完整。

> **给接手者的注意**：集群侧的事实（分区可用性、坏节点列表、`--mem` 是否仍报错）
> 是 2026-03/04 的快照，已过去数月。第一次提交前建议先跑一次第 8 节的体检脚本
> 确认，不要把本文当成实时状态。

---

## 1. 基本信息

| 项 | 值 |
|---|---|
| 主机 | `hpcbh.hhu.edu.cn` |
| 用户 | `sunyiq` |
| OS | CentOS 7（GLIBC 2.17） |
| 调度 | SLURM |
| 项目路径 | `~/neuralhydrology`（= `/data1/home/sunyiq/neuralhydrology`） |
| Conda 环境 | **`nh_final`**（Python 3.11, PyTorch 2.4.0, transformers 已装） |
| Git remote | `https://github.com/yiqun-sun-rookie/neuralhydrology.git` |
| 登录 | 静态密码 + 动态 OTP，**无法免密**，每次都要手输 |

**Claude Code 装不上 HPC**：CentOS 7 的 GLIBC 太旧。所有 HPC 操作只能靠人工 SSH，
或通过 `ssh ... "bash -s" < local_script.sh` 的方式远程执行本地脚本。

### 官方支持渠道（手册 §1）

| 项 | 值 |
|---|---|
| 邮箱 | `hpc@hhu.edu.cn` |
| 电话 | 025-83787629 |
| 地址 | 南京市鼓楼区西康路 1 号河海馆 916 |
| 平台网址 | https://hpc.hhu.edu.cn |
| **作业与计费查询** | https://hpcsp.hhu.edu.cn （江宁校区） |
| 微信群 | 平台按课题组建群，技术人员在群里响应 |

**平台是有偿使用的**，按机时收费。跑大批量 array job 前先算一下量级，
计费明细可以在 hpcsp 上查。

### 登录（手册 §3）

- 密码 = **静态密码 + 动态验证码，两段连在一起一次性输入**（不是分两次提示）
- 动态码 6 位、每 30 秒刷新，来自 FreeOTP（安卓）/ Google Authenticator（iOS）
  / 微信小程序 `LogBaseMFA`
- 登录后有一层**交互式设备选择菜单**：江宁校区选登录节点 1–3，常州新校区选节点 4
  （这层菜单就是 SCP 协议会卡死的原因）
- 官方推荐工具：Xshell + Xftp（对个人和学校用户免费）

---

## 2. 分区与资源

**以下是 2026-08-06 在集群上实测 `sinfo` 的结果，不是回忆：**

| 分区 | 节点数 | 节点名 | 每节点 GPU | CPU 核 | 实测负载(A/I/O/T) |
|---|---|---|---|---|---|
| `hcpu48` (默认) | 64 | `icn[201-264]` | 无 | 48 | 15/33/16/64 |
| `hcpu48y` | 12 | `icn[270-281]` | 无 | 48 | 3/6/3/12 |
| `hgpu8` | 3 | `ngu[201-203]` | **8** | 64 | 3/0/0/3（全忙） |
| `hgpu4` | 4 | `ngu[101-104]` | **4** | 96 | 0/3/1/4 |
| `hgpu2` | 2 | `ngu[003,009]` | 2 | 96 | 1/1/0/2 |
| **`hgpu2p`** | **9** | `ngu[001-002,004-008,010-011]` | 2 | 96/32 | **1/8/0/9（八个空闲）** |

**所有分区 `TIMELIMIT` 都是 `infinite`** —— 平台不限作业时长，第 2 节那张"6h/24h/72h"的表是我们自己的约定，不是平台约束，可以按需设长。

`hgpu2p` 作为主力分区的经验成立：9 个节点里 8 个 idle，排队最快。
`hgpu4`（4 卡/节点）和 `hgpu2` 此前完全没记录过，需要多卡时可以考虑 `hgpu4`。

### ⚠️ 坏节点：`ngu002`（实测，2026-08-06）

**必须知道的前提：`sinfo` 不体检 GPU。** 它只管节点能不能接活，
卡坏了它照样报 `idle` / `REASON=none`。判断 GPU 节点好坏**只能靠真跑一个 CUDA 任务**。

2026-08-06 给 17 个 GPU 节点各派了一个真实作业
（`nvidia-smi` 点卡 → torch 初始化 → 4000×4000 矩阵乘法上卡），结果：

| 分区 | 节点 | nvidia-smi 卡数 | 判定 |
|---|---|---|---|
| `hgpu2p` | ngu001, 004, 005, 006, 007, 008, 010, 011 | 2 | ✅ 健康 |
| `hgpu2p` | **`ngu002`** | **1（应为 2）** | ❌ **CUDA_INIT_FAILED** |
| `hgpu2` | ngu003, ngu009 | 2 | ✅ 健康 |
| `hgpu8` | ngu202 | 8 | ✅ 健康 |
| `hgpu8` | ngu201, ngu203 | — | ⏳ 排队 10 分钟未跑上（该分区常年满载），未测 |
| `hgpu4` | ngu101, ngu102, ngu104 | 4 | ✅ 健康 |
| `hgpu4` | ngu103 | — | SLURM 标 `down*` / Not responding（2026-01-13 起） |

`ngu002` 的症状：`nvidia-smi` 只能看到 1 张卡（健康节点是 2 张），
torch 报 `CUDA unknown error`，`cuda_available=False`，作业以 `ExitCode 2:0` 失败。
**而 `sinfo` 至今显示它 `idle` / `REASON=none`。**

**建议的 exclude**：

```bash
#SBATCH --exclude=ngu002        # hgpu2p 上唯一实测有问题的节点
```

`ngu103` 由 SLURM 自动避开（`down` 状态），不用手写。

### 旧的 exclude 名单是错的

旧版本文档和此前所有 slurm 脚本写的是
`--exclude=ngu001,ngu201,ngu202`，**三个都不对**：

- `ngu001` 实测**健康**（2 张卡、matmul 0.31s 通过）
- `ngu201`/`ngu202` 属于 `hgpu8`，而 `ngu001`/`ngu002` 属于 `hgpu2p` ——
  旧脚本在 `hgpu8` 上排除 `ngu001` 毫无作用（它压根不在那个分区）
- `ngu202` 实测健康（8 张卡通过）
- **真正坏的 `ngu002` 反而不在名单里**

### 那批"节点故障"崩溃其实是脚本问题

`sacct` 显示 157838–157847 十个作业全在 `ngu203`、退出码 **`127:0`**。
`127` 是 shell 的 "command not found"，成因是铁律 4（CRLF 换行）或
铁律 2（`conda activate` 静默失败导致 `python` 不存在）。
同期 `hgpu2p` 上的失败退出码是 `1:0`（Python 正常抛异常），其中一个跑满
8 分 50 秒才失败，同节点另一个作业还成功了。**这些是代码问题，不是硬件问题。**

> **两条教训**：
> 1. **判断节点好坏，`sinfo` 不算数，必须真跑 CUDA 任务。**
>    本文档曾经拿 `sinfo` 的 `idle` 去推翻"坏节点"经验，结果漏掉了真坏的 `ngu002`。
> 2. **把作业失败归因给节点之前，先看 `sacct` 的 `ExitCode`。**
>    `127`=命令找不到（脚本/环境问题），`1`=程序自己报错，
>    `2`=本文测试脚本判定 CUDA 初始化失败，`NODE_FAIL`=真的节点问题。
>
> 这两条错法方向相反、代价对称：误判成坏节点会白白放弃健康算力且真 bug 不修；
> 误判成健康会让作业在坏卡上反复挂掉。**只有真跑才知道。**

复测脚本保存在信箱分支：`inbox/node_test.slurm`（见第 12.5 节），
以后怀疑节点有问题时可以直接复用，每节点约 20–40 秒。

CPU 侧另有 16 个 `icn` 节点处于 `Not responding`（icn203/215/218/224/230/233/234/
235/236/237/239/242/243/245/247/256/278/279/281），由 SLURM 自动避开。

### 资源请求参考

| 任务 | 分区 | CPUs | GPU | 时间 |
|---|---|---|---|---|
| Smoke test | hgpu2p | 4 | 1 | 10–30m |
| 小训练（50 basins） | hgpu2p | 4 | 1 | 6h |
| 中训练（531 basins LSTM） | hgpu2p | 8 | 1 | 24h |
| 大训练（Caravan / Mamba） | hgpu2p | 16 | 1 | 72h |
| 超长（Mamba 长序列） | hgpu2p | 8 | 1 | 168h |
| Array chunk（50 basins/chunk） | hgpu2p | 4 | 1 | 2–6h |
| 纯 CPU（Numba 率定） | hgpu2p | 4 | 0 | 24h |

纯 CPU 任务也可以占 GPU 节点跑，只是浪费一张卡；急着排队时可以这么干。

---

## 3. 六条铁律

第 1 条是**平台规章**（官方手册明令，违反会被管理员干预）；第 2–6 条是踩坑换来的，
违反任何一条都会失败，而且大多数**失败时没有日志**：

0. **禁止在登录节点上直接跑计算程序**（手册 §1 红字明令）
   所有计算任务一律 `sbatch` 提交。登录节点只能做 `git pull`、`sed`、`ls`、
   编辑脚本、装 conda 包这类轻量操作。想快速验证代码能不能跑，也要走
   smoke test 作业，不要图省事在登录节点直接 `python train.py`。

1. **任何分区都不要写 `--mem`**
   写了直接报 `Memory specification can not be satisfied`，作业根本进不了队列。
   **原因见手册 §2.3**：平台的 CPU 资源"以计算节点为单位"分配、GPU 资源"以卡为
   单位"分配，内存跟着节点整体走，不接受用户单独指定。

2. **用 `set -eo pipefail`，绝不能带 `-u`**
   `-u`（未定义变量报错）会让 `conda activate` 静默退出——conda.sh 内部引用了未设置的变量。
   现象是脚本无声结束，看不出原因。

3. **必须 `export MKL_THREADING_LAYER=GNU`**
   否则报 `iJIT_NotifyEvent` 或 GLIBC 段错误。配套加 `export MKL_SERVICE_FORCE_INTEL=1`。

4. **上传后必须修换行符**
   `sed -i 's/\r$//' src/<idea>/hpc/*.slurm`
   Windows 的 CRLF 会让作业秒挂且**不产生任何日志**。走 Git 同步时如果 `.gitattributes`
   没管住也一样会中招，养成提交前先 sed 的习惯。

5. **日志目录必须先存在**
   `#SBATCH -o logs/<idea>/xxx-%j.out` 指向的目录若不存在，作业秒挂无日志。
   两道保险：本地 `mkdir -p logs/<idea>` 并 commit 一个 `.gitkeep`，脚本内也再 `mkdir -p` 一次。

---

## 4. 标准 SLURM 脚本骨架

以下骨架**逐行核对过三份实跑脚本**（见 4.2 的溯源表），只保留有实跑背书的写法。
新任务从这里改，**不要**从 `src/templates/hpc/submit_template.slurm` 改（那份含
`srun`、`--exclude=ngu001` 单节点、168h 默认时长等已过时或未经验证的内容）。

### 4.1 骨架

```bash
#!/usr/bin/env bash
#SBATCH -J <job-name>
#SBATCH -p hgpu2p
#SBATCH -N 1
#SBATCH -n 1
#SBATCH --cpus-per-task=4
#SBATCH --gres=gpu:1          # 纯 CPU 任务（如 Numba 率定）整行删掉
#SBATCH -t 06:00:00
#SBATCH -o logs/<idea>/<task>-%j.out
#SBATCH -e logs/<idea>/<task>-%j.err
# 注意：绝不写 --mem

set -eo pipefail          # 不能是 -euo

# --- 环境 ---
source /data1/home/${USER}/miniconda3/etc/profile.d/conda.sh || \
source $HOME/miniconda3/etc/profile.d/conda.sh
conda activate "${CONDA_ENV:-nh_final}" || { echo "[FATAL] conda activate failed"; exit 1; }

export MKL_THREADING_LAYER=GNU
export MKL_SERVICE_FORCE_INTEL=1
# 可选，按需开：
# export CUDA_DEVICE_ORDER=PCI_BUS_ID
# export PYTORCH_CUDA_ALLOC_CONF=max_split_size_mb:512   # 大模型防显存碎片
# export OMP_NUM_THREADS=${SLURM_CPUS_PER_TASK}

cd ${SLURM_SUBMIT_DIR}
export PYTHONPATH=$(pwd):$PYTHONPATH

IDEA="<id>_<idea_name>"
mkdir -p "logs/${IDEA}" "results/${IDEA}"

# --- Pre-flight（见第 5 节，这一段是省时间的关键）---
echo "=========================================="
echo "[$(date)] <Task Name>"
echo "=========================================="
echo "[INFO] Job: $SLURM_JOB_ID, Node: $(hostname)"
echo "[INFO] Python: $(python --version 2>&1)"
python -c "import torch; print(f'[INFO] PyTorch {torch.__version__}, CUDA: {torch.cuda.is_available()}')"

# --- 运行 ---
# 直接 python，不要套 srun（见 4.2 注 1）；-u 必须，否则日志不实时
python -u <script> <args>
EXIT_CODE=$?

echo "=========================================="
echo "[$(date)] Done (exit: ${EXIT_CODE})"
echo "=========================================="
exit ${EXIT_CODE}
```

### 4.2 每一行的溯源与验证状态

核对基准（三份有实跑痕迹的脚本）：

| 脚本 | 日期 | 类型 | 分区 | GPU | `--mem` | `set` | MKL | `srun` |
|---|---|---|---|---|---|---|---|---|
| `xaj_global_pilot/hpc/submit_benchmark_531_repro.slurm` | 04-26 | CPU 率定 | hgpu2p | 无 | 无 | `-eo` | 有 | **无** |
| `xaj_global_pilot/hpc/submit_benchmark_531.slurm` | 03-31 | CPU 率定 | hgpu2p | 无 | 无 | `-eo` | 有 | **无** |
| `adversarial/hpc/submit_exp1_core.slurm` | 03-11 | **GPU 推理** | hgpu2p | `gpu:1` | 无 | `-eo` | **无** | **无** |

| 骨架元素 | 验证状态 |
|---|---|
| `-p hgpu2p` | ✅ 三份全用，CPU/GPU 任务都是它 |
| 不写 `--mem` | ✅ 三份全不写 |
| `set -eo pipefail` | ✅ 三份逐字一致 |
| `-N 1 -n 1 --cpus-per-task=4` | ✅ 三份一致 |
| `--gres=gpu:1` | ✅ 由 `submit_exp1_core.slurm` 背书（hgpu2p + gpu:1 组合可用） |
| conda **两路** fallback | ✅ 531 两份如此。exp1 只有单路（无 fallback），两路更稳 |
| `conda activate nh_final` | ✅ 三份一致 |
| MKL 两个 export | ⚠️ **见注 2** |
| `cd ${SLURM_SUBMIT_DIR}` + `PYTHONPATH` | ✅ 三份一致 |
| `mkdir -p logs/ results/` | ✅ 531 两份有 |
| `python -u`（不套 `srun`） | ✅ **见注 1** |
| `echo` 头尾分隔块 + `$(date)` + `EXIT_CODE` | ✅ 531 两份一致 |
| `CUDA_DEVICE_ORDER` | ❌ **见注 3**，已降为可选 |
| `PYTORCH_CUDA_ALLOC_CONF` / `OMP_NUM_THREADS` | ❌ 无实跑脚本使用，已降为可选注释 |
| `--exclude=...` | ➖ 用 hgpu2p 时三份都不需要；换 hgpu8 才加（第 2 节） |

**注 1（重要，与旧 template 冲突）**：**三份实跑脚本没有一份用 `srun`**，全部是直接
`python -u -m ...`。`srun` 只出现在 `src/templates/hpc/submit_template.slurm` 里，
那份没有实跑证据。单节点单任务用 `srun` 没有好处，还可能引入额外的资源分配层。
**骨架已删掉 `srun`**。

**注 2（MKL 的真实适用范围）**：`MKL_THREADING_LAYER=GNU` 在 531 系列（Numba +
NumPy 密集的传统模型率定）上是刚需，不加会 `iJIT_NotifyEvent` / GLIBC 段错误。
但 `submit_exp1_core.slurm` 这条 GPU 推理链**没加也正常跑完**。
结论：**建议无条件加**（加了无害），但"不加必挂"只对 CPU 数值计算链成立，
不要据此判断一个没加 MKL 的 GPU 脚本一定有问题。

**注 3**：`CUDA_DEVICE_ORDER=PCI_BUS_ID` 只在旧记忆和早期废弃脚本里出现过，
没有任何干净脚本用它。多卡时才有意义，单卡任务可以不管。

### 4.3 骨架里**没有**实跑背书的部分

以下写法来自经验记录，但**仓库里找不到任何脚本实现过**，第一次用务必先 smoke test：

- **两阶段 train + evaluate**（第 6.4 节）：`nh_run train` 后自动 `find` 最新 run_dir
  再 `evaluate`。仓库里没有任何 slurm 脚本这么写过——GPU 训练那条链上最新的干净脚本
  `submit_exp1_core.slurm` 只做推理评估，不做训练。
- **`--signal=TERM@300` 优雅停止**（第 6.6 节）
- **`sbatch --export=CONFIG=...` 参数化提交**（第 6.5 节）
- **`--array=0-23%8` 限并发**（第 6.2 节）：只在反面教材 `submit_film_poc.slurm` 里
  出现过，语法本身是 SLURM 标准写法，但本集群上没有成功案例。

也就是说：**用本骨架跑 `neuralhydrology.nh_run train` 的完整 GPU 训练流程，
在本仓库里没有一份新近的、干净的先例**。最接近的是 2026-03-11 的 adversarial 推理脚本。
第一次跑训练任务，务必先用 1–2 个 basin、10 分钟的 smoke test 走通全链路。

---

## 5. Pre-flight 检查（强烈建议）

最新的实跑脚本把这一段做得最完整，注释里明确写着
**"数据目录缺失是静默失败的第一来源"**。三道检查，任何一道失败立刻 `exit 1`，
避免排队十几小时后才发现路径写错：

```bash
# 1) 数据目录存在
[ -d "${DATA_ROOT}/basin_mean_forcing/${FORCING_SUBDIR}" ] \
    || { echo "[FATAL] Forcing dir missing: ..."; exit 1; }

# 2) 清单/配置文件存在
[ -f "$MANIFEST" ] || { echo "[FATAL] Manifest missing: $MANIFEST"; exit 1; }

# 3) 关键模块能 import（抓 PYTHONPATH / 依赖问题）
python -c "from src.xaj_global_pilot.runner import run_single_model_basin; print('[INFO] Import OK')" \
    || { echo "[FATAL] Import failed"; exit 1; }
```

**跑完之后再验一次协议**——防止"跑完了但跑的是错的实验设置"。
`submit_benchmark_531_repro.slurm:122-140` 的做法：读结果目录里的 metadata JSON，
逐字段核对 forcing 名、率定期/评估期起止日期，对不上就 `sys.exit` 报错。
任何有"协议锁定"要求的实验都应该抄这一段。

---

## 6. 常用模式

### 6.1 Array job：一维索引拆二维（模型 × chunk）

来自 531_repro，33 个任务 = 3 模型 × 11 chunk：

```bash
#SBATCH --array=0-32

N_CHUNKS=11
MODELS=(xaj_pdd hbv gr4j_pdd)
MODEL_IDX=$((SLURM_ARRAY_TASK_ID / N_CHUNKS))
CHUNK_IDX=$((SLURM_ARRAY_TASK_ID % N_CHUNKS + 1))
MODEL=${MODELS[$MODEL_IDX]}
CHUNK_FILE="${CHUNK_DIR}/chunk_$(printf '%03d' ${CHUNK_IDX}).txt"
```

### 6.2 限制并发

```bash
#SBATCH --array=0-23%8     # 24 个任务，最多 8 个同时跑
```

配置矩阵多时（如 2 模型 × 2 条件 × 2 fold × 3 seed = 24）用数组列出 config 路径，
`CFG="${CONFIGS[$SLURM_ARRAY_TASK_ID]}"` 取。

### 6.3 断点续跑 / 补跑

- 运行脚本支持 `--skip-existing`，重复提交自动跳过已完成的 basin
- 只补跑失败的任务：`sbatch --array=5,18 <script>`

### 6.4 两阶段（训练 + 评估）

```bash
srun python -u -m neuralhydrology.nh_run train --config-file "$CFG" --gpu 0
TRAIN_EXIT=$?
[ $TRAIN_EXIT -eq 0 ] || { echo "[FATAL] Training failed"; exit $TRAIN_EXIT; }

# 自动找最新 run_dir（nh 会加时间戳后缀）
RUN_DIR=$(find "results/${IDEA}" -maxdepth 1 -type d -name "${EXP}_*" \
    -printf '%T@ %p\n' | sort -n | tail -1 | cut -d' ' -f2)
srun python -u -m neuralhydrology.nh_run evaluate \
    --run-dir "$RUN_DIR" --period test --epoch $EPOCH --gpu 0
```

### 6.5 参数化提交

```bash
sbatch --export=CONFIG=seqscale_cudalstm_336h src/<idea>/hpc/submit.slurm
# 脚本内：CONFIG_FILE="${TASK_ROOT}/configs/${CONFIG}.yml"
```

### 6.6 超时前优雅保存

```bash
#SBATCH --signal=TERM@300   # 到点前 5 分钟发 SIGTERM，给 checkpoint 留时间
```

---

## 7. 文件同步

### 推荐：Git（SSH 协议更快，HTTPS 也能用但很慢）

**2026-08-06 严格实测**（TCP 三轮 + curl + 真实 git/pip 操作）：

| 目标 | 结果 | 耗时 |
|---|---|---|
| `github.com:22`（SSH） | ✅ 通 | 快 |
| `github.com:443`（HTTPS） | ✅ 通 | **TLS 握手 11.0s**，总 11.7s |
| `git ls-remote` via HTTPS | ✅ 成功 | — |
| `git ls-remote` via SSH | ✅ 成功 | — |
| pypi.org / files.pythonhosted.org | ✅ 通 | **20s** / 11s |
| `pip download six` | ✅ **成功** | — |
| DNS 解析 | ✅ 正常 | — |
| gitee / ghproxy 等镜像 | ❌ Network unreachable | — |

> ⚠️ **本文档一度写着"HTTPS 不通、pypi 不通"，那是误判。**
> 起因是用 `timeout 10~12` 做探测，而这台机器的 TLS 握手就要 11 秒，全部超时。
> **教训：在慢网络上用短超时探测，会把"慢"读成"断"。**
> 这个误判的代价不小——它会让人放弃本来可用的通道，去做没必要的绕行。
> 以后在 HPC 上测网络，**超时至少给 30 秒，并且要测到应用层**
> （`curl` / `git ls-remote` / `pip download`），光测 TCP 端口不够。

`origin` 已于 2026-08-06 从 HTTPS 改为 SSH——**这个改动仍然值得**（SSH 明显更快），
但不是"HTTPS 不可用"，而是"HTTPS 慢"：

```bash
# 一次性改 remote（已做过，此处备查）
cd ~/neuralhydrology
git remote set-url origin git@github.com:yiqun-sun-rookie/neuralhydrology.git
ssh -T git@github.com    # 应显示 Hi <用户名>! You've successfully authenticated
```

HPC 上 `~/.ssh/id_rsa.pub` 已加入该 GitHub 账户，无需 token。

日常同步：

```bash
# 本地
git push origin migration/reorg-v1
# HPC
cd ~/neuralhydrology && git pull origin migration/reorg-v1
```

### pip / conda 装包：能用，但慢

`pip download six` 实测成功。pypi 响应约 20 秒，装大包会很慢但可行。
conda 已配清华镜像（`~/.condarc`：tuna 的 conda-forge / pkgs/free / pkgs/main），
走 conda 装包更快。

（本文旧版说"pypi 不通、装不了包"，是短超时导致的误判，已更正。）

### ⚠️ HPC 的 bash 是 4.2 —— `set -u` 会炸空数组

CentOS 7 自带 bash 4.2（2011 年）。**在 `set -u` 下展开空的关联数组会直接退出脚本**：

```bash
set -u
declare -A A
for k in "${!A[@]}"; do ... done      # bash 4.2: A: unbound variable → 脚本死
```

更麻烦的是**各版本行为不一致**：bash 4.4 修了一部分，5.x 又不同
（本地 5.2 实测反而是 `${#A[@]}` 报错、`${!A[@]}` 正常）。
所以**不要试图靠版本判断写兼容代码，那是赌博**。

**结论：脚本里不要用 `set -u`。** 用 `set -o pipefail`（需要时加 `-e`），
变量默认值一律写成 `${VAR:-default}`。

这和铁律 2 是同一条道理的两个表现——`set -u` 在这套环境里既杀 `conda activate`，
又杀空数组。**在 HPC 上，`-u` 就是麻烦制造者。**

### ⚠️ HPC 的 git 是 1.8.3.1（2013 年，CentOS 7 自带）

不支持这些较新语法，脚本里用了会失败：

| 语法 | 需要版本 | 替代 |
|---|---|---|
| `git -C <dir>` | 1.8.5+ | 先 `cd` |
| `git branch --show-current` | 2.22+ | `git rev-parse --abbrev-ref HEAD` |
| `git switch` / `git restore` | 2.23+ | `git checkout` |
| `git worktree` | 2.5+ | 不可用 |

**最阴的一个坑**：`git fetch origin <branch>` 在 1.8.3.1 上**只写 `FETCH_HEAD`，
不更新 `refs/remotes/origin/<branch>`**。于是后续 `git reset --hard origin/<branch>`
会永远重置回旧 commit，而 `fetch` 和 `reset` 的返回码都是 **0**，日志一切正常。
这是完全静默的失败。必须写全 refspec：

```bash
git fetch -q origin "+<branch>:refs/remotes/origin/<branch>"
git reset -q --hard "refs/remotes/origin/<branch>"
```

结果回传同理：HPC 上 `git add/commit/push`，本地 pull。大文件用 tar 打包。

### 备用：rsync from WSL

```bash
rsync -avz --progress --exclude='__pycache__/' --exclude='*.pyc' \
  src/<idea>/ sunyiq@hpcbh.hhu.edu.cn:~/neuralhydrology/src/<idea>/
```

### 已确认不可行（别浪费时间重试）

**根本原因已于 2026-08-06 查明：`hpcbh.hhu.edu.cn` 是一台独立的堡垒机（跳板机），
它有自己的账户体系，且不支持非交互 SSH channel。** 下面这些失败全部由此而来，
不是权限、路径或会话数的问题：

| 方案 | 失败原因（已实测） |
|---|---|
| `ssh hpc "命令"`（exec channel） | **堡垒机吞掉命令**：返回 `RC=0` 但零输出。这是所有自动化失败的总根源 |
| WinSCP / SFTP | 路径是 `/登录节点_Group/<IP>_Device/SFTP22/#/` 多层嵌套，不是 home |
| WinSCP / SCP | 登录有交互式设备选择菜单，SCP 协议卡死 |
| rsync from Windows | stdin 被重定向到 /dev/null，无法输密码 |
| rsync + WSL ControlMaster | ~~撞 MaxSessions 限制~~ **此说法有误**，真实原因是上面第一条 |
| **公钥免密登录** | 认证发生在**堡垒机**，往后端节点 `~/.ssh/authorized_keys` 加公钥无效。要配得管理员在堡垒机侧操作 |
| 在 HPC 上跑 Claude Code | CentOS 7 GLIBC 2.17 太旧 |

**两个必须知道的操作陷阱**：

1. **Windows 原生 OpenSSH 完全用不了** —— 不支持 ControlMaster，
   在 Git Bash 里跑 `ssh hpc` 会重新发起认证并失败。**必须走 WSL。**
2. **`ssh -tt` 复用 ControlMaster 会把正在登录的人踢下线** ——
   它会抢走 master 连接的 TTY，输出串到对方终端上，然后整个共享连接关闭。
   要开独立连接必须加 `-o ControlPath=none`。

---

## 8. 提交前体检

参考 `src/adversarial/hpc/check_hpc_ready.sh`。用法（不用登录、绕开交互菜单）：

```bash
ssh sunyiq@hpcbh.hhu.edu.cn "bash -s" < src/<idea>/hpc/check_hpc_ready.sh
```

它检查六项，新实验照着改数据路径和模块名即可：
1. 数据集目录存在 + forcing 子目录 + basin 数量
2. 模型权重 / checkpoint 在位
3. `conda activate nh_final` 成功 + torch/CUDA/neuralhydrology 可 import
4. Git 分支、最新 commit、remote
5. `nvidia-smi`（登录节点上会失败，正常）
6. 本 idea 的代码目录已同步

---

## 9. 两份反面教材

仓库里有两份脚本违反铁律，都**不要抄**。它们的存在说明：文件日期新 ≠ 经验新，
判断一个脚本能不能抄，要看它是否符合第 3 节的铁律，不看修改时间。

### 9.1 `src/static_falsification/hpc/submit_film_poc.slurm`（2026-04-18）

日期只比 531_repro 早一周，但**同时违反三条铁律**：

| 行 | 写法 | 问题 |
|---|---|---|
| 6 | `--mem=32G` | 违反铁律 1，作业进不了队列 |
| 15 | `set -euo pipefail` | 违反铁律 2，conda activate 会静默退出 |
| 51 | `source activate nh` | 环境名错，应为 `nh_final`，且应走 conda.sh fallback |
| 4 | `--partition=hgpu8` 但无 exclude | hgpu8 必须排除 ngu001/201/202 |

它是否真在 HPC 上跑成功过，仓库里看不出证据。该 idea（原 ID11 static_falsification）
后来已合并进 ID17，这个脚本大概率是搁置状态。

**唯一可借鉴的一点**：用数组列出全部 config 路径、
`CFG="${CONFIGS[$SLURM_ARRAY_TASK_ID]}"` 取值的写法，适合"模型 × 条件 × fold × seed"
这类配置矩阵。但要连同上面四处一起改对。

### 9.2 `src/adversarial/baseline_531/hpc/hpc_full_training.slurm`（早期）

全套违规，明显是没跑通就搁置的产物：

| 写法 | 问题 |
|---|---|
| `--partition=gpu` | 已弃用分区 |
| `--mem=64G` | 违反铁律 1 |
| `--gres=gpu:2` | 本仓库无多卡训练代码，`nh_run` 只吃单卡 |
| 无 `set -eo pipefail` | 中途失败不会停 |
| `module load python/3.10 cuda/11.8 gcc/9.3.0` | 本集群靠 conda，不用 module |
| `conda activate neuralhydrology_gpu` | 环境不存在，应为 `nh_final` |
| `PROJECT_DIR="/data/neuralhydrology"` | 路径不存在，应为 `${SLURM_SUBMIT_DIR}` |
| `--mail-user=your_email@hhu.edu.cn` | 占位符没填 |

同目录下的 `hpc_deploy.sh`、`setup_hpc_environment.sh`、`hpc_optimized_config.py`
出自同一批，一并当作不可信。**唯一还有用的是 `check_hpc_ready.sh`**（在
`src/adversarial/hpc/`，不是 `baseline_531/hpc/`），见第 8 节。

---

## 10. 踩坑速查表

| 现象 | 原因 | 解决 |
|---|---|---|
| `Memory specification can not be satisfied` | 写了 `--mem`（平台按节点/按卡分配，见手册 §2.3） | 删掉，任何分区都不写 |
| 管理员找上门 / 登录节点卡顿 | 在登录节点直接跑了计算程序 | 铁律 0，一律 `sbatch` |
| 作业长期 `PD` 不动 | 见第 11 节原因码 | `squeue` 看原因；`scontrol update ... partition=` 改投别的队列 |
| `CG` 状态卡住 | COMPLETING，等进程退出 | 正常现象，等着；`scancel` 无效也不必用 |
| SFTP 连上后看不到 home | 路径是 `/登录节点_Group/<IP>_Device/SFTP22/#/` 多层嵌套 | 一路点进去才到个人目录；但**仍建议不用 SFTP，走 Git** |
| 脚本无声结束，conda 没激活 | `set -euo pipefail` 的 `-u` | 改 `set -eo pipefail` |
| 脚本报 `xxx: unbound variable` 后退出 | `set -u` + bash 4.2 展开空数组 | 去掉 `-u`，见第 7 节 |
| `iJIT_NotifyEvent` / GLIBC 段错误 | MKL 线程层冲突 | `export MKL_THREADING_LAYER=GNU` |
| **作业秒挂，完全没有日志** | Windows CRLF 换行 | `sed -i 's/\r$//' <script>` |
| **作业秒挂，完全没有日志** | `-o` 指向的目录不存在 | `mkdir -p logs/<idea>` |
| 作业 `FAILED`，`ExitCode=127` | **command not found** —— CRLF 换行 或 conda 没激活导致 `python` 不存在。**不是节点故障** | 查铁律 2 和 4 |
| 作业 `FAILED`，`ExitCode=1` | 程序自己抛异常 | 看 `.err` 日志，是代码问题 |
| 作业 `NODE_FAIL` | 这才是真的节点问题 | SLURM 会自动避开 `down` 节点，一般不用手写 `--exclude` |
| `git fetch` 成功但代码没更新 | git 1.8.3.1 只写 FETCH_HEAD | 写全 refspec，见第 7 节 |
| `pip install` 卡死 | pypi 不通 | 环境必须预建齐，见第 7 节 |
| `git -C` / `--show-current` 报错 | git 1.8.3.1 太老 | 见第 7 节替代写法 |
| `FileNotFoundError` 路径存在却找不到 | Linux 大小写敏感 | 检查 `camels_us` vs `CAMELS_US` |
| 日志不实时刷新 | Python 输出缓冲 | `python -u` |
| 训练中 OOM | 数据集过大 | config 设 `cache_validation_data: False`，减小 `batch_size` |
| CPU 训练 hourly 数据 segfault | TensorBoard / matplotlib | 禁用 `log_tensorboard` 和 `log_n_figures` |
| 跑完发现协议不对 | 没做 metadata 核对 | 抄第 5 节的跑后校验 |

---

## 11. 监控与日志规范

> ⚠️ **官方手册 §5.1/§5.4 说用 `si` 和 `sq`，但登录节点上实测这两个别名不存在**
> （`type: si: not found`）。手册与现实不符，一律用标准的 `sinfo` / `squeue`。

```bash
sinfo                                                         # 看队列/节点状态（提交前先看）
sinfo -R                                                      # 只看故障节点及原因
sinfo -N -o "%12N %12P %10T %5c %10G %30E"                    # 节点级详情：状态/核数/GPU/故障原因
squeue -u sunyiq                                              # 看自己的作业
sacct -j <JOBID> --format=JobID,State,ExitCode,MaxRSS,Elapsed # 看资源与退出码
scontrol show job <JOBID>                                     # 作业详情：提交时间、运行时间、工作目录
tail -f logs/<idea>/<task>-<JOBID>.out                        # 实时日志
scancel <JOBID>                                               # 取消单个
scancel -u sunyiq                                             # 取消全部
scancel -p hgpu2p -t pd                                       # 只取消某队列里还在排队(pd)的作业
```

**排队中还能改参数，不用重新提交**（手册 §5.5）：

```bash
scontrol update jobid=<JOBID> partition=hgpu8    # hgpu2p 排不上，改投 hgpu8
scontrol update jobid=<JOBID> name=myjob         # 改作业名
```

**作业状态与排队原因**（手册 §5.4）：

| 状态 | 含义 |
|---|---|
| `PD` | 排队中，具体原因见下 |
| `R` | 运行中 |
| `CG` | COMPLETING，已跑完在等进程退出。**不用 scancel，也 cancel 不掉** |
| `CD` / `F` / `TO` / `NF` / `CA` | 完成 / 失败 / 超时 / 节点故障 / 被取消 |

`PD` 的常见原因码：

| 原因 | 含义 |
|---|---|
| `Priority` | 优先级不够，前面有人排 |
| `Resources` | 当前空闲资源不满足请求 |
| `PartitionNodeLimit` | 请求节点数超过该分区上限 |
| `AssociationJobLimit` / `AssociationResourceLimit` / `AssociationTimeLimit` | 账号关联的作业数 / 资源 / 时长配额已满 |
| `ReqNodeNotAvail` | 指定的节点不可用（比如 `--exclude` 之后没剩下可用节点） |

**官方样例的一个好习惯**：脚本末尾加 `scontrol show job $SLURM_JOBID`，
把资源分配和运行信息一并写进日志，事后排查省事。

目录规范（与 `results/` 一一对应）：

```
logs/<id>_<idea_name>/
  <task>-%j.out          # %j = SLURM_JOB_ID
  <task>-%j.err
  <task>_%A_%a.out       # array job：%A=主 ID, %a=task ID
```

日志内容统一格式：

```
==========================================
[TIME] Task Name
==========================================
[INFO] Job ID / Node / GPU / Config / Protocol
[INFO] Pre-flight passed
[TIME] Stage 1/2: Training...
[TIME] Stage 2/2: Evaluating...
[DONE] Results: <path>
==========================================
```

---

## 12. 新 Idea 上 HPC 的完整清单

1. 本地建 `src/<id>_<idea>/{configs,scripts,hpc}/`、`results/<id>_<idea>/`、`logs/<id>_<idea>/`
2. 抄第 4 节骨架写 `src/<id>_<idea>/hpc/submit_<task>.slurm`
3. 加第 5 节的三道 pre-flight + 跑后 metadata 校验
4. config.yml 里路径全小写、`run_dir` 指向 `results/<id>_<idea>`
5. 本地 `git commit && git push origin migration/reorg-v1`
6. HPC：`cd ~/neuralhydrology && git pull origin migration/reorg-v1`
7. HPC：`sed -i 's/\r$//' src/<id>_<idea>/hpc/*.slurm`
8. HPC：`mkdir -p logs/<id>_<idea>`
9. 先跑 smoke test（10–30 min，1–2 个 basin）确认全链路通
10. 再 `sbatch` 正式作业，`squeue -u sunyiq` 确认进队列
11. 跑完 HPC 上 commit 结果并 push，本地 pull 回来

---

## 12.5 无人值守自动化通道：Git 信箱（2026-08-06 建成，可用）

因为堡垒机不支持非交互 channel（第 7 节），**没有任何办法让本地程序直接在 HPC
上执行命令**。绕过办法是让 HPC 主动来取命令：

```
本地 --push 命令--> GitHub (hpc-mailbox 分支) <--pull-- HPC 守护循环
                                              --push 结果-->
```

**部署位置**：HPC 上 `~/hpc_mailbox/`（`hpc-mailbox` 分支的浅克隆）

**启动**（登录节点上，只需一次；注意括号，`&` 必须只作用于子 shell）：

```bash
( cd ~/hpc_mailbox && nohup bash runner.sh > runner.log 2>&1 & )
```

**停止**：`pkill -f "bash runner.sh"`

**用法**：改 `inbox/cmd.sh` → 改 `inbox/seq`（递增）→ push。
HPC 端 20 秒内执行，结果写入 `outbox/result_<seq>.txt` 并 push 回来。

**几个必须知道的点**：

- **推之前先 `git pull --rebase`**，否则会被 HPC 推回来的结果挡住（non-fast-forward）
- **这个循环会执行推到该分支的任意命令**，等于把执行权交给了有 push 权限的人。
  不用时 `pkill` 掉。
- 它跑在**登录节点**上，只做 git 和轻量命令，符合铁律 0。真正的计算必须 `sbatch`。
- 写 `runner.sh` 之类的脚本时，仓库里要有 `.gitattributes` 强制 `eol=lf`，
  否则 Windows 写的文件带 CRLF，传到 HPC 直接踩铁律 4。

**已知的两个设计坑（都已修，记录备查）**：

1. ~~启动时把当前 seq 记为基线、不重跑~~ —— 这会**吞掉启动前就已存在的第一条命令**。
   已改为按 `outbox/result_<seq>.txt` 是否存在判重。
2. ~~`git fetch origin <branch>`~~ —— 老 git 静默失败，导致 runner 原地打转、
   而且**永远拉不到修复后的自己**（死锁，必须人工登录打破一次）。已改为全 refspec。

---

## 13. 官方手册要点与我们做法的对照

手册：`docs/hpc/reference/河海大学高性能计算平台用户手册V4.1.pdf`（20 页）。
下面是与本仓库相关的部分，以及**为什么我们的做法和手册样例长得不一样**。

### 13.1 手册里有、本文采纳的

| 手册位置 | 内容 | 落在本文 |
|---|---|---|
| §1 红字 | 禁止登录节点直接跑计算 | 铁律 0 |
| §1 | 有偿使用；计费查询 hpcsp.hhu.edu.cn | 第 1 节 |
| §2.3 | CPU 按节点分配 / GPU 按卡分配 | 铁律 1 的**原因** |
| §3.1–3.2 | 静态+动态密码连着输；江宁登录节点 1–3 | 第 1 节 |
| §5.1 | `si` 看空闲资源 | 第 11 节 |
| §5.4 | 作业状态 + PD 原因码 | 第 11 节 |
| §5.5 | `scontrol update` 改排队作业的队列/名字 | 第 11 节 |
| §5.6 | `scancel -p <queue> -t pd` | 第 11 节 |
| §7 样例 | 末尾 `scontrol show job $SLURM_JOBID` | 第 11 节 |

### 13.2 手册里有、本仓库**不适用**的

| 手册内容 | 为什么不用 |
|---|---|
| `module load anaconda3/2020.07` 加载 Python | 我们用自建的 `nh_final`（Py3.11 + torch 2.4.0）。平台的 anaconda3 是 2020 版，太旧。手册也说了缺第三方模块要"在**登录节点 2** 上自行安装" |
| `module load intel/2017u5` 等编译器模块 | 纯 Python + PyTorch 栈，不需要 |
| `mpirun -np 40 ...` | 单节点单卡任务，不用 MPI |
| `-n 40` / `-p hcpu40` 之类的整节点核数 | **见 13.4**——那是 CPU 队列的规矩 |
| 全部 7.x 应用样例（vasp / lammps / Gaussian / fluent / MS / comsol …） | 与本项目无关 |

### 13.3 手册里**没有**、只能靠实跑经验的

手册通篇没提这些，第 2、3、7 节的内容手册补不上：

- **GPU 队列的存在**：`hgpu2p` / `hgpu8` 在手册里一次都没出现，
  §2.1 的硬件资源表实际是空的，§7 的九个样例**全是 CPU 队列**
- 坏节点 `ngu001` / `ngu201` / `ngu202`
- `MKL_THREADING_LAYER=GNU` 与 `iJIT_NotifyEvent` 段错误
- `set -euo pipefail` 的 `-u` 会杀掉 `conda activate`
- Windows CRLF 导致秒挂无日志
- Git 同步可行、rsync/WinSCP 全不可行
- `nh_final` 环境的存在和内容

**所以：查规章找手册，查怎么跑找本文。**

### 13.4 一条重要的计费差异：CPU 队列 vs GPU 队列

手册 §2.3 写得很明确：

> CPU 资源分配策略是"以计算节点为单位"，GPU 资源分配策略是"以卡为单位"。
> 平台计算任务提交时计算节点的 CPU 须全部占满使用，部分占用的按全部占用计费，
> 如 hcpu48 队列的计算 CPU 核数必须为 48 的倍数。

这意味着：

- **在 CPU 队列（`hcpu40/48/64/128`）上写 `--cpus-per-task=4` 是在烧钱**
  ——你只用 4 核，但按整节点 40/48 核计费。手册的样例全是 `-n 40`、`-np 48`
  这种整节点数就是这个原因。
- **在 GPU 队列（`hgpu2p`）上按卡计费，`--cpus-per-task=4` 是合理的**，
  不存在"必须占满整节点"的问题。

本文第 4 节骨架和三份实跑脚本用的都是 `hgpu2p` + `--cpus-per-task=4`，
**在 GPU 队列上没问题**。但注意第 2 节说过"纯 CPU 任务（如 Numba 率定）
也可以占 GPU 节点跑，只是浪费一张卡"——`submit_benchmark_531*.slurm` 正是这么做的
（`-p hgpu2p`，不申请 `--gres`）。这个选择在**排队速度**上占便宜，
在**计费**上是否划算（占了 GPU 节点却不用卡）手册没有明确规定，
如果批量很大，建议先发邮件问 `hpc@hhu.edu.cn` 确认计费口径。

---

## 14. 2026-08-06 实测清单（哪些是实测，哪些仍是回忆）

当天通过 WSL ControlMaster + Git 信箱在集群上实际执行验证。**以下为实测结论**：

| # | 结论 | 对旧文档的影响 |
|---|---|---|
| 1 | `hpcbh` 是独立堡垒机，认证不在后端节点；不支持非交互 channel | **推翻**"MaxSessions 限制"的旧解释；解释了所有同步方案为何失败 |
| 2 | 网络**都通但很慢**：HTTPS TLS 握手 11s、pypi 20s。origin 已改 SSH（更快，非必需） | 先误判为"HTTPS 不通"，**已自我更正** |
| 3 | pypi **能用**，`pip download` 实测成功；conda 配了清华镜像 | 先误判为"不通"，**已自我更正** |
| 3b | **短超时探测会把"慢"读成"断"**——测网络超时至少 30s 且要测到应用层 | 方法论，新增 |
| 4 | HPC git = 1.8.3.1，`fetch origin <branch>` 静默不更新远程跟踪分支 | 新增 |
| 5 | 分区实况：另有 `hgpu4`(4卡) / `hgpu2`；`hgpu2p` 9 节点 8 空闲；全部 `TIMELIMIT=infinite` | **补全**（旧文档只有 hgpu2p/hgpu8） |
| 6 | **真坏的是 `ngu002`**（CUDA_INIT_FAILED，只认到 1 张卡，而 sinfo 报 idle）；`ngu001`/`ngu202` 等 14 个节点实跑健康 | **推翻**旧 exclude 名单；同时**推翻**本文档一度基于 sinfo 得出的"全部健康"结论 |
| 6b | **`sinfo` 不体检 GPU**，判断节点好坏只能真跑 CUDA 任务 | 方法论，新增 |
| 7 | 那批崩溃 `ExitCode=127`（command not found），是脚本问题不是硬件 | **推翻**误诊 |
| 8 | 计费 `billing=cpu 数`，按实际核数不按整节点 | 解决 13.4 节悬念 |
| 9 | 官方手册的 `si`/`sq` 别名实际不存在 | 纠正第 11 节 |
| 10 | `ssh -tt` 复用 ControlMaster 会踢掉在线用户 | 新增 |
| 11 | `nh_final` = Python 3.11.13 + torch 2.4.0，存在且完好 | 确认 |
| 12 | 存储 `/data1` 954T，已用 62%，余 364T | 新增 |
| 13 | HPC 上仓库 = `migration/reorg-v1` @ `96703ce`，78 个未提交文件 | 新增 |

**仍未实测、沿用旧经验的部分**（第一次用要自己验）：

- 铁律 1（`--mem` 报错）—— 当天没有提交作业，未复现该报错
- 铁律 2（`set -u` 杀 conda）、铁律 3（MKL）、铁律 4（CRLF）—— 未在作业中复现
  （但 CRLF 在搭 Git 信箱时被间接印证：`.gitattributes` 不强制 `eol=lf` 就会踩）
- 第 4 节骨架跑 `nh_run train` 的完整 GPU 训练流程 —— 仍无新近先例，见 4.3 节

---

## 附：可直接参考的仓库文件

| 文件 | 日期 | 可信度 | 值得抄的部分 |
|---|---|---|---|
| `docs/hpc/reference/河海大学高性能计算平台用户手册V4.1.pdf` | 2024-05 | ✅ **官方** | 平台规章、计费、登录、SLURM 命令。**只覆盖 CPU 队列，无 GPU 内容**，见第 13 节 |
| `src/xaj_global_pilot/hpc/submit_benchmark_531_repro.slurm` | 04-26 | ✅ 高 | **CPU 任务首选模板**：array 二维拆分、pre-flight 三检、跑后 metadata 协议校验、`--skip-existing` |
| `src/xaj_global_pilot/hpc/submit_benchmark_531.slurm` | 03-31 | ✅ 高 | 同上的前一版，结构一致但无 metadata 校验 |
| `src/adversarial/hpc/submit_exp1_core.slurm` | 03-11 | ✅ 中高 | **GPU 任务唯一干净先例**：`hgpu2p + --gres=gpu:1`、一维 chunk 切分、循环跑多个 attack |
| `src/adversarial/hpc/check_hpc_ready.sh` | 04-17 | ✅ 高 | 提交前六项体检，`ssh ... "bash -s" <` 远程执行 |
| `src/xaj_global_pilot/hpc/smoke_test_repro.slurm` | 04-26 | ✅ 高 | smoke test 写法 |
| `src/adversarial/hpc/submit_exp2..5*.slurm` + `submit_all.sh` | 03-11 | ✅ 中高 | 多实验并列提交 + 批量入口 |
| `src/templates/hpc/submit_template.slurm` | 早期 | ⚠️ 低 | 骨架思路可看，但含 `srun`、过时分区/时长，**别直接改它** |
| `src/static_falsification/hpc/submit_film_poc.slurm` | 04-18 | ❌ 反面 | 见 9.1。只有 config 数组取值那个写法可借鉴 |
| `src/adversarial/baseline_531/hpc/*` | 早期 | ❌ 反面 | 见 9.2。整目录不可信（`check_hpc_ready.sh` 不在此目录，不受影响） |
| `docs/hpc/HPC_WORKFLOW_FINAL.md` / `HPC_QUICK_START.md` | 早期 | ❌ 过时 | 已被本文覆盖 |
