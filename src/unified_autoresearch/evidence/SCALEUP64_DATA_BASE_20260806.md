# 64 流域数据底座：冻结、构建、逐流域核查（2026-08-06）

对应任务书 `MILESTONE4_SCALEUP_CHECKLIST_64_531.md` §四第 1–4 条。
本文只记数据底座；**未做任何 64 流域正式搜索，未跑任何候选，未产生任何科研结论**。

## 一、开场自检（动手前）

| 项 | 实测 |
|---|---|
| git HEAD | `81974588 feat(autoresearch): commit unified autoresearch vertical (milestones 0-4 + review hardening)` |
| 工作树 | 干净（仅未跟踪的交接文档 `HANDOFF_20260806_SCALEUP64_DATA_BASE.md`） |
| 全量测试 | 185 通过 / 5 跳过 / 0 失败（371.41 秒） |

三项与交接文档一致，故继续。

## 二、64 流域选择：包含 8 流域，是算法性质而非人为决定

`selection/basins.py` 的 `select_development_basins` 是**贪心最远点法**：第 i 个流域只由前 i−1 个
决定，与传入的 `count` 无关。因此同一份静态表与合格流域表下，`count=64` 的前 8 个必然逐字等于
已冻结的 8 流域记录。实测确认 `64[:8] == 冻结 8 流域 → True`。

交接文档留的"含还是互斥"问题据此判定为**含**：互斥需要额外排除逻辑，会破坏"确定性、可复现"
的选择规则，无理由采用。

**合格流域表原先只有散列、没有路径**。按散列 `cd2d3d466aca736fcd32042d2b0bde3d0b58e42ba37fe552d97480bd914b9e85`
反查定位到 `examples/06-Finetuning/531_basin_list.txt`（531 行，无重复）。此路径现已由
`tests/test_scaleup_64_selection.py` 钉死。

### 冻结产物

- 文件：`selection/development_basins_64_v1.json`
- sha256：`3d75df6cfce527b8f6580a9dcfe0eacccb65c8bd7aae987ce23ead462ab00e53`（1400 字节）
- 静态表 sha256：`085e8b5e0e56b42bfe7e6d012ebb6f2f56681059b60c61c04b835b207864a1f2`
- 合格流域表 sha256：`cd2d3d466aca736fcd32042d2b0bde3d0b58e42ba37fe552d97480bd914b9e85`
- 两个输入散列与 8 流域记录完全相同，即两份记录同源。

**诚实记录一处自造失误**：初版测试第 5 条直接对源码树真实路径调用 `freeze_selection`，红阶段时
反而把该文件写了出来。已改为在临时目录冻结并与已提交记录做逐字节比对，源码树零副作用。该意外
产物被删除后按同一规则重新生成，两次 sha256 逐字节相同（`3d75df6c…`），确定性因此得到额外一次
独立佐证。

## 三、必须改的代码：原先硬编码只认 8 流域

`data/packages.py` 里 `FROZEN_DEVELOPMENT_SELECTION` 是硬编码的 8 流域字典，`packages.py` 与
`real_source.py` 都做 `selection == 那个字典` 的全等比对。64 流域不改代码跑不通。

改法（测试先行，防漂移强度不变）：

1. 新增硬编码常量 `FROZEN_DEVELOPMENT_SELECTION_64`，与 8 流域常量并列为
   `FROZEN_DEVELOPMENT_SELECTIONS`。**仍然硬编码**——若改为从 JSON 读取，篡改该 JSON 就无法被
   发现，这是原设计的关键防线，不能拆。字面量由脚本从冻结文件生成，避免手抄。
2. 新增 `load_frozen_selection(path)`：读入后要求"必须属于已冻结记录集合"，否则抛原文案
   `frozen development basin selection mismatch`。两个构建器改为调用它。
3. `real_source.py` 里写死的静态表散列改为取自传入选择记录自身的 `static_sha256`。该记录已被上一步
   钉死，强度等价、逻辑更正确（不再假定"所有选择都用同一张静态表"）。

新增负例测试钉死：一个**能确定性复现但从未被冻结**的 16 流域记录，照样被拒。即闸门认的是"已冻结"，
不是"可复现"。

## 四、真实数据构建（64 流域）

原始档案在主仓 `G:\github\pycharm\projects\neuralhydrology\data\camels_us`；工作副本内无 `data/`，
构建必须显式传 `--camels-root`。64 流域的 maurer 强迫文件与 usgs 流量文件各 64/64，无缺无重。

```bash
python src/unified_autoresearch/scripts/build_real_development_source.py \
  --camels-root "G:/github/pycharm/projects/neuralhydrology/data/camels_us" \
  --selection src/unified_autoresearch/selection/development_basins_64_v1.json \
  --output-root runs/unified_autoresearch/development_source_real_64_v1

python src/unified_autoresearch/scripts/build_real_development_packages.py \
  --source-root runs/unified_autoresearch/development_source_real_64_v1 \
  --selection src/unified_autoresearch/selection/development_basins_64_v1.json \
  --output-root runs/unified_autoresearch/development_packages_real_64_v1
```

### 产物

| 项 | 值 |
|---|---|
| 数据源根 | `runs/unified_autoresearch/development_source_real_64_v1`，3 619 915 字节 |
| 两协议数据包 | `runs/unified_autoresearch/development_packages_real_64_v1`，8 215 077 字节，12 个文件 |
| `features.parquet` | `1c13a08328a588888c63bb7f44b6677d985e10121421583016a9d8774f414896` |
| `targets.parquet` | `3d070cd4a6f92e291ddf8844455be71b9d19da58e8a2d91824c4b503c2277573` |
| `static_attributes.json` | `a59be77c9cf651112e616b525b215a15f0118527a5f843626538f511e9311734` |

8 流域时数据包为 1.4 兆字节，清单预估 64 流域约 11 兆字节；实测 8.2 兆字节，略低于线性外推。

## 五、逐流域核查

核查器 `data/verification.py` **不复跑构建器**，而是从原始档案与冻结静态表独立重算，因此构建器的
缺陷无法自己给自己背书。它只读开发窗口的行，封存区间只计数、绝不输出。

先写 15 条测试（含 6 条负例：注入封存日期、改坏单位换算、往预测包里塞观测流量、删静态属性、删一天、
破坏清单散列——全部必须判失败），红→绿后才跑真实数据。

### 真实 64 流域结果：全过

| 检查项 | 结果 |
|---|---|
| 流域数 | 64 |
| 封存区间（1989-10-01~1999-09-30）命中行 | **0**（全部 17 个产物文件合计） |
| 开发窗口天数 | 每流域 3288 天，缺失 0 天 |
| 日期边界 | 每流域均为 1999-10-01 ~ 2008-09-30 |
| 单位换算最大绝对误差 | **0.0**（64 流域全部，对原始 cfs × 28316846.592 × 86400 ÷ (面积 × 10⁶) 逐日重算） |
| 静态属性 | 每流域 27 项，缺失 0，与冻结静态表逐值相等 |
| 预测包含观测流量 | 否（forward/reverse 两协议均只有 basin/date/prcp/tmin/tmax/srad/vp） |
| 协议窗口 | forward 训练 2192 天 + 验证 1096 天；reverse 同，两者相加均等于 3288 |
| 清单散列 | 数据源与数据包清单与磁盘逐文件一致 |
| 产物文件散列钉死 | 17 个 |

报告：`runs/unified_autoresearch/VERIFICATION_DEVELOPMENT_ARTIFACTS_64_v2.json`，
sha256 `3de8dc82631856db1e8c67095864fa562be32d1a0f72284e27bc860a9fe637a8`。
（先前的 `..._64.json`，sha256 `bf2acfd09cf833299d361a02d278f408ed57dfbc0d1aa1f00466eb758d0a21a2`，
是加"极端流域排名"字段之前跑的同一批核查，按红线 9 保留不覆盖。）

## 六、发现：交接文档标的两个敏感流域，在 64 规模下不是最极端的

原记两个敏感流域为 06847900（验证期流量标准差极小）与 08190500（大量零流量日）。实测：

**零流量天数（开发窗口 3288 天中）**

| 流域 | 零流量天数 | 占比 |
|---|---|---|
| 06879650 | 2035 | 62% |
| 09512280 | 1982 | 60% |
| 08194200 | 1585 | 48% |
| 08158810 | 836 | 25% |
| 07142300 | 790 | 24% |
| 08190500（原记） | 244 | 7% |

**验证期流量标准差（取两协议中较小者）**

| 流域 | 标准差 |
|---|---|
| 09306242 | 0.006969 |
| 06847900（原记） | 0.018753 |
| 06409000 | 0.038796 |
| 07142300 | 0.045958 |
| 06350000 | 0.069627 |

结论：写死流域名的看护清单在扩规模时会失效——64 里有比原记两个严重得多的流域（06879650 的零流量
占到 62%），531 只会更糟。因此核查器改为**自己算出并排名极端流域**（新字段 `diagnostic_extremes`，
零流量前五 + 标准差最低五），排名逻辑由测试钉死。原来的两个流域名保留在 `sensitive_basins` 字段里
作为历史声明，但判定不再依赖它。

**这只是数据分布的诊断，不是任何模型或候选的结论。** 后续判定规则怎么处理这些流域（是否降权、是否
换指标、是否单列），属于需要拍板的设计项，本次未做。

## 七、全量测试回归

改完全部代码后重跑：**210 通过 / 5 跳过 / 0 失败**（583.52 秒）。
= 原有 185 + 新增 25（选择 5 + 数据底座 5 + 逐流域核查 15）。5 跳过仍是软链接逃逸反向测试，
本机无创建软链接权限，与本次改动无关。

回归期间有一次操作瑕疵，如实记录：核查器里 `prediction_rows_with_discharge` 初版写成
"泄漏列数 × 行数"，语义别扭，改为"有泄漏列则计该流域行数"。改动发生在一次全量测试进行中，
该次结果因此作废并停掉重跑，上面 210 通过是改后跑的。真实 64 流域报告不受影响：真实预测包里
不存在任何流量列，两种写法都恒为 0。

## 八、本次新增/改动文件

| 文件 | 性质 |
|---|---|
| `selection/development_basins_64_v1.json` | 新增，冻结记录 |
| `data/packages.py` | 改，加 64 常量 + `load_frozen_selection` |
| `data/real_source.py` | 改，改用共用校验、静态表散列取自选择记录 |
| `data/verification.py` | 新增，逐流域核查库 |
| `scripts/verify_development_artifacts.py` | 新增，核查 CLI（报告文件拒绝覆盖） |
| `tests/test_scaleup_64_selection.py` | 新增，5 条 |
| `tests/test_scaleup_64_data_base.py` | 新增，5 条 |
| `tests/test_development_artifact_verification.py` | 新增，15 条 |
| `evidence/SCALEUP64_DATA_BASE_20260806.md` | 新增，本文 |

运行产物（`runs/` 被 .gitignore 忽略，不入库）：`development_source_real_64_v1`、
`development_packages_real_64_v1`、两份核查报告。

## 九、未做与仍需拍板

- **未做任何 64 流域正式搜索**（红线 3 允许建底座、禁止搜索）。
- **未提交 git**（红线 6，需用户明确授权）。
- 5 条软链接逃逸反向测试仍因本机无权限跳过，未变。
- 并行度与聚合资源门槛（清单 §五）仍待拍板，未动。
- 531 流域底座未建；按同一套代码与核查器可直接扩，但 531 的冻结记录需另行冻结并把常量加进
  `FROZEN_DEVELOPMENT_SELECTIONS`。
- 极端流域的判定规则设计（第六节）未做，需拍板。
