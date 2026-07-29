# 历史连续多尺度气象模型正式版本09交接

## 当前结论

版本09的协议、代码和轻量测试已经完成；没有开始531流域数据构建、训练、正式预测或评分。

- 有限实施阶段：**PASS**
- 531流域输入构建：**NO-GO，未授权且产物不存在**
- 模型训练：**NO-GO，未授权且本机可用内存不足**
- 正式评分：**NO-GO，未授权且冻结清单问题未处置**

## 工作区状态

- 工作区：`G:\github\pycharm\projects\neuralhydrology\.worktrees\historical-band-experts-pilot`
- 分支：`codex/historical-band-experts-pilot`
- 实施提交：`ce27baaabd2d85ec05229ee93a275147ff020f6c`
- 实施父提交：`75d02d295236b20edc4a593c452d568ce5515dce`
- 本交接和审核记录位于实施提交之后的审核提交中；新上下文应以 `git rev-parse HEAD` 为准。

## 必读文件

1. `docs/plans/2026-07-29-historical-multiscale-formal-v09-protocol.md`
2. `docs/technical/historical_multiscale_formal_v09_implementation_audit.md`
3. `src/26_historical_band_experts/configs/formal_v09_protocol.json`
4. `src/26_historical_band_experts/launch_gate_v09.py`
5. `src/26_historical_band_experts/memory_safety_v09.py`

协议JSON SHA-256：

`6c465ccbce86d34f32062dd6a1a590919a28d33816e24de4cbc8075c4960be10`

## 已完成内容

- 冻结531流域、训练期、评估期、最长3,561天滞后、120个历史块和成功门槛；
- 定义新的无泄漏经典近期控制，不再声称复现旧冻结经典训练轨迹；
- 定义同参数量控制和连续多尺度历史候选；
- 冻结八个训练随机数、30轮和经典学习率计划；
- 实现授权与物理内存双重启动门；
- 禁止全量训练窗口展开，只允许最多256样本的批量；
- 实现同环境零容差严格嵌套检查；
- 实现独立环境预测最大绝对差 `1e-6` 检查；
- 实现不读取观测的正式预测唯一性、有限性和完整覆盖检查；
- 实现固定顺序float64八随机数平均；
- 新增五个原子实验登记，状态均为未授权训练；
- 371项历史分段专家局部测试通过。

## 本机内存硬边界

本机总物理内存31.70 GiB：

- 长任务启动至少需要12.68 GiB可用；
- 建议实际启动前至少有16 GiB可用；
- 运行中至少保留8 GiB；
- 当前进程最多6 GiB驻留内存；
- 单次计划分配最多512 MiB；
- 一个256样本窗口批量17.39 MiB，按四份工作张量为69.57 MiB；
- 全量训练窗口115.84 GiB，代码会在分配前拒绝。

审核快照可用内存11.47 GiB，因此即使以后授权训练，当前内存门也会拒绝启动。启动前应关闭其他大内存程序并重新实测；不得靠分页文件或“先运行看看”绕过。

## 未完成和阻塞

1. 531流域训练期目标包尚未生成；
2. 1980年至2008年 Maurer 内存映射存储尚未生成；
3. 没有训练代码入口、检查点、预测或指标；
4. 没有调用正式评分；
5. 冻结规范文件与旧清单的哈希不一致尚未处置；
6. 当前环境没有YAPF，虽已完成编译、行宽和371项测试检查，仍应在有YAPF的审核环境补一次格式检查；
7. 当前审核是提交后的对抗式自审，最终结果仍需新的干净上下文独立审核。

## 下一步

只有用户明确批准后，下一阶段才生成正式输入。该阶段仍不训练：

1. 先运行启动门并确认可用内存至少12.68 GiB；
2. 实现并测试流式输入构建器；
3. 按流域逐个写入气象内存映射文件；
4. 生成只含训练期观测的目标包；
5. 重载产物，核对531流域、日期、5项 Maurer、27项静态属性、唯一性、有限性和所有哈希；
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

只读确认分支、HEAD、工作区和协议JSON哈希。实施提交应包含
ce27baaabd2d85ec05229ee93a275147ff020f6c；当前HEAD以包含交接文档的提交为准。

当前只允许先做只读审核和内存启动检查。不得生成531流域输入、不得训练、不得生成正式预测、不得调用评分，除非我在新上下文再次明确批准相应阶段。

内存是硬门：本机31.70 GiB，长任务启动至少需要12.68 GiB可用，建议16 GiB；运行中保留8 GiB；进程不超过6 GiB；单次分配不超过512 MiB；禁止展开全部1,745,928个3562天气象窗口。若门槛不满足，直接NO-GO。

下一候选阶段不是训练，而是流式生成并独立审核两个正式输入产物：
1. 531流域、1980-01-01至2008-09-30、5项Maurer的float32内存映射存储；
2. 仅1999-10-01至2008-09-30训练观测的目标包。

只使用Maurer气象和27项静态属性；正式评估观测、usgs_streamflow、camels_hydro和流量派生水文属性继续封存；不得修改src/fair_benchmark/frozen或正式评分代码。

先报告当前可用内存、GO/NO-GO、拟生成文件格式、估计峰值内存、逐块停止条件和输入审核清单，等待我批准后再写输入构建代码或生成数据。
```
