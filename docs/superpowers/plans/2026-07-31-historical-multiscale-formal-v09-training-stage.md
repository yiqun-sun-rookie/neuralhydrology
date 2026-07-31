# 历史连续多尺度气象模型版本09严格嵌套与正式训练阶段实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在531个冻结流域上先完成种子100的30轮逐更新严格嵌套复现，再以完全冻结的批次、损失、优化器和资源规则一次性训练经典近期、同参数量近期控制、连续历史候选各八个随机数，共24次主训练。

**Architecture:** 正式训练只重载已独立审核并封存的输入目录。经典近期模型、停用历史路径模型和369单元同参数量控制只读取270天近期序列；连续历史候选额外读取270至3,561天滞后的120个连续对数分箱。严格嵌套在同一进程、同一批次和同一随机数状态下逐更新比较经典近期模型与停用历史路径模型；主训练在三个模型族之间共享完全相同的样本顺序、30轮训练和八个固定随机数，但每次运行使用独立进程和原子输出目录。

**Tech Stack:** Python 3.11、PyTorch、NumPy、只读 NumPy 内存映射、pandas、psutil、pytest、Git、SHA-256。

## Global Constraints

- 本计划不授权实现、资源预检、训练、正式预测或评分。只有用户逐字批准下述“训练代码实现与独立
  合成资源预检”文本后，才允许写训练代码、运行合成测试和执行一次独立合成资源预检；该批准不授权
  严格嵌套或主训练。
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
- 损失公式与冻结经典配置一致：在全局训练期归一化流量上计算逐样本平方误差，并乘以
  `1 / (raw_per_basin_training_q_std + 0.1) ** 2`后取均值。流域标准差只用训练期原始流量计算。
- Adam固定为`betas=(0.9, 0.999)`、`eps=1e-8`、`weight_decay=0`、
  `amsgrad=False`、`maximize=False`、`foreach=False`、`fused=False`、
  `capturable=False`和`differentiable=False`。梯度范数裁剪1.0、遗忘门偏置5.0、
  输出丢弃率0.4、学习率
  1–10轮为0.001、11–20轮为0.0005、21–30轮为0.0001。
- 正式静态张量必须按输入封存中的`FORMAL_V09_STATIC_COLUMNS`字母顺序读取，静态尺度必须标记
  `ddof=1`；动态和流量尺度必须标记`ddof=0`且只来自训练期。任一列名、顺序、自由度或统计范围
  漂移都停止。
- 训练读取的`statics.npy`已经按旧核心精度顺序完成归一化：源双精度统计、双精度归一化、最后转
  单精度。其有效载荷SHA-256必须为
  `aa53d1d06247b246f5557efe6761b9b7becd2be3a680f99d667d2e3c89b9b37a`；
  训练器不得读取`statics_raw.float64.npy`或再次归一化。
- 气象和目标的封存统计以`float64`记录，但每批运算前中心、尺度和每流域损失尺度只转换一次为
  `float32`。原始`float32`批次必须在中央处理器NumPy中按“减中心、除尺度”的顺序完成
  `float32`归一化，再以C连续`float32`张量传到设备；不得在图形处理器上归一化。
- 连续历史模型必须先归一化完整`[批量,3562,5]`气象窗口，再调用`split_windows_v09()`；
  即120个历史分箱聚合的是归一化Maurer。近期模型单独读取并归一化270天切片，其结果必须与同一
  完整窗口的最后270天逐字节相同。目标同样在中央处理器按单精度归一化；损失权重中的每流域原始
  流量标准差和常数0.1均为单精度。
- 每个主训练随机数拆成互不混用的模型初始化、批次排列和丢弃层随机数流。模型仍用协议随机数
  100至800初始化；每轮批次排列使用既有`seed * 1_000_003 + epoch`；模型和优化器构造完毕后，
  必须把PyTorch中央处理器和全部图形处理器随机数重置为
  `dropout_seed = seed * 1_000_003 + 900_001`。这样不同宽度模型的初始化耗用量不会改变训练期
  丢弃流起点。三个模型族同一主随机数的初始丢弃随机数状态哈希必须相同。
- 只把第30轮检查点用于后续正式预测；第10轮和第20轮检查点只用于中断诊断和审计，不得用于选择。
- 主训练全部24次结束前不得计算验证指标、正式指标、分支消融或根据损失选择模型、随机数或检查点。
- 版本08发现的历史记忆状态大而有限是预先公开的数值警示。版本09不得以该数值设置事后阈值，
  不得据此更换模型或检查点；正式预测前必须按
  `docs/technical/historical_multiscale_formal_v09_state_diagnostics_preregistration.md`
  完成八个连续历史候选的训练期状态分布和独立重放。
- 每次训练使用独立进程，禁止并行运行两个正式训练进程。
- 正式图形处理器运行使用确定性算法：导入PyTorch前固定
  `CUBLAS_WORKSPACE_CONFIG=:4096:8`，启用`torch.use_deterministic_algorithms(True)`，
  关闭cuDNN基准搜索并启用cuDNN确定性模式，禁用矩阵乘法和卷积的TensorFloat-32快速路径。
  两个全新进程必须先对同一合成历史批次产生逐字节相同的状态数组；不支持或不一致时停止，
  不得放宽重放容差。
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
  另以八个实际冻结检查点的同设备合成前向零差异证明函数桥接；不声称重现旧八随机数检查点的
  完整训练轨迹。历史八随机数集合只作为不参与判定的历史参考；清洁配对路线的主基准是同一正式
  训练合同下的新`B09-CLASSIC`八随机数集合。
- `B09-CLASSIC`是使用合法训练期归一化、显式批次排列和冻结优化器后端的干净经典结构控制，
  不是旧八随机数模型的重新训练。旧训练的预热期统计包含正式评估期流量聚合值，旧批次顺序和
  PyTorch环境也没有被封存；禁止为了追求旧轨迹而引入这些信息或猜测旧环境。

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
- `validate_stage_authorization_v09(receipt, *, action, scope=None, protocol_sha256=None, prerequisite_sha256=None, executable_tree_sha256=None) -> dict`
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

训练代码实现与独立合成资源预检批准文本固定为：

```text
批准版本09训练代码实现与独立合成资源预检；不批准严格嵌套训练、主实验训练、正式预测或评分。
```

UTF-8、无末尾换行的SHA-256固定为：

```text
2ca80e4dba179ab8de6ffe81ef515dd7b9f3fb85cf61c9057b840ef7da51a2ba
```

这项批准只允许完成Task 1至Task 6的实现、测试、只读审核和Task 7中的独立合成资源预检。它不能
创建或替代严格嵌套、主训练、正式预测或评分收据；资源预检报告必须记录批准文本哈希和所在任务标识。

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
批准版本09正式主训练阶段；仅授权B09-CLASSIC、B09-CAPACITY和E09-CONTINUOUS各八个固定随机数的一次训练，并授权训练完成后的预注册状态诊断和独立重放审核；不批准正式预测或评分。
```

UTF-8、无末尾换行的SHA-256固定为：

```text
5c6037b557a6ae4bd6bcf0ce99eb78be70c0285a5589ca0707f88a4e92a73d8d
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
`prerequisite_sha256`是键集合也受冻结约束的映射。严格嵌套授权必须恰好包含
`input_seal`、`input_artifact_external_audit`、`trusted_target_external_audit`、
`legacy_checkpoint_bridge_external_audit`和`training_resource_preflight_external_audit`。
主训练授权必须继续包含这五项，并恰好增加`strict_nesting_run_seal`、
`strict_nesting_external_audit`和
`docs/technical/historical_multiscale_formal_v09_state_diagnostics_preregistration.md`
的完整文件SHA-256。未知键、缺失键或任一值漂移都拒绝。
只有既有输入生成动作允许省略`scope`和`prerequisite_sha256`，并继续执行输入计划冻结的收据
固定字段、实际批准任务来源、批准时间和可执行源码树完整检查；输入动作也不得省略
`executable_tree_sha256`。所有训练和后续动作缺少任一适用扩展参数都拒绝。

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
- `post_training_state_diagnostics="preregistered_e09_continuous_8_seed_read_only"`；
- `state_diagnostics_independent_replay_authorized=true`，但只有24项全部封存后才能执行；
- `formal_prediction_generation_authorized=false`
- `official_scoring_authorized=false`

收据还必须保存直接批准所在任务标识、批准时间、批准文本和其SHA-256。批准发生后才把实际
输入封存哈希、两个目录外输入审核报告哈希、旧检查点桥接哈希、资源预检哈希、适用阶段的严格嵌套
证据、状态诊断预注册文件哈希、可执行源码树哈希和Git提交写入收据；禁止预先生成收据。
可执行源码树只包含实际运行的Python文件和科学配置，不包含授权收据、审计文档或结果目录，
避免收据把自身纳入哈希形成循环。

- [ ] **Step 4: 实现原子消费收据**

消费路径固定为：

- 严格嵌套：
  `results/26_historical_band_experts/formal_v09/strict_nesting_authorization_consumed.json`
- 主训练：
  `results/26_historical_band_experts/formal_v09/training_authorization_consumed.json`

文件以独占创建模式写入，内容包括授权收据SHA-256、启动时间、主机、进程标识、Git提交、
工作区树哈希、输入封存哈希、两个输入审核报告哈希、旧检查点桥接哈希、资源预检哈希、适用阶段的
严格嵌套证据、主训练适用的状态诊断预注册文件哈希和启动内存快照。消费文件一旦存在，
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
- `normalize_forcing_batch_v09(values, scaler) -> np.ndarray`
- `normalize_target_batch_v09(values, scaler) -> np.ndarray`
- `load_training_batch_v09(inputs, basin_indices, target_indices, *, variant, device, gate) -> TrainingBatchV09`
- `masked_nse_training_loss_v09(prediction, target, raw_per_basin_std) -> torch.Tensor`

- [ ] **Step 1: 写数据边界、排序和损失失败测试**

测试必须证明：

- 输入目录以只读方式打开；缺失`seal.json`、输入产物外部审核、可信训练目标来源外部审核，
  任一审核状态不通过，或任一授权绑定哈希漂移都拒绝；
- 正式训练输入对象不含`statics_raw`字段，训练进程从不打开`statics_raw.float64.npy`；
- 训练键严格按冻结流域顺序、再按日期1999-10-01至2008-09-30生成，共1,745,928项；
- 每轮使用独立CPU `torch.Generator`和固定种子派生规则生成一个完整排列，不重复、不遗漏；
- 相同随机数和轮次产生相同排列，不同轮次产生不同排列；
- 经典、停用历史和369单元控制只读取270天近期切片；
- 连续历史候选读取一个不超过256样本的3,562天窗口，并生成120个历史分箱；
- 完整窗口先在中央处理器以单精度归一化再分箱；完整窗口末270天与单独近期切片的归一化结果
  逐字节相同；
- 所有模型收到完全相同的静态属性、目标和训练键；
- 静态属性列严格等于输入封存的显式字母顺序，静态尺度`ddof=1`，预归一化有效载荷哈希固定且
  不再归一化；动态和流量尺度`ddof=0`；
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

近期模型直接从只读气象内存映射复制`[batch,270,5]`，在中央处理器以固定单精度顺序归一化后
转设备。连续历史候选调用`gather_causal_windows_v09()`得到`[batch,3562,5]`，先用同一函数
归一化完整窗口，再转为设备张量并调用`split_windows_v09()`得到
`recent=[batch,270,5]`和`history=[batch,120,7]`。每个复制、归一化临时数组或转设备操作前
调用内存门。

`normalize_forcing_batch_v09()`和`normalize_target_batch_v09()`必须先验证输入是C连续
`float32`，把封存`float64`统计转为C连续`float32`，再用显式输出数组执行单精度减法和除法。
目标使用输入封存中的全局训练期中心和尺度；损失权重使用转为`float32`的每流域训练期原始流量
标准差。任何标准差非有限或小于等于0时停止，不临时替换。

归一化函数的运算顺序固定为：

```python
def normalize_forcing_batch_v09(values: np.ndarray, scaler: Mapping) -> np.ndarray:
    if values.dtype != np.float32 or not values.flags.c_contiguous:
        raise FormalTrainingDataError("forcing batch layout drift")
    center = np.ascontiguousarray(
        np.asarray(scaler["dynamic_center"], dtype=np.float32)
    )
    scale = np.ascontiguousarray(
        np.asarray(scaler["dynamic_scale"], dtype=np.float32)
    )
    if not np.isfinite(scale).all() or np.any(scale <= 0):
        raise FormalTrainingDataError("invalid dynamic scale")
    normalized = np.empty_like(values)
    np.subtract(values, center, out=normalized, casting="no")
    np.divide(normalized, scale, out=normalized, casting="no")
    if not np.isfinite(normalized).all():
        raise FormalTrainingDataError("nonfinite normalized forcing")
    return normalized
```

目标函数使用同一两步顺序和标量`q_center`、`q_scale`。测试必须检查输入数组未被修改、输出C连续、
数据类型严格为`float32`，并对人工构造的边界值比较原始字节而不是只用宽松数值容差。

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

固定种子100。经典模型和停用历史模型分别用下列显式参数建立Adam，但活动参数序列在训练前
逐元素相等：

```python
torch.optim.Adam(
    active_parameters,
    lr=current_learning_rate,
    betas=(0.9, 0.999),
    eps=1e-8,
    weight_decay=0.0,
    amsgrad=False,
    foreach=False,
    maximize=False,
    capturable=False,
    differentiable=False,
    fused=False,
)
```

构造后必须逐项检查参数组实际值，不能依赖PyTorch默认值。正式环境记录Python、PyTorch、CUDA、
cuDNN、图形处理器驱动、确定性开关和Adam参数；严格嵌套与后续24次主训练必须完全相同。
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

### Task 4: 实现旧参考函数桥接和独立严格嵌套重放审核

**Files:**
- Create after execution approval:
  `src/26_historical_band_experts/audit_legacy_checkpoint_bridge_v09.py`
- Test:
  `src/26_historical_band_experts/tests/test_audit_legacy_checkpoint_bridge_v09.py`
- Create after execution approval: `src/26_historical_band_experts/audit_strict_formal_v09.py`
- Test: `src/26_historical_band_experts/tests/test_audit_strict_formal_v09.py`
- Generated, not tracked:
  `results/26_historical_band_experts/formal_v09/legacy_checkpoint_forward_bridge.external_audit.json`
- Generated, not tracked:
  `results/26_historical_band_experts/formal_v09/strict_nesting_seed_100.external_audit.json`

**Interfaces:**
- `audit_legacy_checkpoint_bridge_v09(protocol_path, legacy_root, report_path, devices) -> dict`
- `audit_strict_nesting_v09(input_root, strict_root, protocol_path, report_path, device) -> dict`

- [ ] **Step 1: 写旧参考函数桥接和独立审核反驳测试**

旧参考桥接审核必须对八个冻结随机数逐项验证：

- 旧运行配置和第30轮检查点SHA-256与协议一致；
- 检查点恰好包含近期长短期记忆网络和单输出头的六个活动参数张量；
- 检查点严格加载到核心`CudaLSTM`和版本09干净经典模型；
- 加载到停用历史模型时，只允许缺少六个永不执行、不可训练的历史参数键，不能缺少或多出活动键；
- 固定合成输入使用2个样本、270天、5项动态和27项静态属性，生成随机数固定为29,090；
- 核心、干净经典和停用历史三条路径在同一设备上的预测必须逐元素完全相同；
- 另从封存正式输入只读加载全部531个流域、每流域12个固定训练日期，共6,372个真实语义样本；
  日期索引固定为`floor(linspace(0, 3287, 12))`，与状态诊断预注册面板相同；
- 真实语义桥接只读取Maurer、显式字母顺序且已预归一化的`statics.npy`以及Maurer训练期归一化
  字段，不打开
  `targets.npy`，不读取旧动态或流量归一化文件，也不反归一化流量输出；
- 对每个旧检查点、每个设备，核心、干净经典和停用历史三条路径在6,372个真实语义样本上的
  归一化输出字节流SHA-256必须完全相同，逐块最大绝对差必须为0；
- 审核不能读取训练或正式评估流量、旧`test_results.p`或正式评分答案。

审核器必须拒绝：

- 审核报告位于封存严格运行目录内部；
- 检查点、批次顺序、环境、源码或输入任一哈希漂移；
- 旧参考桥接缺少531乘12个真实语义训练键、静态列顺序证据、输出字节流哈希，或任一配对
  最大绝对差不为0；
- 训练轮数不是30或更新数不是204,630；
- 任一步的零容差标志缺失；
- 第30轮经典和嵌套活动参数或Adam状态不完全相同；
- 历史模块进入优化器或出现梯度；
- 训练期预测摘要最大差不为0；
- 独立进程重算的固定训练键预测与封存预测字节流最大绝对差超过`1e-6`。

- [ ] **Step 2: 运行两个审核测试并确认失败**

Run:

```powershell
pytest src/26_historical_band_experts/tests/test_audit_legacy_checkpoint_bridge_v09.py `
  src/26_historical_band_experts/tests/test_audit_strict_formal_v09.py -q
```

Expected: FAIL，原因是两个审核器尚不存在。

- [ ] **Step 3: 实现只读旧参考函数桥接**

桥接审核器只读取协议登记的八份旧配置、第30轮检查点，以及正式输入封存中明确允许的气象、静态
属性、流域、日期和相应训练期归一化字段。它不得调用会同时打开`targets.npy`的通用输入重载接口。
它在中央处理器和正式训练设备上分别构建核心`CudaLSTM`、版本09干净经典模型和停用历史模型，
加载同一活动参数，先对固定合成输入执行评估模式前向，再对6,372个真实语义训练样本流式前向。
每个随机数、每个设备、每个面板的两个配对最大绝对差都必须为0，输出字节流哈希必须相同。

该审核只证明“冻结检查点的函数映射可由版本09近期路径和停用历史路径逐元素复现”，不证明旧训练
批次、随机数状态、归一化来源或完整训练轨迹可重建。报告路径必须预先不存在，并记录八个配置、
八个检查点、正式静态列名与顺序、固定面板键、输入封存、审核源码和环境哈希；后继严格嵌套授权
从最终报告文件外部计算并绑定报告SHA-256。

- [ ] **Step 4: 实现只读严格嵌套独立审核**

审核器从第30轮检查点分别重建经典和停用历史模型，使用一个新进程和独立加载的只读输入，
按冻结训练键流式重算全部训练期预测，并与封存的
`training_predictions_classic.float32.npy`逐块比较。它验证：

- 同一审核进程内经典与停用历史预测最大差严格为0；
- 两个重放模型与封存经典参考数组的最大绝对差均不超过`1e-6`、相对容差为0；
- 预测键覆盖531个流域、每流域3,288个训练日期；
- 没有正式评估观测访问、正式预测或评分调用。

审核报告只写在严格运行目录之外，且输出路径预先不存在。

- [ ] **Step 5: 运行两个审核测试**

Run:

```powershell
pytest src/26_historical_band_experts/tests/test_audit_legacy_checkpoint_bridge_v09.py `
  src/26_historical_band_experts/tests/test_audit_strict_formal_v09.py -q
```

Expected: PASS。

- [ ] **Step 6: 提交两个审核器**

```powershell
git add src/26_historical_band_experts/audit_legacy_checkpoint_bridge_v09.py `
  src/26_historical_band_experts/audit_strict_formal_v09.py `
  src/26_historical_band_experts/tests/test_audit_legacy_checkpoint_bridge_v09.py `
  src/26_historical_band_experts/tests/test_audit_strict_formal_v09.py
git commit -m "Feat: Add formal v09 legacy bridge and nesting audit"
```

---

### Task 5: 冻结24次主训练顺序并实现单运行训练器

**Files:**
- Create after execution approval:
  `src/26_historical_band_experts/configs/formal_v09_run_order.json`
- Create after execution approval:
  `src/26_historical_band_experts/resource_preflight_formal_v09.py`
- Create after execution approval: `src/26_historical_band_experts/train_formal_v09.py`
- Create after execution approval: `src/26_historical_band_experts/run_formal_training_v09.py`
- Test: `src/26_historical_band_experts/tests/test_resource_preflight_formal_v09.py`
- Test: `src/26_historical_band_experts/tests/test_train_formal_v09.py`
- Test: `src/26_historical_band_experts/tests/test_run_formal_training_v09.py`

**Interfaces:**
- `validate_run_order_v09(order) -> tuple[FormalRunSpecV09, ...]`
- `dropout_seed_v09(seed) -> int`
- `reset_training_dropout_rng_v09(seed) -> dict`
- `run_resource_preflight_v09(protocol_path, *, device, report_path) -> dict`
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
- Adam全部显式参数、实现后端和正式环境字段与严格嵌套封存完全相同；
- 连续历史模型第1步前两个历史门严格为0；第1次反向传播时历史编码器梯度存在、有限且
  逐元素为0，两个门梯度存在且有限，合并欧氏范数严格大于0；
- 连续历史模型第3步结束前历史编码器必须出现非零有限梯度；
- 训练中健康信息只读取同一次反向传播已经产生的张量，不增加第二次前向；启用或停用记录时，
  预测、损失、梯度、参数、Adam状态及全部随机数状态必须零差异；
- 历史门初值严格为0，但训练过程中允许学习；每轮记录门参数、门梯度和历史编码器梯度统计；
- 两个全新图形处理器进程在冻结确定性开关下产生相同的合成状态数组SHA-256；任一确定性
  开关漂移、算法不支持或数组不一致时失败；
- 不计算验证指标，不读取正式评估观测，不生成正式期预测；
- 同一随机数的三个模型每轮排列哈希完全相同；
- 同一随机数的三个模型在第一个训练批次前具有完全相同的中央处理器和图形处理器随机数状态哈希；
  经典与连续历史候选因近期隐藏宽度相同且历史前向不使用随机数，每一步近期输出丢弃流必须保持配对；
- 资源预检在独立一次性子进程中只用合成数据和可丢弃模型；它不能打开正式输入、创建正式输出或把
  模型、Adam、随机数状态带入正式训练进程；
- 输出目录存在、哈希漂移、非有限损失或内存越界时立即失败。

资源预检测试必须覆盖四种固定工作负载：

1. 经典近期模型与停用历史模型同时驻留的严格锁步工作负载；
2. 256隐藏单元经典近期模型；
3. 369隐藏单元同参数量控制；
4. 256隐藏单元连续历史候选。

每种工作负载使用批量256及其正式窗口形状，在两个依次启动的全新图形处理器子进程中，以同一合成
输入完成一次前向、损失、反向和Adam更新。测试必须证明两个子进程输出的参数、Adam状态、损失、
峰值显存和随机数状态字段完整；除峰值显存外的数值数组哈希完全相同。工作进程拒绝任何输入根目录、
正式输出根目录或真实文件参数；只有父进程可以在全部工作进程退出后原子写一份报告。

- [ ] **Step 2: 运行主训练测试并确认失败**

Run:

```powershell
pytest src/26_historical_band_experts/tests/test_train_formal_v09.py `
  src/26_historical_band_experts/tests/test_resource_preflight_formal_v09.py `
  src/26_historical_band_experts/tests/test_run_formal_training_v09.py -q
```

Expected: FAIL，原因是主训练模块尚不存在。

- [ ] **Step 3: 实现单运行训练器**

每个运行在独立进程中执行以下固定顺序：

1. 验证协议、配置、收据、输入封存、源码树、Git工作区和内存；
2. 核对正式环境字段与严格嵌套封存完全相同，再用协议随机数固定Python、NumPy和模型初始化；
3. 构建模型和显式Adam并验证参数量与参数组；
4. 把PyTorch中央处理器和全部图形处理器重置为固定`dropout_seed`，记录初始状态哈希；
5. 用独立CPU生成器生成每轮排列；
6. 执行30轮、204,630次Adam更新；
7. 在第10、20、30轮原子保存检查点；
8. 重载第30轮检查点并验证模型、优化器、随机数和哈希；
9. 写`seal.json`并原子提交运行目录。

连续历史候选只在正式前向和反向中记录计算图健康信息，不在训练进程内另算状态分布。八个
候选的状态分布在24次主训练全部结束后由独立进程从封存检查点计算，避免诊断前向影响训练随机数、
优化器、显存峰值或运行时模型状态。

图形处理器资源预检必须由独立预检驱动器启动一次性子进程，用同一模型结构、最大批量、同一窗口
形状和纯合成数据执行一次完整前向、反向和优化器步。预检进程不得打开正式输入或正式输出目录；
退出后模型、Adam和随机数状态全部丢弃。只有预检进程完全退出、无残留图形处理器进程且缓存释放后，
才启动全新的正式训练进程，并从步骤1重新验证和播种。正式运行前可用图形处理器内存必须至少达到
`max(预检峰值的2倍, 预检峰值加2 GiB)`；该门只保护资源，不允许改变批量大小或科学配置。
资源预检在申请严格嵌套授权前执行一次，报告同时覆盖严格锁步双模型和三个主模型族，写在正式输入
封存目录之外，并绑定协议、可执行源码树、设备和环境哈希。严格嵌套与主训练授权都必须绑定该报告
SHA-256；实际启动仍重新检查当前可用主机内存、图形处理器内存和环境完全一致。
报告路径固定为
`results/26_historical_band_experts/formal_v09/training_resource_preflight.external_audit.json`；
状态只能是`complete_resource_preflight`。报告逐工作负载记录输入形状、参数量、两次独立数组哈希、
峰值已分配和保留显存、确定性开关、工作进程标识与退出码，并证明进程不曾接收正式输入或输出路径。

- [ ] **Step 4: 实现串行编排器**

编排器先验证全部24个最终目录、`.building`目录和失败目录均不存在，再消费主训练授权。
它逐项启动子进程，等待退出并只做运行完整性审核。任一子进程非零退出、封存失败或资源门失败时，
停止后续运行并写`training_attempt_01.failure.json`；不删除已完成运行，不自动重试。

24个运行不得另造统一`training/`父目录。父目录必须逐模型与三份已冻结配置的`results_root`
完全相等：

- `B09-CLASSIC`：`results/26_historical_band_experts/formal_v09/classic`；
- `B09-CAPACITY`：`results/26_historical_band_experts/formal_v09/capacity`；
- `E09-CONTINUOUS`：`results/26_historical_band_experts/formal_v09/continuous`。

每个最终目录为`<results_root>/seed_<seed>`，临时目录为
`<results_root>/seed_<seed>.building`，失败目录为`<results_root>/seed_<seed>.failed`。
运行标识、模型族、随机数和父目录必须从冻结顺序文件与对应模型配置共同验证，不能由目录扫描、
已完成结果或编排器默认值反推。

每次子进程退出后必须释放模型、关闭内存映射并确认没有残留正式训练进程，才允许启动下一项。
编排器不读取训练目标值、模型预测或性能指标。

- [ ] **Step 5: 运行主训练测试**

Run:

```powershell
pytest src/26_historical_band_experts/tests/test_train_formal_v09.py `
  src/26_historical_band_experts/tests/test_resource_preflight_formal_v09.py `
  src/26_historical_band_experts/tests/test_run_formal_training_v09.py -q
```

Expected: PASS。

- [ ] **Step 6: 提交主训练实现和顺序**

```powershell
git add src/26_historical_band_experts/configs/formal_v09_run_order.json `
  src/26_historical_band_experts/resource_preflight_formal_v09.py `
  src/26_historical_band_experts/train_formal_v09.py `
  src/26_historical_band_experts/run_formal_training_v09.py `
  src/26_historical_band_experts/tests/test_resource_preflight_formal_v09.py `
  src/26_historical_band_experts/tests/test_train_formal_v09.py `
  src/26_historical_band_experts/tests/test_run_formal_training_v09.py
git commit -m "Feat: Add serial formal v09 training suite"
```

---

### Task 6: 实现24次训练的独立完整性审核和总封存

**Files:**
- Create after execution approval: `src/26_historical_band_experts/audit_formal_training_v09.py`
- Create after execution approval: `src/26_historical_band_experts/state_diagnostics_formal_v09.py`
- Create after execution approval: `src/26_historical_band_experts/audit_state_diagnostics_formal_v09.py`
- Test: `src/26_historical_band_experts/tests/test_audit_formal_training_v09.py`
- Test: `src/26_historical_band_experts/tests/test_state_diagnostics_formal_v09.py`
- Test: `src/26_historical_band_experts/tests/test_audit_state_diagnostics_formal_v09.py`
- Generated, not tracked:
  `results/26_historical_band_experts/formal_v09/state_diagnostics/`
- Generated, not tracked:
  `results/26_historical_band_experts/formal_v09/state_diagnostics_external_audit.json`
- Generated, not tracked:
  `results/26_historical_band_experts/formal_v09/training_external_audit.json`
- Generated, not tracked:
  `results/26_historical_band_experts/formal_v09/training_seal.json`

**Interfaces:**
- `audit_training_run_v09(run_root, expected_spec, input_seal, source_seal) -> dict`
- `write_history_state_diagnostics_v09(input_root, formal_root, run_order, output_root, device) -> dict`
- `audit_history_state_diagnostics_v09(input_root, formal_root, run_order, diagnostic_root, report_path, device) -> dict`
- `audit_training_suite_v09(formal_root, run_order, report_path) -> dict`
- `seal_training_suite_v09(formal_root, audit_report) -> dict`

- [ ] **Step 1: 写总审核反驳测试**

测试必须拒绝：

- 24项中缺失、重复或多出任一运行；
- 运行顺序、模型族、随机数、参数量、30轮或204,630步不匹配；
- 同随机数三个模型的任一轮排列哈希不同；
- 同随机数三个模型的初始丢弃随机数状态哈希不同，或丢弃流没有在模型和优化器构造后重置；
- 资源预检与正式训练共用进程、模型、优化器、随机数状态或正式输入；
- 第30轮检查点缺失或不是唯一允许的正式预测来源；
- 输入、源码、环境、授权或运行清单哈希漂移；
- 任何非有限损失、非有限参数、历史候选无梯度、内存越界或失败收据；
- 八个连续历史候选缺少第10、20、30轮固定面板状态数组，或第30轮缺少全部1,745,928个
  训练键状态数组；
- 任一状态非有限、固定面板不是531个流域乘12个冻结日期、状态诊断访问训练目标或正式评估观测；
- 同设备独立重放的样本键或五列`float32`状态数组SHA-256不一致；
- 任何验证指标、正式期观测、正式期预测或评分产物提前出现；
- 训练封存写在审核完成之前；
- 总审核报告写入任一运行封存目录。

- [ ] **Step 2: 运行总审核测试并确认失败**

Run:

```powershell
pytest src/26_historical_band_experts/tests/test_audit_formal_training_v09.py `
  src/26_historical_band_experts/tests/test_state_diagnostics_formal_v09.py `
  src/26_historical_band_experts/tests/test_audit_state_diagnostics_formal_v09.py -q
```

Expected: FAIL，原因是总审核器、状态诊断器和独立重放审核器尚不存在。

- [ ] **Step 3: 实现独立审核和总封存**

24次训练全部结束后，状态诊断进程按预注册文件只读取训练期Maurer气象、27项静态属性和
八个连续历史候选的第10、20、30轮检查点。每个检查点对531个流域乘12个冻结训练日期计算
原始与门控后的隐藏状态和记忆状态范数；第30轮另覆盖全部1,745,928个训练键。诊断不读取训练
目标，不执行近期路径或流量输出头，不生成流量预测。第二个进程在同一正式设备和环境上重算，
样本键固定为小端`int32[样本数,2]`，五列状态固定为小端`float32[样本数,5]`；数组原始字节
和`.npy`文件必须哈希完全相同。状态诊断目录和外部审核报告只由最终训练封存绑定，
不得回写已封存运行目录。

训练审核器逐项重算运行目录哈希树，重载第30轮检查点并验证所有张量有限、结构和参数量正确。
它不运行正式期推理，不读取正式评估观测，也不计算性能。全部24项和全部状态诊断通过后才写
目录外训练审核报告。

`training_seal.json`固定包含：

- 协议、输入封存、输入产物外部审核、可信训练目标来源外部审核、旧参考函数桥接审核、
  独立合成资源预检、严格嵌套运行封存、严格嵌套独立审核、状态诊断预注册文件、授权收据、
  可执行源码树和环境哈希；
- 24项运行的固定顺序、运行封存哈希和第30轮检查点SHA-256；
- 第10、20轮检查点哈希，但明确标记`not_eligible_for_formal_prediction=true`；
- 八个连续历史候选状态诊断目录哈希和状态诊断外部审核报告SHA-256；
- `formal_prediction_generated=false`和`official_score_called=false`；
- 独立训练审核报告SHA-256。

- [ ] **Step 4: 运行总审核测试**

Run:

```powershell
pytest src/26_historical_band_experts/tests/test_audit_formal_training_v09.py `
  src/26_historical_band_experts/tests/test_state_diagnostics_formal_v09.py `
  src/26_historical_band_experts/tests/test_audit_state_diagnostics_formal_v09.py -q
```

Expected: PASS。

- [ ] **Step 5: 提交总审核器**

```powershell
git add src/26_historical_band_experts/audit_formal_training_v09.py `
  src/26_historical_band_experts/state_diagnostics_formal_v09.py `
  src/26_historical_band_experts/audit_state_diagnostics_formal_v09.py `
  src/26_historical_band_experts/tests/test_audit_formal_training_v09.py `
  src/26_historical_band_experts/tests/test_state_diagnostics_formal_v09.py `
  src/26_historical_band_experts/tests/test_audit_state_diagnostics_formal_v09.py
git commit -m "Feat: Add formal v09 training audit"
```

---

### Task 7: 在两次独立授权下执行严格嵌套和24次主训练

**Files:**
- Create only after direct strict approval:
  `src/26_historical_band_experts/configs/formal_v09_strict_nesting_authorization.json`
- Create only after direct main approval:
  `src/26_historical_band_experts/configs/formal_v09_training_authorization.json`
- Generated before strict approval, not tracked:
  `results/26_historical_band_experts/formal_v09/legacy_checkpoint_forward_bridge.external_audit.json`
- Generated before strict approval, not tracked:
  `results/26_historical_band_experts/formal_v09/training_resource_preflight.external_audit.json`
- Modify after each completed audit: `src/26_historical_band_experts/registry.csv`
- Create after strict audit:
  `docs/technical/historical_multiscale_formal_v09_strict_nesting_audit.md`
- Create after main audit:
  `docs/technical/historical_multiscale_formal_v09_training_audit.md`

**Interfaces:**
- Consumes: 已通过全部测试的训练提交、协议登记的旧参考结果根目录、正式输入封存、两个逐阶段直接授权。
- Produces: 旧参考函数桥接审核、严格嵌套封存、24次主训练封存、两个独立审核和训练总封存。

- [ ] **Step 1: 在任何正式训练前完成代码审核**

用户逐字发送上述训练代码实现与独立合成资源预检批准文本，且实现代码全部提交后：

1. 运行YAPF，仅格式化本计划新增或修改的Python文件；
2. 在可用物理内存至少12.68 GiB时运行
   `pytest src/26_historical_band_experts/tests -q`；
3. 记录准确通过数量、警告和耗时；
4. 核对工作区干净；
5. 核对协议SHA-256仍为
   `b81bce8fc83aa8c4cad2d36475c6e6da553567f54b5f5f8d52457006fb446ed8`；
6. 核对冻结目录和评分代码相对版本09实施父提交没有差异；
7. 由独立上下文审查训练代码的数据边界、随机数、损失、原子性和停止条件；
8. 在中央处理器和正式训练设备上运行八随机数旧参考函数桥接审核；任一最大差不为0都停止。
9. 在独立子进程中用合成数据完成严格锁步和三个主模型族的资源预检，封存报告；任一工作负载
   不支持确定性算法、超过资源门或污染正式输入／输出时停止。

资源预检命令固定为：

```powershell
python src\26_historical_band_experts\resource_preflight_formal_v09.py `
  --protocol src\26_historical_band_experts\configs\formal_v09_protocol.json `
  --device cuda:0 `
  --report results\26_historical_band_experts\formal_v09\training_resource_preflight.external_audit.json
```

桥接审核命令固定为：

```powershell
python src\26_historical_band_experts\audit_legacy_checkpoint_bridge_v09.py `
  --protocol src\26_historical_band_experts\configs\formal_v09_protocol.json `
  --legacy-root G:\github\pycharm\projects\neuralhydrology\results\18_lstm_fair_531 `
  --devices cpu,cuda:0 `
  --report results\26_historical_band_experts\formal_v09\legacy_checkpoint_forward_bridge.external_audit.json
```

任一项失败时不得申请严格嵌套授权。

- [ ] **Step 2: 请求并固化严格嵌套授权**

只有用户逐字发送Task 1给出的严格嵌套批准文本后，才创建收据。收据绑定实际输入封存哈希、
输入产物外部审核报告哈希、可信训练目标来源外部审核报告哈希、旧参考函数桥接审核报告哈希、
独立合成资源预检报告哈希、可执行源码树哈希、严格输出目录和当前批准任务标识，并提交：

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

只有严格嵌套审计通过且用户逐字发送Task 1给出的主训练批准文本后，才创建主训练收据。收据必须
继续绑定同一独立合成资源预检报告，并新增严格嵌套运行封存、外部审核哈希和冻结状态诊断预注册
文件哈希。该批准同时明确允许24项全部封存后的只读状态诊断和独立重放，不允许提前诊断或生成
正式期流量预测。然后提交：

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

先在24项全部完成后执行预注册状态诊断：

```powershell
python src\26_historical_band_experts\state_diagnostics_formal_v09.py `
  --protocol src\26_historical_band_experts\configs\formal_v09_protocol.json `
  --input-root results\26_historical_band_experts\formal_v09\input_attempt_01 `
  --formal-root results\26_historical_band_experts\formal_v09 `
  --run-order src\26_historical_band_experts\configs\formal_v09_run_order.json `
  --output-root results\26_historical_band_experts\formal_v09\state_diagnostics `
  --device cuda:0
```

诊断进程不得读取训练目标、执行近期路径或生成流量输出。随后由另一个独立进程全量重放：

```powershell
python src\26_historical_band_experts\audit_state_diagnostics_formal_v09.py `
  --protocol src\26_historical_band_experts\configs\formal_v09_protocol.json `
  --input-root results\26_historical_band_experts\formal_v09\input_attempt_01 `
  --formal-root results\26_historical_band_experts\formal_v09 `
  --run-order src\26_historical_band_experts\configs\formal_v09_run_order.json `
  --diagnostic-root results\26_historical_band_experts\formal_v09\state_diagnostics `
  --report results\26_historical_band_experts\formal_v09\state_diagnostics_external_audit.json `
  --device cuda:0
```

状态诊断只接受三份模型配置所指目录中的24个已封存运行和冻结运行顺序；任何额外统一
`training/`目录、父目录漂移或目录扫描推断都拒绝。最终`training_seal.json`此时必须不存在。
状态诊断及其外部审核通过后，才运行总训练审核并生成最终封存：

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

- 事实：严格嵌套差异、运行数、随机数、更新数、检查点、资源、状态分布和哈希；
- 数值边界：大而有限的历史状态只作报告；没有预注册数值上限，也不能解释成历史气象因果贡献；
- 未知：尚未生成正式期预测，模型效果仍无法确定；
- 下一条件：单独批准正式预测与封存阶段；
- 禁止推断：训练损失或运行完成不能证明候选优于清洁经典主基准。

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
- 第1步零门/梯度链路不成立，或第3步结束前历史编码器没有非零有限梯度；
- 任何非有限值、状态诊断覆盖或哈希不完整、诊断改变训练轨迹、残留训练进程或原子封存失败；
- 正式评估观测、正式预测或评分服务被提前访问；
- 24项没有全部完成独立审核。

## Self-Review

- 科学对齐：模型结构、270天近期路径、3,561天最长历史滞后、120分箱、30轮、八随机数、
  经典损失、同参数量控制和单流量输出均由协议和测试共同约束。
- 嵌套强度：同进程204,630步零容差加独立进程全部训练键预测`1e-6`容差，不能用少量合成批次替代。
- 公平性：三个主模型共享训练键、批次顺序、目标、归一化、优化器和随机数；只有结构和参数量按预注册变化。
- 防选择：24项全部完成前不计算性能，第30轮是唯一预测来源。
- 数值诊断：训练后独立覆盖全部531个流域和全部训练键；有限大状态强制报告但不触发事后选择。
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
