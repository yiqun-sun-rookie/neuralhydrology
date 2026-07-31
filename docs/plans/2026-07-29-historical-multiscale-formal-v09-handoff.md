# 历史连续多尺度气象模型正式版本09交接

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
- 正式评分：**NO-GO，未授权且冻结清单问题未处置**

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
5. `docs/technical/historical_multiscale_formal_v09_goal_completion_audit.md`
6. `src/26_historical_band_experts/configs/formal_v09_protocol.json`
7. `src/26_historical_band_experts/launch_gate_v09.py`
8. `src/26_historical_band_experts/memory_safety_v09.py`

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
6. 当前环境没有YAPF；修复前已完成编译、行宽和371项测试检查，修复后完整复验因内存门尚未运行；
7. 当前审核是提交后的对抗式自审，最终结果仍需新的干净上下文独立审核。

## 下一步

只有用户明确批准后，下一阶段才生成正式输入。该阶段仍不训练：

1. 先运行启动门并确认可用内存至少12.68 GiB；
2. 实现并测试流式输入构建器；
3. 按流域逐个写入气象内存映射文件；
4. 生成只含训练期观测的目标包；
5. 重载产物，核对531流域、日期、5项 Maurer、27项静态属性的字母语义顺序与`ddof=1`尺度、
   唯一性、有限性和所有哈希；
6. 由独立上下文审核输入产物；
7. 输入审核通过后，再单独申请严格嵌套和训练授权。

## 可直接粘贴到新上下文的提示词

```text
对话名称：历史连续多尺度气象模型正式版本09输入门

继续以下隔离工作区：
G:\github\pycharm\projects\neuralhydrology\.worktrees\historical-band-experts-pilot

先完整阅读：
docs/plans/2026-07-29-historical-multiscale-formal-v09-handoff.md
docs/plans/2026-07-29-historical-multiscale-formal-v09-protocol.md
docs/technical/historical_multiscale_formal_v09_implementation_audit.md
docs/technical/historical_multiscale_formal_v09_core_classic_repair.md
docs/technical/historical_multiscale_formal_v09_classic_training_alignment_audit.md
docs/technical/historical_multiscale_formal_v09_goal_completion_audit.md

只读确认分支、HEAD、工作区和协议JSON哈希。历史实施提交为
ce27baaabd2d85ec05229ee93a275147ff020f6c，修复起点为
262c8eae785d226e1a51a7b0eaa40660d0bd8c7d；当前HEAD以包含核心兼容修复的提交为准。

当前只允许先做只读审核和内存启动检查。不得生成531流域输入、不得训练、不得生成正式预测、不得调用评分，除非我在新上下文再次明确批准相应阶段。

内存是硬门：本机31.70 GiB，长任务启动至少需要12.68 GiB可用，建议16 GiB；运行中保留8 GiB；进程不超过6 GiB；单次分配不超过512 MiB；禁止展开全部1,745,928个3562天气象窗口。若门槛不满足，直接NO-GO。

下一候选阶段不是训练，而是流式生成并独立审核两个正式输入产物：
1. 531流域、1980-01-01至2008-09-30、5项Maurer的float32内存映射存储；
2. 仅1999-10-01至2008-09-30训练观测的目标包。

只使用Maurer气象和27项静态属性；正式评估观测、usgs_streamflow、camels_hydro和流量派生水文属性继续封存；不得修改src/fair_benchmark/frozen或正式评分代码。

先报告当前可用内存、GO/NO-GO、拟生成文件格式、估计峰值内存、逐块停止条件和输入审核清单，等待我批准后再写输入构建代码或生成数据。
```
