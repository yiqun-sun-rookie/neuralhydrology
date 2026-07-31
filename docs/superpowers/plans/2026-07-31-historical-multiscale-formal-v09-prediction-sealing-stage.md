# 历史连续多尺度气象模型版本09正式预测与产物封存阶段实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 从24个已独立审核的第30轮检查点一次性生成531流域正式期逐随机数预测，按固定顺序组成三个八随机数均值集合，预先锁定连续历史模型为唯一挑战者，并把清洁经典基准、同参数量控制、输入、检查点、源码、环境和预测封存为可独立重放的只读证据。

**Architecture:** 预测进程只读取正式输入封存和训练总封存，不读取任何正式评估观测。每个模型族的八个随机数分别生成严格的`basin,date,qsim`长表，再用固定随机数顺序和`float64`累加器组成均值集合。连续历史集合在预测前已被预注册为唯一挑战者；清洁经典集合是清洁配对路线的唯一主基准，同参数量集合只作预注册次要比较。三个文件只能作为一个封存评分包进入`S09C-CLEAN-PAIR`，均不得单独进入旧赛道。独立上下文从第30轮检查点重放全部24个预测并重建三个集合，随后封存一个不含可信目标导出工具、但包含候选实际运行源码的静态扫描包。

**Tech Stack:** Python 3.11、PyTorch、NumPy、pandas、只读 NumPy 内存映射、psutil、pytest、Git、SHA-256、正式基准静态泄漏扫描器。

## Global Constraints

- 本计划不授权实现、正式预测或评分。只有用户另行批准执行本计划后，才允许写预测代码和合成测试。
- 正式预测运行还需要一次性的直接批准文本和精确授权收据；训练完成或训练审核通过不能替代该授权。
- 前置证据必须同时存在并通过：正式输入封存、输入产物独立审核、可信训练目标来源独立审核、
  旧参考函数桥接审核、严格嵌套封存、严格嵌套独立审核、状态数值诊断预注册及其独立重放审核、
  24次主训练总封存和训练独立审核。
- 只允许Maurer五个命名气象变量、27项静态属性、训练期归一化统计和24个第30轮检查点。
- 禁止读取正式评估观测、原始流量目录、水文签名属性、其他气象产品、其他模型输出或正式评分答案。
- 正式期固定为1989-10-01至1999-09-30，共3,652天；固定531个流域；每个逐随机数文件和每个集合
  必须恰有1,939,212行。
- 输出列必须严格为`basin,date,qsim`，顺序必须是冻结流域列表顺序，再按日期升序。
  不允许额外列、重复键、缺失键、非有限值、日期格式变体或未知流域。
- 模型使用评估模式，关闭丢弃层；不截断负值、不做偏差订正、不平滑、不集成后选择、
  不根据任何正式结果改变检查点、权重或输出。
- 每个集合固定使用随机数100、200、300、400、500、600、700、800的顺序，
  采用`float64`累加后除以8，并以`%.17g`写出。
- 三个集合只能一起进入新清洁配对服务：`B09-CLASSIC`为主基准、`B09-CAPACITY`为不改变判定的
  次要控制、`E09-CONTINUOUS`为唯一挑战者。任何集合都不得单独进入旧
  `track0_forcing_only`或被交换角色。
- 第10轮和第20轮检查点不得加载到正式预测入口。
- 长任务启动和运行内存门与版本09训练阶段完全相同；预测批量最大256；一次只运行一个预测进程。
- 预测授权在编排器首次启动时即消耗。成功、失败、中断或异常退出都不得复用；禁止自动重试。
- 预测根目录使用`predictions.building`，全部24个逐随机数文件、三个集合、源码包、清单和审核前封存
  完成后才原子改名为`predictions`。任一同名最终、临时或失败目录存在时拒绝启动。
- 本阶段不得调用`fair_benchmark.score`、不得写正式评分账本、不得计算Nash-Sutcliffe模型效率系数，
  也不得查看候选相对冻结基准的任何性能。
- 经典近期和同参数量控制在531流域上的性能在本阶段仍然未知；生成其预测不等于对它们进行正式评估。

---

### Task 1: 预注册清洁配对三集合角色和正式预测授权作用域

**Files:**
- Read after clean-pair route implementation:
  `src/26_historical_band_experts/configs/formal_v09_clean_pair_scoring_contract.json`
- Create after execution approval:
  `src/26_historical_band_experts/configs/formal_v09_submission.json`
- Modify after execution approval: `src/26_historical_band_experts/stage_authorization_v09.py`
- Test: `src/26_historical_band_experts/tests/test_formal_v09_submission.py`
- Modify: `src/26_historical_band_experts/tests/test_stage_authorization_v09.py`
- Create only after direct prediction approval:
  `src/26_historical_band_experts/configs/formal_v09_prediction_authorization.json`

**Interfaces:**
- `validate_submission_config_v09(config, protocol, clean_pair_contract) -> dict`
- `validate_stage_authorization_v09(receipt, *, action, scope=None, protocol_sha256=None, prerequisite_sha256=None, executable_tree_sha256=None) -> dict`

- [ ] **Step 1: 写固定三角色评分包和授权失败测试**

`formal_v09_submission.json`必须固定：

```json
{
  "submission_id": "S09C-CLEAN-PAIR-BUNDLE",
  "track": "track0_forcing_only_clean_v09",
  "roles": {
    "baseline": "B09-CLASSIC",
    "capacity_control": "B09-CAPACITY",
    "challenger": "E09-CONTINUOUS"
  },
  "challenger_variant": "continuous_multiscale_history",
  "eligible_checkpoint_epoch": 30,
  "seeds": [100, 200, 300, 400, 500, 600, 700, 800],
  "ensemble_operation": "arithmetic_mean",
  "accumulator_dtype": "float64",
  "expected_basin_count": 531,
  "expected_dates_per_basin": 3652,
  "expected_rows": 1939212,
  "prediction_columns": ["basin", "date", "qsim"],
  "formal_score_calls_allowed": 1,
  "standalone_scoring_allowed": false,
  "capacity_control_may_affect_verdict": false
}
```

验证器必须拒绝改变赛道、三角色、挑战者、检查点轮次、随机数、集合运算、行数、列、独立评分
禁止项或同参数量控制的判定作用。

正式预测直接批准文本固定为：

```text
批准版本09正式预测与封存阶段；仅授权24个已审核第30轮检查点生成固定正式预测和三个八随机数均值集合，不批准评分。
```

UTF-8、无末尾换行的SHA-256固定为：

```text
05923aa9ef9f0945c15d125f6f019cc6c6128384f5cfdbab89e783c412b010c0
```

预测收据固定：

- `receipt_id="A09-PREDICT-01"`
- `attempt_id="prediction_attempt_01"`
- `action="formal_prediction_generation"`
- `scope="FORMAL-PREDICT-24"`
- `maximum_attempts=1`
- `output_root="results/26_historical_band_experts/formal_v09/predictions"`
- `allowed_checkpoint_epoch=30`
- `official_scoring_authorized=false`

收据的`prerequisite_sha256`键集合必须恰好绑定清洁配对合同、输入封存、两个输入外部审核报告、
旧参考函数桥接审核、
严格嵌套运行封存、严格嵌套外部审核报告、状态数值诊断预注册文件、状态数值诊断外部审核报告、
训练总封存、训练外部审核报告、24个第30轮检查点和提交配置。
收据还必须绑定可执行源码树和环境哈希。可执行源码树只包含实际运行的Python文件和科学配置，
不包含授权收据、审计文档或结果目录。

- [ ] **Step 2: 运行提交和授权测试并确认失败**

Run:

```powershell
pytest src/26_historical_band_experts/tests/test_formal_v09_submission.py `
  src/26_historical_band_experts/tests/test_stage_authorization_v09.py -q
```

Expected: 新测试失败；既有输入和训练收据测试保持通过。

- [ ] **Step 3: 实现提交配置和预测作用域**

预测作用域使用完整相等比较，不能由`training=true`、协议内布尔值或目录存在推断。
消费收据路径固定为：

```text
results/26_historical_band_experts/formal_v09/prediction_authorization_consumed.json
```

消费发生在全部资源和前置哈希预检通过之后、首个预测子进程启动之前。

- [ ] **Step 4: 运行提交和授权测试**

Run:

```powershell
pytest src/26_historical_band_experts/tests/test_formal_v09_submission.py `
  src/26_historical_band_experts/tests/test_stage_authorization_v09.py -q
```

Expected: PASS。

- [ ] **Step 5: 提交预注册配置和授权验证**

```powershell
git add src/26_historical_band_experts/configs/formal_v09_submission.json `
  src/26_historical_band_experts/stage_authorization_v09.py `
  src/26_historical_band_experts/tests/test_formal_v09_submission.py `
  src/26_historical_band_experts/tests/test_stage_authorization_v09.py
git commit -m "Feat: Freeze formal v09 submission and prediction scope"
```

---

### Task 2: 实现观察盲的逐随机数正式预测

**Files:**
- Create after execution approval: `src/26_historical_band_experts/predict_formal_v09.py`
- Test: `src/26_historical_band_experts/tests/test_predict_formal_v09.py`
- Reuse: `src/26_historical_band_experts/formal_training_data_v09.py`
- Reuse: `src/26_historical_band_experts/prediction_preflight_v09.py`

**Interfaces:**
- `formal_prediction_keys_v09(inputs) -> tuple[np.ndarray, np.ndarray]`
- `load_epoch30_model_v09(run_seal, *, variant, seed, device) -> torch.nn.Module`
- `predict_one_seed_v09(inputs, *, variant, seed, checkpoint, output_path, gate) -> dict`

- [ ] **Step 1: 写正式预测边界失败测试**

测试必须证明：

- 固定键从1989-10-01至1999-09-30生成，531×3,652恰为1,939,212；
- 最早目标日使用1980-01-01至1989-10-01的3,562天因果窗口，不读取更早或未来气象；
- 第30轮检查点的实验标识、模型族、随机数、参数量和哈希必须匹配训练总封存；
- 第10轮、第20轮、未封存检查点或手工复制检查点均拒绝；
- 模型处于`eval()`且`torch.no_grad()`，输出丢弃层不消耗随机数；
- 经典、停用历史和同参数量控制只读取270天近期；连续历史读取固定120个历史分箱；
- 输出严格按冻结键顺序，列为`basin,date,qsim`；
- 反归一化使用封存的训练期流量中心和尺度；
- 负值保持原样，任何裁剪、校准或后处理参数都拒绝；
- 预测路径无法导入可信目标导出模块，也无法打开正式评估观测；
- 临时文件在异常时删除，已存在最终文件不覆盖；
- 分块之间内存门持续执行。

- [ ] **Step 2: 运行预测测试并确认失败**

Run:

```powershell
pytest src/26_historical_band_experts/tests/test_predict_formal_v09.py -q
```

Expected: FAIL，原因是正式预测模块尚不存在。

- [ ] **Step 3: 实现固定正式键和检查点重载**

正式键不从预测、目标或文件内容推断，而由协议日期和冻结流域列表直接构造。检查点加载使用
`weights_only`安全路径或显式受控的字典结构，只接受：

- `model_state_dict`
- `optimizer_state_dict`
- `epoch`
- `seed`
- `variant`
- `protocol_sha256`
- `input_seal_sha256`
- `source_tree_sha256`
- `environment_sha256`

预测只使用`model_state_dict`；其余字段用于完整相等验证。

- [ ] **Step 4: 实现流式预测和原子文件**

每个批次最多256项。输出先写同目录`.tmp`文件；每一块立即验证键顺序和`qsim`有限性。
文件完成后调用`validate_exact_prediction_coverage_v09()`，只有通过才原子改名。

逐随机数文件路径固定为：

```text
predictions/per_seed/B09-CLASSIC/seed_100.csv
predictions/per_seed/B09-CAPACITY/seed_100.csv
predictions/per_seed/E09-CONTINUOUS/seed_100.csv
```

其余随机数替换末尾数值，目录和大小写不得变化。

- [ ] **Step 5: 运行预测和覆盖测试**

Run:

```powershell
pytest src/26_historical_band_experts/tests/test_predict_formal_v09.py `
  src/26_historical_band_experts/tests/test_prediction_preflight_v09.py -q
```

Expected: PASS。

- [ ] **Step 6: 提交逐随机数预测实现**

```powershell
git add src/26_historical_band_experts/predict_formal_v09.py `
  src/26_historical_band_experts/tests/test_predict_formal_v09.py
git commit -m "Feat: Add observation-blind formal v09 prediction"
```

---

### Task 3: 实现24文件串行编排和三个固定集合

**Files:**
- Create after execution approval: `src/26_historical_band_experts/run_formal_prediction_v09.py`
- Test: `src/26_historical_band_experts/tests/test_run_formal_prediction_v09.py`
- Reuse: `src/26_historical_band_experts/prediction_preflight_v09.py`

**Interfaces:**
- `prediction_run_order_v09(training_order) -> tuple[PredictionRunSpecV09, ...]`
- `compose_formal_ensembles_v09(prediction_root, submission_config, gate) -> dict`
- `run_formal_prediction_suite_v09(protocol_path, submission_path, authorization_path, input_root, training_seal_path, output_root, device) -> dict`

- [ ] **Step 1: 写编排和集合失败测试**

预测顺序固定复用训练阶段的24项顺序。编排测试必须拒绝：

- 缺失、多出、交换或重复逐随机数任务；
- 同时存在两个正式预测子进程；
- 输入、训练、源码或环境哈希在子进程之间漂移；
- 任一逐随机数文件未通过1,939,212行精确覆盖；
- 集合输入顺序不是100至800；
- 集合使用`float32`累加、不同键顺序、少于或多于八个文件；
- 集合输出已存在或临时文件残留；
- 经典或同参数量集合被标记为可正式评分；
- 任一失败后仍启动后续预测。

- [ ] **Step 2: 运行编排测试并确认失败**

Run:

```powershell
pytest src/26_historical_band_experts/tests/test_run_formal_prediction_v09.py -q
```

Expected: FAIL，原因是编排器尚不存在。

- [ ] **Step 3: 实现串行预测编排**

编排器在启动前一次性验证24个第30轮检查点和所有输出路径，再消费授权。每个逐随机数预测在独立进程
中运行；完成后立即执行精确覆盖和哈希审核。任一失败把`predictions.building`原子改名为
`predictions.failed`，写`prediction_attempt_01.failure.json`并停止，不删除已完成文件。
正常完成24个文件和三个集合后仍保留`predictions.building`名称；独立重放和源码包审核通过前不得
改名为最终`predictions`。

- [ ] **Step 4: 实现三个集合**

固定输出：

```text
predictions/ensembles/B09-CLASSIC_ensemble.csv
predictions/ensembles/B09-CAPACITY_ensemble.csv
predictions/ensembles/E09-CONTINUOUS_ensemble.csv
```

调用`compose_seed_mean_v09()`逐块构建。三个集合完成后再次运行精确覆盖检查。
集合清单明确：

- `B09-CLASSIC_ensemble.csv`:
  `clean_pair_role=baseline, standalone_scoring=false`
- `B09-CAPACITY_ensemble.csv`:
  `clean_pair_role=capacity_control_descriptive, standalone_scoring=false`
- `E09-CONTINUOUS_ensemble.csv`:
  `clean_pair_role=challenger, standalone_scoring=false`

- [ ] **Step 5: 运行编排和集合测试**

Run:

```powershell
pytest src/26_historical_band_experts/tests/test_run_formal_prediction_v09.py `
  src/26_historical_band_experts/tests/test_prediction_preflight_v09.py -q
```

Expected: PASS。

- [ ] **Step 6: 提交预测编排器**

```powershell
git add src/26_historical_band_experts/run_formal_prediction_v09.py `
  src/26_historical_band_experts/tests/test_run_formal_prediction_v09.py
git commit -m "Feat: Add serial formal v09 prediction suite"
```

---

### Task 4: 构建评分静态扫描专用候选源码包

**Files:**
- Create after execution approval: `src/26_historical_band_experts/build_candidate_source_bundle_v09.py`
- Test: `src/26_historical_band_experts/tests/test_candidate_source_bundle_v09.py`
- Generated, not tracked:
  `results/26_historical_band_experts/formal_v09/predictions/source_bundle/`

**Interfaces:**
- `trace_repo_local_runtime_sources_v09(entrypoints, synthetic_args) -> tuple[Path, ...]`
- `build_candidate_source_bundle_v09(source_paths, config_paths, output_root) -> dict`
- `audit_candidate_source_bundle_v09(bundle_root, training_seal, prediction_manifest) -> dict`

- [ ] **Step 1: 写源码包完整性和泄漏扫描失败测试**

测试必须证明：

- 包含候选训练和预测实际执行的全部仓库内Python源码及科学配置；
- 仓库外依赖不复制，但`pip freeze`、Python、PyTorch、CUDA和驱动版本在环境封存中绑定；
- 源码列表来自受控合成运行的仓库内模块导入追踪，并与训练、预测清单中的运行时源码集合并；
- 手工删除一个被执行的本地模块时审核失败；
- 加入未执行的可信训练目标导出工具、正式评分答案工具或包含禁用访问标记的文件时扫描失败；
- 评分扫描器`scan_for_forbidden_access()`对最终包返回零命中；
- `formal_v09_protocol.json`因自身列出禁用访问词而不复制进静态扫描包，但其SHA-256、
  Git对象和完整路径由预测封存在包外绑定；
- 排除协议文件不能排除任何候选实际数据读取代码；
- 源码包不能包含预测数值、训练目标、检查点或正式观测；
- 包完成后不可覆盖。

- [ ] **Step 2: 运行源码包测试并确认失败**

Run:

```powershell
pytest src/26_historical_band_experts/tests/test_candidate_source_bundle_v09.py -q
```

Expected: FAIL，原因是源码包构建器尚不存在。

- [ ] **Step 3: 实现运行时源码追踪**

追踪器记录所有`module.__file__`位于仓库根目录下且在下列入口的受控合成执行中实际加载的文件：

- 严格嵌套训练；
- 三个主模型训练；
- 三个模型正式预测；
- 八随机数集合构建。

最终清单取合成追踪、24个训练运行清单和24个预测运行清单的并集。测试文件、计划文档、
可信输入构建入口、正式评分代码和冻结答案不属于候选运行源码，不进入包。

- [ ] **Step 4: 实现无规避的静态扫描包**

源码包保留仓库相对目录。`source_bundle_manifest.json`只列入包文件及其哈希、外部协议哈希和环境哈希；
它不得改写源码、删除源码行、重命名变量或把可扫描源码改成扫描器不识别的扩展名。

如果实际候选运行源码本身触发禁用词，状态为`HOLD`并修改代码的数据边界设计后重新走测试和训练，
不得通过改后缀或过滤行绕过。

- [ ] **Step 5: 运行正式扫描器测试**

Run:

```powershell
pytest src/26_historical_band_experts/tests/test_candidate_source_bundle_v09.py `
  src/fair_benchmark/tests/test_leakage.py -q
```

Expected: PASS，最终测试包扫描命中数为0。

- [ ] **Step 6: 提交源码包构建器**

```powershell
git add src/26_historical_band_experts/build_candidate_source_bundle_v09.py `
  src/26_historical_band_experts/tests/test_candidate_source_bundle_v09.py
git commit -m "Feat: Add formal v09 candidate source bundle"
```

---

### Task 5: 实现全部24个预测和三个集合的独立重放审核

**Files:**
- Create after execution approval: `src/26_historical_band_experts/audit_formal_prediction_v09.py`
- Test: `src/26_historical_band_experts/tests/test_audit_formal_prediction_v09.py`
- Generated, not tracked:
  `results/26_historical_band_experts/formal_v09/prediction_external_audit.json`

**Interfaces:**
- `audit_prediction_file_v09(path, expected_spec, checkpoint_sha256) -> dict`
- `replay_prediction_suite_v09(input_root, training_seal, prediction_root, scratch_root, device) -> dict`
- `audit_formal_prediction_suite_v09(protocol_path, submission_path, input_root, training_seal_path, prediction_root, scratch_root, report_path, device) -> dict`
- `finalize_formal_prediction_v09(staging_root, external_audit_path, final_root) -> dict`

- [ ] **Step 1: 写独立审核反驳测试**

审核器必须拒绝：

- 任一逐随机数文件或集合的行数、键、顺序、有限性或哈希不正确；
- 任一文件包含`qobs`、模型选择指标或额外列；
- 任一检查点不是第30轮；
- 反归一化、负值处理、随机数顺序或`float64`集合规则漂移；
- 预注册提交不是连续历史八随机数集合；
- 源码包不完整或正式扫描器命中不为0；
- 正式评分账本在本阶段新增；
- 重放临时目录位于封存预测目录内部；
- 独立重放任一`qsim`最大绝对差超过`1e-6`或键不完全相同。

- [ ] **Step 2: 运行独立审核测试并确认失败**

Run:

```powershell
pytest src/26_historical_band_experts/tests/test_audit_formal_prediction_v09.py -q
```

Expected: FAIL，原因是预测审核器尚不存在。

- [ ] **Step 3: 实现24文件全量重放**

独立上下文在封存目录之外创建一次性临时根目录，重新加载输入和24个第30轮检查点，生成全部
24个正式期预测，再重建三个集合。每个重放文件与封存文件比较：

- 键逐行完全相同；
- 行数恰为1,939,212；
- `qsim`全部有限；
- 最大绝对差不超过`1e-6`，相对容差为0。

审核结束后保留审核报告和重放文件哈希清单；临时数值文件可在报告写成并验证后删除，但不得删除或修改
正式封存目录。

- [ ] **Step 4: 审核评分源码包和账本边界**

审核器调用静态扫描函数，但不调用`score_submission()`或命令行评分入口。它记录：

- 源码包文件数和哈希树；
- 正式禁用词扫描命中数0；
- 预注册候选文件路径和SHA-256；
- 正式评分账本行数和SHA-256与预测前快照相同；
- `official_score_called=false`。

- [ ] **Step 5: 运行预测审核测试**

Run:

```powershell
pytest src/26_historical_band_experts/tests/test_audit_formal_prediction_v09.py -q
```

Expected: PASS。

- [ ] **Step 6: 实现审核后唯一终结器**

终结器只接受`predictions.building`，验证独立报告位于目录外且状态完整，重新计算27个预测文件、
源码包和清单哈希，在暂存目录内最后写入`seal.json`。随后只读重载全部哈希，才把
`predictions.building`原子改名为`predictions`。最终目录已存在、独立报告漂移或封存重载失败时
拒绝改名。

- [ ] **Step 7: 提交预测审核器和终结器**

```powershell
git add src/26_historical_band_experts/audit_formal_prediction_v09.py `
  src/26_historical_band_experts/tests/test_audit_formal_prediction_v09.py
git commit -m "Feat: Add independent formal v09 prediction replay"
```

---

### Task 6: 执行一次正式预测、独立审核并最终封存

**Files:**
- Create only after direct approval:
  `src/26_historical_band_experts/configs/formal_v09_prediction_authorization.json`
- Modify after completion: `src/26_historical_band_experts/registry.csv`
- Create after completion:
  `docs/technical/historical_multiscale_formal_v09_prediction_audit.md`
- Generated, not tracked:
  `results/26_historical_band_experts/formal_v09/predictions/`
- Generated, not tracked:
  `results/26_historical_band_experts/formal_v09/prediction_external_audit.json`

**Interfaces:**
- Consumes: 已通过测试的预测代码、训练总封存和逐字预测批准。
- Produces: 24个逐随机数文件、三个集合、候选源码包、独立重放审核和预测总封存。

- [ ] **Step 1: 在任何正式预测前完成代码审核**

代码全部提交后：

1. 只格式化本计划新增或修改的Python文件；
2. 可用物理内存至少12.68 GiB时运行
   `pytest src/26_historical_band_experts/tests -q`；
3. 记录准确测试数量、警告和耗时；
4. 确认工作区干净、协议哈希不变、冻结目录和评分代码没有差异；
5. 确认正式评分账本没有新增行；
6. 独立审查预测路径无法访问正式评估观测。

任一项失败不得请求预测授权。

- [ ] **Step 2: 请求并固化一次性预测授权**

只有用户逐字发送Task 1中的预测批准文本后，才创建收据，填入实际输入、训练、24个检查点、
提交配置、源码树和环境哈希，并提交：

```powershell
git add src/26_historical_band_experts/configs/formal_v09_prediction_authorization.json `
  src/26_historical_band_experts/registry.csv
git commit -m "Phase: Authorize formal v09 prediction"
```

- [ ] **Step 3: 一次性运行24个正式预测和三个集合**

```powershell
python src\26_historical_band_experts\run_formal_prediction_v09.py `
  --protocol src\26_historical_band_experts\configs\formal_v09_protocol.json `
  --submission src\26_historical_band_experts\configs\formal_v09_submission.json `
  --authorization src\26_historical_band_experts\configs\formal_v09_prediction_authorization.json `
  --input-root results\26_historical_band_experts\formal_v09\input_attempt_01 `
  --training-seal results\26_historical_band_experts\formal_v09\training_seal.json `
  --output-root results\26_historical_band_experts\formal_v09\predictions `
  --device cuda:0
```

运行只报告行数、进度、资源和哈希，不报告性能。

- [ ] **Step 4: 构建并审核候选源码包**

```powershell
python src\26_historical_band_experts\build_candidate_source_bundle_v09.py `
  --training-seal results\26_historical_band_experts\formal_v09\training_seal.json `
  --prediction-root results\26_historical_band_experts\formal_v09\predictions.building `
  --output-root results\26_historical_band_experts\formal_v09\predictions.building\source_bundle
```

Expected: 运行时源码完整，正式静态扫描命中数0。

- [ ] **Step 5: 在独立上下文全量重放**

```powershell
python src\26_historical_band_experts\audit_formal_prediction_v09.py `
  --protocol src\26_historical_band_experts\configs\formal_v09_protocol.json `
  --submission src\26_historical_band_experts\configs\formal_v09_submission.json `
  --input-root results\26_historical_band_experts\formal_v09\input_attempt_01 `
  --training-seal results\26_historical_band_experts\formal_v09\training_seal.json `
  --prediction-root results\26_historical_band_experts\formal_v09\predictions.building `
  --scratch-root results\26_historical_band_experts\formal_v09\prediction_replay_scratch `
  --report results\26_historical_band_experts\formal_v09\prediction_external_audit.json `
  --device cuda:0
```

Expected: 24个逐随机数文件和三个集合全部最大绝对差不超过`1e-6`，静态扫描命中0，
正式评分账本未变化。

- [ ] **Step 6: 写预测总封存并原子终结**

独立审核通过后运行：

```powershell
python src\26_historical_band_experts\audit_formal_prediction_v09.py `
  --finalize `
  --prediction-root results\26_historical_band_experts\formal_v09\predictions.building `
  --report results\26_historical_band_experts\formal_v09\prediction_external_audit.json `
  --final-root results\26_historical_band_experts\formal_v09\predictions
```

终结器在暂存目录内写`seal.json`，其内容包括：

- 输入、训练、严格嵌套、提交配置、授权、源码和环境哈希；
- 输入产物外部审核、可信训练目标来源外部审核、旧参考函数桥接审核、严格嵌套外部审核、
  状态数值诊断预注册、状态数值诊断外部审核和训练外部审核哈希；
- 24个逐随机数预测和三个集合的路径、行数、覆盖报告和SHA-256；
- 候选源码包哈希树和扫描命中数0；
- 独立重放报告SHA-256；
- 清洁配对角色、三个集合路径及SHA-256，其中`E09-CONTINUOUS`是唯一挑战者；
- 三个集合均为`standalone_scoring=false`，只允许固定组合`S09C-CLEAN-PAIR`；
- `official_score_called=false`。

封存写出后先只读重载并重算全部哈希，再把整个目录原子改名为最终`predictions`。

- [ ] **Step 7: 记录预测阶段结论**

预测审计文档必须区分：

- 事实：27个预测文件、覆盖、最大重放差、源码扫描和哈希；
- 未知：尚未调用正式评分服务，因此候选效果仍无法确定；
- 下一条件：独立评分前置审核和用户对唯一候选哈希的一次评分批准；
- 禁止推断：预测完成或文件之间差异不能证明模型优于冻结基准。

```powershell
git add docs/technical/historical_multiscale_formal_v09_prediction_audit.md `
  src/26_historical_band_experts/registry.csv
git commit -m "Phase: Record formal v09 prediction audit"
```

## Stopping Conditions

以下任一情况立即停止并保持正式评分`NO-GO`：

- 输入、严格嵌套、状态数值诊断、24次训练或对应独立审核未通过；
- 用户没有逐字直接批准预测；
- 授权已消费、预测目录已存在或工作区不干净；
- 任一第30轮检查点、输入、源码、环境或配置哈希漂移；
- 内存、驻留内存、单次分配或显存资源门失败；
- 任一正式键缺失、重复、越界、顺序错误或`qsim`非有限；
- 出现后处理、检查点选择、集合权重变化或随机数顺序变化；
- 任一逐随机数文件或集合不是1,939,212行；
- 独立重放最大绝对差超过`1e-6`；
- 候选源码包不完整或正式静态扫描命中不为0；
- 正式评估观测被读取、评分账本变化或评分入口被调用；
- 三个集合的固定角色、文件和预测总封存尚未通过只读重载。

## Self-Review

- 选择前置：连续历史候选和第30轮八随机数均值在预测前固定，不能按正式结果改选控制或随机数。
- 覆盖强度：24个逐随机数文件和三个集合均要求531×3,652个精确键，而不是评分服务的99%最低线。
- 数值规则：评估模式、无后处理、`float64`固定顺序集合和17位写出全部由测试约束。
- 数据边界：预测入口只读气象、静态属性、训练统计和检查点；不含任何正式观测。
- 独立重放：全部27个文件重建，最大绝对差`1e-6`，不能用抽样检查代替。
- 扫描边界：评分显式扫描一个完整候选运行源码包；协议因自述禁用词导致的假阳性在包外用哈希绑定，
  不能借此排除实际运行代码。
- 评分边界：本阶段没有正式评分调用；三个集合只能按清洁配对固定角色一起交付，不能单独评分。

## Execution Handoff

当前状态应保持`NO-GO`：本文件只是实施计划，正式输入、严格嵌套和24次训练尚未完成，
正式预测也未获授权。执行顺序不可合并：

1. 训练总封存和独立审核通过；
2. 用户批准实施预测代码和合成测试；
3. 代码审核通过后，用户逐字批准一次正式预测；
4. 24个逐随机数文件、三个集合、源码包和全量独立重放全部通过；
5. 锁定三个集合及其固定角色的实际SHA-256后，才进入清洁配对唯一一次评分计划。
