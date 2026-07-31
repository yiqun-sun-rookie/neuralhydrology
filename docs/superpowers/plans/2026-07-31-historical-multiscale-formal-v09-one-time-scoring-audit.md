# 历史连续多尺度气象模型版本09唯一一次正式评分与独立终审实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

## 当前停止状态

本计划当前为`HOLD`，不得实施或执行。只读审核已证明正式评分冻结经典基准的训练统计包含
`1999-01-05`至`1999-09-30`的可用正式评估期流量，违反冻结赛道禁止正式评估期观测和测试期统计
的相同信息条件。证据见
`docs/technical/historical_multiscale_formal_v09_frozen_baseline_information_audit.md`。

只有新的独立基准资格审核返回`eligible_same_information`，并且用户批准一条不修改受保护文件的
明确修复路线后，本计划才可恢复。现有冻结基准资格状态为`ineligible_same_information`；候选预测
哈希授权和冻结清单历史例外均不能覆盖该失败。

**Goal:** 在连续历史八随机数集合、完整候选源码包和全部前置证据封存后，由未参与实现的独立审查者执行唯一一次正式评分调用，并在不重复评分的前提下审核代码、结构、数据边界、产物、账本和最终结论。

**Architecture:** 一个外层只读前置门验证预测哈希、531流域精确覆盖、源码扫描、冻结规范历史例外、评分代码、账本链和一次性授权。授权在正式评分函数启动前原子消费。独立审查者从固定工作区的干净提交调用现有`fair_benchmark.score`一次，显式把`--experiment-dir`指向候选源码包。评分后同一独立审查流程验证报告与账本的唯一追加、重新执行门槛逻辑但不再次读取观测或调用评分服务，并形成不依赖实现者自签名的终审结论。

**Tech Stack:** Python 3.11、pandas、NumPy、SciPy、ruamel.yaml、pytest、Git、SHA-256、现有`fair_benchmark.score`、现有哈希链账本。

## Global Constraints

- 本计划不授权实现或评分。只有用户另行批准执行本计划后，才允许写外层前置门和合成测试。
- 冻结基准资格审核必须为`eligible_same_information`；任何缺失、`HOLD`或
  `ineligible_same_information`都在创建评分授权前停止。
- 正式评分还需要在实际候选预测SHA-256已知后，由用户发送一条包含该具体哈希和冻结清单历史例外的
  逐字直接批准；预测授权、训练授权或“继续”均不能替代。
- 不修改`src/fair_benchmark/frozen/`、`src/fair_benchmark/score.py`、
  `tracks.py`、`gate.py`、`stats.py`、`ledger.py`、`leakage.py`、`io.py`或`metrics.py`。
- 唯一评分对象是预注册的`S09-SEALED`，来源文件固定为连续历史模型第30轮八随机数均值集合。
  经典近期集合和同参数量控制集合不得调用评分服务。
- 正式评分命令最多启动一次。授权在调用开始时消耗；通过、暂缓、拒绝、异常退出、机器中断或报告写入
  失败都不得凭原授权重试。
- 独立终审不得第二次调用`score.py`、`score_submission()`或任何会读取正式评估观测并追加账本的入口。
- 正式评分前候选预测必须已通过531个流域、每流域3,652天、总计1,939,212行的精确覆盖；
  不能只依赖评分服务内部99%最低覆盖线。
- 评分调用必须显式传入候选源码包作为`--experiment-dir`；不得使用预测文件父目录、整个研究目录或
  可信正式输入构建工具目录。
- 候选源码包的正式禁用访问扫描命中数必须为0。
- 不使用`--allow-unconfirmed`；冻结赛道规范必须保持`confirmed: true`。
- 正式结论完全服从评分服务返回的`PASS`、`HOLD`或`REJECT`。不得由自算指标、内部60流域结果、
  干净经典控制或训练损失覆盖正式结论。
- `PASS`只表示连续历史八随机数集合相对冻结经典八随机数基准通过正式门；不表示优于未评分的
  369单元控制，也不表示所有流域、所有时期或其他气象产品均改进。
- `HOLD`表示有效提交没有形成可声明胜利或秘密流域不一致；`REJECT`表示覆盖、合同或其他完整性失败。
  若唯一调用异常且没有完整服务报告，终审结论固定为`HOLD`，并明确“正式结果不完整、禁止重试和性能声明”。
- 无论结果为何，最后都必须由未参与实现的独立审查者审核源码、模型结构、输入边界、封存链、
  评分调用、账本和文字结论。

## Frozen Scoring Contract

以下值来自2026-07-31只读审核，并作为外层评分合同的当前基线。执行时必须再次重算；任何漂移均停止，
不得自动更新合同。

| 文件 | Git对象标识 | 当前工作区字节SHA-256 |
|---|---|---|
| `score.py` | `138be0ee8fe994223365a4dc2a7739a26aa7edd1` | `9e3cb83254842e98ee4c5a61a4a273d7ce73c0676573573855e174bbc97779d7` |
| `tracks.py` | `f86647c36d3d1eef9ebb511e6fea24387522f673` | `e591f838410f063c6b128e3a244688fb66f7915f7b7ce0ea1275fb22f7219b5c` |
| `gate.py` | `9fa57cf98e381da84aec7e1794afce9695437904` | `7913505435c7a56a2fa38c80028c188270ef573379ccca53172ea75339d5b5df` |
| `stats.py` | `f5a16d152e9c5e58b68049133c40873c3d4fc5b3` | `284e18b8296c82b0a04a90a4deeb7b51cea0dc3a27c8ac9df31481d8025b8bb3` |
| `ledger.py` | `3e02e5621e0d85c88abec7970b4cdb67a3a5dc74` | `bad6edb772d3b162cea37a165e679c8eb9656c2813403ad0b7d784c20ec181a2` |
| `leakage.py` | `2ca77412e49aa4aec3846e54fb19fff902149c6f` | `20aafe9e704eaabea312da29b8ea3791310076b98a2e86f4b0780d7c75689856` |
| `io.py` | `dbed5a3c1df7c25a5d0d408a5ec08a1b1f129f64` | `88126942f6fec6d9df0c0f60389c3ebec2c0e711bbeeccaa795595aa5ef31903` |
| `metrics.py` | `2f7afcbc25c35dadaf05a260b8e9e81bcdb42199` | `4331717056f241af110876cb7b84922e15171120de897dd0073cdf1e5587a6cc` |

冻结规范历史例外固定为：

- `MANIFEST.sha256`登记值：
  `1beb31af1e7d1131370ffe6c3f829b897869599cb75dbd42917265da0e1a9c00`
- 规范文件Git对象标识：
  `cde74e4a68ccf7bc0b0943c62eb0667cc542fbec`
- Git换行字节SHA-256：
  `0439eb55cd059300eca9c90c20aaed1901cd8be5e9b556bd4ae2e4609a2f5d5e`
- 当前Windows换行字节SHA-256：
  `8fb707cb5e2ec0f8edbf3f191f9ce836d259e8a31286466da63e6e62791388fb`
- 规范化语义SHA-256：
  `dedf11d4efa6117410a90922835036b4c0748b8d9d1340caa927b7f292a96170`

`MANIFEST.sha256`登记值无法从现有Git历史重建；评分代码也不读取该清单。唯一允许的非破坏性处置是：
保持冻结目录不变，由外层前置门验证Git对象、实际字节和语义哈希，并要求用户在唯一评分批准中逐字接受
这一个已记录的历史例外。

当前只读账本快照有7条数据记录、没有`S09-SEALED`，工作区字节SHA-256为
`f6d703a7fb0067c45f80494b00b6a3fcd32c6dc7aff82e3a69d1328b6f20b409`。
这只是计划编写时的事实，不是未来评分时的固定值；正式授权必须绑定评分前即时账本行数、末行哈希和
文件SHA-256。

---

### Task 1: 冻结外层评分合同并实现只读前置门

**Files:**
- Create after execution approval:
  `src/26_historical_band_experts/configs/formal_v09_scoring_contract.json`
- Create after execution approval: `src/26_historical_band_experts/formal_scoring_preflight_v09.py`
- Test: `src/26_historical_band_experts/tests/test_formal_scoring_preflight_v09.py`

**Interfaces:**
- `validate_scoring_contract_v09(contract) -> dict`
- `canonical_track_spec_sha256_v09(path) -> str`
- `preflight_one_time_score_v09(*, prediction_seal, source_bundle, ledger, contract, authorization=None) -> dict`

- [ ] **Step 1: 写评分合同失败测试**

合同必须精确固定：

- `experiment_id="S09-SEALED"`
- `track="track0_forcing_only"`
- `score_calls_allowed=1`
- `allow_unconfirmed=false`
- 正式公开门：配对中位提升至少0.01、Wilcoxon检验p值小于0.05、
  10,000次流域自助抽样区间下界大于0；
- 秘密流域门：配对中位提升至少0.005且至少保留公开配对中位提升的50%；
- 评分代码表中的Git对象和字节哈希；
- 冻结规范的五个历史例外指纹；
- 相对提交`75d02d295236b20edc4a593c452d568ce5515dce`，
  冻结目录和正式评分代码差异必须为空；
- 候选源码扫描命中必须为0；
- 正式预测精确覆盖必须为531×3,652；
- 账本必须没有`S09-SEALED`；
- 评分报告和调用日志必须位于
  `results/26_historical_band_experts/formal_v09/scoring/S09-SEALED/`。

测试必须在任一字段、门槛、哈希、Git对象、规范语义或实验标识漂移时失败。

- [ ] **Step 2: 写前置门反驳测试**

使用临时合成预测、临时冻结规范和临时账本，覆盖：

- 预测封存或独立重放报告缺失；
- 输入产物审核、可信训练目标来源审核、旧参考函数桥接审核、严格嵌套审核、状态数值诊断预注册、
  状态数值诊断外部审核、训练审核或预测审核未被后继封存逐层绑定；
- 唯一候选路径不是连续历史集合；
- 候选文件SHA-256与预测封存不一致；
- 行数、键、日期或有限性不是精确覆盖；
- 候选源码包哈希不一致或静态扫描命中；
- 工作区不干净或受保护文件存在差异；
- 评分代码Git对象或字节哈希漂移；
- 冻结规范Git对象、LF字节、Windows字节或语义哈希不在合同中；
- `confirmed`不是`true`；
- 评分门槛或自助抽样次数、随机数不是合同值；
- 账本哈希链断裂、已有`S09-SEALED`或评分进程正在运行；
- 正式报告、临时报告、消费收据、标准输出或错误输出路径已存在；
- 没有具体预测哈希的一次性评分收据。

- [ ] **Step 3: 运行前置门测试并确认失败**

Run:

```powershell
pytest src/26_historical_band_experts/tests/test_formal_scoring_preflight_v09.py -q
```

Expected: FAIL，原因是评分合同和前置门尚不存在。

- [ ] **Step 4: 实现只读评分合同验证**

前置门必须使用Git对象标识验证受保护评分代码，并同时计算当前工作区字节哈希。规范语义哈希固定使用：

1. `ruamel.yaml`安全模式加载；
2. `json.dumps(..., ensure_ascii=False, sort_keys=True, separators=(',', ':'))`；
3. 对UTF-8字节计算SHA-256。

它还必须独立验证`gate.py`实际构造的门槛和`stats.py`的10,000次、随机数0，而不是只信计划JSON。

- [ ] **Step 5: 实现账本和候选前置审核**

账本审核记录：

- 即时文件SHA-256；
- 数据行数；
- 末行`row_hash`；
- `verify_chain()`结果；
- `S09-SEALED`出现次数0。

候选审核重新运行精确覆盖、预测哈希、预测总封存、独立重放报告和源码包静态扫描。
前置门不加载正式评估观测，不调用评分函数，也不修改任何文件。

- [ ] **Step 6: 运行前置门和正式评分组件测试**

Run:

```powershell
pytest src/26_historical_band_experts/tests/test_formal_scoring_preflight_v09.py `
  src/fair_benchmark/tests/test_gate.py `
  src/fair_benchmark/tests/test_stats.py `
  src/fair_benchmark/tests/test_tracks.py `
  src/fair_benchmark/tests/test_ledger.py `
  src/fair_benchmark/tests/test_leakage.py -q
```

Expected: PASS。

- [ ] **Step 7: 提交评分合同和前置门**

```powershell
git add src/26_historical_band_experts/configs/formal_v09_scoring_contract.json `
  src/26_historical_band_experts/formal_scoring_preflight_v09.py `
  src/26_historical_band_experts/tests/test_formal_scoring_preflight_v09.py
git commit -m "Feat: Add formal v09 one-time scoring preflight"
```

---

### Task 2: 实现一次性评分包装器和不可重试收据

**Files:**
- Create after execution approval: `src/26_historical_band_experts/run_one_time_score_v09.py`
- Test: `src/26_historical_band_experts/tests/test_run_one_time_score_v09.py`
- Modify after execution approval: `src/26_historical_band_experts/stage_authorization_v09.py`
- Modify: `src/26_historical_band_experts/tests/test_stage_authorization_v09.py`
- Create only after direct scoring approval:
  `src/26_historical_band_experts/configs/formal_v09_scoring_authorization.json`

**Interfaces:**
- `render_scoring_approval_text_v09(candidate_predictions_sha256) -> str`
- `validate_scoring_authorization_v09(receipt, preflight_report) -> dict`
- `run_one_time_score_v09(...) -> dict`

- [ ] **Step 1: 写动态但精确的批准文本测试**

批准文本不能在预测哈希未知时预生成。渲染器接收预测总封存中实际的64位小写SHA-256，
按以下字符串连接规则生成完整文本：

```python
def render_scoring_approval_text_v09(candidate_predictions_sha256: str) -> str:
    return (
        "批准版本09唯一一次正式评分；连续历史候选预测SHA-256为"
        + candidate_predictions_sha256
        + "；我确认冻结清单登记1beb31af1e7d1131370ffe6c3f829b897869599cb75dbd42917265da0e1a9c00"
        + "与Git规范0439eb55cd059300eca9c90c20aaed1901cd8be5e9b556bd4ae2e4609a2f5d5e"
        + "及Windows字节8fb707cb5e2ec0f8edbf3f191f9ce836d259e8a31286466da63e6e62791388fb"
        + "不一致，并接受语义哈希dedf11d4efa6117410a90922835036b4c0748b8d9d1340caa927b7f292a96170"
        + "的已记录历史例外；只授权S09-SEALED在track0_forcing_only评分一次，不批准任何重试。"
    )
```

用户必须收到渲染后的完整具体文本并逐字发送；不能发送变量名、缩短哈希或概括同意。
收据保存完整文本及其UTF-8无末尾换行SHA-256。

- [ ] **Step 2: 写一次性包装器失败测试**

使用完全临时的合成赛道、合成观测和临时账本，测试：

- 授权作用域固定为`action="official_scoring"`、`scope="S09-SEALED-ONCE"`；
- 收据绑定候选预测、预测总封存、源码包、评分合同、评分代码、冻结规范、账本前快照和报告目录；
- 收据`maximum_attempts=1`且`retry_authorized=false`；
- 消费收据使用独占创建，已存在时拒绝；
- 前置门失败时不消费授权；
- 前置门通过后、评分函数调用前消费授权；
- 正式评分函数恰好调用一次；
- 无论返回、抛出异常或报告写入失败，都保留消费收据和尝试日志；
- 异常后第二次调用固定失败；
- 包装器不接受经典或同参数量控制集合；
- 包装器不传`allow_unconfirmed`，并显式传候选源码包；
- 临时合成评分追加恰好一条临时账本记录。

- [ ] **Step 3: 运行包装器测试并确认失败**

Run:

```powershell
pytest src/26_historical_band_experts/tests/test_run_one_time_score_v09.py `
  src/26_historical_band_experts/tests/test_stage_authorization_v09.py -q
```

Expected: FAIL，原因是一次性包装器尚不存在。

- [ ] **Step 4: 实现不可重试评分事务外壳**

消费收据固定路径：

```text
results/26_historical_band_experts/formal_v09/scoring_authorization_consumed.json
```

评分目录固定包含：

- `preflight.json`
- `attempt.json`
- `score_report.json`
- `score_report.json.tmp`（仅在评分服务写入期间存在；成功验证后原子改名）
- `stdout.txt`
- `stderr.txt`
- `post_score_ledger.json`

包装器按以下顺序执行：

1. 只读前置门并把结果原子写入`preflight.json`；
2. 再次确认报告目录除前置报告外为空、没有评分进程、账本未变化；
3. 原子独占写消费收据；
4. 写`attempt.json`的`status="started"`、确切命令参数和启动时间；
5. 调用现有评分服务一次，并把唯一`--out`指向事先不存在的`score_report.json.tmp`；
6. 进程正常退出后验证临时报告是完整JSON、实验标识和候选哈希正确，再原子改名为
   `score_report.json`；外层包装器不得第二次写同一报告内容；
7. 捕获标准输出、错误输出和退出状态；
8. 重算账本并写`post_score_ledger.json`；
9. 把尝试状态写为`completed`或`failed_after_authorization_consumed`。

现有评分服务先追加账本、后写报告，因此第5步异常可能留下账本记录但没有完整报告。不管第5步之后
发生什么，都禁止第二次进入第5步；该状态由评分后终审归类为`HOLD`。

- [ ] **Step 5: 固定唯一评分参数**

包装器调用现有服务时必须等价于：

```powershell
Set-Location src
python -m fair_benchmark.score `
  --predictions ..\results\26_historical_band_experts\formal_v09\predictions\ensembles\E09-CONTINUOUS_ensemble.csv `
  --experiment S09-SEALED `
  --track track0_forcing_only `
  --frozen-dir fair_benchmark\frozen `
  --ledger fair_benchmark\registry\portfolio_ledger.csv `
  --experiment-dir ..\results\26_historical_band_experts\formal_v09\predictions\source_bundle `
  --out ..\results\26_historical_band_experts\formal_v09\scoring\S09-SEALED\score_report.json.tmp
```

实际执行由包装器完成，不手工另行运行该命令。参数中不得出现`--allow-unconfirmed`。

- [ ] **Step 6: 运行包装器和评分端到端合成测试**

Run:

```powershell
pytest src/26_historical_band_experts/tests/test_run_one_time_score_v09.py `
  src/fair_benchmark/tests/test_score_e2e.py `
  src/fair_benchmark/tests/test_governance.py -q
```

Expected: PASS；所有评分都使用临时合成数据和临时账本，没有调用正式评分服务。

- [ ] **Step 7: 提交一次性包装器**

```powershell
git add src/26_historical_band_experts/run_one_time_score_v09.py `
  src/26_historical_band_experts/stage_authorization_v09.py `
  src/26_historical_band_experts/tests/test_run_one_time_score_v09.py `
  src/26_historical_band_experts/tests/test_stage_authorization_v09.py
git commit -m "Feat: Add non-retryable formal v09 scoring wrapper"
```

---

### Task 3: 完成评分前独立审查并请求具体哈希授权

**Files:**
- Create after execution approval:
  `src/26_historical_band_experts/audit_pre_score_v09.py`
- Test: `src/26_historical_band_experts/tests/test_audit_pre_score_v09.py`
- Generated, not tracked:
  `results/26_historical_band_experts/formal_v09/pre_score_independent_audit.json`
- Create only after direct scoring approval:
  `src/26_historical_band_experts/configs/formal_v09_scoring_authorization.json`

**Interfaces:**
- `audit_pre_score_v09(...) -> dict`
- Produces: 一条带实际预测SHA-256的完整评分批准请求文本。

- [ ] **Step 1: 写评分前独立审核测试**

审核器必须从零重算而不是复制预测封存声明，至少验证：

- 当前分支、Git提交、工作区干净；
- 全部局部测试证据属于当前可执行源码提交；
- 输入、严格嵌套、训练、预测四层封存和独立审核链完整；
- 24个第30轮检查点和27个预测文件的哈希树完整；
- 连续历史集合是预注册唯一候选，精确覆盖1,939,212行；
- 正式候选文件SHA-256由文件本身重算；
- 候选源码包包含全部实际运行源码且静态扫描命中0；
- 没有正式观测访问证据；
- 冻结规范历史例外五个指纹完全匹配；
- 评分代码和门槛完全匹配合同；
- 账本链完整、没有`S09-SEALED`；
- 评分报告、消费收据和调用日志尚不存在；
- 没有训练、预测或评分进程残留。

- [ ] **Step 2: 运行评分前审核测试并确认失败**

Run:

```powershell
pytest src/26_historical_band_experts/tests/test_audit_pre_score_v09.py -q
```

Expected: FAIL，原因是独立审核器尚不存在。

- [ ] **Step 3: 实现独立审核和批准文本渲染**

审核器只读运行，不调用评分服务。全部通过时输出：

- `status="ready_for_single_score_authorization"`
- 实际候选预测SHA-256；
- 即时账本行数、末行哈希和文件SHA-256；
- 评分代码、冻结规范和源码包哈希；
- `render_scoring_approval_text_v09()`产生的完整具体批准文本。

任何一项失败输出`status="no_go"`，不产生可用授权收据。

- [ ] **Step 4: 运行独立审核测试**

Run:

```powershell
pytest src/26_historical_band_experts/tests/test_audit_pre_score_v09.py -q
```

Expected: PASS。

- [ ] **Step 5: 提交评分前审核器**

```powershell
git add src/26_historical_band_experts/audit_pre_score_v09.py `
  src/26_historical_band_experts/tests/test_audit_pre_score_v09.py
git commit -m "Feat: Add independent formal v09 pre-score audit"
```

- [ ] **Step 6: 在当前可执行提交上运行全部测试**

可用物理内存至少12.68 GiB时运行：

```powershell
pytest src/26_historical_band_experts/tests -q
pytest src/fair_benchmark/tests -q
```

记录两个命令的准确通过数量、警告、耗时和测试提交。核对冻结目录与评分代码未变。
由于新增了评分前置代码，不得复用旧的378项通过证据。

- [ ] **Step 7: 由未参与实现的独立上下文运行评分前审核**

```powershell
python src\26_historical_band_experts\audit_pre_score_v09.py `
  --protocol src\26_historical_band_experts\configs\formal_v09_protocol.json `
  --submission src\26_historical_band_experts\configs\formal_v09_submission.json `
  --scoring-contract src\26_historical_band_experts\configs\formal_v09_scoring_contract.json `
  --formal-root results\26_historical_band_experts\formal_v09 `
  --ledger src\fair_benchmark\registry\portfolio_ledger.csv `
  --report results\26_historical_band_experts\formal_v09\pre_score_independent_audit.json
```

只有独立报告为`ready_for_single_score_authorization`时，才把报告中已经渲染、带具体64位候选哈希的
完整文本发给用户。

- [ ] **Step 8: 请求并固化唯一评分授权**

只有用户逐字发送独立报告中的完整文本后，才创建
`formal_v09_scoring_authorization.json`。收据固定：

- `receipt_id="A09-SCORE-01"`
- `attempt_id="S09-SEALED-ATTEMPT-01"`
- `action="official_scoring"`
- `scope="S09-SEALED-ONCE"`
- `maximum_attempts=1`
- `retry_authorized=false`
- 实际候选预测SHA-256；
- 预测总封存和源码包SHA-256；
- 评分合同和八个评分源码哈希；
- 冻结规范五个历史例外指纹；
- 评分前账本行数、末行哈希和文件SHA-256；
- 评分前独立审核报告SHA-256；
- 用户完整批准文本、文本SHA-256和批准任务标识。

提交收据：

```powershell
git add src/26_historical_band_experts/configs/formal_v09_scoring_authorization.json
git commit -m "Phase: Authorize single formal v09 score"
```

收据提交后再次运行只读前置门；任何非收据文件漂移均使授权不可用。

---

### Task 4: 由独立审查者执行唯一一次正式评分

**Files:**
- Generated, not tracked:
  `results/26_historical_band_experts/formal_v09/scoring/S09-SEALED/`
- Modified only by existing scoring service:
  `src/fair_benchmark/registry/portfolio_ledger.csv`

**Interfaces:**
- Consumes: 完整评分前审核、具体哈希授权、候选预测和候选源码包。
- Produces: 一份评分服务报告和账本中唯一一条`S09-SEALED`记录。

- [ ] **Step 1: 独立审查者接管唯一调用**

执行者必须是未参与训练、预测和外层包装器实现的独立上下文。它先只读核对：

- 固定工作区路径、分支、提交和干净状态；
- 评分授权收据与用户批准文本；
- 评分前独立报告；
- 没有`S09-SEALED`账本记录；
- 评分目录和消费收据不存在；
- 当前没有其他评分进程。

实现者不得自行执行唯一调用，也不得在独立执行者运行后再次执行。

- [ ] **Step 2: 运行一次性包装器**

独立执行者只运行一次：

```powershell
python src\26_historical_band_experts\run_one_time_score_v09.py `
  --protocol src\26_historical_band_experts\configs\formal_v09_protocol.json `
  --submission src\26_historical_band_experts\configs\formal_v09_submission.json `
  --scoring-contract src\26_historical_band_experts\configs\formal_v09_scoring_contract.json `
  --authorization src\26_historical_band_experts\configs\formal_v09_scoring_authorization.json `
  --prediction-seal results\26_historical_band_experts\formal_v09\predictions\seal.json `
  --prediction-root results\26_historical_band_experts\formal_v09\predictions `
  --ledger src\fair_benchmark\registry\portfolio_ledger.csv `
  --output-root results\26_historical_band_experts\formal_v09\scoring\S09-SEALED
```

命令开始后无论发生什么都不得重新运行。

- [ ] **Step 3: 立即冻结评分后状态**

独立执行者记录：

- 进程退出状态、标准输出和错误输出；
- 消费收据SHA-256；
- 报告存在性和SHA-256；
- 账本评分前后行数、文件SHA-256和末行哈希；
- `S09-SEALED`出现次数；
- 候选预测SHA-256是否与报告和账本一致。

预期正常状态是账本恰好增加一行、`S09-SEALED`恰好出现一次、报告完整。任何其他状态进入终审，
但不允许重试。

---

### Task 5: 在不重复评分的前提下完成独立终审

**Files:**
- Create after execution approval: `src/26_historical_band_experts/audit_post_score_v09.py`
- Test: `src/26_historical_band_experts/tests/test_audit_post_score_v09.py`
- Create after score:
  `docs/technical/historical_multiscale_formal_v09_final_independent_audit.md`
- Modify after score: `src/26_historical_band_experts/registry.csv`
- Create after score:
  `src/fair_benchmark/experiments/S09-SEALED/submission/predictions.sha256`
- Generated, not tracked:
  `results/26_historical_band_experts/formal_v09/final_audit.json`

**Interfaces:**
- `audit_post_score_v09(...) -> dict`
- `derive_final_claim_v09(score_report, audit_report) -> dict`

- [ ] **Step 1: 写评分后终审反驳测试**

使用合成报告和临时账本，测试必须拒绝：

- 消费收据缺失或评分启动次数不为1；
- `S09-SEALED`账本记录不是恰好一条；
- 账本哈希链断裂或不是在前快照后追加一行；
- 报告、账本和预测封存中的预测SHA-256不一致；
- 报告实验标识、赛道或源码扫描命中不正确；
- 报告覆盖不是通过；
- 报告公开或秘密统计字段缺失、非有限或与门槛重算不一致；
- 文字结论把`HOLD`写成胜利、把`REJECT`写成有效非胜利，或声称优于未评分控制；
- 终审器调用评分服务、读取正式观测文件或修改冻结目录；
- 实现者被标记为独立审查签署人。

- [ ] **Step 2: 运行终审测试并确认失败**

Run:

```powershell
pytest src/26_historical_band_experts/tests/test_audit_post_score_v09.py -q
```

Expected: FAIL，原因是评分后终审器尚不存在。

- [ ] **Step 3: 实现只读评分后审核**

终审器不得加载正式评估观测。它只使用服务报告、账本、封存和受保护评分源码来：

1. 验证唯一调用和唯一账本追加；
2. 验证候选预测哈希和源码扫描结果；
3. 用报告中的公开、秘密统计重新调用纯门槛函数`decide()`；
4. 确认重算判定与报告判定完全相同；
5. 审核代码、模型结构、输入边界、训练、预测、环境和产物封存链；
6. 搜索训练或预测后是否出现第二个模型选择、后处理或正式评分调用；
7. 生成与判定严格对应的可声明结论。

终审不重新计算逐流域Nash-Sutcliffe模型效率系数，因为正式观测只由评分服务持有；这项限制必须
明确写入报告，不能把报告字段审核说成独立重评分。

- [ ] **Step 4: 固定最终判定文本边界**

若服务和终审均为`PASS`，允许结论：

```text
在531流域、Maurer气象驱动、27项静态属性和冻结反向时段下，连续历史八随机数集合相对冻结经典八随机数基准通过预注册正式门。
```

同时必须报告公开配对中位提升、Wilcoxon检验p值、自助抽样区间、秘密流域提升和保留比例的具体值。

若服务为`HOLD`，固定结论：

```text
正式提交有效，但没有通过全部预注册胜利门；不能声称连续历史模型优于冻结经典基准。
```

若服务为`REJECT`，固定结论：

```text
正式提交未通过完整性合同，本次结果不能用于模型效果判断。
```

若唯一调用异常且没有完整报告，固定结论：

```text
唯一评分授权已经消耗，但正式服务结果不完整；状态为HOLD，不重试，也不作性能声明。
```

所有情况都必须补充：同参数量控制没有接受正式评分，因此不能在531流域上声明连续历史结构优于该控制。

- [ ] **Step 5: 运行终审测试**

Run:

```powershell
pytest src/26_historical_band_experts/tests/test_audit_post_score_v09.py -q
```

Expected: PASS。

- [ ] **Step 6: 提交终审器**

该代码必须在正式评分之前实现、测试和提交，避免看到结果后改变审核逻辑：

```powershell
git add src/26_historical_band_experts/audit_post_score_v09.py `
  src/26_historical_band_experts/tests/test_audit_post_score_v09.py
git commit -m "Feat: Add formal v09 post-score audit"
```

- [ ] **Step 7: 由同一独立审查上下文运行终审**

正式评分后只运行：

```powershell
python src\26_historical_band_experts\audit_post_score_v09.py `
  --protocol src\26_historical_band_experts\configs\formal_v09_protocol.json `
  --submission src\26_historical_band_experts\configs\formal_v09_submission.json `
  --scoring-contract src\26_historical_band_experts\configs\formal_v09_scoring_contract.json `
  --authorization src\26_historical_band_experts\configs\formal_v09_scoring_authorization.json `
  --formal-root results\26_historical_band_experts\formal_v09 `
  --ledger src\fair_benchmark\registry\portfolio_ledger.csv `
  --report results\26_historical_band_experts\formal_v09\final_audit.json
```

该命令只读评分证据，不调用评分服务。

- [ ] **Step 8: 写最终审计文档和治理侧车**

`historical_multiscale_formal_v09_final_independent_audit.md`必须逐项给出：

- 分支、提交、工作区和受保护文件状态；
- 输入、严格嵌套、24次训练、27个预测文件和环境封存；
- 模型结构和参数量；
- 数据读取边界与源码扫描；
- 冻结清单历史例外及用户接受证据；
- 唯一调用、账本前后状态和预测哈希；
- 服务原始判定和全部门槛数值；
- 独立审核能验证和不能独立重算的内容；
- 最终允许结论和禁止外推。

治理侧车只保存候选预测SHA-256，不复制正式预测：

```text
src/fair_benchmark/experiments/S09-SEALED/submission/predictions.sha256
```

- [ ] **Step 9: 提交唯一账本追加和最终结论**

先确认差异只包括正式评分服务追加的一条账本记录、治理侧车、研究登记和终审文档：

```powershell
git diff -- src/fair_benchmark/registry/portfolio_ledger.csv `
  src/fair_benchmark/experiments/S09-SEALED/submission/predictions.sha256 `
  src/26_historical_band_experts/registry.csv `
  docs/technical/historical_multiscale_formal_v09_final_independent_audit.md
```

然后提交：

```powershell
git add src/fair_benchmark/registry/portfolio_ledger.csv `
  src/fair_benchmark/experiments/S09-SEALED/submission/predictions.sha256 `
  src/26_historical_band_experts/registry.csv `
  docs/technical/historical_multiscale_formal_v09_final_independent_audit.md
git commit -m "Phase: Record formal v09 independent verdict"
```

提交后再验证账本哈希链、治理侧车与账本预测哈希一致、工作区干净。

## Stopping Conditions

以下任一情况使正式评分保持`NO-GO`：

- 输入、严格嵌套、24次训练、正式预测或任一独立审核未通过；
- 唯一候选预测SHA-256未确定或精确覆盖失败；
- 候选源码包扫描命中不为0；
- 用户未逐字接受具体预测哈希和冻结清单历史例外；
- 授权收据、评分合同、评分代码、冻结规范或账本前快照漂移；
- 冻结目录或正式评分代码存在改动；
- `S09-SEALED`已有账本记录；
- 评分目录、消费收据或调用日志已存在；
- 工作区不干净、存在其他评分进程或账本哈希链断裂。

评分一旦启动，以下情况不允许重试，并进入独立终审：

- 服务返回`PASS`、`HOLD`或`REJECT`；
- 服务异常、机器中断、报告写入失败；
- 账本已追加但报告不完整；
- 报告已生成但后处理审核失败。

## Self-Review

- 唯一性：实验标识、候选哈希、账本前快照、消费收据和单调用包装器共同约束一次评分。
- 独立性：未参与实现的审查者先审核、再执行唯一调用、最后终审；实现者不自签名。
- 冻结边界：不修改清单、规范或评分代码；已知清单不一致由多重指纹和用户逐字接受处理。
- 评分边界：正式观测只由现有评分服务读取；终审不伪称独立重算观测指标。
- 统计边界：公开中位提升、Wilcoxon检验、自助抽样区间和秘密流域门全部由受保护服务决定。
- 结论边界：结果只比较连续历史集合与冻结经典集合；369单元控制没有正式性能结论。
- 失败边界：任何调用后故障都不重试，仍保留证据并给出`HOLD`或`REJECT`边界结论。

## Execution Handoff

当前状态应保持`NO-GO`：本文件只是实施计划，正式预测尚不存在，实际候选SHA-256未知，
具体评分授权也不可能提前生成。执行顺序不可合并：

1. 完成正式预测、源码包、全量重放和预测总封存；
2. 用户批准实施评分前置门、一次性包装器和终审器；
3. 在结果未知时完成全部代码、测试和提交；
4. 未参与实现的独立上下文运行评分前审核；
5. 用户逐字批准带实际候选哈希和冻结历史例外的完整文本；
6. 独立审查者执行唯一一次正式评分；
7. 不重复评分，完成账本、产物、结构、数据边界和结论终审；
8. 无论`PASS`、`HOLD`、`REJECT`或调用异常，都记录并提交唯一最终结论。
