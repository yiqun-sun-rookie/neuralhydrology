# 历史连续多尺度气象模型版本09严格嵌套与正式训练阶段实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在531个冻结流域上先完成种子100的30轮逐更新严格嵌套复现，再以完全冻结的批次、损失、优化器和资源规则一次性训练经典近期、同参数量近期控制、连续历史候选各八个随机数，共24次主训练。

**Architecture:** 正式训练只重载已独立审核并封存的输入目录。经典近期模型、停用历史路径模型和369单元同参数量控制只读取270天近期序列；连续历史候选额外读取270至3,561天滞后的120个连续对数分箱。严格嵌套在同一进程、同一批次和同一随机数状态下逐更新比较经典近期模型与停用历史路径模型；主训练在三个模型族之间共享完全相同的样本顺序、30轮训练和八个固定随机数，但每次运行使用独立进程和原子输出目录。

**Tech Stack:** Python 3.11、PyTorch、NumPy、只读 NumPy 内存映射、pandas、psutil、pytest、Git、SHA-256。

## Global Constraints

- 本计划不授权实现、训练、正式预测或评分。只有用户另行批准执行本计划后，才允许写训练代码和合成测试。
- 正式输入必须已经位于
  `results/26_historical_band_experts/formal_v09/input_attempt_01`，具有通过的内部
  `seal.json`、目录外输入产物审核报告
  `input_attempt_01.external_audit.json`和目录外可信训练目标来源审核报告
  `input_attempt_01.trusted_source_external_audit.json`。训练授权必须绑定这三个文件的
  SHA-256；任一报告缺失、状态不通过或哈希漂移都立即停止。
- 不修改`src/fair_benchmark/frozen/`、`src/fair_benchmark/score.py`、正式流域列表、
  正式切分、评分门槛或版本09科学协议。
- 训练只允许Maurer五个命名气象变量、27项静态属性和1999-10-01至2008-09-30训练目标。
  正式评估期观测、由观测计算的水文属性、其他气象产品和其他模型输出不得进入任何训练进程。
- 训练目标只作监督和训练期损失权重计算，不得拼接到模型输入、历史状态或静态属性。
- 固定训练样本数为1,745,928；每轮6,821次更新，其中前6,820批各256个样本，最后一批8个样本；
  30轮合计204,630次更新。不得丢弃最后一批、限制批次数或用验证期早停。
- 损失与冻结经典配置一致：在全局训练期归一化流量上计算逐样本平方误差，并乘以
  `1 / (raw_per_basin_training_q_std + 0.1) ** 2`后取均值。流域标准差只用训练期原始流量计算。
- Adam、梯度范数裁剪1.0、遗忘门偏置5.0、输出丢弃率0.4、学习率
  1–10轮为0.001、11–20轮为0.0005、21–30轮为0.0001。
- 只把第30轮检查点用于后续正式预测；第10轮和第20轮检查点只用于中断诊断和审计，不得用于选择。
- 主训练全部24次结束前不得计算验证指标、正式指标、分支消融或根据损失选择模型、随机数或检查点。
- 每次训练使用独立进程，禁止并行运行两个正式训练进程。
- 长任务启动可用物理内存必须达到
  `max(12 GiB, 机器总物理内存的40%)`；当前机器对应硬门为12.68 GiB。运行中必须保留
  `max(8 GiB, 总物理内存的25%)`，单进程驻留内存不超过
  `min(6 GiB, 总物理内存的20%)`，单次计划分配不超过
  `min(512 MiB, 总物理内存的2%)`。
- 每个批次前重新采样物理内存。低于运行保留量、进程驻留内存超限、出现非有限值或输入哈希漂移时，
  当前运行写出失败收据后停止整个阶段；不得自动重试。
- 正式运行输出采用同父目录`.building`临时目录，完成审核后才原子改名。最终目录、临时目录或失败目录
  任何一个已存在时都拒绝启动。
- 严格嵌套和24次主训练分别需要单独、一次性的直接授权。一个授权在首次进程启动时即消耗；
  通过、失败、手动中断或异常退出都不得复用。
- 本阶段证明的是新正式管线中“停用历史路径模型”和“干净经典近期模型”的逐元素嵌套关系；
  不声称重现2019式历史八随机数检查点的训练轨迹。历史八随机数集合仍只作为正式评分服务中的冻结基准。

---

### Task 1: 将阶段授权扩展为严格嵌套和主训练两个精确作用域

**Files:**
- Modify after execution approval: `src/26_historical_band_experts/stage_authorization_v09.py`
- Modify after execution approval: `src/26_historical_band_experts/launch_gate_v09.py`
- Test: `src/26_historical_band_experts/tests/test_stage_authorization_v09.py`
- Test: `src/26_historical_band_experts/tests/test_launch_gate_v09.py`
- Create only after strict-run approval:
  `src/26_historical_band_experts/configs/formal_v09_strict_nesting_authorization.json`
- Create only after main-training approval:
  `src/26_historical_band_experts/configs/formal_v09_training_authorization.json`

**Interfaces:**
- `validate_stage_authorization_v09(receipt, *, action, scope, protocol_sha256, input_seal_sha256, input_external_audit_sha256, trusted_source_external_audit_sha256, executable_tree_sha256) -> dict`
- `consume_stage_authorization_v09(receipt, *, consumption_path) -> dict`
- `assert_launch_allowed_v09(config, *, action, estimated_peak_bytes, snapshot=None, stage_authorization=None, authorization_scope=None) -> dict`

- [ ] **Step 1: 写作用域和一次性消费失败测试**

测试必须覆盖：

1. 输入阶段收据仍只能授权正式输入生成；
2. 严格嵌套收据只允许`action="training"`、`scope="R09-NEST-S100"`；
3. 主训练收据只允许下列24个运行标识，不能包含严格嵌套或正式预测；
4. 协议哈希、输入封存哈希、任一输入外部审核报告哈希、可执行源码树哈希、输出根目录或批准文本
   任一漂移都拒绝；
5. 消费收据已经存在时拒绝第二次启动；
6. 创建消费收据必须使用独占创建，不能先覆盖再检查；
7. 内存门发生在消费收据之前；内存通过后、正式训练子进程启动前原子写入消费收据。

严格嵌套直接批准文本固定为：

```text
批准版本09严格嵌套训练阶段；仅授权R09-NEST种子100的一次531流域30轮训练，不批准主实验训练、正式预测或评分。
```

UTF-8、无末尾换行的SHA-256固定为：

```text
93cefe8b905dbb5dcfe336a79b30eb5ae66254fc16d4f7d5dd727a423b37b6dd
```

主训练直接批准文本固定为：

```text
批准版本09正式主训练阶段；仅授权B09-CLASSIC、B09-CAPACITY和E09-CONTINUOUS各八个固定随机数的一次训练，不批准正式预测或评分。
```

UTF-8、无末尾换行的SHA-256固定为：

```text
ba2ad43c7e363729386b53e0ffaa65c39ad73fd6b82d5a92aa3e95a506a76623
```

- [ ] **Step 2: 运行授权测试并确认失败**

Run:

```powershell
pytest src/26_historical_band_experts/tests/test_stage_authorization_v09.py `
  src/26_historical_band_experts/tests/test_launch_gate_v09.py -q
```

Expected: 新增严格嵌套和主训练作用域测试失败；既有输入收据测试保持通过。

- [ ] **Step 3: 实现多阶段精确授权**

授权模式不得使用“任意训练均允许”的布尔值。验证器使用动作、作用域、批准文本哈希、协议哈希、
输入封存哈希、输入产物外部审核报告哈希、可信训练目标来源外部审核报告哈希、可执行源码树哈希、
固定运行集合和固定输出根目录的完整相等比较。

严格嵌套收据固定：

- `receipt_id="A09-NEST-01"`
- `attempt_id="strict_nesting_attempt_01"`
- `action="training"`
- `scope="R09-NEST-S100"`
- `maximum_attempts=1`
- `allowed_runs=["R09-NEST-S100"]`
- `formal_prediction_generation_authorized=false`
- `official_scoring_authorized=false`

主训练收据固定：

- `receipt_id="A09-TRAIN-01"`
- `attempt_id="training_attempt_01"`
- `action="training"`
- `scope="FORMAL-MAIN-24"`
- `maximum_attempts=1`
- `allowed_runs`与Task 5的24项顺序完全一致；
- `formal_prediction_generation_authorized=false`
- `official_scoring_authorized=false`

收据还必须保存直接批准所在任务标识、批准时间、批准文本和其SHA-256。批准发生后才把实际
输入封存哈希、两个目录外输入审核报告哈希、可执行源码树哈希和Git提交写入收据；禁止预先生成收据。
可执行源码树只包含实际运行的Python文件和科学配置，不包含授权收据、审计文档或结果目录，
避免收据把自身纳入哈希形成循环。

- [ ] **Step 4: 实现原子消费收据**

消费路径固定为：

- 严格嵌套：
  `results/26_historical_band_experts/formal_v09/strict_nesting_authorization_consumed.json`
- 主训练：
  `results/26_historical_band_experts/formal_v09/training_authorization_consumed.json`

文件以独占创建模式写入，内容包括授权收据SHA-256、启动时间、主机、进程标识、Git提交、
工作区树哈希、输入封存哈希、两个输入审核报告哈希和启动内存快照。消费文件一旦存在，
任何入口都拒绝同一阶段重启。

- [ ] **Step 5: 运行授权和启动门测试**

Run:

```powershell
pytest src/26_historical_band_experts/tests/test_stage_authorization_v09.py `
  src/26_historical_band_experts/tests/test_launch_gate_v09.py -q
```

Expected: PASS。

- [ ] **Step 6: 提交授权门实现**

```powershell
git add src/26_historical_band_experts/stage_authorization_v09.py `
  src/26_historical_band_experts/launch_gate_v09.py `
  src/26_historical_band_experts/tests/test_stage_authorization_v09.py `
  src/26_historical_band_experts/tests/test_launch_gate_v09.py
git commit -m "Feat: Scope formal v09 training authorization"
```

---

### Task 2: 实现只读训练数据、固定样本顺序和经典损失

**Files:**
- Create after execution approval: `src/26_historical_band_experts/formal_training_data_v09.py`
- Test: `src/26_historical_band_experts/tests/test_formal_training_data_v09.py`
- Reuse: `src/26_historical_band_experts/bands_formal_v09.py`
- Reuse after input stage:
  `src/26_historical_band_experts/formal_input_v09.py`

**Interfaces:**
- `load_sealed_training_inputs_v09(input_root, protocol_path) -> FormalTrainingInputsV09`
- `ordered_training_keys_v09(inputs) -> tuple[np.ndarray, np.ndarray]`
- `epoch_order_v09(sample_count, *, seed, epoch) -> np.ndarray`
- `load_training_batch_v09(inputs, basin_indices, target_indices, *, variant, device, gate) -> TrainingBatchV09`
- `masked_nse_training_loss_v09(prediction, target, raw_per_basin_std) -> torch.Tensor`

- [ ] **Step 1: 写数据边界、排序和损失失败测试**

测试必须证明：

- 输入目录以只读方式打开；缺失`seal.json`、输入产物外部审核、可信训练目标来源外部审核，
  任一审核状态不通过，或任一授权绑定哈希漂移都拒绝；
- 训练键严格按冻结流域顺序、再按日期1999-10-01至2008-09-30生成，共1,745,928项；
- 每轮使用独立CPU `torch.Generator`和固定种子派生规则生成一个完整排列，不重复、不遗漏；
- 相同随机数和轮次产生相同排列，不同轮次产生不同排列；
- 经典、停用历史和369单元控制只读取270天近期切片；
- 连续历史候选读取一个不超过256样本的3,562天窗口，并生成120个历史分箱；
- 所有模型收到完全相同的静态属性、目标和训练键；
- 损失与`neuralhydrology.training.loss.MaskedNSELoss(eps=0.1)`在构造样本上逐元素一致；
- 训练目标列不能进入动态输入或静态输入；
- 试图读取正式评估观测、原始流量目录或水文签名文件时失败；
- 批量大小超过256、一次密集物化全部窗口或计划分配超过硬门时失败。

- [ ] **Step 2: 运行训练数据测试并确认失败**

Run:

```powershell
pytest src/26_historical_band_experts/tests/test_formal_training_data_v09.py -q
```

Expected: FAIL，原因是`formal_training_data_v09`尚不存在。

- [ ] **Step 3: 实现只读重载和固定训练键**

`FormalTrainingInputsV09`只保留只读内存映射、冻结流域元数据、训练期目标矩阵、训练期归一化统计和
哈希清单，不持有完整3,562天窗口副本。训练键由531个流域乘3,288个训练日期直接构造，不从目标值、
模型结果或运行状态筛选。

样本排列采用独立于模型和丢弃层随机数流的CPU生成器。派生规则固定为：

```text
epoch_seed = seed * 1_000_003 + epoch
```

每轮执行一次`torch.randperm(1_745_928, generator=epoch_generator)`。每轮排列的原始
`int64`字节SHA-256写入运行清单；三个模型族同一随机数和轮次必须得到相同哈希。

- [ ] **Step 4: 实现分模型批量读取**

近期模型直接从只读气象内存映射复制`[batch,270,5]`。连续历史候选调用
`gather_causal_windows_v09()`得到`[batch,3562,5]`，再调用`split_windows_v09()`得到
`recent=[batch,270,5]`和`history=[batch,120,7]`。每个复制或转设备操作前调用内存门。

目标使用输入封存中的全局训练期中心和尺度归一化；损失权重使用每流域训练期原始流量标准差。
任何标准差非有限或小于等于0时停止，不临时替换。

- [ ] **Step 5: 运行训练数据和既有分箱测试**

Run:

```powershell
pytest src/26_historical_band_experts/tests/test_formal_training_data_v09.py `
  src/26_historical_band_experts/tests/test_bands_formal_v09.py -q
```

Expected: PASS。

- [ ] **Step 6: 提交训练数据实现**

```powershell
git add src/26_historical_band_experts/formal_training_data_v09.py `
  src/26_historical_band_experts/tests/test_formal_training_data_v09.py
git commit -m "Feat: Add sealed formal v09 training batches"
```

---

### Task 3: 实现531流域、30轮、204,630步严格嵌套训练

**Files:**
- Create after execution approval: `src/26_historical_band_experts/train_strict_formal_v09.py`
- Test: `src/26_historical_band_experts/tests/test_train_strict_formal_v09.py`
- Reuse: `src/26_historical_band_experts/models_formal_v09.py`
- Reuse: `src/26_historical_band_experts/strict_nesting_formal_v09.py`
- Reuse: `src/26_historical_band_experts/formal_training_data_v09.py`

**Interfaces:**
- `run_strict_nesting_v09(inputs, *, seed, output_dir, device, authorization, gate) -> dict`
- `stream_training_prediction_digest_v09(model, inputs, *, batch_size, gate) -> dict`

- [ ] **Step 1: 写严格嵌套失败测试**

合成小数据测试必须在下列任一差异的第一步失败：

- 初始活动参数名称、顺序、形状或值；
- 批次流域索引、目标日期索引或排列哈希；
- 丢弃层前后的PyTorch CPU或图形处理器随机数状态；
- 预测、损失、未裁剪梯度、梯度范数、已裁剪梯度；
- Adam步数、动量、方差、参数组学习率；
- 更新后活动参数；
- 训练期流式最终预测。

还必须证明停用历史路径的历史编码器和两个门参数既不执行、也不进入优化器。

- [ ] **Step 2: 运行严格训练测试并确认失败**

Run:

```powershell
pytest src/26_historical_band_experts/tests/test_train_strict_formal_v09.py -q
```

Expected: FAIL，原因是严格训练入口尚不存在。

- [ ] **Step 3: 实现逐更新锁步训练**

固定种子100。经典模型和停用历史模型分别建立Adam，但活动参数序列在训练前逐元素相等。
每个批次执行`lockstep_train_step_v09()`；每一步都执行零绝对容差、零相对容差断言。

每轮记录：

- 轮次、学习率、6,821次更新和累计更新数；
- 样本排列SHA-256；
- 损失的有限性和均值，只作运行完整性检查；
- 经典和嵌套活动参数、Adam状态、CPU随机数状态、图形处理器随机数状态的滚动SHA-256；
- 主机内存最小可用量、进程最大驻留内存和图形处理器峰值显存。

第10、20、30轮保存一对检查点；保存后立即重载并重算哈希。训练完成后，对全部1,745,928个
训练键流式执行无丢弃预测，不写观测、不算Nash-Sutcliffe模型效率系数。按冻结键顺序保存一份经典模型
`float32`参考预测数组；停用历史模型不重复保存相同数组，只记录其预测字节流哈希和逐块最大绝对差。
通过条件为两个预测字节流哈希相同且最大差严格等于0。

- [ ] **Step 4: 实现严格输出原子封存**

临时目录固定：

```text
results/26_historical_band_experts/formal_v09/strict_nesting/seed_100.building
```

最终目录固定：

```text
results/26_historical_band_experts/formal_v09/strict_nesting/seed_100
```

最终目录至少包含：

- `config_snapshot.json`
- `authorization_snapshot.json`
- `environment.json`
- `epoch_trace.csv`
- `batch_order.sha256`
- `checkpoints/epoch010.pt`
- `checkpoints/epoch020.pt`
- `checkpoints/epoch030.pt`
- `training_predictions_classic.float32.npy`
- `training_prediction_digest.json`
- `data_access.json`
- `run_manifest.json`
- `seal.json`

`seal.json`是最后写入文件，包含目录中其余全部文件的固定排序哈希树。写出后以只读方式重载，
通过才把`.building`原子改名为最终目录。

- [ ] **Step 5: 运行严格训练测试**

Run:

```powershell
pytest src/26_historical_band_experts/tests/test_train_strict_formal_v09.py `
  src/26_historical_band_experts/tests/test_strict_nesting_formal_v09.py `
  src/26_historical_band_experts/tests/test_models_formal_v09.py -q
```

Expected: PASS。

- [ ] **Step 6: 提交严格训练实现**

```powershell
git add src/26_historical_band_experts/train_strict_formal_v09.py `
  src/26_historical_band_experts/tests/test_train_strict_formal_v09.py
git commit -m "Feat: Add full formal v09 lockstep training"
```

---

### Task 4: 实现独立严格嵌套重放审核

**Files:**
- Create after execution approval: `src/26_historical_band_experts/audit_strict_formal_v09.py`
- Test: `src/26_historical_band_experts/tests/test_audit_strict_formal_v09.py`
- Generated, not tracked:
  `results/26_historical_band_experts/formal_v09/strict_nesting_seed_100.external_audit.json`

**Interfaces:**
- `audit_strict_nesting_v09(input_root, strict_root, protocol_path, report_path, device) -> dict`

- [ ] **Step 1: 写独立审核反驳测试**

审核器必须拒绝：

- 审核报告位于封存严格运行目录内部；
- 检查点、批次顺序、环境、源码或输入任一哈希漂移；
- 训练轮数不是30或更新数不是204,630；
- 任一步的零容差标志缺失；
- 第30轮经典和嵌套活动参数或Adam状态不完全相同；
- 历史模块进入优化器或出现梯度；
- 训练期预测摘要最大差不为0；
- 独立进程重算的固定训练键预测与封存预测字节流最大绝对差超过`1e-6`。

- [ ] **Step 2: 运行审核测试并确认失败**

Run:

```powershell
pytest src/26_historical_band_experts/tests/test_audit_strict_formal_v09.py -q
```

Expected: FAIL，原因是审核器尚不存在。

- [ ] **Step 3: 实现只读独立审核**

审核器从第30轮检查点分别重建经典和停用历史模型，使用一个新进程和独立加载的只读输入，
按冻结训练键流式重算全部训练期预测，并与封存的
`training_predictions_classic.float32.npy`逐块比较。它验证：

- 同一审核进程内经典与停用历史预测最大差严格为0；
- 两个重放模型与封存经典参考数组的最大绝对差均不超过`1e-6`、相对容差为0；
- 预测键覆盖531个流域、每流域3,288个训练日期；
- 没有正式评估观测访问、正式预测或评分调用。

审核报告只写在严格运行目录之外，且输出路径预先不存在。

- [ ] **Step 4: 运行审核测试**

Run:

```powershell
pytest src/26_historical_band_experts/tests/test_audit_strict_formal_v09.py -q
```

Expected: PASS。

- [ ] **Step 5: 提交严格审核器**

```powershell
git add src/26_historical_band_experts/audit_strict_formal_v09.py `
  src/26_historical_band_experts/tests/test_audit_strict_formal_v09.py
git commit -m "Feat: Add independent formal v09 nesting audit"
```

---

### Task 5: 冻结24次主训练顺序并实现单运行训练器

**Files:**
- Create after execution approval:
  `src/26_historical_band_experts/configs/formal_v09_run_order.json`
- Create after execution approval: `src/26_historical_band_experts/train_formal_v09.py`
- Create after execution approval: `src/26_historical_band_experts/run_formal_training_v09.py`
- Test: `src/26_historical_band_experts/tests/test_train_formal_v09.py`
- Test: `src/26_historical_band_experts/tests/test_run_formal_training_v09.py`

**Interfaces:**
- `validate_run_order_v09(order) -> tuple[FormalRunSpecV09, ...]`
- `run_training_v09(inputs, *, variant, seed, output_dir, device, gate) -> dict`
- `run_training_suite_v09(protocol_path, authorization_path, run_order_path, input_root, formal_root, device) -> dict`

- [ ] **Step 1: 写24项顺序和单运行失败测试**

主训练顺序固定如下；每行从左到右依次执行：

| 随机数 | 第1个 | 第2个 | 第3个 |
|---:|---|---|---|
| 100 | B09-CLASSIC | B09-CAPACITY | E09-CONTINUOUS |
| 200 | B09-CLASSIC | E09-CONTINUOUS | B09-CAPACITY |
| 300 | B09-CAPACITY | B09-CLASSIC | E09-CONTINUOUS |
| 400 | B09-CAPACITY | E09-CONTINUOUS | B09-CLASSIC |
| 500 | E09-CONTINUOUS | B09-CLASSIC | B09-CAPACITY |
| 600 | E09-CONTINUOUS | B09-CAPACITY | B09-CLASSIC |
| 700 | B09-CLASSIC | B09-CAPACITY | E09-CONTINUOUS |
| 800 | B09-CAPACITY | E09-CONTINUOUS | B09-CLASSIC |

验证器必须证明恰有24项、三个模型族各8项、八个随机数各出现3次、没有重复运行标识，
且顺序与表格逐项相同。任何交换都失败。

单运行测试还要证明：

- 只允许协议中的模型和随机数；
- 参数量分别为297,217、595,198、596,737；
- 轮数、更新数、学习率、批次哈希、损失、梯度裁剪和检查点周期固定；
- 连续历史模型第3步前历史编码器必须出现非零有限梯度；
- 历史门初值严格为0，但训练过程中允许学习；
- 不计算验证指标，不读取正式评估观测，不生成正式期预测；
- 同一随机数的三个模型每轮排列哈希完全相同；
- 输出目录存在、哈希漂移、非有限损失或内存越界时立即失败。

- [ ] **Step 2: 运行主训练测试并确认失败**

Run:

```powershell
pytest src/26_historical_band_experts/tests/test_train_formal_v09.py `
  src/26_historical_band_experts/tests/test_run_formal_training_v09.py -q
```

Expected: FAIL，原因是主训练模块尚不存在。

- [ ] **Step 3: 实现单运行训练器**

每个运行在独立进程中执行以下固定顺序：

1. 验证协议、配置、收据、输入封存、源码树、Git工作区和内存；
2. 固定Python、NumPy、PyTorch CPU和图形处理器随机数；
3. 构建模型并验证参数量；
4. 用独立CPU生成器生成每轮排列；
5. 执行30轮、204,630次Adam更新；
6. 在第10、20、30轮原子保存检查点；
7. 重载第30轮检查点并验证模型、优化器、随机数和哈希；
8. 写`seal.json`并原子提交运行目录。

图形处理器运行前用同一模型、最大批量和同一窗口形状执行一次完整前向、反向和优化器步的资源预检。
正式运行前可用图形处理器内存必须至少达到
`max(预检峰值的2倍, 预检峰值加2 GiB)`；该门只保护资源，不允许改变批量大小或科学配置。

- [ ] **Step 4: 实现串行编排器**

编排器先验证全部24个最终目录、`.building`目录和失败目录均不存在，再消费主训练授权。
它逐项启动子进程，等待退出并只做运行完整性审核。任一子进程非零退出、封存失败或资源门失败时，
停止后续运行并写`training_attempt_01.failure.json`；不删除已完成运行，不自动重试。

每次子进程退出后必须释放模型、关闭内存映射并确认没有残留正式训练进程，才允许启动下一项。
编排器不读取训练目标值、模型预测或性能指标。

- [ ] **Step 5: 运行主训练测试**

Run:

```powershell
pytest src/26_historical_band_experts/tests/test_train_formal_v09.py `
  src/26_historical_band_experts/tests/test_run_formal_training_v09.py -q
```

Expected: PASS。

- [ ] **Step 6: 提交主训练实现和顺序**

```powershell
git add src/26_historical_band_experts/configs/formal_v09_run_order.json `
  src/26_historical_band_experts/train_formal_v09.py `
  src/26_historical_band_experts/run_formal_training_v09.py `
  src/26_historical_band_experts/tests/test_train_formal_v09.py `
  src/26_historical_band_experts/tests/test_run_formal_training_v09.py
git commit -m "Feat: Add serial formal v09 training suite"
```

---

### Task 6: 实现24次训练的独立完整性审核和总封存

**Files:**
- Create after execution approval: `src/26_historical_band_experts/audit_formal_training_v09.py`
- Test: `src/26_historical_band_experts/tests/test_audit_formal_training_v09.py`
- Generated, not tracked:
  `results/26_historical_band_experts/formal_v09/training_external_audit.json`
- Generated, not tracked:
  `results/26_historical_band_experts/formal_v09/training_seal.json`

**Interfaces:**
- `audit_training_run_v09(run_root, expected_spec, input_seal, source_seal) -> dict`
- `audit_training_suite_v09(formal_root, run_order, report_path) -> dict`
- `seal_training_suite_v09(formal_root, audit_report) -> dict`

- [ ] **Step 1: 写总审核反驳测试**

测试必须拒绝：

- 24项中缺失、重复或多出任一运行；
- 运行顺序、模型族、随机数、参数量、30轮或204,630步不匹配；
- 同随机数三个模型的任一轮排列哈希不同；
- 第30轮检查点缺失或不是唯一允许的正式预测来源；
- 输入、源码、环境、授权或运行清单哈希漂移；
- 任何非有限损失、非有限参数、历史候选无梯度、内存越界或失败收据；
- 任何验证指标、正式期观测、正式期预测或评分产物提前出现；
- 训练封存写在审核完成之前；
- 总审核报告写入任一运行封存目录。

- [ ] **Step 2: 运行总审核测试并确认失败**

Run:

```powershell
pytest src/26_historical_band_experts/tests/test_audit_formal_training_v09.py -q
```

Expected: FAIL，原因是总审核器尚不存在。

- [ ] **Step 3: 实现独立审核和总封存**

审核器逐项重算运行目录哈希树，重载第30轮检查点并验证所有张量有限、结构和参数量正确。
它不运行正式期推理，不读取正式评估观测，也不计算性能。全部24项通过后才写目录外审核报告。

`training_seal.json`固定包含：

- 协议、输入封存、严格嵌套独立审核、授权收据、可执行源码树和环境哈希；
- 24项运行的固定顺序、运行封存哈希和第30轮检查点SHA-256；
- 第10、20轮检查点哈希，但明确标记`not_eligible_for_formal_prediction=true`；
- `formal_prediction_generated=false`和`official_score_called=false`；
- 独立训练审核报告SHA-256。

- [ ] **Step 4: 运行总审核测试**

Run:

```powershell
pytest src/26_historical_band_experts/tests/test_audit_formal_training_v09.py -q
```

Expected: PASS。

- [ ] **Step 5: 提交总审核器**

```powershell
git add src/26_historical_band_experts/audit_formal_training_v09.py `
  src/26_historical_band_experts/tests/test_audit_formal_training_v09.py
git commit -m "Feat: Add formal v09 training audit"
```

---

### Task 7: 在两次独立授权下执行严格嵌套和24次主训练

**Files:**
- Create only after direct strict approval:
  `src/26_historical_band_experts/configs/formal_v09_strict_nesting_authorization.json`
- Create only after direct main approval:
  `src/26_historical_band_experts/configs/formal_v09_training_authorization.json`
- Modify after each completed audit: `src/26_historical_band_experts/registry.csv`
- Create after strict audit:
  `docs/technical/historical_multiscale_formal_v09_strict_nesting_audit.md`
- Create after main audit:
  `docs/technical/historical_multiscale_formal_v09_training_audit.md`

**Interfaces:**
- Consumes: 已通过全部测试的训练提交、正式输入封存、两个逐阶段直接授权。
- Produces: 严格嵌套封存、24次主训练封存、两个独立审核和训练总封存。

- [ ] **Step 1: 在任何正式训练前完成代码审核**

实现代码全部提交后：

1. 运行YAPF，仅格式化本计划新增或修改的Python文件；
2. 在可用物理内存至少12.68 GiB时运行
   `pytest src/26_historical_band_experts/tests -q`；
3. 记录准确通过数量、警告和耗时；
4. 核对工作区干净；
5. 核对协议SHA-256仍为
   `b81bce8fc83aa8c4cad2d36475c6e6da553567f54b5f5f8d52457006fb446ed8`；
6. 核对冻结目录和评分代码相对版本09实施父提交没有差异；
7. 由独立上下文审查训练代码的数据边界、随机数、损失、原子性和停止条件。

任一项失败时不得申请严格嵌套授权。

- [ ] **Step 2: 请求并固化严格嵌套授权**

只有用户逐字发送Task 1给出的严格嵌套批准文本后，才创建收据。收据绑定实际输入封存哈希、
输入产物外部审核报告哈希、可信训练目标来源外部审核报告哈希、可执行源码树哈希、
严格输出目录和当前批准任务标识，并提交：

```powershell
git add src/26_historical_band_experts/configs/formal_v09_strict_nesting_authorization.json `
  src/26_historical_band_experts/registry.csv
git commit -m "Phase: Authorize formal v09 strict nesting"
```

- [ ] **Step 3: 运行一次严格嵌套训练**

启动前再次检查可用物理内存、显存、输出不存在、工作区干净和所有哈希。命令固定为：

```powershell
python src\26_historical_band_experts\train_strict_formal_v09.py `
  --protocol src\26_historical_band_experts\configs\formal_v09_protocol.json `
  --authorization src\26_historical_band_experts\configs\formal_v09_strict_nesting_authorization.json `
  --input-root results\26_historical_band_experts\formal_v09\input_attempt_01 `
  --output-root results\26_historical_band_experts\formal_v09\strict_nesting\seed_100 `
  --seed 100 `
  --device cuda:0
```

命令首次启动即消费授权。任何失败都保持`HOLD`并等待新的用户决定。

- [ ] **Step 4: 独立审核严格嵌套**

```powershell
python src\26_historical_band_experts\audit_strict_formal_v09.py `
  --protocol src\26_historical_band_experts\configs\formal_v09_protocol.json `
  --input-root results\26_historical_band_experts\formal_v09\input_attempt_01 `
  --strict-root results\26_historical_band_experts\formal_v09\strict_nesting\seed_100 `
  --report results\26_historical_band_experts\formal_v09\strict_nesting_seed_100.external_audit.json `
  --device cuda:0
```

通过条件同时为：204,630步全部零容差、训练期全部预测最大差0、独立重放最大差不超过`1e-6`、
无越界数据访问、全部哈希通过。把事实写入严格嵌套审计文档并提交。未通过时不得申请主训练授权。

- [ ] **Step 5: 请求并固化主训练授权**

只有严格嵌套审计通过且用户逐字发送Task 1给出的主训练批准文本后，才创建主训练收据并提交：

```powershell
git add src/26_historical_band_experts/configs/formal_v09_training_authorization.json `
  src/26_historical_band_experts/registry.csv
git commit -m "Phase: Authorize formal v09 main training"
```

- [ ] **Step 6: 串行运行24次主训练**

```powershell
python src\26_historical_band_experts\run_formal_training_v09.py `
  --protocol src\26_historical_band_experts\configs\formal_v09_protocol.json `
  --authorization src\26_historical_band_experts\configs\formal_v09_training_authorization.json `
  --run-order src\26_historical_band_experts\configs\formal_v09_run_order.json `
  --input-root results\26_historical_band_experts\formal_v09\input_attempt_01 `
  --formal-root results\26_historical_band_experts\formal_v09 `
  --device cuda:0
```

监控只报告运行标识、轮次、更新数、内存、显存、进程状态和哈希完整性，不报告候选优劣或性能。

- [ ] **Step 7: 独立审核并封存全部训练**

```powershell
python src\26_historical_band_experts\audit_formal_training_v09.py `
  --protocol src\26_historical_band_experts\configs\formal_v09_protocol.json `
  --run-order src\26_historical_band_experts\configs\formal_v09_run_order.json `
  --formal-root results\26_historical_band_experts\formal_v09 `
  --report results\26_historical_band_experts\formal_v09\training_external_audit.json `
  --seal results\26_historical_band_experts\formal_v09\training_seal.json
```

只有报告为`complete_training_audit`且总封存哈希重载通过，才可申请正式预测授权。

- [ ] **Step 8: 记录训练阶段结论**

训练审计文档必须明确：

- 事实：严格嵌套差异、运行数、随机数、更新数、检查点、资源和哈希；
- 未知：尚未生成正式期预测，模型效果仍无法确定；
- 下一条件：单独批准正式预测与封存阶段；
- 禁止推断：训练损失或运行完成不能证明候选优于冻结经典基准。

```powershell
git add docs/technical/historical_multiscale_formal_v09_strict_nesting_audit.md `
  docs/technical/historical_multiscale_formal_v09_training_audit.md `
  src/26_historical_band_experts/registry.csv
git commit -m "Phase: Record formal v09 training audit"
```

## Stopping Conditions

以下任一情况立即停止，不进入下一阶段：

- 正式输入或其独立审核不完整；
- 用户没有对应阶段的逐字直接授权；
- 授权已消费、输出目录已存在或工作区不干净；
- 协议、输入、源码、环境、运行顺序或配置哈希漂移；
- 可用物理内存低于启动门，运行保留量不足，进程驻留内存或单次分配超限；
- 严格嵌套任一步出现任何非零差异；
- 独立严格重放超过`1e-6`；
- 任何运行不是30轮、204,630步或第30轮检查点缺失；
- 同随机数三个模型的批次排列哈希不同；
- 任何非有限值、历史候选无有效梯度、残留训练进程或原子封存失败；
- 正式评估观测、正式预测或评分服务被提前访问；
- 24项没有全部完成独立审核。

## Self-Review

- 科学对齐：模型结构、270天近期路径、3,561天最长历史滞后、120分箱、30轮、八随机数、
  经典损失、同参数量控制和单流量输出均由协议和测试共同约束。
- 嵌套强度：同进程204,630步零容差加独立进程全部训练键预测`1e-6`容差，不能用少量合成批次替代。
- 公平性：三个主模型共享训练键、批次顺序、目标、归一化、优化器和随机数；只有结构和参数量按预注册变化。
- 防选择：24项全部完成前不计算性能，第30轮是唯一预测来源。
- 数据边界：训练目标只作监督，正式评估观测和水文签名保持封存。
- 资源边界：单进程、逐批内存门、显存预检、失败即停和禁止自动重试。
- 可追溯性：输入、源码、环境、收据、每轮排列、检查点、运行目录和总封存均有SHA-256。

## Execution Handoff

当前状态应保持`NO-GO`：本文件只是实施计划，正式输入尚未生成，训练代码尚未按本计划实现，
严格嵌套和24次主训练也未获授权。执行顺序不可合并：

1. 完成并独立审核正式输入；
2. 用户批准实施本训练计划中的代码和合成测试；
3. 代码审核通过后，用户单独批准严格嵌套训练；
4. 严格嵌套独立审核通过后，用户单独批准24次主训练；
5. 24次训练独立审核和总封存通过后，才进入正式预测计划。
