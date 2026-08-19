# CAMELS parFC 线 → 论文对表决策文稿 v01（2026-08-17）

依据：`HANDOFF_20260817_CAMELS_PARFC_NOISE_FIX_LINE_COMPLETE.md`（sha256
`1ca0238732da3ac9366c0486e4ad6c94cb611b25ca8fd8524ecdffc98fa840fd`）及其引用的冻结证据。
本文只做对表决策准备，不改论文、不跑实验。用户选定方向2（论文对表落地）后由本会话起草。

## 一、可写入论文的四条结论（证据、声称等级、诚实边界）

### C1 参数候选辨认在月尺度可实现（合成、90流域）——事实级

- 90天窗（跑前预登记副档）：C 方法 893/1080 事件通过、六类转移全≥0.5（min 0.689）；
  P 方法 899/1080、六类全≥0.5（min 0.706）。出处：03D
  `verification/verification_summary.json`（sha256 `ce75e88f…1529`）。
- 边界：仅 parFC（土壤最大蓄水容量）三候选；90流域设计子集、种子0/1；合成真值；
  claim_boundary 登记为 `exploratory_design90_only`。

### C2 辨认速度方向不对称，是物理不是估计器缺陷——推断级（有强数字支撑）

- 减容切换中位响应 0 天（30天窗减容通过率 0.92–0.94）；增容中位 13–37 天
  （30天窗增容通过率 0.28–0.46，03B/03C/03D 三版本一致不过门）。
- 解释：容量减小当天即产生可观测超额产流；容量增大需等足量降雨蓄满新增库容才显形。
  "三版本一致失败+中位响应天数"支持物理下限解释，但无独立物理推导，故标推断级。
- 论文表述建议：30天主档增容未过门必须如实报告，且**框架为对信息速度的测量结果**，
  不是方法失败；不得事后改门。

### C3 噪声诚实是参数辨认的前提；不诚实时不是变钝而是自信地错——事实级（有反事实因果链）

- 修复轨迹（90流域，每方法180任务）：P 方法零概率日 814→256→17、平均NLL 653→32.6→0.977
  （03D 首次过 log 3 门）；C 方法 2044→1215→549、9543→1999→41.5。
- 因果证据：SLZ 过程噪声方差错配约320倍（代码事实）；07184000·s0 第540天只换 SM 均值即恢复
  （充分且必要，五变体反事实）；03049800·s1 第1000天只换主导候选 SM 均值，末段真候选概率
  0.017→0.701。
- 机制句（已有背书）：噪声无处归因→创新误塞进未建模噪声的状态→方差坍缩→概率自信锁死在
  错误候选。

### C4 噪声诚实后，九路径观测合并（P）比完整状态交互（C）更抗状态腐坏——现象级

- 03D 残余零概率任务 P 3/180 vs C 7/180；P 平均NLL 0.977 过门、C 41.5 未过。
- 边界：机制未验证（C 端 07145700 从未做状态诊断）、尾部3流域未收口；03B/03C 阶段两方法
  几乎不可分（此前 C/P 之争大半是噪声错配伪影）。**建议只作现象级表述并注明机制待查**，
  除非先做 C 尾部诊断（原方向1）。

## 二、与主线的对表逻辑（建议叙事）

主线结论（Regge 真实案例、draft-6）：IMM 做参数是错误工具——参数加权预报在预报窗内输给
率定单套。CAMELS parFC 线不推翻它，而是给出机制解释并划定适用域：

1. 参数证据积累是周~月尺度（C1+C2），比洪水预报窗慢一个量级 → 在预报窗内指望参数辨认
   是**时间尺度错配**，主线负结果因此有了机制；
2. 主线实验中滤波噪声与真实误差结构必然失配（真实观测无已知σ）→ 按 C3，参数概率不是
   变钝而是可能自信地错，进一步解释"参数 IMM 在真实案例更差"；
3. 两线声称维度不同：CAMELS 只声称"候选辨认"（月尺度、合成、噪声诚实），主线声称
   "预报价值"（小时~天尺度、真实观测）。分开声称，互不越界。

## 三、决策点（由用户拍板）

### D1 判据取舍：30天主档 vs 90天副档

**已裁定（2026-08-17）：a 双报。** 试稿见附录A，用户核准（"go"）。

| 选项 | 内容 | 代价/风险 |
|---|---|---|
| **a 双报（推荐）** | 正文以90天窗为辨认结论支柱，30天窗作为"信息速度物理测量"如实报告（含增容未过门） | 篇幅略增；需写清两档均为跑前预登记 |
| b 90天为主、30天入SI | 正文更干净 | 有藏起主档失败之嫌，审稿风险 |
| c 只报30天 | — | 不可行：会把物理慢检误读为方法失败 |

### D2 落点：这些结果写到哪里 —— 用户已裁定（2026-08-17）

**裁定：不独立成文。** 理由（用户）：当前全部为合成（理想）实验、无真实观测应用，
独立成文分量不够。该裁定与本线自身诚实边界一致：修复方案 multiplier=1 与降雨系数 0.2
依赖合成噪声已知σ，审稿人必然追问"真实场景σ从哪来"，缺在线噪声估计与真实案例前
故事不完整。

| 选项 | 内容 | 状态 |
|---|---|---|
| a 独立成文（仅合成） | — | **已否决**（合成-only 分量不够） |
| **d 攒作第二篇的合成骨架（修订后路径）** | 第二篇 = CAMELS 合成机制（已完成）+ 在线噪声估计 + 真实流域应用；本线冻结结果保持待用 | 在线噪声估计（原方向3）由"可选"变为必经前置，立项仍需授权 |
| b 写进 draft-6 Discussion | 加新机制违反"当前论文不加新机制"边界、合著审阅期不动结构 | 维持否决 |
| c draft-6 SI | 同 b | 维持否决 |

draft-6 至多在 Discussion 加一句不引未发表数字的前瞻（参数证据时间尺度）。

### D3 C4（九路径更稳健）声称强度

**修订裁定（2026-08-17 同日晚）：暂缓。** 用户指示：论文措辞层面的声称强度现在定为时
过早；待方法用实际数据（至少在 CAMELS 真实观测上）跑起来之后再回来定。此前"go"核准的
"现象级"撤回为暂缓，选项表保留备查。

| 选项 | 内容 |
|---|---|
| **a 现象级（推荐）** | 报告 3/180 vs 7/180 与过门差异，注明机制待查 |
| b 先做 C 尾部诊断再强声称 | 回到原方向1（约3流域×2种子带审计重跑），成本有限但需授权 |

## 四、禁止声称清单（写作红线）

1. 噪声候选辨认、完整状态精度、预报价值、真实观测同化价值：全部未测，不得声称。
2. 03D 降雨比例噪声方案在含全部受灾任务的扫描上选出——受灾任务疗效估计有乐观偏差
   （预登记已声明），叙述时必须带此声明。
3. 零概率日=0 的严格概率质量门仍未达成（P 残余17天、C 549天），不得写"完全解决"。
4. 30天增容门未过且推断为物理不可达：不得事后改门，不得删除主档。
5. multiplier=1 与降雨系数0.2依赖合成噪声已知σ；真实观测需在线噪声估计（未做）。
6. 种子仅0/1、90流域设计子集：外推到531流域全量未授权也未测。

## 五、决策后的执行路径

- D2=d（已裁定）：本线冻结结果保持不动；第二篇论文的必经前置=在线噪声估计立项
  （原方向3）；draft-6 照旧推进合著审阅与投稿。
- 在线噪声估计已立项（2026-08-17 用户"go"授权）：立项书
  `docs/plans/2026-08-17-online-noise-estimation-charter-v01.md`；阶段1（单流域试点）
  起的任何运行需再授权+跑前预登记。
- **总优先级修订（2026-08-17 用户）**：论文文本工作（D1 试稿启用、D3 措辞等）整体暂缓；
  路线优先级 = 一步一步走向实际数据应用——在线噪声估计合成验证 → **CAMELS 真实观测
  跑通**（已纳入立项书为目标终点，评价框架见其七b节）。
- D1 任一选择：判据表述模板可直接从本文 C1/C2 段落改写。
- D3=b：先出方向1实验预登记草案再跑。

## 六、证据文件索引

- 总交接：`docs/plans/HANDOFF_20260817_CAMELS_PARFC_NOISE_FIX_LINE_COMPLETE.md`
- 细节层：`docs/plans/HANDOFF_20260814_CAMELS_PARFC_PROPQ_03C_STUBBORN_SM.md`
- 03D 汇总：`results/23_camels_switch_confirmation/camels_parfc_transition_path_03d_design90_smrain_s01_20260814_local/verification/verification_summary.json`
- 03D 预登记：`docs/plans/2026-08-14-camels-parfc-transition-path-03d-design90-smrain-prereg-v01.md`
- 以上散列均于 2026-08-17 本会话实测核验一致。

## 附录A：D1 双报试稿（2026-08-17，用户要求先看后定；D2 已裁定攒作第二篇，本试稿为模板存档，不进 draft-6）

### 中文措辞（供拍板）

方法段（判据定义）：

> 事件级判据在实验执行前登记为双档：主档要求切换后30天内出现连续5天真候选后验概率
> 大于0.5（且对次高候选边距不小于0.1）；副档将窗宽放宽至90天，其余规则相同。两档均按
> 六类转移与容量增/减方向分别报告。

结果段（双报+物理解释，数字取03D）：

> 90天窗下两方法六类转移通过率全部≥0.5（完整交互法最低0.689、九路径法最低0.706；
> 总通过893与899/1080）。30天窗下减容方向通过率0.92–0.93，增容方向按转移类型仅
> 0.28–0.46，未达每类≥0.5之门，且该失败在三个噪声配置（03B/03C/03D）下一致。减容
> 切换中位响应0天，增容13–37天：容量减小当天即产生可观测的超额产流，容量增大需累积
> 足量降雨填充新增库容方能在流量中显形。据此将30天窗增容方向的未通过解释为参数信息
> 到达速度的物理下限而非估计器缺陷；在本设定下参数候选辨认是月尺度任务。

### English draft (for the eventual paper-2 manuscript)

Methods:

> Event-level identification criteria were registered prior to execution at two window
> widths: a primary 30-day window and a secondary 90-day window. An event passes if,
> within the window after a switch, the posterior probability of the true candidate
> exceeds 0.5 for five consecutive days with a margin of at least 0.1 over the runner-up.
> Results are reported separately for the six transition types and for capacity-increase
> versus capacity-decrease directions.

Results:

> Under the 90-day window, per-type pass rates exceed 0.5 for all six transition types
> under both methods (minimum 0.689 and 0.706; 893 and 899 of 1080 events passed). Under
> the 30-day window, decrease-direction pass rates reach 0.92–0.93, whereas
> increase-direction rates by transition type remain at 0.28–0.46, below the 0.5 gate — a
> failure consistent across all three noise configurations. Median response times are
> 0 days for capacity decreases and 13–37 days for increases: a reduced capacity produces
> excess runoff immediately, whereas an enlarged capacity becomes visible in discharge
> only after sufficient rainfall has filled the added storage. We therefore interpret the
> 30-day increase-direction failure as a physical lower bound on the arrival speed of
> parameter information rather than an estimator deficiency; identifying storage-capacity
> candidates is a monthly-scale task in this setting.
