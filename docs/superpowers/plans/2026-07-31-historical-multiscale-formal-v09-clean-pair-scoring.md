# 历史连续多尺度气象模型版本09清洁同信息配对评分实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 不修改现有受保护评分文件，在一次可信服务调用和一次账本追加中，以清洁训练的八随机数经典近期集合为主基准，同时评价连续历史候选和同参数量控制。

**Architecture:** 新的可信入口从已经封存的三组八随机数集合中现场派生逐流域纳什－萨特克利夫效率系数，以清洁经典集合构造内存中的新赛道，再调用现有`fair_benchmark.score.score_submission()`恰好一次完成主比较。三个预测文件封存且一次性评分授权被独占消费后，唯一评分进程从操作系统密码学随机源抽取一次256位随机数，并与三组预测身份共同确定新的107流域后封存留出集；旧留出集已经被重复评分，只保留为不具资格的历史文件。服务在同一进程内计算候选相对同参数量控制的预注册次要比较；正式评估答案不复制到隔离工作区，也不向报告泄露逐流域留出结果。

**Tech Stack:** Python 3.11、pandas、NumPy、SciPy、ruamel.yaml、pytest、Git、SHA-256、现有`fair_benchmark.score`、现有哈希链账本。

## Global Constraints

- 本计划当前状态为`PROPOSED-HOLD`，不授权写代码、生成正式输入、训练、正式预测或评分。
- 只有用户逐字发送本计划冻结的“清洁同信息配对评分路线实施批准”后，才允许实现该文本逐项列明的
  合同、评分包构建器、评分入口、一次性授权与随机划分模块、两个审核器及合成测试。该批准不允许
  用真实预测构建评分包，也不允许任何正式输入、训练、预测或评分动作。
- 不修改`src/fair_benchmark/frozen/`、`src/fair_benchmark/score.py`、`gate.py`、`stats.py`、
  `metrics.py`、`ledger.py`、`io.py`、`leakage.py`或`tracks.py`。
- 不覆盖或改写现有`track0_forcing_only`。新赛道固定为
  `track0_forcing_only_clean_v09`，评分尝试固定为`S09C-CLEAN-PAIR`。
- 模型、训练期、Maurer五个命名气象变量、27项静态属性、3,561天最长滞后、270天近期路径、
  30轮和八个随机数均保持正式版本09协议不变。
- 新合同只允许替代协议中的六项评分治理语义：旧评分标识、旧赛道标识、旧八随机数基准资格、旧赛道
  冻结清单问题的适用范围，以及两项留出门槛从旧107流域到后封存107流域的集合绑定。门槛数值、
  协议中的其他科学字段、四项正式动作授权和正式评估目标封存字段均不得覆盖；`S09-SEALED`保持
  不可授权，新评分仍必须另取一次精确外部授权。
- 候选选择来源固定为版本08的60流域三随机数内部确认及独立审核
  `complete_multiseed_go`；正式版本09不得重选候选、模型族、随机数、检查点或集合权重。
- 主比较固定为连续历史候选`E09-CONTINUOUS`减清洁经典近期控制`B09-CLASSIC`。
- 同参数量控制`B09-CAPACITY`是预注册次要比较，不影响主`PASS/HOLD/REJECT`，不得用于选择候选、
  检查点、随机数、集合权重或后处理。
- 旧八随机数集成只作`historical_reference_nonqualifying`，不得参与正式判定。
- 原冻结留出集已被同一研究程序重复查询，固定为`legacy_reused_holdout_nonqualifying`，不得用于
  新主判定，也不得再称为未触碰的秘密留出集。
- 新留出集固定为`postseal_nonce_sha256_rank_v1`：三组预测全部封存且授权被独占消费后，唯一
  评分进程用操作系统密码学随机源抽取一次256位随机数，再与三组预测身份共同确定107个流域；
  其余424个为公开比较集。随机数不得预生成、挑选或重抽，留出集不得用于重训、选择、后处理或
  第二次评分。
- 三个集合在评分授权前全部封存；每个文件必须恰有531个流域、每流域3,652天、总计1,939,212行，
  且列严格为`basin,date,qsim`。
- 评分包必须同时绑定输入封存、旧检查点函数桥接审核、30轮零容差严格嵌套运行及独立审核、24次
  主训练总封存及独立审核、24个第30轮检查点、正式预测总封存和24文件独立重放审核；任一缺失、
  非通过或哈希漂移均不得评分。
- 清洁配对服务只允许一次进程启动、一次`score_submission()`调用、一次账本追加；没有重试。
- 编写训练、预测或评分包装代码的实施者不得消费正式评分授权。唯一评分调用必须由未参与实现的
  独立干净上下文在重算全部哈希后执行；这一次调用同时承担独立重执行，不再允许第二次“审核重跑”。
- 授权首次消费后，无论成功、失败、中断、答案根缺失、账本已追加但报告失败，均不得复用。
- 当前仓库不会把`src/fair_benchmark`安装为顶层包。正式入口必须在授权消费前把当前工作树
  `src`的解析后绝对路径设为唯一`PYTHONPATH`并完成只读导入探针；启动快照和授权收据必须绑定该
  路径、Python解释器绝对路径和模块文件SHA-256，禁止依赖用户会话中偶然存在的搜索路径。
- 留出划分必须在打开正式答案前由随机数抽取收据重新派生并核对；收据、划分盐或集合摘要不一致时，
  `load_obs_csv()`调用次数必须为0。
- 最终报告必须是严格JSON。现有评分函数在全零配对差异时会返回非有限Wilcoxon检验值；可信包装器
  必须把允许出现的非有限聚合统计规范化为`null`并记录原因，再以`allow_nan=false`序列化。逐流域
  指标非有限仍是合同失败，不能用`null`掩盖。
- 正式答案文件不在隔离工作区。可信入口必须显式接收主仓库只读冻结根
  `G:\github\pycharm\projects\neuralhydrology\src\fair_benchmark\frozen`，逐项验证哈希，且不得复制答案。
- 正式答案只能由已授权的可信评分进程解析。无观测前置门、候选代码和独立终审不得解析或复制答案。
- 候选侧还不得读取旧逐流域基准向量、旧留出列表、既有评分报告或评分账本；这些都是正式评估
  派生反馈。可信前置门只能核对其路径、字节哈希和账本链，不能把内容交给候选。
- 主成功门保持不变：公开流域配对中位提升至少0.01、Wilcoxon检验`p < 0.05`、10,000次自助抽样
  区间下界大于0、后封存留出流域提升至少0.005且至少保留公开提升50%。
- 主比较的清洁经典、候选和同参数量控制必须各得到531个有限逐流域指标；任一缺失或非有限使正式
  合同失败，不能返回`PASS`。
- 报告不得写出留出流域标识、逐流域指标或逐日观测；只允许公开集和后封存留出集的聚合统计。
- 长任务启动可用物理内存至少12.68 GiB；低于门槛不得运行完整测试、正式数据构建、训练、预测或评分。

---

## 评分前公平性审计事实

- 当前真实账本有7条`track0_forcing_only`记录，7条公开比较数均为424，说明它们复用了同一个107流域
  留出集合。
- 主仓库保留6份评分报告，均公开了该107流域集合的聚合结果；其中一个实验被评分两次，第二次报告
  覆盖了第一次报告，但两次都在账本中。
- 自主研究总结明确使用“留出集也变差”和“公开集与留出集都过拟合”等结果解释后续研究，因此原
  留出集已经参与研究反馈。
- 这些事实不证明版本09候选读取过逐流域留出答案；版本09候选尚未正式评分。它们证明的是：原107
  流域集合不再具备全局未查询的独立性，不能承担新候选的正式秘密留出声明。
- 修复原则是先封存`B09-CLASSIC`、`B09-CAPACITY`和`E09-CONTINUOUS`三个完整预测；评分授权
  独占消费后，由唯一评分进程抽取一次256位随机数，并与联合预测身份共同确定新107流域集合。由于
  随机数在封存后才产生且预测禁止修改，这个集合不能反馈到模型、训练随机数、检查点、权重或后处理。

逐文件哈希、账本记录和报告证据见
`docs/technical/historical_multiscale_formal_v09_holdout_reuse_audit.md`。

---

### Task 1: 冻结清洁配对科学合同、可信文件身份和后封存留出规则

**Files:**
- Create after route approval:
  `src/26_historical_band_experts/configs/formal_v09_clean_pair_scoring_contract.json`
- Create after route approval: `src/fair_benchmark/clean_pair_contract_v09.py`
- Create after route approval: `src/fair_benchmark/postseal_holdout_v09.py`
- Test: `src/fair_benchmark/tests/test_clean_pair_contract_v09.py`
- Test: `src/fair_benchmark/tests/test_postseal_holdout_v09.py`

**Interfaces:**
- Consumes: 正式版本09协议配置、现有评分模块字节和主仓库只读冻结文件身份。
- Produces:
  `load_clean_pair_contract_v09(path, *, protocol_path) -> dict`。
- Produces:
  `validate_clean_pair_contract_v09(contract, *, protocol, protocol_sha256) -> dict`。
- Produces:
  `derive_postseal_holdout_v09(basins, *, protocol_sha256, prediction_sha256, nonce_hex, holdout_count) -> dict`。

- [ ] **Step 1: 固定路线实施批准文本**

用户必须逐字发送：

```text
批准版本09清洁同信息配对评分路线及三组预测封存后由唯一评分进程抽取256位随机数派生107流域留出规则；仅授权编写清洁评分合同、三集合评分包构建器、新评分入口、一次性授权与随机划分模块、评分前置审核器、最终不重评分审核器及合成测试，不批准生成正式输入、训练、正式预测或评分。
```

UTF-8、无末尾换行的SHA-256固定为：

```text
f85f846c0bea8135b6c8effd1aaa44dd75f9611fcfa3442b90edb95c0f353c8d
```

先前只写“新评分入口、前置门和合成测试”的较窄文本及其
`7a73fcbd2ca916d4764d1b3791ddb9e037385f6a69cd73307c29376a6c088fd3`哈希已被本版取代，不再接受；
原因是它没有明确授权评分包构建器、一次性随机划分和最终不重评分审核器的代码实现。

- [ ] **Step 2: 写科学合同失败测试**

```python
import copy
import json

import pytest

from fair_benchmark.clean_pair_contract_v09 import (
    CleanPairContractError,
    validate_clean_pair_contract_v09,
)


def test_clean_pair_contract_freezes_roles_gates_and_one_call():
    contract = json.loads(CONTRACT_PATH.read_text(encoding="utf-8"))
    validated = validate_clean_pair_contract_v09(
        contract,
        protocol=PROTOCOL,
        protocol_sha256=PROTOCOL_SHA256,
    )
    assert validated["contract_id"] == "S09C-CLEAN-PAIR"
    assert validated["track_id"] == "track0_forcing_only_clean_v09"
    assert len(
        validated["protocol_scoring_supersession"]["permitted_semantic_supersessions"]
    ) == 6
    assert validated["protocol_scoring_supersession"]["scientific_fields_overridden"] == []
    assert validated["protocol_scoring_supersession"]["protocol_authorization_overridden"] is False
    assert validated["protocol_scoring_supersession"]["external_authorization_required"] is True
    assert validated["protocol_scoring_supersession"]["legacy_route_authorizable"] is False
    assert validated["roles"] == {
        "baseline": "B09-CLASSIC",
        "capacity_control": "B09-CAPACITY",
        "challenger": "E09-CONTINUOUS",
    }
    assert validated["execution"]["score_submission_calls"] == 1
    assert validated["execution"]["ledger_appends"] == 1
    assert validated["execution"]["retries"] == 0
    assert validated["historical_reference"]["qualifying"] is False
    assert validated["selection_provenance"]["status"] == "complete_multiseed_go"
    assert validated["selection_provenance"]["may_reselect"] is False
    assert validated["postseal_holdout"]["method"] == "postseal_nonce_sha256_rank_v1"
    assert validated["postseal_holdout"]["holdout_count"] == 107
    assert validated["postseal_holdout"]["public_count"] == 424
    assert validated["legacy_nonqualifying_inputs"]["secret_holdout"]["qualifying"] is False


@pytest.mark.parametrize(
    ("path", "value"),
    [
        (("primary_gate", "min_effect"), 0.009),
        (("execution", "score_submission_calls"), 2),
        (("roles", "baseline"), "legacy_lstm_ensemble"),
        (("historical_reference", "qualifying"), True),
        (("postseal_holdout", "holdout_count"), 106),
        (("legacy_nonqualifying_inputs", "secret_holdout"), {}),
        (
            ("protocol_scoring_supersession", "scientific_fields_overridden"),
            ["/forcing_product"],
        ),
        (
            ("protocol_scoring_supersession", "permitted_semantic_supersessions"),
            ["/track"],
        ),
    ],
)
def test_clean_pair_contract_rejects_scientific_drift(path, value):
    contract = json.loads(CONTRACT_PATH.read_text(encoding="utf-8"))
    changed = copy.deepcopy(contract)
    changed[path[0]][path[1]] = value
    with pytest.raises(CleanPairContractError):
        validate_clean_pair_contract_v09(
            changed,
            protocol=PROTOCOL,
            protocol_sha256=PROTOCOL_SHA256,
        )
```

- [ ] **Step 3: 运行测试并确认失败**

Run:

```powershell
pytest src/fair_benchmark/tests/test_clean_pair_contract_v09.py `
  src/fair_benchmark/tests/test_postseal_holdout_v09.py -q
```

Expected: FAIL，原因是可信合同模块和配置尚不存在。

- [ ] **Step 4: 写入完整合同**

合同必须逐项包含：

```json
{
  "contract_id": "S09C-CLEAN-PAIR",
  "track_id": "track0_forcing_only_clean_v09",
  "protocol_id": "P09-FORMAL",
  "protocol_sha256": "b81bce8fc83aa8c4cad2d36475c6e6da553567f54b5f5f8d52457006fb446ed8",
  "protocol_scoring_supersession": {
    "scope": "scoring_governance_semantics_only",
    "permitted_semantic_supersessions": [
      "/sealed_scoring_id",
      "/track",
      "/legacy_reference/description",
      "/legacy_frozen_manifest_issue/must_be_resolved_before_scoring_authorization",
      "/success_gates/secret_holdout_median_delta_at_least",
      "/success_gates/secret_retained_public_fraction_at_least"
    ],
    "mapping": {
      "/sealed_scoring_id": {
        "protocol_value": "S09-SEALED",
        "clean_route_value": "S09C-CLEAN-PAIR"
      },
      "/track": {
        "protocol_value": "track0_forcing_only",
        "clean_route_value": "track0_forcing_only_clean_v09"
      },
      "/legacy_reference/description": {
        "protocol_value": "frozen eight-seed classic LSTM ensemble; scoring reference only",
        "clean_route_interpretation": "historical_reference_nonqualifying"
      },
      "/legacy_frozen_manifest_issue/must_be_resolved_before_scoring_authorization": {
        "protocol_value": true,
        "legacy_route_status": "unresolved_and_blocks_S09-SEALED",
        "clean_route_applicability": "not_applicable_direct_hash_bindings_required"
      },
      "/success_gates/secret_holdout_median_delta_at_least": {
        "protocol_value": 0.005,
        "clean_route_partition": "postseal_nonce_sha256_rank_v1_first_107",
        "numeric_value_overridden": false
      },
      "/success_gates/secret_retained_public_fraction_at_least": {
        "protocol_value": 0.5,
        "clean_route_partition": "postseal_nonce_sha256_rank_v1_first_107",
        "numeric_value_overridden": false
      }
    },
    "scientific_fields_overridden": [],
    "protocol_authorization_overridden": false,
    "external_authorization_required": true,
    "formal_evaluation_target_access_overridden": false,
    "legacy_route_authorizable": false
  },
  "roles": {
    "baseline": "B09-CLASSIC",
    "capacity_control": "B09-CAPACITY",
    "challenger": "E09-CONTINUOUS"
  },
  "selection_provenance": {
    "status": "complete_multiseed_go",
    "scope": "fixed_60_basin_internal_confirmation_only",
    "candidate_config_sha256": "837563c11fc792b522a798423da35d43ce307f166b32fe39cc421ca6608765cb",
    "analysis_manifest_sha256": "3540fd0ec30ebd979ed1f4a1ac9e19180ad3e4dd71332455ffc626d145d561ce",
    "summary_sha256": "b6f506b560287619c3d2362c741accdd4c84ecb12fac779ceb63bc7764db4342",
    "independent_audit_sha256": "9298a7a9d22a8210366ebde03c68255d9815da5d2dd4b100ce3f39ea23c1a104",
    "formal_observations_used": false,
    "may_reselect": false
  },
  "ensemble_paths": {
    "baseline": "predictions/ensembles/B09-CLASSIC_ensemble.csv",
    "capacity_control": "predictions/ensembles/B09-CAPACITY_ensemble.csv",
    "challenger": "predictions/ensembles/E09-CONTINUOUS_ensemble.csv"
  },
  "prediction_contract": {
    "basin_count": 531,
    "start_date": "1989-10-01",
    "end_date": "1999-09-30",
    "dates_per_basin": 3652,
    "rows_per_file": 1939212,
    "columns": ["basin", "date", "qsim"],
    "seeds": [100, 200, 300, 400, 500, 600, 700, 800],
    "ensemble_operation": "float64_arithmetic_mean"
  },
  "trusted_frozen_inputs": {
    "answer_key": {
      "relative_path": "track0_forcing_only_obs_eval.parquet",
      "sha256": "576d548253064699ade1e312ea875097d070557e3eef334874c310df61d8fd1e"
    },
    "basins": {
      "relative_path": "track0_forcing_only_basins.txt",
      "sha256": "cd2d3d466aca736fcd32042d2b0bde3d0b58e42ba37fe552d97480bd914b9e85"
    }
  },
  "postseal_holdout": {
    "method": "postseal_nonce_sha256_rank_v1",
    "domain_separator": "P09C-CLEAN-HOLDOUT-V1",
    "nonce_source": "python_secrets_token_bytes_32_after_authorization_consumption",
    "nonce_draws": 1,
    "nonce_redraws": 0,
    "holdout_count": 107,
    "public_count": 424,
    "preimage_order": [
      "domain_separator",
      "protocol_sha256",
      "baseline_prediction_sha256",
      "capacity_control_prediction_sha256",
      "challenger_prediction_sha256",
      "nonce_hex"
    ],
    "field_separator": "\n",
    "basin_rank_preimage": "partition_salt_sha256 + newline + basin_id",
    "selection": "ascending_rank_sha256_then_basin_id_first_107",
    "set_digest": "sha256(sorted_selected_basin_ids_joined_by_newline_with_final_newline)",
    "may_affect_training_or_selection": false
  },
  "legacy_nonqualifying_inputs": {
    "secret_holdout": {
      "relative_path": "track0_forcing_only_secret_holdout_basins.txt",
      "sha256": "305211b0fd256769a65cfe662ec94a66f58aab5730fd5eb1b964dfc2c64c2494",
      "status": "legacy_reused_holdout_nonqualifying",
      "qualifying": false,
      "minimum_recorded_score_calls": 7
    },
    "historical_baseline": {
      "relative_path": "track0_forcing_only_baseline_per_basin_nse.csv",
      "sha256": "63d989d155f6806d52f996e28f734afb9ec7cecbdcc797ac414d3cd2ff8670d6",
      "status": "historical_reference_nonqualifying",
      "qualifying": false
    }
  },
  "primary_gate": {
    "min_effect": 0.01,
    "max_wilcoxon_p": 0.05,
    "bootstrap_samples": 10000,
    "bootstrap_seed": 0,
    "ci_low_must_exceed": 0.0,
    "holdout_min_effect": 0.005,
    "holdout_retention": 0.5
  },
  "capacity_comparison": {
    "status": "descriptive_preregistered_no_verdict",
    "may_select_model": false
  },
  "historical_reference": {
    "status": "historical_reference_nonqualifying",
    "qualifying": false,
    "may_affect_verdict": false
  },
  "execution": {
    "score_submission_calls": 1,
    "ledger_appends": 1,
    "retries": 0,
    "allow_unconfirmed": false
  }
}
```

验证器必须读取实际协议字节并核对协议SHA-256，逐项确认上述六个旧值仍与协议一致。允许的语义替代
集合必须完整相等，不能用前缀、通配符或父对象替代；任何科学字段覆盖、正式动作授权覆盖、正式评估
目标访问覆盖、未知指针或把旧路线改为可授权都拒绝。旧冻结清单问题仍阻断`S09-SEALED`，新路线只能
依靠合同登记的答案、流域、评分模块和三组预测直接SHA-256绑定，不能把旧问题写成已经修复。

可信模块把该对象逐字段与常量比较，拒绝未知键、缺失键、额外模型、门槛漂移、旧基准或旧留出集
重新取得正式资格，或把同参数量比较用于选择。

- [ ] **Step 5: 写并验证后封存留出算法**

纯派生算法只接受冻结流域列表、协议哈希、三个预测SHA-256和已经由唯一评分进程抽取的64位小写
十六进制`nonce_hex`。它本身不得抽取随机数。精确步骤：

```python
fields = [
    "P09C-CLEAN-HOLDOUT-V1",
    protocol_sha256,
    prediction_sha256["baseline"],
    prediction_sha256["capacity_control"],
    prediction_sha256["challenger"],
    nonce_hex,
]
partition_salt_sha256 = sha256("\n".join(fields).encode("utf-8")).hexdigest()
ranked = sorted(
    (
        sha256(f"{partition_salt_sha256}\n{basin}".encode("utf-8")).hexdigest(),
        basin,
    )
    for basin in basins
)
holdout_ids = {basin for _, basin in ranked[:107]}
holdout_set_sha256 = sha256(
    ("".join(f"{basin}\n" for basin in sorted(holdout_ids))).encode("utf-8")
).hexdigest()
```

`derive_postseal_holdout_v09()`必须拒绝非531个唯一流域、非64位小写十六进制预测哈希或
`nonce_hex`、未知角色和非107的留出数。返回值在进程内含`holdout_ids`，持久化摘要只含方法、
107/424计数、`nonce_sha256`、`partition_salt_sha256`和`holdout_set_sha256`，不得含随机数原文
或流域标识。随机数原文只进入独占抽取收据，供终审复核。

```python
def test_postseal_holdout_is_deterministic_complete_and_prediction_bound():
    first = derive_postseal_holdout_v09(
        BASINS,
        protocol_sha256=PROTOCOL_SHA,
        prediction_sha256=PREDICTION_SHA,
        nonce_hex="1" * 64,
        holdout_count=107,
    )
    second = derive_postseal_holdout_v09(
        list(reversed(BASINS)),
        protocol_sha256=PROTOCOL_SHA,
        prediction_sha256=PREDICTION_SHA,
        nonce_hex="1" * 64,
        holdout_count=107,
    )
    assert first["holdout_ids"] == second["holdout_ids"]
    assert len(first["holdout_ids"]) == 107
    assert len(set(BASINS) - first["holdout_ids"]) == 424
    changed_prediction = derive_postseal_holdout_v09(
        BASINS,
        protocol_sha256=PROTOCOL_SHA,
        prediction_sha256=dict(PREDICTION_SHA, challenger="f" * 64),
        nonce_hex="1" * 64,
        holdout_count=107,
    )
    changed_nonce = derive_postseal_holdout_v09(
        BASINS,
        protocol_sha256=PROTOCOL_SHA,
        prediction_sha256=PREDICTION_SHA,
        nonce_hex="2" * 64,
        holdout_count=107,
    )
    assert first["holdout_set_sha256"] != changed_prediction["holdout_set_sha256"]
    assert first["holdout_set_sha256"] != changed_nonce["holdout_set_sha256"]
    assert "holdout_ids" not in public_partition_summary(first)


def test_postseal_holdout_matches_frozen_nonobservational_test_vector():
    basins = [
        line
        for line in FROZEN_BASIN_LIST.read_text(encoding="utf-8").splitlines()
        if line
    ]
    result = derive_postseal_holdout_v09(
        basins,
        protocol_sha256="b81bce8fc83aa8c4cad2d36475c6e6da553567f54b5f5f8d52457006fb446ed8",
        prediction_sha256={
            "baseline": "a" * 64,
            "capacity_control": "b" * 64,
            "challenger": "c" * 64,
        },
        nonce_hex="1" * 64,
        holdout_count=107,
    )
    assert result["partition_salt_sha256"] == (
        "ead35266f8e8063dd066339d88404bbd275610c5055250007f9913409b06a5b7"
    )
    assert result["holdout_set_sha256"] == (
        "370543e8b4f06b1ba7da6e7c047b83cd8023dba5e57c7ca6928adb120d3ff9e1"
    )
```

- [ ] **Step 6: 冻结被复用评分模块哈希**

合同审核报告另行绑定以下当前字节SHA-256；这些值不写入受保护文件：

| 文件 | SHA-256 |
|---|---|
| `score.py` | `9e3cb83254842e98ee4c5a61a4a273d7ce73c0676573573855e174bbc97779d7` |
| `gate.py` | `7913505435c7a56a2fa38c80028c188270ef573379ccca53172ea75339d5b5df` |
| `stats.py` | `284e18b8296c82b0a04a90a4deeb7b51cea0dc3a27c8ac9df31481d8025b8bb3` |
| `metrics.py` | `4331717056f241af110876cb7b84922e15171120de897dd0073cdf1e5587a6cc` |
| `ledger.py` | `bad6edb772d3b162cea37a165e679c8eb9656c2813403ad0b7d784c20ec181a2` |
| `io.py` | `88126942f6fec6d9df0c0f60389c3ebec2c0e711bbeeccaa795595aa5ef31903` |
| `leakage.py` | `20aafe9e704eaabea312da29b8ea3791310076b98a2e86f4b0780d7c75689856` |
| `tracks.py` | `e591f838410f063c6b128e3a244688fb66f7915f7b7ce0ea1275fb22f7219b5c` |

- [ ] **Step 7: 运行测试并提交**

```powershell
pytest src/fair_benchmark/tests/test_clean_pair_contract_v09.py `
  src/fair_benchmark/tests/test_postseal_holdout_v09.py -q
git add src/26_historical_band_experts/configs/formal_v09_clean_pair_scoring_contract.json `
  src/fair_benchmark/clean_pair_contract_v09.py `
  src/fair_benchmark/postseal_holdout_v09.py `
  src/fair_benchmark/tests/test_clean_pair_contract_v09.py `
  src/fair_benchmark/tests/test_postseal_holdout_v09.py
git commit -m "Feat: Freeze formal v09 clean pair contract"
```

---

### Task 2: 构建不读取观测的三集合评分包

**Files:**
- Create after route approval: `src/26_historical_band_experts/clean_pair_bundle_v09.py`
- Test: `src/26_historical_band_experts/tests/test_clean_pair_bundle_v09.py`
- Generated only after prediction seal:
  `results/26_historical_band_experts/formal_v09/predictions/clean_pair_bundle.json`

**Interfaces:**
- Consumes: `prediction_seal.json`、三个已封存集合、Task 1合同，以及预测封存所绑定的输入、函数
  桥接、严格嵌套、24次训练和预测独立重放证据。
- Produces: `validate_clean_pair_prediction_file_v09(path, basin_ids, dates) -> dict`。
- Produces: `build_clean_pair_bundle_v09(contract, prediction_seal, prediction_root) -> dict`。
- Produces: `clean_pair_bundle_sha256(bundle) -> str`。

- [ ] **Step 1: 写角色、覆盖和无观测边界测试**

```python
def test_clean_pair_bundle_assigns_three_fixed_roles(tmp_path):
    root, seal = write_three_synthetic_ensembles(tmp_path)
    bundle = build_clean_pair_bundle_v09(SYNTHETIC_CONTRACT, seal, root)
    assert tuple(bundle["predictions"]) == (
        "baseline",
        "capacity_control",
        "challenger",
    )
    assert bundle["predictions"]["baseline"]["experiment_id"] == "B09-CLASSIC"
    assert bundle["predictions"]["challenger"]["experiment_id"] == "E09-CONTINUOUS"
    assert bundle["postseal_holdout"]["method"] == "postseal_nonce_sha256_rank_v1"
    assert bundle["postseal_holdout"]["status"] == "awaiting_authorized_nonce_draw"
    assert bundle["postseal_holdout"]["holdout_count"] == 107
    assert bundle["postseal_holdout"]["public_count"] == 424
    assert "nonce_hex" not in bundle["postseal_holdout"]
    assert "holdout_set_sha256" not in bundle["postseal_holdout"]
    assert bundle["status"] == "complete_clean_pair_bundle"


def test_clean_pair_bundle_rejects_duplicate_missing_or_nonfinite_rows(tmp_path):
    root, seal = write_three_synthetic_ensembles(tmp_path)
    corrupt_one_prediction(root, duplicate=True)
    with pytest.raises(CleanPairBundleError):
        build_clean_pair_bundle_v09(SYNTHETIC_CONTRACT, seal, root)


def test_clean_pair_bundle_module_contains_no_answer_key_or_discharge_reader():
    hits = scan_for_forbidden_access(MODULE_ROOT)
    assert hits == []
```

- [ ] **Step 2: 运行测试并确认失败**

```powershell
pytest src/26_historical_band_experts/tests/test_clean_pair_bundle_v09.py -q
```

Expected: FAIL，原因是评分包模块尚不存在。

- [ ] **Step 3: 实现流式精确覆盖审核**

每个集合必须按块读取，只保留当前块，不同时驻留三个完整表。审核固定检查：

- 文件SHA-256等于预测封存；
- 表头精确等于`basin,date,qsim`；
- 流域顺序等于冻结531流域顺序；
- 每个流域日期严格覆盖`1989-10-01`至`1999-09-30`；
- 总行数1,939,212；
- 键唯一；
- `qsim`全部有限；
- 三个文件路径和角色与合同逐项相同；
- 评分包固定`postseal_nonce_sha256_rank_v1`和107/424计数，状态为
  `awaiting_authorized_nonce_draw`；
- 评分包构建器不得抽取随机数或调用`derive_postseal_holdout_v09()`，不得保存流域标识。

评分包使用排序键的紧凑JSON计算自身哈希：

```python
def clean_pair_bundle_sha256(bundle: Mapping) -> str:
    payload = dict(bundle)
    payload.pop("bundle_sha256", None)
    encoded = json.dumps(
        payload,
        sort_keys=True,
        separators=(",", ":"),
        ensure_ascii=False,
    ).encode("utf-8")
    return hashlib.sha256(encoded).hexdigest()
```

输出只包含合同、全部前置封存与独立审核哈希、源码包、环境、三个预测文件哈希和待抽取的后封存
划分规则；不包含
随机数、划分结果、指标、观测路径绝对值、留出流域标识或任何正式性能。评分包哈希在评分授权前
固定，后续随机数抽取不能改变评分包。

- [ ] **Step 4: 运行测试并提交**

```powershell
pytest src/26_historical_band_experts/tests/test_clean_pair_bundle_v09.py -q
git add src/26_historical_band_experts/clean_pair_bundle_v09.py `
  src/26_historical_band_experts/tests/test_clean_pair_bundle_v09.py
git commit -m "Feat: Seal formal v09 clean pair bundle"
```

---

### Task 3: 实现一次调用的可信清洁配对评分核心

**Files:**
- Create after route approval: `src/fair_benchmark/score_clean_pair_v09.py`
- Test: `src/fair_benchmark/tests/test_score_clean_pair_v09.py`

**Interfaces:**
- Consumes: Task 1合同、Task 2评分包、只读可信冻结根、候选源码包、现有账本。
- Produces:
  `score_clean_pair_core_v09(*, contract, bundle, holdout_draw_receipt, trusted_frozen_root, prediction_root, source_bundle, ledger_path, timestamp) -> dict`。
- Calls: `fair_benchmark.score.score_submission()`恰好一次。

- [ ] **Step 1: 写真实评分接线的合成端到端测试**

```python
def test_clean_pair_service_calls_existing_scorer_once_and_logs_once(
    tmp_path,
    monkeypatch,
):
    frozen_root, prediction_root, source_bundle = write_synthetic_clean_pair_case(
        tmp_path,
        basin_count=531,
        holdout_count=107,
        dates_per_basin=4,
    )
    calls = {"count": 0}
    real = score_clean_pair_v09.score_submission

    def counted(**kwargs):
        calls["count"] += 1
        return real(**kwargs)

    monkeypatch.setattr(score_clean_pair_v09, "score_submission", counted)
    report = score_clean_pair_core_v09(
        contract=SYNTHETIC_CONTRACT,
        bundle=SYNTHETIC_BUNDLE,
        holdout_draw_receipt=SYNTHETIC_HOLDOUT_DRAW_RECEIPT,
        trusted_frozen_root=frozen_root,
        prediction_root=prediction_root,
        source_bundle=source_bundle,
        ledger_path=tmp_path / "ledger.csv",
        timestamp="2026-07-31T00:00:00",
    )
    assert calls["count"] == 1
    assert count_attempts(tmp_path / "ledger.csv") == 1
    assert report["track"] == "track0_forcing_only_clean_v09"
    assert report["primary"]["baseline_id"] == "B09-CLASSIC"
    assert report["capacity_comparison"]["verdict_role"] == "descriptive_only"
    assert report["historical_reference"]["qualifying"] is False
```

还必须测试：

- 清洁经典集合变差时，主基准随之变化；
- 旧冻结基准和旧留出集均不被可信核心解析，也不改变主判定；
- 改变任一封存预测哈希会使评分包与授权失效；
- 改变评分进程的一次性随机数会改变派生留出摘要；
- 可信核心派生的`nonce_sha256`必须等于抽取收据登记值；
- 随机数抽取收据、划分盐或留出集合摘要漂移时，`load_obs_csv()`调用次数为0；
- 同参数量控制只改变次要比较，不改变主判定；
- 任一集合缺失531个有限逐流域指标时`contract_ok=false`，不能`PASS`；
- 公开比较数必须为424且后封存留出比较数必须为107，否则不能`PASS`；
- 报告不含留出流域标识、逐流域指标或观测值；
- 禁止访问扫描命中时主结果为`HOLD`；
- 候选源码包出现旧逐流域基准、旧留出列表、既有评分报告或评分账本访问词时也强制`HOLD`；
- 答案哈希或流域哈希漂移时，在调用现有评分函数前失败；
- 原冻结留出文件即使存在，也不能传入`Track.secret_holdout`。
- 主比较或同参数量比较全部配对差异为0时仍产生可解析的严格JSON报告：Wilcoxon检验值写为
  `null`并附`all_paired_differences_zero`，账本中的`nan`字符串由终审显式映射，不能导致评分后
  报告写出失败。

- [ ] **Step 2: 运行测试并确认失败**

```powershell
pytest src/fair_benchmark/tests/test_score_clean_pair_v09.py -q
```

Expected: FAIL，原因是可信评分核心尚不存在。

- [ ] **Step 3: 实现可信根解析和现场清洁基准**

可信入口只接受根目录参数，不接受答案文件任意路径。它只按合同拼接正式答案和531流域列表两个
正式输入并验证SHA-256；旧基准与旧留出文件不得解析。工作区内答案不存在不是错误修复目标；服务
必须使用显式可信根，不能复制答案。

核心固定顺序是先验证后封存划分，再打开正式答案。下列划分代码必须发生在首次
`load_obs_csv()`之前：

```python
partition = derive_postseal_holdout_v09(
    basin_ids,
    protocol_sha256=contract["protocol_sha256"],
    prediction_sha256=bundle_prediction_sha256,
    nonce_hex=holdout_draw_receipt["nonce_hex"],
    holdout_count=107,
)
assert partition["method"] == bundle["postseal_holdout"]["method"]
assert len(partition["holdout_ids"]) == bundle["postseal_holdout"]["holdout_count"]
assert partition["nonce_sha256"] == holdout_draw_receipt["nonce_sha256"]
assert partition["partition_salt_sha256"] == holdout_draw_receipt["partition_salt_sha256"]
assert partition["holdout_set_sha256"] == holdout_draw_receipt["holdout_set_sha256"]

obs = load_obs_csv(answer_key_path)
classic_sim = load_predictions(classic_path)
classic_nse = per_basin_score(obs, classic_sim, nse)
del classic_sim

capacity_sim = load_predictions(capacity_path)
capacity_nse = per_basin_score(obs, capacity_sim, nse)
del capacity_sim

candidate_sim = load_predictions(candidate_path)
candidate_nse = per_basin_score(obs, candidate_sim, nse)
del candidate_sim
```

三个字典必须键集合等于冻结531流域且值全部有限；公开和留出数量分别固定为424和107。然后构造：

```python
track = Track(
    name="track0_forcing_only_clean_v09",
    baseline_nse=classic_nse,
    obs=obs,
    secret_holdout=partition["holdout_ids"],
    gate_cfg=GateConfig(
        min_effect=0.01,
        max_wilcoxon_p=0.05,
        holdout_min_effect=0.005,
        holdout_retention=0.5,
    ),
    allow_observed_q=False,
    forbidden_patterns=CLEAN_PAIR_FORBIDDEN_PATTERNS,
    metric=nse,
    spec={"confirmed": True, "contract_id": "S09C-CLEAN-PAIR"},
)
```

`CLEAN_PAIR_FORBIDDEN_PATTERNS`固定为现有`DEFAULT_FORBIDDEN`的完整顺序加上：

```python
[
    r"track0_forcing_only_baseline_per_basin_nse",
    r"track0_forcing_only_secret_holdout_basins",
    r"portfolio_ledger",
    r"fair_benchmark[/\\]experiments[/\\].*report\.json",
]
```

不得删除或放宽现有模式。候选静态扫描包已在预测封存阶段按实际运行模块追踪构建；协议文件因只声明
禁用词而在包外绑定原字节哈希，实际运行源码不得过滤、改写或漏包。

- [ ] **Step 4: 调用现有正式评分函数一次**

```python
primary = score_submission(
    predictions_path=candidate_path,
    track=track,
    ledger_path=ledger_path,
    experiment_id="S09C-CLEAN-PAIR",
    timestamp=timestamp,
    contract_ok=contract_ok,
    coverage_min_ratio=0.99,
    experiment_dir=source_bundle,
)
```

源码中只能有这一个`score_submission(`调用点。测试用替身计数，并在源码审核中拒绝第二个调用点、
动态导入或间接重复入口。

在调用前，核心用同一`paired_comparison()`计算候选相对清洁经典及候选相对同参数量控制的聚合
统计；调用后要求主比较逐字段等于`score_submission()`返回的公开与后封存留出统计。次要比较只在
主调用成功追加账本后写入最终报告。旧基准只记录预先审核过的标量
`historical_reference_nonqualifying=0.759225`及其文件哈希，不在可信进程中读取逐流域旧基准。

- [ ] **Step 5: 限定报告结构**

报告必须包含：

- 主`PASS/HOLD/REJECT`和原因；
- 清洁经典、同参数量控制、候选三个预测文件SHA-256；
- 公开424流域和后封存留出107流域的主聚合统计；
- 同参数量控制的预注册描述性聚合统计；
- 旧基准的`historical_reference_nonqualifying=0.759225`，不报告新的旧基准比较；
- 合同、评分包、预测封存、源码包、可信服务树、答案、流域、随机数抽取收据、划分盐和留出集合
  摘要哈希；
- 账本追加前后行数、前后SHA-256、新行哈希；
- `score_submission_call_count=1`和`ledger_append_count=1`。

报告不得包含逐流域字典、留出流域列表或逐日值。

报告写入使用同目录独占`.building`文件，先把仅允许出现于聚合统计的`NaN`或正负无穷规范化为
`null`和明确原因，再调用`json.dumps(..., allow_nan=False, sort_keys=True)`；刷新并同步到磁盘后
原子改名为`report.json`。若账本已追加但严格报告未能完成，授权保持已消费，终审输出
`HOLD_INCOMPLETE_NO_RETRY`。

- [ ] **Step 6: 运行测试并提交**

```powershell
pytest src/fair_benchmark/tests/test_score_clean_pair_v09.py `
  src/fair_benchmark/tests/test_score_e2e.py `
  src/fair_benchmark/tests/test_gate.py `
  src/fair_benchmark/tests/test_stats.py `
  src/fair_benchmark/tests/test_ledger.py -q
git add src/fair_benchmark/score_clean_pair_v09.py `
  src/fair_benchmark/tests/test_score_clean_pair_v09.py
git commit -m "Feat: Add one-call clean pair scoring"
```

---

### Task 4: 实现动态哈希授权、独占消费和不可重试入口

**Files:**
- Create after route approval: `src/fair_benchmark/clean_pair_authorization_v09.py`
- Test: `src/fair_benchmark/tests/test_clean_pair_authorization_v09.py`
- Create only after direct score approval:
  `results/26_historical_band_experts/formal_v09/authorizations/clean_pair_scoring_authorization.json`
- Generated at first launch:
  `results/26_historical_band_experts/formal_v09/clean_pair_scoring_authorization_consumed.json`
- Generated once after authorization consumption:
  `results/26_historical_band_experts/formal_v09/clean_pair_holdout_draw_receipt.json`

**Interfaces:**
- `render_clean_pair_score_approval_text(bundle_sha256) -> str`。
- `validate_clean_pair_score_authorization_v09(receipt, *, contract, bundle, source_tree, ledger_snapshot) -> dict`。
- `consume_clean_pair_score_authorization_v09(receipt, consumption_path, launch_snapshot) -> dict`。
- `draw_holdout_nonce_once_v09(consumption_path, draw_receipt_path, *, contract, bundle, basin_ids, random_bytes=secrets.token_bytes) -> dict`。

- [ ] **Step 1: 写精确作用域和消费测试**

```python
def test_clean_pair_authorization_binds_all_three_predictions_and_ledger():
    receipt = valid_receipt()
    validated = validate_clean_pair_score_authorization_v09(
        receipt,
        contract=CONTRACT,
        bundle=BUNDLE,
        source_tree=SOURCE_TREE,
        ledger_snapshot=LEDGER_SNAPSHOT,
    )
    assert validated["maximum_attempts"] == 1
    assert validated["allowed_experiment_id"] == "S09C-CLEAN-PAIR"
    assert validated["prediction_sha256"] == {
        "baseline": CLASSIC_SHA,
        "capacity_control": CAPACITY_SHA,
        "challenger": CANDIDATE_SHA,
    }
    assert validated["postseal_holdout"] == {
        "method": "postseal_nonce_sha256_rank_v1",
        "nonce_source": "python_secrets_token_bytes_32_after_authorization_consumption",
        "nonce_draws": 1,
        "nonce_redraws": 0,
        "holdout_count": 107,
        "public_count": 424,
    }


def test_clean_pair_authorization_consumes_exclusively_once(tmp_path):
    path = tmp_path / "consumed.json"
    consume_clean_pair_score_authorization_v09(RECEIPT, path, SNAPSHOT)
    with pytest.raises(CleanPairAuthorizationError):
        consume_clean_pair_score_authorization_v09(RECEIPT, path, SNAPSHOT)


def test_holdout_nonce_is_drawn_once_only_after_consumption(tmp_path):
    consumption = tmp_path / "consumed.json"
    draw = tmp_path / "holdout_draw.json"
    with pytest.raises(CleanPairAuthorizationError):
        draw_holdout_nonce_once_v09(
            consumption,
            draw,
            contract=CONTRACT,
            bundle=BUNDLE,
            basin_ids=BASINS,
        )
    consume_clean_pair_score_authorization_v09(RECEIPT, consumption, SNAPSHOT)
    receipt = draw_holdout_nonce_once_v09(
        consumption,
        draw,
        contract=CONTRACT,
        bundle=BUNDLE,
        basin_ids=BASINS,
        random_bytes=lambda n: b"\x01" * n,
    )
    assert receipt["nonce_hex"] == "01" * 32
    with pytest.raises(CleanPairAuthorizationError):
        draw_holdout_nonce_once_v09(
            consumption,
            draw,
            contract=CONTRACT,
            bundle=BUNDLE,
            basin_ids=BASINS,
        )
```

- [ ] **Step 2: 运行测试并确认失败**

```powershell
pytest src/fair_benchmark/tests/test_clean_pair_authorization_v09.py -q
```

Expected: FAIL，原因是授权模块尚不存在。

- [ ] **Step 3: 固定未来评分批准文本渲染规则**

评分包哈希已知后，前置审核必须输出且用户必须逐字回复：

```text
批准版本09清洁同信息配对正式评分；仅授权评分包SHA-256=<实际64位小写十六进制>在S09C-CLEAN-PAIR中消费一次授权、抽取一次256位留出随机数并调用评分一次；不批准重抽、重试或其他评分。
```

`<实际64位小写十六进制>`由`render_clean_pair_score_approval_text()`替换为
`clean_pair_bundle.json`内的实际哈希。收据保存完整批准文本、其UTF-8 SHA-256、所在任务标识和时间；
不接受“继续”“批准评分”或旧`S09-SEALED`授权。

- [ ] **Step 4: 固定收据键集合**

收据必须恰好绑定：

- 合同SHA-256；
- 评分包SHA-256；
- 三个集合SHA-256；
- 预测总封存SHA-256；
- 训练总封存SHA-256；
- 输入总封存、旧检查点函数桥接审核、严格嵌套运行封存、严格嵌套独立审核、训练独立审核和预测
  独立重放审核SHA-256；
- 版本08候选配置、60流域内部确认摘要、分析清单和独立审核SHA-256；
- 24个第30轮检查点SHA-256；
- 候选源码包哈希树；
- 新可信评分入口和全部复用评分模块哈希；
- Python解释器解析后绝对路径、当前工作树`src`解析后绝对路径，以及
  `PYTHONPATH`严格等于该单一路径的启动合同；
- 正式答案和流域列表的预期SHA-256；
- `postseal_nonce_sha256_rank_v1`、操作系统密码学随机源、抽取数1、重抽数0和107/424计数；
- 旧留出列表及不合格历史基准的受保护快照SHA-256，并明确两者不参与主判定；
- 只读可信冻结根解析后的绝对路径；
- 评分前账本行数、文件SHA-256和末行哈希；
- 固定实验标识、赛道标识、输出根和`maximum_attempts=1`。

未知键、缺失键、路径漂移、哈希漂移、账本变化或既有同标识行均拒绝。授权收据不能预先包含
随机数、划分盐或留出集合摘要。

入口必须先以独占创建方式写消费收据，随后调用`secrets.token_bytes(32)`恰好一次，并以独占创建
方式写抽取收据。抽取收据绑定消费收据SHA-256、64位`nonce_hex`、`nonce_sha256`、三组预测哈希、
`partition_salt_sha256`、`holdout_set_sha256`和107/424计数。消费收据或抽取收据任一已存在都立即
停止；消费后在抽取前崩溃也不得重试。

- [ ] **Step 5: 运行测试并提交**

```powershell
pytest src/fair_benchmark/tests/test_clean_pair_authorization_v09.py -q
git add src/fair_benchmark/clean_pair_authorization_v09.py `
  src/fair_benchmark/tests/test_clean_pair_authorization_v09.py
git commit -m "Feat: Authorize one clean pair score"
```

---

### Task 5: 完成不解析观测的评分前独立审核并执行一次

**Files:**
- Create after route approval:
  `src/26_historical_band_experts/audit_clean_pair_score_preflight_v09.py`
- Test:
  `src/26_historical_band_experts/tests/test_audit_clean_pair_score_preflight_v09.py`
- Generated before score approval:
  `results/26_historical_band_experts/formal_v09/clean_pair_score_preflight.external_audit.json`
- Generated by the trusted service:
  `results/26_historical_band_experts/formal_v09/clean_pair_score_attempt_01/report.json`

**Interfaces:**
- `audit_clean_pair_score_preflight_v09(contract_path, bundle_path, prediction_seal_path, source_bundle, ledger_path, trusted_frozen_root) -> dict`。
- The preflight must not import `load_obs_csv` or open the answer parquet.

- [ ] **Step 1: 写无观测前置审核测试**

测试必须证明：

- 三个预测、评分包、预测封存和源码包哈希全部重新计算；
- 输入、旧检查点函数桥接、严格嵌套运行及独立审核、24次训练及独立审核、24个第30轮检查点和
  24文件预测独立重放的状态与哈希全部重新计算；
- 版本08的候选配置、60流域内部确认摘要、分析清单和独立审核哈希匹配，状态仍为
  `complete_multiseed_go`，且没有正式结果后重选记录；
- 三个预测均通过精确覆盖；
- 评分包的后封存划分状态严格为`awaiting_authorized_nonce_draw`，且不含随机数或划分结果；
- 新服务和复用评分模块哈希正确；
- 使用授权将绑定的Python解释器，且`PYTHONPATH`严格设为当前工作树解析后的`src`绝对路径时，
  `fair_benchmark.score_clean_pair_v09`及其全部可信依赖能够只读导入；模块文件均位于该工作树，
  不从主仓库、用户目录或其他环境阴影导入；
- 旧冻结赛道文件没有变化；
- 旧留出列表被标记为`legacy_reused_holdout_nonqualifying`，真实账本中至少7条历史记录均不得被
  当作新留出集证据；
- 工作区干净，协议配置SHA-256仍为
  `b81bce8fc83aa8c4cad2d36475c6e6da553567f54b5f5f8d52457006fb446ed8`；
- 正式答案在隔离工作区缺失，在显式可信根存在；
- 前置审核只检查答案文件元数据和合同登记值，不解析、不复制、不计算内容指标；
- 账本链有效且没有`S09C-CLEAN-PAIR`；
- 账本当前快照的行数、SHA-256和末行哈希与授权输入一致；当前已知历史快照为7行且0个链断点，
  但正式前置门必须以届时重算值为准，不能硬编码7；
- 授权消费收据、留出随机数抽取收据和正式报告均不存在；
- 可用物理内存至少12.68 GiB；
- 任一失败时状态不是`ready_for_clean_pair_score_authorization`。

- [ ] **Step 2: 运行测试并确认失败**

```powershell
pytest src/26_historical_band_experts/tests/test_audit_clean_pair_score_preflight_v09.py -q
```

Expected: FAIL，原因是前置审核器尚不存在。

- [ ] **Step 3: 实现和提交前置审核器**

```powershell
pytest src/26_historical_band_experts/tests/test_audit_clean_pair_score_preflight_v09.py -q
git add src/26_historical_band_experts/audit_clean_pair_score_preflight_v09.py `
  src/26_historical_band_experts/tests/test_audit_clean_pair_score_preflight_v09.py
git commit -m "Feat: Audit clean pair score preflight"
```

- [ ] **Step 4: 运行全部代码审核**

只有可用物理内存至少12.68 GiB时运行：

```powershell
pytest src/26_historical_band_experts/tests -q
pytest src/fair_benchmark/tests -q
```

记录两个准确通过数量、警告、耗时、Git提交、环境、内存和源码树哈希。任一失败不得请求评分授权。

- [ ] **Step 5: 生成真实前置报告**

```powershell
python src\26_historical_band_experts\audit_clean_pair_score_preflight_v09.py `
  --contract src\26_historical_band_experts\configs\formal_v09_clean_pair_scoring_contract.json `
  --bundle results\26_historical_band_experts\formal_v09\predictions\clean_pair_bundle.json `
  --prediction-seal results\26_historical_band_experts\formal_v09\predictions\seal.json `
  --source-bundle results\26_historical_band_experts\formal_v09\predictions\source_bundle `
  --trusted-frozen-root G:\github\pycharm\projects\neuralhydrology\src\fair_benchmark\frozen `
  --ledger src\fair_benchmark\registry\portfolio_ledger.csv `
  --report results\26_historical_band_experts\formal_v09\clean_pair_score_preflight.external_audit.json
```

状态必须严格为`ready_for_clean_pair_score_authorization`，否则停止。

- [ ] **Step 6: 请求动态哈希批准并创建收据**

把前置报告渲染的完整批准文本原样交给用户。只有用户逐字回复后，才以独占创建方式写入
`results/26_historical_band_experts/formal_v09/authorizations/clean_pair_scoring_authorization.json`。
授权收据是正式封存产物，不修改或提交源码；其SHA-256写入启动快照。收据生成后再次只读验证全部
哈希，不能改预测、合同、源码、账本或输出路径。

- [ ] **Step 7: 由未参与实现的独立评分执行者执行唯一一次可信评分**

```powershell
$env:PYTHONPATH = (Resolve-Path 'src').Path
python -c "import fair_benchmark.score_clean_pair_v09 as m; print(m.__file__)"
python -m fair_benchmark.score_clean_pair_v09 `
  --contract src\26_historical_band_experts\configs\formal_v09_clean_pair_scoring_contract.json `
  --bundle results\26_historical_band_experts\formal_v09\predictions\clean_pair_bundle.json `
  --authorization results\26_historical_band_experts\formal_v09\authorizations\clean_pair_scoring_authorization.json `
  --prediction-root results\26_historical_band_experts\formal_v09 `
  --source-bundle results\26_historical_band_experts\formal_v09\predictions\source_bundle `
  --trusted-frozen-root G:\github\pycharm\projects\neuralhydrology\src\fair_benchmark\frozen `
  --ledger src\fair_benchmark\registry\portfolio_ledger.csv `
  --consumption results\26_historical_band_experts\formal_v09\clean_pair_scoring_authorization_consumed.json `
  --holdout-draw-receipt results\26_historical_band_experts\formal_v09\clean_pair_holdout_draw_receipt.json `
  --out results\26_historical_band_experts\formal_v09\clean_pair_score_attempt_01\report.json
```

导入探针属于消费授权前的只读门，输出的模块路径必须位于当前工作树`src/fair_benchmark`并与授权
哈希一致。入口先检查内存、三个输出不存在、解释器、`PYTHONPATH`、模块来源和账本快照，再独占
消费授权；随后恰好抽取一次256位随机数、派生107流域集合并独占写抽取收据，之后才解析答案。
任何异常均停止且禁止重抽或重试。评分调用前再次验证账本仍等于授权快照；变化时不调用评分并进入
`HOLD_INCOMPLETE_NO_RETRY`。正式评分窗口内不得启动其他评分进程。执行上下文必须记录其独立任务
标识并声明未参与候选、训练、预测或可信评分包装器的实现；实施者自己的任务标识不得通过启动门。

---

### Task 6: 不再次读取答案的独立终审和结论

**Files:**
- Create after route approval:
  `src/26_historical_band_experts/audit_clean_pair_score_final_v09.py`
- Test:
  `src/26_historical_band_experts/tests/test_audit_clean_pair_score_final_v09.py`
- Generated after the one call:
  `results/26_historical_band_experts/formal_v09/clean_pair_score_final_audit.json`
- Create after the one call:
  `docs/technical/historical_multiscale_formal_v09_clean_pair_score_final_audit.md`

**Interfaces:**
- `audit_clean_pair_score_final_v09(report_path, authorization_path, consumption_path, holdout_draw_receipt_path, bundle_path, basin_file_path, ledger_path) -> dict`。
- Must not import or call `load_obs_csv`、`score_submission`、`score_clean_pair_core_v09`。

- [ ] **Step 1: 写不重评分的终审测试**

```python
def test_final_audit_uses_only_report_ledger_and_hashes(monkeypatch):
    monkeypatch.setattr(
        "fair_benchmark.score.score_submission",
        lambda **_: (_ for _ in ()).throw(AssertionError("rescoring forbidden")),
    )
    result = audit_clean_pair_score_final_v09(
        REPORT,
        AUTHORIZATION,
        CONSUMPTION,
        HOLDOUT_DRAW_RECEIPT,
        BUNDLE,
        BASIN_FILE,
        LEDGER,
    )
    assert result["score_submission_call_count"] == 1
    assert result["ledger_rows_added"] == 1
    assert result["answer_reopened"] is False
```

还要覆盖：

- 报告主结果与账本新行逐字段一致；
- 账本链有效，只有一个`S09C-CLEAN-PAIR`；
- 三个预测哈希与评分包、授权和报告一致；
- 主判定可由报告中的公开、后封存留出聚合值和固定门槛重新推导；
- 报告是`allow_nan=false`可解析的严格JSON；账本字段值`nan`只允许对应报告中因
  `all_paired_differences_zero`而规范化的`null`，其他非有限或无法逐字段映射的值使终审失败；
- 抽取收据只有一个64位随机数，且其SHA-256、划分盐和留出集合摘要可由三组封存预测哈希确定性
  复核，计数严格为107/424；
- 冻结流域列表SHA-256与合同相同，恰有531个唯一标识；终审只读取该非观测列表来重算107流域集合
  摘要，不读取答案、预测值或逐流域指标；
- 同参数量控制没有改变主判定；
- 旧基准始终标记不具资格；
- 报告或账本缺失时结论为`HOLD_INCOMPLETE_NO_RETRY`；
- 任何留出流域标识或逐流域指标泄露使终审失败。

- [ ] **Step 2: 运行测试并确认失败**

```powershell
pytest src/26_historical_band_experts/tests/test_audit_clean_pair_score_final_v09.py -q
```

Expected: FAIL，原因是终审模块尚不存在。

- [ ] **Step 3: 实现、测试并提交终审器**

```powershell
pytest src/26_historical_band_experts/tests/test_audit_clean_pair_score_final_v09.py -q
git add src/26_historical_band_experts/audit_clean_pair_score_final_v09.py `
  src/26_historical_band_experts/tests/test_audit_clean_pair_score_final_v09.py
git commit -m "Feat: Audit clean pair score once"
```

- [ ] **Step 4: 由另一个未参与实现的独立上下文执行终审**

独立上下文只读取合同、评分包、三个预测哈希、授权、消费收据、留出随机数抽取收据、冻结531流域
标识列表、服务报告、账本、源码树和封存链。它不得打开正式答案或预测数值、调用任何评分入口或重算
逐流域指标。该终审上下文不得是实施者；优先与唯一评分执行上下文也分离，并记录两个任务标识。

最终状态限定为：

- `PASS`：主比较通过全部公开和后封存留出门，且全部完整性证据通过；
- `HOLD`：有效主比较未通过胜利门；
- `REJECT`：覆盖、合同、泄漏或其他完整性失败，并已由唯一账本行记录；
- `HOLD_INCOMPLETE_NO_RETRY`：授权已消费但没有完整服务报告或账本追加状态不完整。

同参数量控制另行报告`capacity_comparison_descriptive`，不能覆盖主状态。只有其公开与后封存留出
结果方向一致、
Wilcoxon检验和自助抽样区间均支持正差时，文字讨论才能写为“结果不能仅由增加经典近期模型宽度
解释”；否则明确写为“容量解释仍未排除”。无论结果如何，都不得据此声称长期气象历史具有因果作用。

- [ ] **Step 5: 写最终文档和登记**

最终文档必须区分事实、推断和未知，记录：

- 清洁经典、同参数量控制、连续历史候选三个集合身份；
- 一次评分调用和一条账本追加；
- 主门逐项结果；
- 原冻结留出集至少被7次评分查询，因而不具新秘密留出资格；
- 新107流域集合只在三组预测封存且一次性授权消费后，由一次256位随机数和固定哈希算法确定，
  且没有结果后训练或选择；
- 同参数量次要比较；
- 不合格旧基准的历史参考结果；
- 源码、数据边界、资源、封存和独立审核结论；
- 无重试、无第二个评分进程、终审未重开答案、无结果后选择。

```powershell
git add docs/technical/historical_multiscale_formal_v09_clean_pair_score_final_audit.md `
  src/26_historical_band_experts/registry.csv `
  src/fair_benchmark/registry/portfolio_ledger.csv
git commit -m "Phase: Record formal v09 clean pair result"
```

## 自审

- Spec coverage：保留531流域、Maurer、27项静态属性、3,561天最长滞后、经典256单元近期路径、
  30轮、八随机数、同参数量控制、一次正式评分和独立终审。
- Fairness repair：主基准由同一干净训练合同下的`B09-CLASSIC`现场派生，不再使用含正式评估期统计
  的旧训练结果作正式判定。
- Protected scope：现有冻结目录和八个评分模块均不修改；新可信入口只导入并调用现有函数。
- One-call proof：源码一个调用点、运行时计数1、账本新增1行、授权一次消费、重试数0。
- Sealing：三组预测在答案访问前同时封存；评分包和授权绑定全部哈希。
- Holdout repair：旧107流域集合不参与新判定；新107流域集合由唯一评分进程在授权消费后抽取的
  一次256位随机数与三组已封存预测身份共同确定，公开集为其424流域补集；不允许预生成、重抽、
  修改或重试。
- Information boundary：候选和前置审核不解析答案；只有唯一可信评分进程解析，终审不重开答案。
- Feedback boundary：候选侧不得读取旧逐流域基准、旧留出列表、历史评分报告或账本；新赛道扫描
  模式是在现有禁用模式上只增不减。
- Type consistency：逐日预测为`float64`解析值；逐流域指标为Python浮点数；哈希均为64位小写十六进制。
- No placeholders：未来动态评分包哈希由固定渲染函数产生，不存在人工填写字段。
- Current blocker：路线尚未获用户批准，正式输入、训练、预测和评分授权仍全部为`false`。
