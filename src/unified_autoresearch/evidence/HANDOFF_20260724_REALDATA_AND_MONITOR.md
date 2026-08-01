# 交接：真实数据接通与资源监督走通（2026-07-24）

本文件用于在新对话中无缝续接。读完本文件加 `PROGRESS.md` 末尾两条即可继续工作，不需要旧对话记录。

---

## 一、环境与仓库状态

- 工作目录：`G:\github\pycharm\projects\neuralhydrology\.worktrees\unified-autoresearch-vertical`
- 分支：`codex/unified-autoresearch-vertical`，HEAD `ffbde6d`
- `git status` 只有一项：`?? src/unified_autoresearch/`（**整个目录未跟踪**）
- 本次全部改动**未暂存、未提交**。是否提交需用户明确授权。
- 原始档案在主仓库：`G:\github\pycharm\projects\neuralhydrology\data\camels_us`（本工作树内**没有** `data/`，脚本必须显式传 `--camels-root`）
- 机器：32 逻辑核心，内存 31.7 吉字节（运行时可用约 6.6～7.1），可用磁盘约 2158 吉字节
- 本机**可以创建软链接**（旧审核机器不能，这一点造成过漏检，见第四节）

## 二、仍然生效的硬约束（逐条照抄，不得放宽）

- 不得读取、寻找、枚举或评分 1989-10-01 至 1999-09-30 的封存最终评估数据。
- 不得运行 `src/fair_benchmark/score.py`，不得执行 64 或 531 个流域的正式搜索，不得宣称任何候选超过基线。
- 候选预测只能使用气象驱动和静态属性，不得挂载或读取观测流量、开发验证真值或最终评估真值。
- 不得清理、重置、覆盖、暂存或提交用户修改。
- 计算资源不设统一内存门槛；执行前按实际任务规模确认可用内存有安全余量。
- 结果需由一个独立上下文审核、再由第二个独立上下文从原始证据复验；确认的问题下一轮修，未复验的记录并放下。
- 回答去掉过程性叙述，末尾必须有结论段；禁止未解释的缩写、代号和自造词。

## 三、里程碑状态（关键：**没有全部完成**）

| 里程碑 | 状态 |
|---|---|
| 零、一、二、三 | 完成，且过了双重独立复核 |
| 四 | **未完成**，六条中完成一条半，见下表 |
| 最终审核 | 未开始 |

里程碑四逐条：

| # | 内容 | 状态 |
|---|---|---|
| 1 | 冻结代表性资源小试验和峰值估算方法 | ❌ 只有一个实测标定点 |
| 2 | 峰值/余量/实际容量/监督决定/进程归属/受控退出的失败测试 | 🟡 归属、受控退出、越限已覆盖；估算方法未冻结故不算完 |
| 3 | 独立监督进程 + 原子资源日志 | ✅ 完成 |
| 4 | 连续两次完整纵向运行 + 五项门槛 | 🟡 两次连跑已做、五项门槛全过、逐字节一致，但**监督是关的**；开监督只跑了 1 类 × 1 协议 |
| 5 | 扩至 64 与 531 流域前的时间、存储、并行、数据准备剩余清单 | ❌ 未做 |
| 6 | 两个独立上下文的审核与定向复验 | ❌ 未做 |

## 四、本次会话做了什么

### 4.1 真实数据接通（台阶 A，已完成）

- 新增 `data/real_source.py`：**唯一被授权打开原始档案的组件**。落盘前先切开发窗口，对封存区间显式硬拒。
- 新增三个脚本（见第六节命令）。
- 新增 `tests/test_real_source_root.py`：9 项契约测试，先失败后实现。
- 观测流量换算沿用既有约定：`28316846.592 × 流量(立方英尺每秒) × 86400 ÷ (面积平方米 × 10^6)`，面积取气象文件第 3 行。
- 静态属性来自与冻结流域选择**同一张表**，散列钉死
  `085e8b5e0e56b42bfe7e6d012ebb6f2f56681059b60c61c04b835b207864a1f2`
  （`src/fair_benchmark/frozen/bundle/track0_statics.csv`）；8 个流域 27 项属性无缺失。
- 8 个冻结开发流域：`10259000 04045500 12175500 02300700 08190500 02038850 11230500 06847900`

### 4.2 修掉两轮审核都漏掉的真实安全缺口

旧审核机器建不了软链接，冻结测试里的软链接反向测试被跳过，掩盖了五处问题：

1. `runtime/layout.py` 在链接检查**之前**调用 `Path.resolve()`，`is_symlink()` 恒为假 →
   声明输入文件、声明输入目录、候选源根三种软链接被静默跟随到隔离区之外。
2. `evaluation/scoring.py` 对候选预测文件和评分报告的软链接检查同样在 `resolve()` 之后，属**失效代码** →
   候选可用软链接把“自己的输出”指向任意外部文件。

修法：在 `resolve()` 抹除链接属性之前检验给定路径（`_unlinked_path` / `_is_symbolic_link`）。硬链接检查未改动。
新增 4 项失败测试驱动。冻结测试由 **156 通过 1 跳过** 变为全通过。

### 4.3 里程碑四第 3 条：独立资源监督（已完成）

新增 `runtime/monitor.py`：

- `verify_process_ownership`：进程号、创建时间、可执行文件路径、运行标识**四项全对**才承认归属。
- `evaluate_stop_reason`：磁盘低于停写下限**立即**触发；系统内存需**连续两次**低于下限才触发（取自冻结协议）。
- `append_resource_sample`：单次 `os.write` 写一条完整 JSON 行并 `fsync`，不重写既有字节。
- `supervise`：核验归属 → 采样 → 追加 → 判定 → 越限则写冻结格式 `STOP_REQUEST.json`。
- `publish_monitor_target` / `await_monitor_target`：**监督先启动**，运行器随后公布候选归属身份；
  监督起不来则直接拒绝，**候选根本不会被创建**（测试断言：无访问日志、标准输出为空、无产物）。

`runtime/runner.py`：`independent_monitor_enabled` 为真时走监督路径；新增 `monitor_sample_interval_seconds` 参数。
`runtime/orchestrator.py`：把该参数透传给运行器。
`tests/test_resource_monitor.py`：10 项测试，先失败后实现。

**被替换的旧规则**：`test_restricted_runtime_refuses_declared_monitor_need_until_monitor_is_active`
断言“监督尚未实现所以一律拒绝”，该规则随实现失效，已改写为
`test_restricted_runtime_publishes_process_ownership_when_a_monitor_is_declared`；
仍有效的“监督起不来就不许启动候选”由 `test_supervised_candidate_refuses_to_launch_when_the_monitor_cannot_start` 承担。

## 五、产物与可复验数字

冻结测试：**180 项通过、0 跳过、0 失败**，约 5 分 42 秒。

### 真实开发数据根 `runs/unified_autoresearch/development_source_real_v1`
- 日期边界 `1999-10-01` 至 `2008-09-30`，`sealed_final_evaluation_present` 为 `false`
- `features.parquet` `de51200644f2704861dfb696fd97455668dc084ce7e4c2d3786759e2458a105b`
- `targets.parquet` `de1fe37997b87c355e3c1000020e416c511a54517b923d9c681ea3f5b51920ca`
- `static_attributes.json` `80dbaefd7858c017b0f80bf4afc22fef862228b157ae55bdede0a08003742feb`
- 源清单散列 `8693f0ccd10f414f03b693d3c9b60cefbeed5d1ab0afae184fc9592be56efbb8`

### 真实开发数据包 `runs/unified_autoresearch/development_packages_real_v1`
- 清单散列 `4bbc0bf98c8fce8868c4f1887c871a967075b5a54878e3af3af205e07315a039`，12 个文件
- 训练包各 17,536 行；预测与评分包各 8,768 行；日期区间逐位对上；**封存区间命中 0**
- 预测包列集合 `basin date prcp srad tmax tmin vp`，**无 qobs**

### 两次完整真实循环 `development_loop_real_v1` 与 `_v2`
- 每次：4 类候选、2 套协议、16 个已登记运行、8 份评分报告、**32 个唯一有限单元**、493 个物理文件
- 候选访问事件 19,512 条，**禁止路径命中 0、越界 0**
- 两次 32 个单元的正向/反向/均值纳什效率**最大绝对差 0.0**；12 份评分与汇总产物**逐字节一致**
- 四个标记均为 `false`：封存读取、公平基准评分程序、正式流域搜索、超基线声明
- 参考候选中位纳什效率 −0.18 至 0.05（约等于预测均值）。**它们是入口可运行性证明，不是模型，不得当结果引用。**

### 监督下的缩减演示 `supervised_walkthrough_real_v1`
类别 `conceptual_rainfall_runoff`，协议 `forward`，采样间隔 0.25 秒：

| 项 | 训练 | 预测 |
|---|---|---|
| 状态 | succeeded | succeeded |
| 采样条数（序号连续） | 15 | 20 |
| 实测进程峰值内存 | 0.117 吉字节 | 0.099 吉字节 |
| 采样期最低系统可用内存 | 7.11 吉字节 | 6.82 吉字节 |
| 受控停止 | 未触发 | 未触发 |

评分 8 流域、8,768 行。**首个申报对实测的标定点**：申报峰值 0.35 + 余量 0.25 吉字节，实测 0.117 吉字节，**保守约三倍**。

## 六、可直接复跑的命令（工作目录为工作树根）

```
python -m pytest src/unified_autoresearch/tests -q

python src/unified_autoresearch/scripts/build_real_development_source.py \
  --camels-root "G:/github/pycharm/projects/neuralhydrology/data/camels_us" \
  --output-root runs/unified_autoresearch/development_source_real_vN

python src/unified_autoresearch/scripts/build_real_development_packages.py \
  --source-root runs/unified_autoresearch/development_source_real_vN \
  --output-root runs/unified_autoresearch/development_packages_real_vN

python src/unified_autoresearch/scripts/run_real_development_loop.py \
  --package-root runs/unified_autoresearch/development_packages_real_v1 \
  --output-root runs/unified_autoresearch/development_loop_real_vN

python src/unified_autoresearch/scripts/run_supervised_real_walkthrough.py \
  --package-root runs/unified_autoresearch/development_packages_real_v1 \
  --output-root runs/unified_autoresearch/supervised_walkthrough_real_vN \
  --sample-interval-seconds 0.25
```

所有输出根都拒绝覆盖：复跑必须换新的 `vN`。

## 七、已知问题与注意事项

- **停止路径没有真实运行证据**。真跑时资源充裕未触发；只有测试用临时调高门限验证过。**未修改冻结的
  `protocols/resource_safety_v1.json`**。
- 协议里的**汇总间隔**（`summary_interval_seconds`）尚未实现，只实现了采样间隔。
- **真实训练规模的重任务一次没跑过**：演示候选峰值约 0.1 吉字节、单次数秒；图形处理器任务、长时任务、
  并行任务下监督的行为未知。
- 真实数据暴露的评分敏感性：**06847900** 验证期流量标准差仅 0.019～0.060 毫米每日，
  **08190500** 有 7%～15% 零流量日。这两个流域的纳什效率对微小误差极敏感，判定规则不能只看中位数。
- `runs/unified_autoresearch/` 下另有里程碑一至三的历史产物目录，勿删。
- 本次结果**尚未**经过两个独立上下文的审核与复验。

## 八、下一步建议顺序

1. **开着监督把完整循环连跑两次**（4 类 × 2 协议 × 2 轮 = 32 次运行，估计十几分钟）。
   同时补齐第 4 条为“监督下的”，并量出第 5 条需要的时间与存储数字。
2. 用量得的数据**冻结峰值估算方法**（第 1 条）。
3. 产出**扩至 64 与 531 流域的剩余清单**（第 5 条）。
4. **双重独立复核**（第 6 条），里程碑四收口。
5. 之后才进最终审核三关：只读审数据边界与证据链、干净目录完整重跑、对抗测试。

第 1 步不碰封存数据、不碰正式搜索，可直接执行。
