# 统一自动研究系统第三里程碑完成态任务交接摘要

生成日期：2026-07-20

## 1. 整体最终目标和当前阶段

整体最终目标是在公平基准的同等预测信息约束下，建立能够自主提出、执行、登记、复验和筛选候选方法的统一自动研究系统。最终科学胜出只能由正式评分服务和独立审核确认；当前阶段不具备执行该步骤的授权。

第三里程碑目标已经完成：仅使用 8 个冻结开发流域、Maurer 气象驱动结构和 1999-10-01 至 2008-09-30 的两套开发协议，建立隔离数据包、外部开发验证评分、四类轻量参考候选、受控中断恢复、干净重跑、不可覆盖登记与数字指纹，以及恰好 32 个有限开发结果单元的完整闭环。两个无实现历史的独立上下文分别给出 `PASS` 和 `CONFIRMED_PASS`。

当前没有第三里程碑内的阻塞。下一阶段尚未形成经过审核的具体科学候选目标；允许的最小下一步是在同一受限开发环境中选择一个可独立检验的新候选问题，先定义成功标准，再按失败测试、实现、不可覆盖证据、独立方法审核、独立原始证据复验的顺序推进。

## 2. 必须遵守的限制、成功标准和停止条件

- 工作目录固定为 `G:\github\pycharm\projects\neuralhydrology\.worktrees\unified-autoresearch-vertical`，分支为 `codex/unified-autoresearch-vertical`。
- 不得读取、寻找、枚举或评分 1989-10-01 至 1999-09-30 的封存最终评估数据。
- 不得运行 `src/fair_benchmark/score.py`，不得执行 64 或 531 个流域的正式搜索，不得宣称任何候选超过基线。
- 当前已审核数据只是假数据生成的预切分开发数据，不是真实 Maurer 数据；任何数值都不能解释为真实水文性能。
- 候选预测只能使用气象驱动和静态属性，不得挂载或读取观测流量、开发验证真值或最终评估真值。
- 不得清理、重置、覆盖、暂存或提交用户修改。当前 `src/unified_autoresearch/` 整体未跟踪；必须原样保护，除非后续任务明确授权相应 Git 操作。
- 修改可执行行为前必须先保存能够复现问题的失败测试。失败证据根永久保留，新一轮必须使用新的不可覆盖根。
- 每轮成功标准是：目标反例通过、相关完整测试通过、真实调度锁和外部登记凭据闭合、Git 差异与状态原始字节进入指纹、只读干净快照与根散列一致、第一层独立审核通过、第二层不读取第一层结论而从原始证据确认通过。
- 任一独立审核失败时停止准入，保存失败证据，只在下一轮修复已确认问题；未经验证的问题记录后不继续扩展。
- 计算资源不设统一内存门槛。执行前按实际任务规模确认可用内存有安全余量；不足时减少并行数量或任务规模。只有实际任务需要时才启用相称的独立资源监督，轻量串行测试不强制套用固定监督方案。
- 第三里程碑停止条件已经达到。它只授权受限开发环境内的新候选研究，不授权真实数据、最终评估或正式评分。

## 3. 已完成方案、关键结果和有效结论

### 当前有效的最终证据

- 源 Git 提交：`ffbde6d9091df08363ff5b7ab0492bdd02873c42`。
- 第三里程碑第十二轮外层根：`27273db6b786e48356cb2fc72adb0aaee37971a6a51951b35e58d76263fb905a`。
- 冻结开发数据包清单散列：`821154026057e806e547d8ccd901e4a878dedbf38c1ab7a0e75eb56c50ac0114`。
- 证据包清单散列：`94395f7ec9ee412c29860bdab72965b300710b5fd291fffb518a85cf8b7d8194`。
- 冻结测试：157 项中 156 项通过、1 项因当前 Windows 账户不能创建符号链接而跳过、0 项失败、0 项错误。
- 完整循环：4 类候选、2 套开发协议、16 个已登记训练或预测运行、8 份外部评分报告、4 份候选汇总、32 个唯一有限“候选类别—流域”结果单元。
- 每个运行有 8 条登记、8 份外部凭据和 9 份日志；合计 128 条登记、128 份凭据、144 份日志。
- 19,512 条候选访问事件中禁止路径命中和越界事件均为 0。
- 循环目录有 493 个物理文件，等于 492 项预汇总清单加 `LOOP_SUMMARY.json`；长路径复验无遗漏。
- 第二层审核从原始预测和开发真值重新计算 64 个协议—流域纳什效率值及 32 组正向、反向、均值，最大绝对差为 0。
- 全新 Git 仓库完整重跑再次得到 4 类候选、16 个运行、8 份评分和 32 个结果单元；重复输出根由 `FileExistsError` 拒绝，原字节不变。
- 当轮运行前实际可用内存为 2.99 吉字节；候选串行运行，每次声明峰值内存加安全余量为 0.60 吉字节，未发生内存崩溃。这只是该轻量任务的实测，不是统一门槛。

### 恢复闭环的有效证据

- 第十一轮恢复证据根：`bfc9d799e008bfcb35dbffb011b3e0a6a8c82a4b1ace8a6849d8a76230f5abd1`。
- 检查点根：`06a4c8e0684a906d3288c34edc0eac1be5da7a4d98ea2b0a5e86b9630adfeed6`。
- 恢复模型与干净重跑模型的原始字节散列均为 `7bb0dca0335bcf387f46799f6d9e8b6d4ce0345a87ca7708797d0a2f47cb2e64`。
- 中断、恢复、干净三个运行各有 8 条登记、8 份凭据和 9 份日志；297 至 299 字符的检查点路径及最长 362 字符的归档路径均通过复验。

### 可复现性分类

第三里程碑开发闭环的状态为 `reproducible`：代码、协议、合成输入、运行、模型产物、预测、评分、日志、检查点、登记链、外部凭据、数字指纹和只读快照均已绑定；两个新上下文都完成了全新仓库复验。

## 4. 当前代码、配置、模型、日志和结果的准确路径

### 核心代码

- 完整循环：`G:\github\pycharm\projects\neuralhydrology\.worktrees\unified-autoresearch-vertical\src\unified_autoresearch\workflow\development_loop.py`
- 中断恢复：`G:\github\pycharm\projects\neuralhydrology\.worktrees\unified-autoresearch-vertical\src\unified_autoresearch\workflow\recovery.py`
- 开发数据包：`G:\github\pycharm\projects\neuralhydrology\.worktrees\unified-autoresearch-vertical\src\unified_autoresearch\data\packages.py`
- 外部开发评分：`G:\github\pycharm\projects\neuralhydrology\.worktrees\unified-autoresearch-vertical\src\unified_autoresearch\evaluation\scoring.py`
- 候选目录与四类实现：`G:\github\pycharm\projects\neuralhydrology\.worktrees\unified-autoresearch-vertical\src\unified_autoresearch\candidates\`
- 受限运行编排：`G:\github\pycharm\projects\neuralhydrology\.worktrees\unified-autoresearch-vertical\src\unified_autoresearch\runtime\orchestrator.py`
- 运行时访问边界：`G:\github\pycharm\projects\neuralhydrology\.worktrees\unified-autoresearch-vertical\src\unified_autoresearch\runtime\bootstrap.py`
- 检查点：`G:\github\pycharm\projects\neuralhydrology\.worktrees\unified-autoresearch-vertical\src\unified_autoresearch\runtime\checkpoints.py`
- 登记存储：`G:\github\pycharm\projects\neuralhydrology\.worktrees\unified-autoresearch-vertical\src\unified_autoresearch\registry\store.py`
- 调度锁：`G:\github\pycharm\projects\neuralhydrology\.worktrees\unified-autoresearch-vertical\src\unified_autoresearch\registry\scheduler_lock.py`
- 数字指纹：`G:\github\pycharm\projects\neuralhydrology\.worktrees\unified-autoresearch-vertical\src\unified_autoresearch\registry\fingerprint.py`
- 外层证据包：`G:\github\pycharm\projects\neuralhydrology\.worktrees\unified-autoresearch-vertical\src\unified_autoresearch\evidence_package.py`

### 冻结协议和配置

- 开发协议：`G:\github\pycharm\projects\neuralhydrology\.worktrees\unified-autoresearch-vertical\src\unified_autoresearch\protocols\development_v1.json`
- 候选契约：`G:\github\pycharm\projects\neuralhydrology\.worktrees\unified-autoresearch-vertical\src\unified_autoresearch\protocols\candidate_contract_v1.json`
- 当前资源安全协议：`G:\github\pycharm\projects\neuralhydrology\.worktrees\unified-autoresearch-vertical\src\unified_autoresearch\protocols\resource_safety_v2.json`
- 冻结开发流域：`G:\github\pycharm\projects\neuralhydrology\.worktrees\unified-autoresearch-vertical\src\unified_autoresearch\selection\development_basins_v1.json`
- 第三里程碑设计：`G:\github\pycharm\projects\neuralhydrology\.worktrees\unified-autoresearch-vertical\src\unified_autoresearch\docs\2026-07-19-milestone3-development-loop-design.md`

### 当前有效的运行、模型、日志和评分产物

- 合成源：`G:\github\pycharm\projects\neuralhydrology\.worktrees\unified-autoresearch-vertical\runs\unified_autoresearch\milestone3_round12_synthetic_source`
- 开发数据包：`G:\github\pycharm\projects\neuralhydrology\.worktrees\unified-autoresearch-vertical\runs\unified_autoresearch\milestone3_round12_development_packages`
- 完整循环根：`G:\github\pycharm\projects\neuralhydrology\.worktrees\unified-autoresearch-vertical\runs\unified_autoresearch\milestone3_round12_full_development_loop`
- 循环汇总：`G:\github\pycharm\projects\neuralhydrology\.worktrees\unified-autoresearch-vertical\runs\unified_autoresearch\milestone3_round12_full_development_loop\LOOP_SUMMARY.json`
- 四类候选模型、预测、访问日志、资源预检、运行策略、登记数据库和凭据都位于完整循环根的 `runs\<候选类别>\<forward或reverse>\<train或predict>\` 下。
- 八份评分位于完整循环根的 `scores\<候选类别>\<forward或reverse>.json`。
- 四份候选汇总位于完整循环根的 `summaries\<候选类别>.json`。
- 外层证据根：`G:\github\pycharm\projects\neuralhydrology\.worktrees\unified-autoresearch-vertical\runs\unified_autoresearch\milestone3_round12_full_loop`
- 只读干净快照：`G:\github\pycharm\projects\neuralhydrology\.worktrees\unified-autoresearch-vertical\runs\unified_autoresearch_audits\milestone3_round12_full_loop_27273db6b786e483_clean`

### 当前有效的审核和进度文件

- 总进度：`G:\github\pycharm\projects\neuralhydrology\.worktrees\unified-autoresearch-vertical\src\unified_autoresearch\evidence\PROGRESS.md`
- 第十二轮独立审核：`G:\github\pycharm\projects\neuralhydrology\.worktrees\unified-autoresearch-vertical\src\unified_autoresearch\evidence\audits\milestone3_round12_full_loop_review.md`
- 第十二轮原始证据复验：`G:\github\pycharm\projects\neuralhydrology\.worktrees\unified-autoresearch-vertical\src\unified_autoresearch\evidence\audits\milestone3_round12_full_loop_raw_verification.md`
- 第十一轮恢复审核：`G:\github\pycharm\projects\neuralhydrology\.worktrees\unified-autoresearch-vertical\src\unified_autoresearch\evidence\audits\milestone3_round11_recovery_review.md`
- 第十一轮恢复原始复验：`G:\github\pycharm\projects\neuralhydrology\.worktrees\unified-autoresearch-vertical\src\unified_autoresearch\evidence\audits\milestone3_round11_recovery_raw_verification.md`

本交接文件在第十二轮证据封存和审核完成后创建，因此不属于根 `27273db6b786e48356cb2fc72adb0aaee37971a6a51951b35e58d76263fb905a`。审核该根时必须使用只读快照，不能拿创建本文件后的活动工作区状态与封存的 8,420 字节 Git 状态原始文件直接比较。

## 5. 已确认的问题、已排除的问题和证据

### 会影响后续实现的历史失败及修复

- 第三轮外部评分曾允许数据包清单自我授权、评分身份未完全绑定、双协议不要求同源，并可能因有限极端值相加溢出留下部分文件。第四轮修复后双重独立审核通过。证据见 `src\unified_autoresearch\evidence\audits\milestone3_round3_scoring_review.md`、`milestone3_round3_scoring_raw_verification.md`、`milestone3_round4_scoring_review.md` 和 `milestone3_round4_scoring_raw_verification.md`。
- 第五轮候选运行曾在访问记录和限制启用前导入依赖；随后又确认标准库父目录会隐式授权整个 `site-packages`。第六轮修复初始化顺序，第八轮把读取范围收紧到声明依赖及实际初始化闭包，双重独立审核通过。证据见第五、六、八轮候选审核文件。
- 第六、九、十轮先后确认普通 Windows 路径处理会漏读或漏枚举 260 字符以上的候选、检查点、外部凭据和快照文件。第七轮修复候选物化，第十一轮完成检查点、指纹、恢复汇总和外层快照的扩展长度路径闭包，双重独立审核通过。
- 第九轮指纹曾引用快照不存在的历史 `PROGRESS.md` 字节。修复后每个运行排他保存当时的 Git 差异与状态原始字节，并只登记显式代码、配置、依赖和数据范围内的未跟踪文件；第十一轮确认三个恢复运行的未跟踪范围均为 0。

### 已排除或明确限定

- 已排除候选读取封存最终评估、评分真值或禁止路径：第十二轮 19,512 条访问事件中相关命中为 0。
- 已排除执行公平基准评分和正式流域搜索：外层 `RUN_METADATA.json` 与循环 `LOOP_SUMMARY.json` 中对应标志均为 `false`。
- 已排除登记链、调度锁和凭据缺失：外层与 16 个内层运行均逐项复验。
- 已排除长路径静默遗漏：两个独立上下文使用扩展长度路径重新枚举，并在全新仓库重跑。
- 已排除评分汇总错误：第二层从原始表重算的最大绝对差为 0。
- 已排除覆盖已有输出：重复根触发 `FileExistsError`，原文件数量和散列不变。
- Windows 符号链接测试因当前账户权限跳过 1 项。这不是当前阶段阻塞，因为源和产物还接受独立的非链接文件检查；若以后修改链接处理，必须在能创建符号链接的环境补做该测试。
- 合成概念降雨径流候选出现的满分只是合成构造结果，不能用于候选排序、真实性能推断或基线比较。

## 6. 未完成事项、阻塞原因和最高优先级下一步

- 第三里程碑没有未完成事项，也没有当前阻塞。
- 尚无经过审核的第四里程碑目标。最高优先级是围绕一个新候选提出边界清晰、可独立证伪的受限开发问题，不扩大到真实最终评估或正式搜索。
- 真实开发数据准入仍未完成。当前只有合成预切分数据；在使用任何真实文件之前，必须先独立证明其专用数据根只包含允许日期、允许字段和 8 个冻结开发流域，并且从未打开包含封存期的完整历史文件。缺少该证明时必须停止真实数据工作。
- 当前实现未暂存、未提交，整个 `src/unified_autoresearch/` 是用户工作区中的未跟踪目录。是否提交或集成需要用户明确授权；在此之前不得擅自操作。

## 7. 新对话开始后首先检查的文件和命令

在 PowerShell 中执行：

```powershell
Set-Location 'G:\github\pycharm\projects\neuralhydrology\.worktrees\unified-autoresearch-vertical'
git status --short --branch
git rev-parse HEAD
python -m pytest src/unified_autoresearch/tests -q
Get-Content -LiteralPath 'src/unified_autoresearch/evidence/HANDOFF_20260720_MILESTONE3_COMPLETE.md' -Raw
Get-Content -LiteralPath 'src/unified_autoresearch/evidence/PROGRESS.md' -Tail 40
Get-Content -LiteralPath 'src/unified_autoresearch/evidence/audits/milestone3_round12_full_loop_review.md' -Raw
Get-Content -LiteralPath 'src/unified_autoresearch/evidence/audits/milestone3_round12_full_loop_raw_verification.md' -Raw
Get-Content -LiteralPath 'runs/unified_autoresearch/milestone3_round12_full_loop/RUN_METADATA.json' -Raw
Get-Content -LiteralPath 'runs/unified_autoresearch_audits/milestone3_round12_full_loop_27273db6b786e483_clean/SNAPSHOT.json' -Raw
```

如果需要单独重跑完整 32 单元闭环测试，执行：

```powershell
python -m pytest 'src/unified_autoresearch/tests/test_development_recovery.py::test_full_development_loop_produces_exactly_32_finite_registered_cells' -q
```

应首先核对的实现文件是：

```text
src/unified_autoresearch/registry/store.py
src/unified_autoresearch/registry/scheduler_lock.py
src/unified_autoresearch/registry/fingerprint.py
src/unified_autoresearch/runtime/orchestrator.py
src/unified_autoresearch/runtime/bootstrap.py
src/unified_autoresearch/runtime/checkpoints.py
src/unified_autoresearch/workflow/recovery.py
src/unified_autoresearch/workflow/development_loop.py
```

PowerShell 启动时出现的空命令 Conda 参数错误是本机启动脚本噪声；判断命令是否成功必须看实际退出码和有效输出。

## 可直接粘贴到新对话的下一轮任务提示词

```text
对话名称：统一自动研究系统—第四里程碑受限候选迭代

请继续统一自动研究系统任务。唯一工作目录为：
G:\github\pycharm\projects\neuralhydrology\.worktrees\unified-autoresearch-vertical

先完整读取：
G:\github\pycharm\projects\neuralhydrology\.worktrees\unified-autoresearch-vertical\src\unified_autoresearch\evidence\HANDOFF_20260720_MILESTONE3_COMPLETE.md

以实际隔离工作区状态、只读快照和原始证据为准，不依赖未验证的历史描述。首先执行交接文档第 7 节的检查命令。第三里程碑已经完成并由两个独立上下文确认通过；不要重复修复已关闭问题，也不要把旧的失败证据根当成当前状态。

请先独立判断第四里程碑的可行范围和检验方式，然后围绕一个关键且可独立证伪的新候选问题自主推进。每次修改可执行行为前先保存失败测试；每轮使用新的不可覆盖证据根，并由没有实现历史的独立上下文完成方法审核，再由另一个不读取前一审核结论的独立上下文从原始证据复验。只有两者都通过才准入下一阶段。

必须继续遵守：不得读取、寻找或评分 1989-10-01 至 1999-09-30 封存最终评估数据；不得运行 src/fair_benchmark/score.py；不得执行 64 或 531 流域正式搜索；不得宣称超过基线；不得清理、重置、覆盖、暂存或提交用户修改。当前只允许气象驱动和静态属性，现有结果只来自 8 个冻结流域的合成预切分开发数据。真实开发数据必须先取得独立的预切分边界证明。

计算资源不设统一内存门槛。根据实际任务规模确认可用内存有安全余量；不足时降低并行数量或任务规模。除非遇到必须由用户决定的授权问题，否则自主推进，只在完成完整阶段结论或出现真实阻塞时报告。
```
