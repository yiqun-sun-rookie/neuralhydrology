# ID07 Goal: 可辨识性闸门方法论文（identifiability gate）

**立项**: 2026-08-01（用户指令"全部做 + 制定 1 个计划 1 个 goal"）
**状态**: Stage 0 ✅ / Stage 1 ✅ / Stage 2 🔄 **批量运行中** (2026-08-01 启动, 脱离会话 pid 38568, 日志 `screen_v03_mini/batch_log.txt`) / Stage 3 阈值已预注册 ✅（worktree `docs/plans/2026-08-01-id07-gate-preregistration.md`, 先于数据提交）

## Goal（唯一目标）

产出一篇方法论文的完整证据链：**AI/自动化搜索水文模型结构时，必须先通过"可辨识性检查"（结构能否被数据唯一钉住）才能宣称"发现"；不加这道闸门，发现不可信。**

大白话：给"AI 自动搭水文模型"装一道防自欺的体检关卡，用我们自己的两组失败当"不体检会出事"的证据。

## 验收标准（论文级证据三件套，全部需独立复核）

1. **Before（无闸门会失败）**: 两条线的负结果定量化——纯概念线留出崩（已有，双重验证过）+ 混合线结构跨种子不复现/并列第一成堆（Stage 1 产出）。
2. **Gate（闸门可执行）**: 预注册的闸门定义（阈值先写死再看数据）：①跨种子结构一致性 ②合成"埋答案"恢复测试 ③近并列冠军计数。
3. **After（闸门在干净实验上工作）**: 修复后的小规模干净重跑上，闸门正确拦截不可辨识的"发现"、放行可辨识的（若有）。

**Pivot 条件**: 若 Stage 2 干净重跑意外显示结构高度可复现且有竞争力（<20% 分支），闸门故事削弱 → 停下重估（那本身是另一种值得报的正结果）。

## 硬边界（继承 + 新增）

- 旧 screen_v02 结果目录**只读冻结**；密封十年 1989-1999 流量仅留给最终一次性确认，前置披露 reverse 暖机曾用其最后一年气象输入。
- 大计算前查内存余量（上次批量死于 395MB < 609MB 保留线）；重跑串行、带资源守卫。
- 不碰 `src/fair_benchmark` 密封评估。

## Stages

### Stage 0: 审计 + 修复 + 留痕 — ✅ 完成 (2026-08-01)
- 双独立审计（机械真/科学作废）；PET≡0 bug 修复（同 repro_v01 的 PT 实现 + 退化保险丝）；A/B 量化 +0.41/+0.19 NSE；250 测试绿；worktree commit `54874c40`，主仓 `7a363056`。

### Stage 1: 免费 Before 证据固化（零训练，读盘统计）— ✅ 完成 (2026-08-01)
- **做**: 对 screen_v02 的 11 个完成单元：①逐 (河×方向×家族) 跨种子选中结构一致性表；②候选池"近并列冠军"计数（选择分距冠军 ≤0.01 的不同结构数）。
- **产出**: worktree `results/07_hydroagent/cd/identifiability_gate_stage1/`（表 + 汇总 + 复算说明）。
- **结果**: ①两个搜索家族在 4 个 (河×方向) 组里**零组做到 3 种子同结构**（genetic 3/3/3/2、agent 3/2/2/2），不搜索的 fixed 对照臂 4/4 全一致 → 不稳定性来自搜索本身；②单池近并列中位=1 → 单次运行冠军看似唯一是假象，**闸门必须含跨种子重搜，单池并列计数不够**（此发现修正了闸门草案的权重）。
- **注意**: 此层证据带"PET bug 时代"标签——只能说"当时的搜索不可复现"，机制级结论等 Stage 2。

### Stage 2: 干净小重跑（screen_v03-mini, 12 单元）
- **做**: 修复后管线 + 基线对称化（混合家族获得与 LSTM 相同的训练配方: NSE loss + LR 调度 + 梯度裁剪；预算摊薄问题至少显式披露，可加"LSTM 也走 16 候选选择"对照），跑原 2 河 × 2 方向 × 3 种子。
- **前置**: TDD 改 training/experiment 配方注入点；内存余量 ≥3GB 才开跑；串行。
- **成功标准**: 12/12 单元完成、报告里 ep 均值 >0.5 mm/d、数据哈希 != 污染版。
- **Kill-gate**: 任一单元因资源死 → 停，修资源再续，不硬闯。

### Stage 3: 闸门预注册 + 应用
- **做**: 先写死阈值（草案: 跨种子 ≥2/3 同构过、埋答案恢复率 ≥K、近并列 ≤2）成 spec 提交 git，然后一次性应用到 Stage 2 输出。合成"埋答案"测试复用放置探针经验（scratchpad probes 系统化）。
- **成功标准**: 闸门判定与人工核查一致；无事后改阈值。

### Stage 4: 论文骨架
- **做**: 文献碰撞检查（闸门框架 vs 已有 equifinality/model selection 文献，防"新瓶装旧酒"被拒）→ WRR/HESS 方法文骨架（story: before-gate-after），负结果全部入弹药。
- **成功标准**: 骨架过 wrr-paper-review 独立审稿无 blocker。

#### Stage 4 文献碰撞检查结果 — ❌ **原框架判死** (2026-08-03，提前于 Stage 2 完成执行)

约 48 次检索 + 4 条最伤证据经**原始出处逐字复核**（Wiley 正文 402 付费墙，用 Semantic Scholar 官方摘要 / HydroShare / Copernicus 摘要页核）：

| 撞车对象 | 已发表的内容（逐字） | 撞掉我们的哪一条 | 核实状态 |
|---|---|---|---|
| **Spieler, Mai, Craig, Tolson & Schütze (2020), WRR 56:e2019WR027009** | "We demonstrate the feasibility of the approach by **reidentifying given model structures that produced a specific hydrograph**" ；"**The variance in the identified structures is high due to near equivalent diagnostic measures for multiple model structures, reflecting substantial model equifinality.**" | 判据②（近并列）的现象与成因 + 判据③（合成埋答案）——**在自动模型结构搜索场景下、WRR、2020 年** | 摘要逐字确认 |
| **Spieler & Schütze (2024), WRR 60:e2023WR036199**（Gold OA） | 每流域 **100 次 AMSI 运行**，HydroShare 公开"all 100 AMSI models for each of the 12 catchments … as well as the **identified structural choices** for every model" | 判据①（跨种子重搜）的原始数据已公开；**但正文是否计算过"结构一致率"未能核实**（付费墙，HydroShare 描述未提） | 数据描述确认；正文未核 |
| **Prieto, Kavetski, Le Vine, Álvarez & Medina (2021), WRR 57:e2020WR028338** | "a test statistic that defines a '**dominant**' mechanism as a mechanism more probable than all its alternatives given observed data"；bootstrap 定不确定性；"As data/model errors increase, **statistical power (identifiability) decreases, manifesting as trials where no mechanism is identified as dominant**." | **正规范式的最强撞车**：水文里已有可执行的结构机制可辨识性通过/不通过检验，且"认不出"是合法输出 | 摘要逐字确认 |
| **Schultze, Eythorsson, Clark & Klaus (2026), EGU26-8123**（Bonn + Calgary，Martyn Clark 组） | LLM "**demonstrated inconsistency by recommending different model components across repeated identical prompts**"；"commonly did not recommend the top-performing structures" | 直接抢我们"LLM 提出的结构跨次不复现"这条 Before 观察 | 摘要逐字确认 |

其余高伤但未逐字核：Meinshausen & Bühlmann (2010) stability selection（判据①的正确统计版，带错误率控制）；Knoben et al. (2025) HESS 29:2361（用抽样不确定性量化近并列 → **我们预注册的 0.01 边界大概率过松**）；Beven (2018) WIREs Water 5:e1278（limits of acceptability = 先定阈值再跑，水文里的"预注册"先例）；D'Amour et al. (2022) JMLR underspecification；Kuskova et al. (2026) arXiv:2606.08390（两种子一致性当作 operational discovery gate，同一逻辑异领域）；McCormick (2026) arXiv:2606.02632（LLM 把等价类塌成单一叙事）。

**判定**：**「我们提出可辨识性闸门」这个框架不能写**。它 = 实践不可辨识性 + stability selection + 结构等效性 的改名，且水文内已有 Prieto 2021 的可执行版本。

**仍未被占的窄缝（按可行性排序）**：
1. **门槛校准**（干净、无人做）：把近并列边界锚到效率指标的抽样不确定性（Knoben 2025 的机器 + Prieto 2021 的 bootstrap 统计量），再回溯检验已发表的自动归纳结果有多少能活下来。0.01 从软肋变成研究对象。
2. **负结果/警示短文**：我们两条线的失败 + **"弃搜索式一致"**（agent 靠塌回基线换一致 —— 与 Schultze 的"不一致"正好是相反的失败模式，检索中未见先例）。必须快，Clark 组在前面。
3. **审计已发表方法**（最强但最贵）：Chadalawada et al. (2020) WRR 与 Herath et al. (2021) HESS 跑了多次独立 GP 搜索并声称"equifinality handled satisfactorily"却**未公布结构一致性统计**——复现并证伪这条未挣得的声明。代价 = 重实现别人的工具箱。

**必引清单**（漏引即被认定不懂本领域）：Spieler 2020/2024；Prieto 2021；Beven 2006 J.Hydrol. 320:18 + Beven 2018；Knoben 2020 WRR/2025 HESS；Clark 2008 FUSE；Fenicia & Kavetski 2011 SUPERFLEX（两篇）；Clark, Kavetski & Fenicia 2011 多重工作假说；Knoben 2019 MARRMoT；Chadalawada 2020；Herath 2021；Meinshausen & Bühlmann 2010；Nogueira 2018 JMLR；Fasel 2022 / Maddu 2022；D'Amour 2022；Yu 2020 ICLR NAS 复现性；Semenova & Rudin 2022 Rashomon；Guimerà 2020 Sci.Adv.；Eythorsson & Clark 2025 HP 39:e70065；Khatami 2019 WRR；Schultze 2026 EGU；McCormick 2026；Kuskova 2026；Pilz 2020 WRR。

**⭐ 遗留待核已办结（2026-08-03，同日）**：绕开 Wiley 从 TU Dresden 机构库取到 **Spieler 博士论文全文 184 页**（qucosa:92573，含 2020 与 2024 两篇的完整章节）。结果**比上表更糟——闸门三件套全部已发表，且含同一个数字**：

| 我们的判据 | Spieler 已发表的对应物（逐字） | 位置 |
|---|---|---|
| ① 跨种子结构一致 | "it thus identifies **between 27 (EG) and 68 (SM) unique model structures**"（每流域 100 次运行的唯一结构数）；图 4.10 标题含 "**consistency information** of the identified best validation model for each catchment" | 论文 p101 / 图 4.10 |
| ② 近并列 ≤ 阈值 | Table 5.3 **Equifinality Levels：EQF-LV1 ΔKGE = 0.010**（另 0.025 / 0.05），理由 "We believe that if given the choice between different models, a difference of 0.1 in KGE would cause most modellers to clearly favour the other model" | 论文 p97 |
| ③ 合成埋答案恢复 | "Graphs show **how many out of 100 AMSI runs identified the true model structure**"，20 个合成目标 × 5 种计算预算 | 图 4.5/4.6/4.8 |

**我们预注册的近并列边界 0.01 与其 EQF-LV1 逐字相同。** 判据①不是"被预示"而是"已有逐流域统计量"。原框架**确定性判死**，不留余地。

**连带影响**：窄缝 (1)"门槛校准"比初判**更窄**——0.01 已被 Spieler 选用并给了理由，剩下的空白只是"把边界锚到指标的抽样不确定性（Knoben 2025）而非专家判断"。窄缝 (2)(3) 不受影响。

**仍未核**：Prieto 2021 正文阈值是否事前指定；Chadalawada 2020 正文是否有种子一致性统计（Herath 2021 HESS 正文已确认没有）。

## 决策日志
- 2026-08-01: 用户拍板"全部做"（提交留痕 + 基线对称化重跑 + 闸门论文主线）。
