# 交接：统一自动科研纵向 · HPC 迁移卡在沙箱 dlopen 禁令

写于 2026-08-08。本文自包含，新对话只读本文即可续接，不依赖任何特定 AI 工具的记忆或私有文件。

---

## 一、总目标与当前阶段定位

**总目标**：建一条自动化科研流水线，能自动提出并**安全**评估水文模型候选——隔离运行、独立资源监督、
可复现打分、防作弊双重复核，最终扩到 64 → 531 个 CAMELS-US 流域做正式候选搜索。

**已走到哪**：里程碑 0–4（隔离运行时 → 登记 → 开发循环 → 真实数据 → 独立监督）早已完成。
本轮完成了 64 流域数据底座、极端流域判定规则、并行聚合资源门槛、**第一个真实候选（HBV-lite）**，
并做完了一次双重独立复核。这条线**不再是零科研产出**。

**当前阶段目标**：把运行环境从本地 Windows 迁到河海大学 HPC，因为用户要求腾出本地机器。
迁移不改变科学内容，只改变执行位置。

**当前阶段在总目标中的作用**：531 流域的正式搜索必然要在集群上跑（本地不可行），
所以"能在 HPC 上跑通一个候选"是通向正式搜索的必经关口。现在卡在这一关。

---

## 二、一句话现状

数据底座与判定规则在 HPC 上已跑通并核查全过；**候选运行仍失败**，
唯一原因是沙箱禁止 `ctypes.dlopen`，而 Linux 上的依赖库在导入期间会触发它。

---

## 三、必须遵守的限制、成功标准、停止条件

### 九条红线（全程有效）

1. 禁止读取/枚举/打分封存的最终评估区间（1989-10-01 至 1999-09-30）。
2. 禁止运行 `src/fair_benchmark/score.py`。
3. 禁止跑 64/531 流域**正式搜索**。建数据底座、跑**单个已声明候选**不属于正式搜索，允许。
4. 禁止宣称任何候选超过任何基线。
5. 候选预测只能用气象强迫 + 静态属性，禁止用观测流量/真值。
6. 禁止清理/重置/覆盖/暂存/提交用户的改动；**任何 git 提交需用户明确授权**。
7. 里程碑收口必须双重独立复核：一个功能对抗式审核 + 一个从原始字节复验，两者互不通气。
8. 一切改动测试先行（先写红测试再实现）。同一问题失败 5 次必须停下问人。
9. 污染/异常产物不清理、不覆盖，留作证据。

### HPC 侧附加限制

- **不要碰 `~/neuralhydrology`**（有 78 个未提交文件）和 `~/adv531`（用户 ID05 对抗攻击任务）。
- **不要修改 `nh_final` conda 环境**，其他工作线依赖它。
- **登录节点禁止跑计算**，一律 `sbatch`。
- 信箱 `outbox/` 是所有 channel 共用的：**清理 slurm 日志必须用 `rm -f outbox/slurm_${JID}.*`**，
  绝不能用通配符 `slurm_*`，否则会删掉别人正在跑的作业日志（本轮已实际造成过这个风险）。
- 用户已明确授权：机时不用问，`sbatch` 随便用。

### 成功标准（当前阶段）

HBV-lite 在 HPC 上跑完 64 流域两协议，产出 `CANDIDATE_SUMMARY.json`，
4 个已登记运行全部 `succeeded`，独立复算的禁止访问数为 0。

### 停止条件

同一问题失败 5 次必须停下问人。**沙箱 dlopen 这个问题目前已失败 4 次**（见第六节），
下一次尝试若再失败，必须停下来让用户拍板，不得继续试。

---

## 四、已完成的有效方案与关键结论

### 4.1 64 流域数据底座（已提交 `d410fb21`）

- 流域选择用**贪心最远点法**，第 i 个只由前 i−1 个决定、与 `count` 无关，
  因此 `count=64` 的前 8 个**必然逐字等于**已冻结的 8 流域记录。实测确认为 True。
- 合格流域表原先只有散列没有路径，按散列反查定位到 `examples/06-Finetuning/531_basin_list.txt`。
- 两个构建器原先硬编码只认 8 流域，改为"必须属于一组已冻结记录"（仍硬编码，未改成从 JSON 读，
  否则篡改 JSON 无法被发现）。
- 真实 64 流域核查全过：封存区间命中 **0**、每流域 **3288 天**无缺失、
  单位换算最大绝对误差 **0.0**、27 项静态属性齐全、预测包无观测流量。

### 4.2 极端流域判定规则（已提交 `2b982f3a`）

NSE 分母是观测方差，方差集中在一两天时它衡量的不是水文技巧。三条判据，**只读验证期真值、
不读任何候选预测**，在候选运行前写定：

| 判据 | 阈值 |
|---|---|
| `zero_variance` | 方差为 0 |
| `zero_flow_fraction` | ≥ 0.5 |
| `single_day_variance_share` | ≥ 0.5 |

**真实 64 流域结果：53 标准 / 11 不稳定。** 最极端的 09430600 有 **91.9%** 的分母来自一天。
unstable 列表（顺序即记录中的顺序）：
`02300700, 08190500, 06847900, 05458000, 11151300, 06879650, 08194200, 08158810, 02102908, 09512280, 09430600`

### 4.3 并行聚合资源门槛（已提交 `2b982f3a`）

- 判"同时启动这一批的总和"，留白直接复用 v3 停机线（内存 max(1.5 GB, 4%)、磁盘 max(10 GB, 5%)），
  理由是一批任务绝不能被放行进入监督器会立刻停掉的状态。
- 并行上限 4，**明确标注为设的不是测的**；`default_max_concurrent_tasks = 1`（仍是串行）。
- **并行执行尚未接进运行器**，只有门槛与规划器。

### 4.4 第一个真实候选 HBV-lite（已提交 `d1e93d46`）

四水库（雪/土壤/上层/下层），每流域 8 参数，种子化差分进化（24 个体 × 60 代）。

三个设计点：
1. **蒸散发不用短波辐射**（Hargreaves 需大气顶辐射，代入实测短波会低估数倍）。
   改用温度季节形状缩放到静态属性 `pet_mean`，缩放系数训练期定死。
2. **预测不继承训练末状态**（reverse 协议验证期在训练期之前）。
3. 质量守恒有测试，`rel=1e-9`。

**本地 Windows 上 64 流域两协议实测结果**（`runs/unified_autoresearch/hbv_lite_64_v1`）：

| 分组 | n | mean-NSE 中位数 | 最小 | 最大 | >0 |
|---|---|---|---|---|---|
| 全部 | 64 | 0.502257 | −8.63 | 0.89 | 54 |
| standard | 53 | 0.545619 | −8.63 | 0.89 | 46 |
| unstable | 11 | 0.320272 | −4.97 | 0.54 | 8 |

耗时 8.8 分钟，监督器实测进程峰值 **0.269 GB**，505 个采样，禁止访问数 0。
**未与任何基线比较**（红线 4）。

两个衍生结论：
- 判定规则有用：不分组会把 headline 从 0.546 拉到 0.502。
- 但规则不万能：最差的 06409000（mean −8.63）**没有**被判为 unstable，它既不干旱、方差也不集中在单日。

### 4.5 双重独立复核（2026-08-07）

- 原始字节复验：**CONFIRMED_PASS**，全部数字独立重算一致。
- 功能对抗审核：**PASS WITH RESERVATIONS**——结论层干净，但三个新闸门删掉后测试全绿。
- 已修并用变异验证（9 个变异修复前绿、修复后红）：真值必须覆盖声明流域、
  `_frozen_basin_list` 补负例、两个阈值双向跨界用例、分组拒绝重复/重叠、classify 绑定冻结集。
- 文档五处夸大已改（"不可能事后调参""不可覆盖""顺序也要对""只读开发窗口的行""0.41 GB"）。

### 4.6 HPC 侧已跑通的部分

数据底座在 HPC 上重建并核查全过：64 流域、封存命中 0、`all passed: True`。
极端流域判定重跑，**53/11 划分与 Windows 上逐个流域完全一致**。

**跨平台字节不一致但内容一致**：parquet 与 JSON 的 sha256 在 Linux 与 Windows 上不同
（pyarrow 版本差异 + JSON 换行符 CRLF/LF），但内容与判定结果相同。
不要期待跨平台逐字节复现。

---

## 五、准确路径

### 本地（Windows）

| 项 | 路径 |
|---|---|
| 代码工作副本 | `G:\github\pycharm\projects\neuralhydrology\.worktrees\unified-autoresearch-vertical` |
| 分支 | `codex/unified-autoresearch-vertical`，HEAD `d1e93d46` |
| 代码包 | `src/unified_autoresearch/` |
| 测试 | `src/unified_autoresearch/tests/`（全量约 10 分钟） |
| 原始 CAMELS 档案 | `G:\github\pycharm\projects\neuralhydrology\data\camels_us`（**主仓，不在 worktree 内**） |
| 冻结静态表 | `src/fair_benchmark/frozen/bundle/track0_statics.csv`，sha256 `085e8b5e0e56b42bfe7e6d012ebb6f2f56681059b60c61c04b835b207864a1f2` |
| 合格流域表 | `examples/06-Finetuning/531_basin_list.txt`，sha256 `cd2d3d466aca736fcd32042d2b0bde3d0b58e42ba37fe552d97480bd914b9e85` |
| 64 流域冻结记录 | `src/unified_autoresearch/selection/development_basins_64_v1.json`，sha256 `3d75df6cfce527b8f6580a9dcfe0eacccb65c8bd7aae987ce23ead462ab00e53` |
| 本地 64 流域数据包 | `runs/unified_autoresearch/development_packages_real_64_v1`（`runs/` 被 gitignore） |
| 本地候选运行产物 | `runs/unified_autoresearch/hbv_lite_64_v1` |
| 预注册判定记录 | `runs/unified_autoresearch/BASIN_ELIGIBILITY_64_v1.json` |

### HPC

| 项 | 路径 |
|---|---|
| 主机 / 用户 | `hpcbh.hhu.edu.cn` / `sunyiq`，登录节点 `login4` |
| 本任务工作区 | `~/autoresearch64` = `/data1/home/sunyiq/autoresearch64`（**本轮新建，与其他工作线隔离**） |
| 虚拟环境 | `~/autoresearch64/.venv`（numpy 1.26.4 / pandas 2.2.3 / pyarrow 17.0.0 / psutil / pytest） |
| HPC 侧数据包 | `~/autoresearch64/runs/unified_autoresearch/development_packages_real_64_hpc` |
| HPC 侧判定记录 | `~/autoresearch64/runs/unified_autoresearch/BASIN_ELIGIBILITY_64_HPC.json` |
| 失败的候选运行 | `~/autoresearch64/runs/unified_autoresearch/hbv_lite_64_hpc_v4`（v1–v3 为更早的失败，保留） |
| CAMELS 档案 | `~/neuralhydrology/data/camels_us`（**只读引用，不可修改该仓库**） |
| 共享 conda 环境 | `nh_final`（Python 3.11.13，numpy 2.3.3 / pandas 2.3.2 / pyarrow 20.0.0 / torch 2.4.0）**不可改** |

### 信箱通道（本地与 HPC 之间唯一自动化通道）

| 项 | 值 |
|---|---|
| 本地 worktree | `G:\github\pycharm\projects\neuralhydrology\.worktrees\hpc-mailbox`，分支 `hpc-mailbox` |
| 本任务 channel | `autoresearch-64`（已在 `CHANNELS.md` 登记） |
| 命令文件 | `inbox/autoresearch-64/cmd.sh`，序号 `inbox/autoresearch-64/seq` |
| 结果 | `outbox/autoresearch-64/result_<seq>.txt` |
| 已用到的最大 seq | **17** |
| 操作手册 | `docs/hpc/HPC_AGENT_GUIDE.md`（本轮已补三处实测坑） |

### 证据文档（全在 `src/unified_autoresearch/evidence/`）

- `SCALEUP64_DATA_BASE_20260806.md` — 64 流域底座
- `JUDGEMENT_AND_PARALLEL_DESIGN_20260806.md` — 判定规则 + 聚合门槛
- `FIRST_REAL_CANDIDATE_HBV_LITE_20260807.md` — 第一个真实候选
- `DUAL_REVIEW_20260807.md` — 双重独立复核全记录
- `MILESTONE4_SCALEUP_CHECKLIST_64_531.md` — 扩规模清单
- 本文

---

## 六、已确认的问题与已排除的问题

### 6.1 当前唯一阻塞：沙箱禁止 `ctypes.dlopen`（**已确认，未解决**）

候选子进程在"声明依赖初始化"阶段被拒：

```
{"decision":"deny","event":"ctypes.dlopen","reason":"candidate dynamic local library loading is disabled"}
```

事件序列：`import ctypes` → `import _ctypes` → `deny ctypes.dlopen`。
候选退出码 2，`output_contract` 报 `model_artifacts` 缺失。
`dependency_preflight_decision` 与 `resource_preflight_decision` 均为 `launch`——**闸门本身是通过的**。

**已排除的错误假设（重要）**：曾判断"numpy 2.x 才调 dlopen，退回 numpy 1.26.4 即可绕过"。
**该判断错误**。当时的探测脚本监控的是 `ctypes.CDLL`，而沙箱拦的是更底层的 `ctypes.dlopen`
审计事件，两者不是一回事。换成 numpy 1.26.4 后**同一条禁令照样触发**（seq=16 实测）。
**不要再沿这条思路试版本。**

**尚未确认**：具体是 numpy / pandas / pyarrow 中的哪一个触发 dlopen，以及为什么本地 Windows
同样版本的 numpy 1.26.4 不触发。**未验证**，需要在沙箱下逐个 import 二分定位。

### 6.2 已确认并已解决

| 问题 | 证据 | 处置 |
|---|---|---|
| `git status --porcelain=v1` 在 git 1.8.3.1 上退出码 129 | HPC git 版本 1.8.3.1，`=v1` 是 git 2.11 才有的语法 | 三处调用点改为 `--porcelain`；实测两种写法输出 sha256 逐字节相同，旧产物指纹不受影响 |
| 打分器硬编码只认 8 流域 | `scoring.py` 第 105/201/245 行 | 改为接受任一冻结流域集；8 流域旧测试全绿 |
| 打分器改动是否破坏冻结产物复现 | 用现行代码重算 8 份冻结评分报告 | **8/8 逐字段完全相同** |
| 三个新闸门删掉后测试全绿 | 24 个变异中 6 个抓不到 | 补 10 条负例，逐个变异验证会红 |
| 标定测试恒真 | `GENERATIONS=0` 时测试仍绿（初始种群随机个体即可满足） | 改为记录 `initial_population_objective`，断言演化必须严格超过它 |

### 6.3 已确认无法在 HPC 上做到（**不要再试**）

| 尝试 | 结果 | 证据 |
|---|---|---|
| `conda create` 新环境 | **三种写法全失败** | 默认写法插件报错；`CONDA_NO_PLUGINS=true` 报 libmamba 未识别；再加 `--solver=classic` 仍 `unexpected error`。conda 23.10.0 本身坏的 |
| 安装 `pandas==2.3.3` | **不可能** | 该版本在 pypi 上不存在（最高 2.3.2），原始契约只能从 conda 渠道满足 |
| `PYTHONPATH` 注入依赖 | **被闸门正确拒绝** | 依赖预检故意用"干净解释器"解析版本，就是为了不认路径注入。这是反伪装设计，不是 bug |

**已验证无副作用**：三次失败的 conda 创建**没留任何残骸**（envs 目录干净、`.condarc` 未改、
`nh_final` 完好）；`~/neuralhydrology` HEAD 与脏文件数与开工前一致；`~/adv531` 未被触碰。

---

## 七、未完成事项、阻塞与最优先下一步

### 最优先：定位并处置 dlopen 阻塞

**第一步（诊断，无风险）**：在沙箱下二分定位，确认到底哪个库、哪一行触发 `ctypes.dlopen`。
把 `numpy` / `pandas` / `pyarrow` 分别作为唯一声明依赖各跑一次最小候选，看哪个被拒。

**第二步（需要用户拍板的设计决策）**：确认之后只有两条路，二者都影响安全属性，**必须让用户选**：

- **A**：把 dlopen 禁令收窄为"仅在声明依赖初始化阶段允许"。访问日志里已经存在
  `reason: "declared dependency initialization"` 这个阶段标记，所以技术上做得到，
  且语义自洽。但它确实放宽了一条真实的隔离防线，下一次对抗审核会重点攻击这里。
- **B**：维持禁令，接受**候选运行只能在本地 Windows 跑**，HPC 只用于数据底座与判定。
  与"腾出本地机器"的目标冲突。

**不要自行选择 A 并悄悄实施。** 这是安全属性的取舍，超出实现层。

### 其他未完成

| 事项 | 状态 |
|---|---|
| 本地 7 个文件未提交 | 见第八节列表，**需用户授权才能提交** |
| HPC 上全量测试 10 条红 | 全部是"启动候选子进程"的测试，与 dlopen 同源；解决 dlopen 后应一并转绿（**未验证**） |
| 并行执行接进运行器 | 未做，只有门槛与规划器 |
| 并行上限 4 在真实并行负载下检验 | 未做 |
| 5 条软链接逃逸反向测试 | 本地 Windows 无权限跳过；**HPC 上是 Linux，本应能跑**，但当前 HPC 跳过数是 8 不是 5，差异原因**未查** |
| 531 流域底座 | 未建。531 = 全部合格流域，选择步骤退化为全选，只剩机械构建；按 64 的实测线性外推约 92 秒 |
| `scoring.py` 对零方差流域抛异常（会连坐毁掉其余流域的分） | 未改，在冻结产物路径上，需单独拍板 |
| 06409000 这类"判定规则抓不到但确实很差"的流域 | 未分析 |
| 换指标（KGE、对数流量）能否救那 11 个流域 | 未测 |
| 闸门之间未互相绑定（跨数据包混用、手写评分报告可被接受） | 复核 P4 后半，未修 |
| `expected_package_manifest_sha256` 在所有调用点都是现读现算 | 复核 P5，文案上是闸门实际是恒等式，需重新设计 |

### 已建立的自动检查

已创建一个云端定时任务，**每 2 小时**检查 `autoresearch-64` 通道最新结果并汇报（纯只读）。
它比对 `inbox/autoresearch-64/seq` 与最大的 `outbox/autoresearch-64/result_N.txt`，
落后即判定"仍在运行"。它接触不到 HPC，只读 GitHub 上的 `hpc-mailbox` 分支。

---

## 八、新对话开场应先做的检查

### 先读（按序）

1. 本文
2. `src/unified_autoresearch/evidence/DUAL_REVIEW_20260807.md`（复核发现与未闭合项）
3. `docs/hpc/HPC_AGENT_GUIDE.md`（信箱操作与本轮补的三处坑）
4. `src/unified_autoresearch/runtime/dependencies.py` 与 `runtime/runner.py`（沙箱如何构造子进程环境）

### 开场自检命令

```bash
cd "G:/github/pycharm/projects/neuralhydrology/.worktrees/unified-autoresearch-vertical"
git log -1 --format="%h %s"        # 应为 d1e93d46
git status --porcelain             # 应为下列 7 项
```

未提交的 7 项（本轮工作成果，勿丢）：

```
 M src/unified_autoresearch/candidates/catalog.py
 M src/unified_autoresearch/evidence_package.py
 M src/unified_autoresearch/registry/fingerprint.py
 M src/unified_autoresearch/runtime/orchestrator.py
 M src/unified_autoresearch/scripts/run_single_candidate.py
?? src/unified_autoresearch/tests/test_frozen_dependency_sets.py
?? src/unified_autoresearch/evidence/HPC_MIGRATION_20260808.md   （来源不明，非本轮所写，勿动）
```

### 检查信箱通道是否活着

```bash
cd "G:/github/pycharm/projects/neuralhydrology/.worktrees/hpc-mailbox"
git fetch origin "+refs/heads/hpc-mailbox:refs/remotes/origin/hpc-mailbox" -q
git show origin/hpc-mailbox:inbox/autoresearch-64/seq
git ls-tree -r --name-only origin/hpc-mailbox | grep "outbox/autoresearch-64/"
```

**注意**：轮询时一律用 `origin/hpc-mailbox` 而不是 `FETCH_HEAD`，否则 `git pull --rebase`
会报 `fatal: Cannot rebase onto multiple branches`（此时提交多半已成功，先 `git log -1` 确认）。

### 本地全量测试（约 10 分钟）

```bash
python -m pytest src/unified_autoresearch/tests -q
```

上次本地基线：**263 通过 / 5 跳过 / 0 失败**。本轮之后新增了
`test_frozen_dependency_sets.py`（10 条），因此新基线**未验证**，预计 273 通过。
