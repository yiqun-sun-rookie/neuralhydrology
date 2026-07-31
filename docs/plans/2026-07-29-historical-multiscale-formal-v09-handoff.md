# 历史连续多尺度气象模型正式版本09交接

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
- 模型训练：**NO-GO，未授权且本机可用内存不足**
- 正式评分：**HOLD，冻结经典基准不满足相同信息条件，且冻结清单问题未处置**

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
6. `docs/technical/historical_multiscale_formal_v09_goal_completion_audit.md`
7. `src/26_historical_band_experts/configs/formal_v09_protocol.json`
8. `src/26_historical_band_experts/launch_gate_v09.py`
9. `src/26_historical_band_experts/memory_safety_v09.py`

协议JSON SHA-256：

`b81bce8fc83aa8c4cad2d36475c6e6da553567f54b5f5f8d52457006fb446ed8`

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

## 本机内存硬边界

本机总物理内存31.70 GiB：

- 长任务启动至少需要12.68 GiB可用；
- 建议实际启动前至少有16 GiB可用；
- 运行中至少保留8 GiB；
- 当前进程最多6 GiB驻留内存；
- 单次计划分配最多512 MiB；
- 一个256样本窗口批量17.39 MiB，按四份工作张量为69.57 MiB；
- 全量训练窗口115.84 GiB，代码会在分配前拒绝。

本次修复期间最低可用内存为7.66 GiB，全部长任务检查都低于12.68 GiB启动线，因此训练和完整测试套件均不得启动。启动前应关闭其他大内存程序并重新实测；不得靠分页文件或“先运行看看”绕过。

## 未完成和阻塞

1. 531流域训练期目标包尚未生成；
2. 1980年至2008年 Maurer 内存映射存储尚未生成；
3. 没有训练代码入口、检查点、预测或指标；
4. 没有调用正式评分；
5. 冻结规范文件与旧清单的哈希不一致尚未处置；
6. 冻结经典基准不满足相同信息条件，现有正式评分目标没有合格比较对象；
7. 当前代码的完整局部测试证据为`378 passed, 1 warning in 48.35s`；以后任何Python变化都必须
   在内存硬门通过后重新运行；
8. 当前审核是提交后的对抗式自审，最终结果仍需新的干净上下文独立审核。

## 下一步

下一步不是生成正式输入，而是由用户选择基准治理路线：

1. 推荐：新建不覆盖现有冻结文件的清洁同信息赛道，在一次封存服务调用中同时评分清洁经典集成和
   连续历史候选；
2. 备选：保留旧基准只作历史参考，明确放弃相同信息正式胜负主张；
3. 不推荐：修改现有冻结基准或继续在现有评分服务上宣称公平胜负。

只有路线1得到明确批准并另行完成协议、服务和独立审核设计后，才重新判断是否值得生成正式输入。

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
docs/technical/historical_multiscale_formal_v09_goal_completion_audit.md

只读确认分支、HEAD、工作区和协议JSON哈希。历史实施提交为
ce27baaabd2d85ec05229ee93a275147ff020f6c，修复起点为
262c8eae785d226e1a51a7b0eaa40660d0bd8c7d；当前HEAD以包含核心兼容修复的提交为准。

当前总体状态为HOLD。冻结经典基准的训练统计包含正式评估期最后269天的可用流量，现有正式评分
不满足相同信息条件。不得生成531流域输入、训练、生成正式预测或调用评分；不得修改受保护冻结目录
或评分代码。

内存是硬门：本机31.70 GiB，长任务启动至少需要12.68 GiB可用，建议16 GiB；运行中保留8 GiB；进程不超过6 GiB；单次分配不超过512 MiB；禁止展开全部1,745,928个3562天气象窗口。若门槛不满足，直接NO-GO。

先独立复核基准资格证据，然后比较三条治理路线：新建清洁同信息赛道、降级为历史参考、修改现有
冻结基准。推荐方案必须保留Maurer气象和27项静态属性、正式评估答案封存、一次性评分和独立终审，
并说明是否需要新的评分入口。等待我选择路线后再写代码或启动任何长任务。
```
