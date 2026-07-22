# 独立审查报告：十五状态候选再识别时间刻画（G1 轮，candidate_likelihood_reidentification_v01）

（独立审查上下文原文存档，2026-07-21）

### 第一次

**审查方式**：全程只读。读了配置、模块、运行器、测试、全部 19 个输出文件、冻结判据源码（`candidate_likelihood_identifiability.py`）与复用的辅助函数；在 scratchpad 用独立实现（纯循环，不 import 被审模块）从六个冻结 `evidence.npz` 原始数组重算了全部数字；跑了 10 个测试（禁写缓存与字节码，未污染仓库）。

**逐项核查结果**

a) 四分类规则：配置中先冻结（`category_rules`，含互斥完备声明）。数学上验证互斥完备：`first==-1`→never_first；`first>=1 且 first_stable==-1`→first_then_lost；`first_stable>6`→stable_too_late；`first_stable∈[1,6]`→stable；非法组合（never 却 stable）显式抛错。阈值 6 = 10−5+1 与冻结判据（10 评分日、末 5 日稳定）机械自洽，且与总目标文档硬约束逐字一致。一个潜在疑点已排除：冻结 `stable_cumulative_identifiable` 比 `[1,6]` 规则多一个"末日 margin>0"条件，但冻结 rank 用 `sum(cumulative >= true)` 含自身，rank==1 即严格第一 ⇒ 末日 margin>0，条件冗余——对六个运行全部实证核过"末日 rank1 ⇒ margin>0"零反例。

b) 重算门槛：用独立循环实现对全部六个运行重算首次登顶日、首次稳定日，与冻结数组零不符；stable 类别与冻结旗标零不符；与 `integrity_checks.json` 报告的 0/0/0/0 完全一致。

c) 主导失败模式：严格最大 + 字母序并列（`tie:a+b`）+ 零失败（`no_failures`）实现忠实（`candidate_likelihood_reidentification.py:64-75`）；独立重算 18 个 (角色,场景,阶段) 的标签全部一致。六行一致性结论纯机械：parameter_switch 开发 never_first vs 确认 first_then_lost → "目前无法确定主导失败模式"（阶段 2、3 均如此）；其余四行 never_first 一致。`summary.json` 的 conclusions 与一致性表逐键相等。

d) 抽查数值：不止抽一个——18 个 stage 行的四类计数、比例、中位数、四分位、每块统计、每日排名分数全部独立重算并与 `stage_reidentification_summary.csv` / `daily_rank_summary.csv` 零误差；六个逐 trial CSV 共 1080 行逐行对 npz 核过零错。三个交接锚点全中：确认参数阶段2 stable 8/36、确认联合阶段2 stable 7/108、开发联合阶段3 stable 9/108；且 18 个 stable 计数与冻结 `scientific_evaluation.json` 的 stable_identifiable_fraction 逐一吻合。

e) 输入保护与封存：before/after 覆盖每个输入目录全部文件且前后逐哈希相等；抽样重算磁盘哈希吻合。复算脚本初次报两个"幽灵文件"，查实是检查工具自身没用 `\\?\` 扩展路径、rglob 漏掉 261/264 字符超长路径文件——被审代码恰好为此用了 `_windows_extended_length_path`，两文件真实存在且哈希与记录一致（假警报，撤回）。输出 `checksums.json` 覆盖输出目录全部文件、哈希全对；配置快照与冻结配置逐字节相同；声明的 13 类输出全在、无多余。

f) 测试：10/10 通过，覆盖手算轨迹、非法输入、四分类、并列规则、一致性判定、汇总统计、门槛失败两种腐蚀。缝隙（均轻微）：① 没测 first_stable==6 的边界（只测了 3 和 7）；② `recomputed_first_stable_day_mismatches` 门从未被腐蚀测试触发；③ 无 `run()` 集成测试（封存/拒绝覆盖）。这些缝隙已被端到端重算兜住，不影响本轮结果。

g) 报告忠实性：`final_reidentification_report.md` 六行结论、两张表、完整性清单、边界段全部机械来自规则输出，无一处超出证据的解释；全文（及 summary.json）没有任何"更长窗口能救回"类措辞，scope_limit 反而显式否认此类 claim。

h) 范围：纯只读、输入即六个冻结目录、无新种子、无 G2/G3 内容泄入，`daily_rank_summary` 为配置内声明的描述性输出。未偏离 G1，无无关扩展。

### 自评

1. **"配置先于读数冻结"实际上未验证**——查 git：整个 `src/hbv_multilead_joint_uncertainty/` 连同本轮配置均为未跟踪状态，版本历史不能证明配置时间先于分析。必须从"事实"降级为"未知（流程声明）"。缓解：阈值 6 由冻结的 10/5 判据机械导出，不是自由参数，事后调参空间极小；且结论对"never_first 占优"并不敏感于该阈值（never_first 的判定根本不用它）。不翻转总结论。
2. 复算脚本虽是独立实现，但 first/stable 日的语义定义与被审模块同源（都读自配置文字）——对照总目标文档 G1 原文"多快登顶、多快稳定登顶、三种失败模式"，配置忠实翻译，无错译。
3. margin 冗余性做了实证核查（六运行零反例）+ 数学论证（rank 定义含自身，核了 `candidate_likelihood_identifiability.py:173-175`），成立。
另补两个轻微实现瑕疵：配置声明使用 `true_candidate_cumulative_margins` 但模块从未用它；配置说不符时"status deferred"但实现只是抛异常、不落 deferred 状态。

### 最终

**事实**：六运行首次登顶日/首次稳定日重算零不符；stable 类别与冻结旗标零不符；1080 行 trial 表、18 行 stage 表、180 行 daily 表零误差；三个锚点及 18 个冻结稳定比例全吻合；主导标签与六行结论纯机械推出；输入 before/after 哈希完整一致（含超长路径文件）；输出封存完整；10/10 测试通过；报告无超证据解释。
**推断**：四分类互斥完备；margin 条件在 rank 定义下冗余，`[1,6]` 规则与冻结旗标数学等价。
**未知**：配置"先冻结后读数"的时间先后无法由版本历史证明（整个模块目录未入 git），仅能依赖 checksums 链与流程声明。

**问题清单**（无严重、无重要，仅轻微）：
1. [轻微] 整个 `src/hbv_multilead_joint_uncertainty/`（含本轮及此前冻结轮代码、配置）未提交 git，"预冻结"不可由版本历史佐证；建议尽快提交以固化时间线。
2. [轻微] 配置 `evidence_keys_used` 列了 `true_candidate_cumulative_margins`，模块通篇未使用该数组——死输入，仅虚增预检内存估计。
3. [轻微] 配置 `input_integrity_rule` 称不符时"stops with status deferred"，实现只是中止、不写任何 deferred 状态工件；行为安全但措辞不符。
4. [轻微] `partition_violations` 门恒为 0（`classify_reidentification` 只能输出四标签之一或抛错），是同义反复检查，无信息量。
5. [轻微] 测试缝隙：first_stable==6 边界未测；first_stable 重算门未被腐蚀测试触发；`run()` 无集成测试。均已被本次端到端复算兜底。
6. [说明] 失败中途 `.incomplete` 目录会残留并阻塞重跑（需手工清理）——沿用前几轮封存模式，非缺陷。

**结论：通过。** 四分类规则先冻结、完备互斥且与冻结判据自洽；全部数字可从冻结 evidence.npz 独立零误差复算；六行结论由规则机械推出；输入保护与封存完整；报告无超出证据的声称；未偏离 G1。六条轻微问题均不改变结论，其中第 1 条（入 git）建议下一轮前处理。
