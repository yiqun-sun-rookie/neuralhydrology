# 历史连续多尺度气象模型正式版本09交接

## 2026-07-31内存政策修订

当前权威内存政策已经取消统一高内存启动门槛，改为“按操作绑定的可复算解析峰值乘
`1.25`安全系数，再同时保留至少`2 GiB`可用物理内存和`2 GiB`已提交内存余量”。
任务必须串行执行；没有可信估算器的正式操作保持禁止，最小合成任务只能用于建立
后续估算器，不能直接授权长任务。最大批量`256`和禁止完整训练窗口一次性展开的
结构保护保持不变。

当前协议原始字节 SHA-256 为
`2a018755422eb102259eba11558bc190ba11034d3390f64df7bbc54e8756a0f7`。
旧协议哈希及旧固定内存门槛仅为修订前历史记录。完整修订证据见
`docs/technical/historical_multiscale_formal_v09_memory_policy_amendment_2026-07-31.md`。
所有正式授权仍为`false`，没有生成正式产物。

## 2026-07-31清洁配对评分路线设计

推荐路线已经获得代码实施和合成测试批准。新赛道不覆盖现有冻结文件，以同一干净训练合同下的
八随机数经典近期模型`B09-CLASSIC`作为主基准，连续历史候选`E09-CONTINUOUS`作为挑战者，
同参数量控制`B09-CAPACITY`只作预注册次要比较。旧`0.759225`基准降级为不具正式资格的历史参考。

附加审计确认原107流域留出集已经被真实账本中的7次评分重复使用，且聚合结果进入了后续研究反馈，
因此也不能继续承担未触碰的秘密留出声明。修复方案固定为：三组预测全部封存且一次性评分授权被
独占消费后，唯一评分进程从操作系统密码学随机源只抽取一次256位随机数，与三组预测哈希共同派生
新107流域留出集；其余424流域为公开比较集。任何中断均不得重抽或重试。

完整证据和实施步骤见：

- `docs/technical/historical_multiscale_formal_v09_holdout_reuse_audit.md`
- `docs/superpowers/plans/2026-07-31-historical-multiscale-formal-v09-clean-pair-scoring.md`

该路线的合同、评分包构建、一次性授权、随机划分、评分入口和前后置审核代码已经实现并通过
受影响回归测试，当前状态为`IMPLEMENTED-HOLD`。本次批准仍不授权生成正式输入、训练、
正式预测、创建正式一次性授权、抽取正式随机数或评分。

## 2026-07-31冻结基准资格更正

当前总体状态改为`HOLD`。旧八随机数经典基准训练把训练起点前269天
（`1999-01-05`至`1999-09-30`）的可用正式评估期流量纳入目标归一化和每流域损失尺度；
正式评分冻结基准文件又与该旧集成逐字节相同。赛道规范明确禁止正式评估期观测和测试期统计，因此
现有唯一评分不能证明相同信息下的正式胜负。影响方向和大小目前未知，不能称为保守基准。

在用户选择新的清洁同信息赛道或明确降级为历史参考比较前，不再请求正式输入、训练、预测或评分授权。
不得修改受保护冻结目录或评分代码。完整证据见
`docs/technical/historical_multiscale_formal_v09_frozen_baseline_information_audit.md`。

## 2026-07-31经典训练对齐补充

只读旧训练审查确认：旧核心数据集把269天预热区间纳入气象、流量和每流域损失尺度统计，
其中`1999-01-05`至`1999-09-30`属于正式评估期。版本09不得复用旧流量统计，也不能声称逐轨迹
复现旧八随机数训练。合法命题是：八个冻结检查点的函数映射桥接，加上新干净训练管线内经典路径与
停用历史路径的30轮逐更新严格嵌套。

同一审查发现原输入计划把真实静态属性顺序和尺度写错：旧核心实际按属性名字母顺序送入27项静态
属性，并用`ddof=1`的样本标准差。输入和训练计划现已改为显式冻结字母顺序和`ddof=1`；动态和
流量统计仍只用训练期并采用`ddof=0`。详细证据见
`docs/technical/historical_multiscale_formal_v09_classic_training_alignment_audit.md`。
旧检查点桥接门还新增531个流域乘12个固定训练日期的真实语义检查；该门必须在正式输入封存后、
严格嵌套授权前通过，当前尚未执行。
静态精度顺序也已收紧为“源双精度统计、双精度归一化、最后转单精度”；原输入计划先降为单精度会
改变8,421个输入位。正式输入必须封存原始双精度和预归一化单精度静态数组，训练只读取后者。
正式训练批次还必须在中央处理器以单精度先归一化完整气象窗口、再生成历史分箱；近期270天切片
必须与完整窗口末270天逐字节相同。
模型与Adam构造后必须另行重置独立的训练期丢弃流；否则369隐藏单元控制会因初始化消耗量不同而
从不同随机数位置开始。批次排列、参数初始化和丢弃层三条随机数流不得混用。
显存资源预检必须使用独立一次性子进程和合成数据；执行过预检步的模型、Adam和随机数状态不得进入
正式训练。

## 2026-07-31补充

可用物理内存达到硬门后，完整命令
`pytest src/26_historical_band_experts/tests -q`
已在提交`23575402ab2bae8857ecf80c3081d16af64434a0`上首次通过：
`378 passed, 1 warning in 48.35s`。协议哈希、四个配置绑定、冻结边界和工作区随后复核无漂移。
正式输入、训练、预测和评分授权仍全部为`false`，没有正式结果目录。
完整记录见
`docs/technical/historical_multiscale_formal_v09_full_test_audit.md`。

## 当前结论

版本09的协议、代码和轻量测试已经完成，并已修复经典控制与核心 `CudaLSTM` 训练期丢弃位置不一致的问题；没有开始531流域数据构建、训练、正式预测或评分。

- 有限实施阶段：**PASS**
- 531流域输入构建：**NO-GO，未授权且产物不存在**
- 模型训练：**NO-GO，未授权；是否满足资源条件须在获批后按任务实测峰值判断**
- 正式评分：**HOLD，旧经典基准不满足相同信息条件，旧107流域留出集也已被重复查询**

## 工作区状态

- 工作区：`G:\github\pycharm\projects\neuralhydrology\.worktrees\historical-band-experts-pilot`
- 分支：`codex/historical-band-experts-pilot`
- 实施提交：`ce27baaabd2d85ec05229ee93a275147ff020f6c`
- 实施父提交：`75d02d295236b20edc4a593c452d568ce5515dce`
- 修复起点提交：`262c8eae785d226e1a51a7b0eaa40660d0bd8c7d`
- 本交接和审核记录位于修复起点之后；新上下文应以 `git rev-parse HEAD` 为准。

## 必读文件

1. `docs/plans/2026-07-29-historical-multiscale-formal-v09-protocol.md`
2. `docs/technical/historical_multiscale_formal_v09_implementation_audit.md`
3. `docs/technical/historical_multiscale_formal_v09_core_classic_repair.md`
4. `docs/technical/historical_multiscale_formal_v09_classic_training_alignment_audit.md`
5. `docs/technical/historical_multiscale_formal_v09_frozen_baseline_information_audit.md`
6. `docs/technical/historical_multiscale_formal_v09_holdout_reuse_audit.md`
7. `docs/superpowers/plans/2026-07-31-historical-multiscale-formal-v09-clean-pair-scoring.md`
8. `docs/technical/historical_multiscale_formal_v09_goal_completion_audit.md`
9. `src/26_historical_band_experts/configs/formal_v09_protocol.json`
10. `src/26_historical_band_experts/launch_gate_v09.py`
11. `src/26_historical_band_experts/memory_safety_v09.py`
12. `src/26_historical_band_experts/formal_action_resources_v09.py`
13. `src/26_historical_band_experts/formal_action_runtime_v09.py`
14. `src/26_historical_band_experts/prepare_targets_formal_v09.py`
15. `docs/technical/historical_multiscale_formal_v09_action_resources_audit_2026-07-31.md`

协议JSON SHA-256：

`2a018755422eb102259eba11558bc190ba11034d3390f64df7bbc54e8756a0f7`

## 已完成内容

- 冻结531流域、训练期、评估期、最长3,561天滞后、120个历史块和成功门槛；
- 定义新的无泄漏经典近期控制，零容差复现核心 `CudaLSTM` 的模型和优化计算，但不声称复现旧数据轨迹；
- 冻结真实静态张量的属性名字母顺序和`ddof=1`尺度，明确禁止复用含预热期流量的旧归一化值；
- 定义同参数量控制和连续多尺度历史候选；
- 冻结八个训练随机数、30轮和经典学习率计划；
- 将八个旧参考运行的标识、配置哈希和第30轮检查点哈希写入机器验证协议；
- 真实旧参考只读验证通过：8个运行、16个文件、随机数100至800和提交前缀全部一致；
- 实现授权与物理内存双重启动门；
- 禁止全量训练窗口展开，只允许最多256样本的批量；
- 实现同环境零容差严格嵌套检查；
- 实现独立环境预测最大绝对差 `1e-6` 检查；
- 实现不读取观测的正式预测唯一性、有限性和完整覆盖检查；
- 实现固定顺序float64八随机数平均；
- 新增五个原子实验登记，状态均为未授权训练；
- 修复后核心兼容、模型、嵌套、协议和旧参考验证专项19项通过；完整复验受内存门约束。

## 本机内存安全边界

- 不使用统一任务启动内存门槛；
- 任务增量峰值采用与操作类型绑定的可复算解析上界，并乘`1.25`安全系数；
- 长任务峰值证据必须使用协议允许的方法并通过规范化SHA-256绑定，零估计和漂移证据拒绝；
- 正式目标包、训练和正式模型预测已经分别绑定逐流域、训练和预测解析估算器；三类证据均绑定
  当前协议内容、操作类型和精确模型几何，不能跨操作或跨模型替换；
- 逐流域目标构建的主机峰值为`482,198,528`字节；三个变体中的训练最大主机/图形处理器峰值
  为`1,447,050,836`/`3,041,335,320`字节；预测最大值为
  `962,071,124`/`1,127,573,512`字节；
- 保护后至少保留`2 GiB`可用物理内存和`2 GiB`已提交内存余量；
- 高负载任务由当前用户会话内的跨进程非阻塞互斥锁保证串行执行；
- 一个256样本窗口批量为17.39 MiB，按四份工作张量为69.57 MiB；
- 全量训练窗口为115.84 GiB，仍禁止一次性展开。

资源安全通过不等于获得实验授权。正式输入、训练、预测和评分必须分别取得明确授权。

## 未完成和阻塞

1. 531流域训练期目标包已生成并通过独立逐值审核，但尚未进入完整正式输入封存；
2. 1980年至2008年 Maurer 内存映射存储和27项静态属性封存尚未生成；
3. 没有训练代码入口、检查点、预测或指标；
4. 没有调用正式评分；
5. 冻结规范文件与旧清单的哈希不一致尚未处置；
6. 冻结经典基准不满足相同信息条件，现有正式评分目标没有合格比较对象；
7. 原107流域留出集合已至少被7次评分查询，不具新独立留出资格；
8. 清洁配对评分路线代码已经实现，但正式一次性授权、随机数和评分产物均不存在；
9. 当前受影响的资源、协议、合同、评分和审核回归集合已扩展并通过
   `172 passed, 1 warning in 44.46s`；最终安全收紧后的直接受影响集合及独立复跑均为
   `44 passed, 1 warning`；完整局部套件较早证据为
   `378 passed, 1 warning in 48.35s`；
10. 训练目标包独立审核为`GO`；训练、正式预测、随机划分和正式评分继续`NO-GO`。

## 下一步

531流域训练目标包已经在生成提交`7c6a95f347d04e122793a19902b4a60124f0d4ba`上串行生成，
并在关闭授权提交`2676f48f6ce4c9cb92d7614dac13fb799cd4b941`上通过独立逐值审核。目标文件
SHA-256为`6abadf7172f1c8ebd48122a8abf68985d7d4f94b8c894371270208eeb45f2ebb`，清单
SHA-256为`3061d548fa0b9c81c8e3e25f0dbdd8cfbdb347aaea965ac6f6400c5f09da13e8`。

下一步不是自动训练，而是另行设计、实现、授权和审核Maurer气象与27项静态属性的完整正式输入
封存。训练、预测、一次性评分授权、正式随机数和评分继续关闭。不得修改现有冻结基准、复用旧
107流域留出集，或在三组预测全部封存前创建正式一次性评分授权。

## 可直接粘贴到新上下文的提示词

```text
对话名称：历史连续多尺度气象模型冻结基准治理

继续以下隔离工作区：
G:\github\pycharm\projects\neuralhydrology\.worktrees\historical-band-experts-pilot

先完整阅读：
docs/plans/2026-07-29-historical-multiscale-formal-v09-handoff.md
docs/plans/2026-07-29-historical-multiscale-formal-v09-protocol.md
docs/technical/historical_multiscale_formal_v09_implementation_audit.md
docs/technical/historical_multiscale_formal_v09_core_classic_repair.md
docs/technical/historical_multiscale_formal_v09_classic_training_alignment_audit.md
docs/technical/historical_multiscale_formal_v09_frozen_baseline_information_audit.md
docs/technical/historical_multiscale_formal_v09_holdout_reuse_audit.md
docs/superpowers/plans/2026-07-31-historical-multiscale-formal-v09-clean-pair-scoring.md
docs/technical/historical_multiscale_formal_v09_goal_completion_audit.md

只读确认分支、HEAD、工作区和协议JSON哈希。历史实施提交为
ce27baaabd2d85ec05229ee93a275147ff020f6c，修复起点为
262c8eae785d226e1a51a7b0eaa40660d0bd8c7d；当前HEAD以包含核心兼容修复的提交为准。

当前总体状态为HOLD。冻结经典基准的训练统计包含正式评估期最后269天的可用流量，原107流域
留出集又已至少被7次评分查询，现有正式评分不满足相同信息和独立留出条件。不得生成531流域输入、
训练、生成正式预测或调用评分；不得修改受保护冻结目录或评分代码。

内存不使用统一启动门槛。每项操作必须提供与操作类型绑定、可复算的峰值证据，乘1.25安全系数后
同时保留至少2 GiB可用物理内存和2 GiB已提交内存余量，并持有当前用户会话内跨进程串行锁。
目标包、训练和正式模型预测目前没有可信估算器，因此不得启动；完整训练窗口始终禁止一次性展开。

清洁同信息配对评分路线的代码实施和合成测试已获批准并完成；该批准不包括生成正式输入、训练、
正式预测、创建正式一次性授权、抽取正式随机数或调用正式评分。先只读确认最终提交和独立审核结论。
```
