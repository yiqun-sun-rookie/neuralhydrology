# 历史分段专家严格嵌套与屏蔽诊断交接

**更新时间：** 2026-07-27  
**仓库：** `G:\github\pycharm\projects\neuralhydrology`  
**隔离工作区：** `G:\github\pycharm\projects\neuralhydrology\.worktrees\historical-band-experts-pilot`  
**分支：** `codex/historical-band-experts-pilot`  
**当前提交：** `ba247c9574ac0037b664f602c86f0974aa526bfd`

## 1. 整体目标与当前阶段目标

整体目标：检验“由不同专家分别处理近期、中期和远期历史气象信息，再共同形成一个流量预测”的结构，是否在只使用 Maurer 气象驱动和流域静态属性时优于经典长短期记忆网络。

当前阶段不是继续追求新正结果，而是审核已有负结果是否受到结构或训练协议问题影响。用户明确要求：

1. 检查三个历史分支使用不同结构是否导致不公平；
2. 对已训练模型屏蔽不同分支，确认只保留基线等价路径时能否接近经典模型；
3. 考虑让近期、中期、远期三个专家使用相同结构后重新比较。

## 2. 必须遵守的限制、成功标准和停止条件

### 输入与评估限制

- 只允许使用 Maurer 的 5 项逐日气象驱动和 27 项流域静态属性。
- 不得读取 `usgs_streamflow`、`camels_hydro`、`*_obs_eval.parquet` 或任何正式评估答案文件。
- 正式评估期 `1989-10-01` 至 `1999-09-30` 保持封存。
- 当前只允许使用固定 60 流域内部验证：
  - 训练目标期：`1999-10-01` 至 `2006-09-30`；
  - 验证目标期：`2006-10-01` 至 `2008-09-30`。
- 不得修改 `src/fair_benchmark/frozen/`、基线冻结配置、正式评分脚本、流域列表或切分文件。

### 公平性要求

- 所有模型只输出一个流量；不得让三个专家分别预测三个流量再平均。
- 新候选与对照必须使用相同原始预测信息、目标接口、数据切分、批次顺序、训练轮数、学习率、损失、梯度裁剪和检查点规则。
- 参数量必须给出精确数值；容量对照与候选差异应低于 1%。
- 不能只验证“训练前评估模式输出相等”。必须额外验证训练随机数、丢弃掩码和活跃参数更新是否严格可比。
- 新实验必须使用新的实验家族、配置快照、输出目录和登记行；不得覆盖版本 03、04、05 的结果。

### 当前冻结门槛

新历史候选第一阶段随机种子 100 必须同时满足：

- 相对经典 256 模型的逐流域纳什－萨特克利夫效率系数差值中位数不低于 `+0.01`；
- 相对参数量控制的差值中位数大于 `0`；
- 相对已有简单历史后期拼接模型的差值中位数大于 `0`；
- 相对经典 256 模型获胜的流域比例不低于 `0.55`。

只有全部通过才允许运行随机种子 200 和 300。任何内部结果都不能表述为正式 531 流域基准结论。

### 调试停止条件

- 若严格“近期单分支嵌套控制”不能在预先规定的数值容差内复现对应经典模型，停止新结构训练，先定位训练随机性、丢弃操作、优化器活跃参数或数据路径差异。
- 若同一根因连续三次修复仍失败，停止补丁式修改，重新审核架构。
- 未经设计批准，不得实施或启动新训练。

## 3. 已完成方案、关键结果与明确结论

### 版本 03：经典结构上的简单历史后期拼接

结构：

- 近期：滞后 `0–269` 天，270 个逐日时间步，隐藏宽度 256；
- 中期：滞后 `270–1824` 天，平均聚合为 60 个时间块，隐藏宽度 24；
- 远期：滞后 `1825–3649` 天，平均聚合为 60 个时间块，隐藏宽度 24；
- 三个状态拼接后由一个线性头输出一个流量。

随机种子 100：

- 相对经典 256 模型逐流域差值中位数：`+0.009156111886`；
- 相对参数量控制：`+0.003833099263`；
- 获胜流域比例：`0.6167`。

没有达到预设 `+0.01` 门槛。

### 版本 04：简单拼接多种子确认与复杂融合

简单历史后期拼接在种子 100、200、300 合并后的结果：

- 相对精确经典模型中位差：`+0.003520150454`；
- 相对容量控制中位差：`+0.002600272970`；
- 获胜流域比例：`0.5667`；
- 配对自助抽样 95% 区间：`[-0.00781654842, 0.01187477759]`。

明确结论：方向为弱正，但未达到效应与置信区间门槛。

两个复杂融合候选的种子 100 结果：

- 持续历史背景：
  - 相对经典模型：`+0.0077949443565`；
  - 相对简单拼接：`-0.00561631457925`。
- 近期条件历史残差：
  - 相对经典模型：`+0.003453943837`；
  - 相对简单拼接：`-0.00552183378`。

### 版本 05：高信息量中期与分层远期结构

结构：

- 近期分支：270 个逐日时间步，输入为 5 个气象变量加重复的 27 个静态属性，单层长短期记忆网络隐藏宽度 256；
- 中期分支：60 个时间块，每块为 5 个气象变量的均值、总体标准差、最小值、最大值，共 20 维，隐藏宽度 64；
- 远期分支：60 个 20 维时间块重排为 `5 年 × 12 块`，年内隐藏宽度 64，跨年隐藏宽度 128；
- 中期和远期用静态属性初始化隐藏状态和记忆状态；
- 拼接 `256 + 64 + 128 = 448` 维表示，由一个线性头输出流量。

参数量：

- 经典 256：`297,217`；
- 简单历史后期拼接：`308,401`；
- 经典 320 容量控制：`453,441`；
- 版本 05 候选：`455,105`；
- 候选与容量控制相差 `1,664`，即候选参数量的 `0.366%`。

随机种子 100 结果：

- 经典 256 的 60 流域中位纳什效率系数：`0.6633911083899999`；
- 经典 320：`0.685890944916`；
- 简单历史后期拼接：`0.6958119098685001`；
- 版本 05 候选：`0.6078308466035001`；
- 候选相对经典 256 的逐流域差值中位数：`-0.039933728412499994`；
- 相对经典 320：`-0.03684029517925004`；
- 相对简单历史后期拼接：`-0.05277372301550001`；
- 获胜流域：`20/60`，比例 `0.3333333333333333`。

四项第一阶段门槛全部失败，因此未运行随机种子 200 和 300。这个结果已由 4 个运行、16 个产物哈希和 175,440 条逐日预测独立重算确认。

## 4. 当前代码、配置、日志和结果路径

### 核心代码

- 版本 03 时间段提取：  
  `G:\github\pycharm\projects\neuralhydrology\.worktrees\historical-band-experts-pilot\src\26_historical_band_experts\bands_v03.py`
- 版本 03 模型：  
  `G:\github\pycharm\projects\neuralhydrology\.worktrees\historical-band-experts-pilot\src\26_historical_band_experts\models_v03.py`
- 版本 04 模型：  
  `G:\github\pycharm\projects\neuralhydrology\.worktrees\historical-band-experts-pilot\src\26_historical_band_experts\models_v04.py`
- 版本 05 高信息量时间块：  
  `G:\github\pycharm\projects\neuralhydrology\.worktrees\historical-band-experts-pilot\src\26_historical_band_experts\bands_v05.py`
- 版本 05 模型：  
  `G:\github\pycharm\projects\neuralhydrology\.worktrees\historical-band-experts-pilot\src\26_historical_band_experts\models_v05.py`
- 版本 05 训练器：  
  `G:\github\pycharm\projects\neuralhydrology\.worktrees\historical-band-experts-pilot\src\26_historical_band_experts\train_v05.py`
- 版本 05 分析器：  
  `G:\github\pycharm\projects\neuralhydrology\.worktrees\historical-band-experts-pilot\src\26_historical_band_experts\analyze_v05.py`
- 全部局部测试：  
  `G:\github\pycharm\projects\neuralhydrology\.worktrees\historical-band-experts-pilot\src\26_historical_band_experts\tests`
- 实验登记：  
  `G:\github\pycharm\projects\neuralhydrology\.worktrees\historical-band-experts-pilot\src\26_historical_band_experts\registry.csv`

### 冻结配置与数据绑定

- 版本 05 冒烟配置：  
  `G:\github\pycharm\projects\neuralhydrology\.worktrees\historical-band-experts-pilot\src\26_historical_band_experts\configs\smoke_v05.json`
- 版本 05 完整内部配置：  
  `G:\github\pycharm\projects\neuralhydrology\.worktrees\historical-band-experts-pilot\src\26_historical_band_experts\configs\pilot_v05.json`
- 60 流域列表：  
  `G:\github\pycharm\projects\neuralhydrology\.worktrees\historical-band-experts-pilot\src\26_historical_band_experts\configs\pilot_basins_60.txt`
- 60 流域列表 SHA-256：  
  `3160dad3b22200fdb596164c9f69e4fbe19cc156cfad768beb193efea7b26b65`
- 训练与内部验证目标包：  
  `G:\github\pycharm\projects\neuralhydrology\.worktrees\historical-band-experts-pilot\results\26_historical_band_experts\trusted_targets\pilot_targets_1999_2008_v02.csv`
- 目标包 SHA-256：  
  `d4c93675eefd433515d6f7e10943caea31c6eb7e30533d4c387cf9325886e05c`
- CAMELS-US 数据根目录：  
  `G:\github\pycharm\projects\neuralhydrology\data\camels_us`

### 设计、计划与结果记录

- 版本 05 设计：  
  `G:\github\pycharm\projects\neuralhydrology\.worktrees\historical-band-experts-pilot\docs\plans\2026-07-26-hierarchical-rich-historical-context-design.md`
- 版本 05 实施计划：  
  `G:\github\pycharm\projects\neuralhydrology\.worktrees\historical-band-experts-pilot\docs\plans\2026-07-26-hierarchical-rich-historical-context.md`
- 版本 05 结果报告：  
  `G:\github\pycharm\projects\neuralhydrology\.worktrees\historical-band-experts-pilot\docs\technical\hierarchical_rich_historical_context_v05.md`

### 结果目录

- 版本 03：  
  `G:\github\pycharm\projects\neuralhydrology\.worktrees\historical-band-experts-pilot\results\26_historical_band_experts\classic_lstm_historical_context_v03`
- 版本 04：  
  `G:\github\pycharm\projects\neuralhydrology\.worktrees\historical-band-experts-pilot\results\26_historical_band_experts\persistent_historical_context_v04`
- 版本 05 冒烟：  
  `G:\github\pycharm\projects\neuralhydrology\.worktrees\historical-band-experts-pilot\results\26_historical_band_experts\hierarchical_rich_historical_context_v05_smoke`
- 版本 05 完整内部结果：  
  `G:\github\pycharm\projects\neuralhydrology\.worktrees\historical-band-experts-pilot\results\26_historical_band_experts\hierarchical_rich_historical_context_v05`
- 版本 05 摘要：  
  `G:\github\pycharm\projects\neuralhydrology\.worktrees\historical-band-experts-pilot\results\26_historical_band_experts\hierarchical_rich_historical_context_v05\summary.json`
- 版本 05 摘要 SHA-256：  
  `ce68c74509dd9a932d284f149619d010c8e362cddb1de75ba6000f88aa3bd67f`

## 5. 已确认问题、已排除问题和验证证据

### 已确认问题

#### 5.1 训练随机数状态没有严格对齐

`build_model_v05()` 对经典模型只初始化一个经典网络；对候选模型则先初始化经典网络，再初始化全部新增分支，然后复制近期权重。新增模块初始化会消耗随机数。

在随机种子 100 下，模型构建后的 PyTorch 随机数状态 SHA-256：

- 经典 256：`f64c6cc839311f6f5a631beed679d5df7968f50e716b4aee6c0fbe24f985ebd6`
- 版本 05 候选：`27b2725392e0b14be3ca10f300d676e9c0ad4a9e91f3c9526ca2b2ad969d8f0d`
- 两者不相同。

因此，虽然训练前评估模式输出严格相等，但训练中的丢弃掩码不是严格相同。当前版本 05 不能作为“完全相同优化随机性下，新增分支必然损害性能”的严格证据。

这项差异是否足以解释 `-0.039934` 的下降：**未验证**。

#### 5.2 当前候选训练后发生明显共同适应

版本 05 训练后输出头权重范数：

- 近期 256 维：`2.4843122959136963`
- 中期 64 维：`0.03594555705785751`
- 远期 128 维：`0.5333290100097656`

与单独训练的经典 256 模型相比：

- 近期长短期记忆网络输入权重矩阵的欧氏距离：`24.00504493713379`
- 近期输出头权重的欧氏距离：`3.594416618347168`

这些数值证明近期路径与历史路径共同训练后发生了明显漂移，且远期输出权重范数明显大于中期。它们不能单独证明远期分支造成损害；分支屏蔽诊断尚未完成。

### 已排除问题

- 版本 05 候选参数量不足：已排除。候选为 `455,105`，容量控制为 `453,441`。
- 版本 05 训练轮数或优化更新不足：已排除。两个新完整运行均为 30 轮、18,000 次更新。
- 候选输出多个流量：已排除。所有版本 03–05 候选均只输出一个流量。
- 训练前近期路径没有复制经典模型：已排除。自动测试验证候选训练前评估模式输出逐元素等于同种子经典模型。
- 显卡初始状态非连续问题：已修复。修复提交为 `b74bb936`，修复后真实显卡冒烟完成。
- 版本 05 汇总计算错误：已排除。190 项局部测试通过；4 个运行、16 个产物哈希和 175,440 条预测独立重算与摘要一致。
- 正式评估期泄漏：静态扫描与结果日期检查未发现。当前验证预测日期严格为 `2006-10-01` 至 `2008-09-30`。没有操作系统级文件访问遥测，因此不能声称得到操作系统层面的独立证明。

## 6. 未完成事项、阻塞原因和最高优先级下一步

### 未完成

1. 尚未对版本 05 已训练检查点执行分支屏蔽评估。
2. 尚未训练严格近期单分支嵌套控制。
3. 尚未设计和实现三个专家结构完全相同的候选。
4. 尚未修复或隔离训练随机数与丢弃掩码不一致问题。

### 当前阻塞

用户所说“屏蔽前面两个”存在歧义：可能指屏蔽中期和远期，只保留近期；也可能指屏蔽近期和中期，只保留远期。为避免遗漏，建议评估全部 7 个非空分支组合。

### 最高优先级下一步

先完成一个新的、独立登记的严格诊断实验家族，建议顺序：

1. **只读屏蔽诊断：** 对版本 05 已训练检查点评估 7 个非空组合：
   - 仅近期；
   - 仅中期；
   - 仅远期；
   - 近期加中期；
   - 近期加远期；
   - 中期加远期；
   - 全部分支。
   
   该诊断只能说明已训练模型依赖哪些分支，不能作因果归因，因为三个分支已经共同适应。

2. **严格嵌套训练控制：** 新增分支存在但在整个训练中保持输出中性，只训练与经典模型完全对应的近期路径。必须显式对齐：
   - 模型构建后的训练随机数状态；
   - 近期丢弃掩码；
   - 批次顺序；
   - 优化器中实际更新的参数及其顺序；
   - 初始近期权重和输出头；
   - 训练预算。
   
   在设计阶段必须先定义“复现经典模型”的数值容差。未经验证，不要假定仅重置 `torch.manual_seed()` 就足够，因为候选当前对 448 维拼接特征整体调用丢弃操作，而经典模型只对 256 维近期特征调用丢弃操作。

3. **三个相同结构的专家候选：** 推荐最干净的候选是：
   - 近期、中期、远期均使用单层长短期记忆网络；
   - 三个编码器隐藏宽度均为 256；
   - 三个分支输入维度统一为 32：5 个气象变量加重复的 27 个静态属性；
   - 中期和远期恢复为 60 个平均时间块，不使用版本 05 的极值统计和五年层次；
   - 三个状态拼接为 768 维，由一个线性头输出一个流量；
   - 预期候选参数量约为 `891,649`；
   - 容量对照可使用隐藏宽度 456 的经典模型，预期参数量约为 `892,393`，差异约 `0.083%`。
   
   以上参数量为按当前公式计算的设计值，实施前必须由代码测试重新确认。

## 7. 新对话开始后首先检查的文件和命令

首先进入隔离工作区：

```powershell
Set-Location 'G:\github\pycharm\projects\neuralhydrology\.worktrees\historical-band-experts-pilot'
```

检查分支和工作区：

```powershell
git status --short --branch
git rev-parse HEAD
git log -10 --oneline
```

预期在写入本交接文档之前的提交为：

```text
ba247c9574ac0037b664f602c86f0974aa526bfd
```

必读文件：

```powershell
Get-Content docs\plans\2026-07-27-historical-expert-strict-nesting-handoff.md -Raw
Get-Content docs\technical\hierarchical_rich_historical_context_v05.md -Raw
Get-Content src\26_historical_band_experts\models_v05.py -Raw
Get-Content src\26_historical_band_experts\train_v05.py -Raw
Get-Content src\26_historical_band_experts\tests\test_models_v05.py -Raw
```

复核版本 05 结果：

```powershell
python src\26_historical_band_experts\analyze_v05.py `
  --config src\26_historical_band_experts\configs\pilot_v05.json
```

预期状态：

```text
complete_stage1_no_go
```

运行当前局部测试：

```powershell
pytest src\26_historical_band_experts\tests -q
```

最近一次已验证结果为：

```text
190 passed, 1 pre-existing Pytest configuration warning
```

复现训练随机数状态差异：

```powershell
python -c "from pathlib import Path; import sys, torch, hashlib; sys.path.insert(0,str(Path('src/26_historical_band_experts'))); from models_v05 import build_model_v05; a=build_model_v05('classic_lstm_256',100); ha=hashlib.sha256(torch.get_rng_state().numpy().tobytes()).hexdigest(); b=build_model_v05('hierarchical_rich_history',100); hb=hashlib.sha256(torch.get_rng_state().numpy().tobytes()).hexdigest(); print({'classic_post_build_rng':ha,'candidate_post_build_rng':hb,'same':ha==hb})"
```

预期输出中的 `same` 为 `False`。

## 8. 可直接粘贴到新对话的下一轮任务提示词

```text
对话名称：历史分段专家严格嵌套与屏蔽诊断

请继续 `G:\github\pycharm\projects\neuralhydrology\.worktrees\historical-band-experts-pilot` 中的历史分段专家研究。

开始前完整阅读：
`G:\github\pycharm\projects\neuralhydrology\.worktrees\historical-band-experts-pilot\docs\plans\2026-07-27-historical-expert-strict-nesting-handoff.md`

先只读确认分支、提交、工作区、版本 05 摘要、冻结输入边界和训练随机数状态差异。保持独立判断：不要直接接受“增加分支必然提高验证效果”，也不要接受现有负结果一定正确；分别检查理论嵌套、实际优化和验证泛化。

当前最优先目标是设计一个严格诊断：
1. 对版本 05 已训练检查点评估全部 7 个非空分支屏蔽组合；
2. 建立能严格复现经典近期模型训练的嵌套控制，显式对齐模型构建后的随机数、近期丢弃掩码、批次顺序、优化器活跃参数和初始权重；
3. 在上述诊断通过后，再设计近期、中期、远期使用相同单层长短期记忆网络结构和相同隐藏宽度的单输出候选，并配置参数量匹配的经典对照。

必须使用 superpowers:brainstorming 先完成设计并获得我的批准；遇到异常使用 superpowers:systematic-debugging；多实验使用 experiment-tracking；实施采用测试驱动开发；完成前使用 superpowers:verification-before-completion。未经设计批准不要写代码或启动训练。

只使用 Maurer 气象驱动和 27 个静态属性；不得读取历史观测流量或正式评估期；不得修改任何冻结公平基准文件；不得覆盖版本 03、04、05 的代码、配置或结果。先给出只读审核结论、2–3 个诊断方案、推荐方案、精确屏蔽定义、严格复现容差和停止条件，然后等待批准。
```
