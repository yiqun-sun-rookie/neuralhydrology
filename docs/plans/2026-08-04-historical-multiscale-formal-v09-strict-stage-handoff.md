# 历史连续多尺度气象模型正式版本09任务交接摘要

**交接日期：** 2026-08-04

**建议对话名称：** 历史连续多尺度气象模型正式版本09—严格嵌套阶段恢复

**结论：** 当前对话已过长，并混入多个已经过时的代码基线、阶段状态和授权边界。新对话应以本摘要和现场只读核验为准，不应继续依赖更早的交接文档。

## 1. 最终目标和当前阶段

### 最终目标

在完全相同的预测信息和评价规则下，比较以下三组模型：

1. 经典近期长短期记忆网络：隐藏宽度256，只使用目标日及此前269天的Maurer气象驱动；
2. 同参数量近期控制：隐藏宽度369，输入信息与经典近期模型相同；
3. 连续多尺度历史气象候选：近期隐藏宽度256，另用隐藏宽度256的历史编码器处理滞后270至3,561天的连续历史气象。

三组模型必须使用相同的531个流域、Maurer五项气象驱动、27项静态属性、训练目标、训练规则和八个固定随机数。全部24次训练和三组集合预测封存后，才允许由唯一评分进程抽取一次操作系统加密随机的256位值、共同派生新的107流域秘密留出集和424流域公开集，并进行一次预注册评分。评分后还必须完成不重复评分的独立代码和原始证据审核。

### 当前阶段及其作用

当前只处于“正式训练前的严格嵌套验证”阶段。该阶段先证明新的清洁训练实现能逐更新、逐状态、逐参数严格复现经典256单元模型，再允许24次主训练。当前最近的完整阶段应包括：

1. 运行一次无参数的封闭前置入口，生成旧模型函数桥接报告和真实代表性资源校准报告；
2. 仅在两份报告和实时资源门均通过后，创建一次性严格嵌套训练授权；
3. 运行随机数100、531流域、30轮的严格嵌套配对训练；
4. 完成训练后独立只读重放审核；
5. 任一前置条件或严格相等条件失败即停止。

这个阶段不包括24次主训练、正式预测或评分。严格嵌套审核通过后，才可另行申请主训练阶段。

## 2. 当前权威代码和协议状态

- 固定工作区：`G:\github\pycharm\projects\neuralhydrology\.worktrees\historical-band-experts-pilot`
- 分支：`codex/historical-band-experts-pilot`
- 当前实现基线提交：`a11d5bc4537e383643db7cca3ed0916f783ad060`
- 该提交说明：`Feat: Add formal v09 strict prerequisite entry`
- 本交接文档提交后，`HEAD`会变为新的仅文档提交；正式动作前必须用`git rev-parse HEAD`读取完整提交，不得继续硬编码旧`HEAD`。
- 正式协议：`src/26_historical_band_experts/configs/formal_v09_protocol.json`
  - 文件SHA-256：`2a018755422eb102259eba11558bc190ba11034d3390f64df7bbc54e8756a0f7`
  - 规范化JSON SHA-256：`d2652a0415677ced1656e24485688c3a3f542e11cdd173523899b6f6d04d184c`
- 严格嵌套配置：`src/26_historical_band_experts/configs/formal_v09_strict_nesting.json`
  - 状态仍为`protocol_implemented_training_not_authorized`
  - `training_authorized`仍为`false`

协议中的`training_target_interface.bundle_generated=false`和总授权字段为冻结的预运行声明，不得为了反映当前运行状态而修改；真实输入和阶段状态由封印、授权和消费收据证明。

## 3. 必须遵守的限制、成功标准和停止条件

### 未经新的完整阶段明确批准，始终禁止

- 不运行`prepare_formal_strict_stage_v09.py`；
- 不创建严格嵌套训练授权；
- 不训练任何模型；
- 不生成正式预测；
- 不创建正式评分授权；
- 不抽取正式256位随机值；
- 不调用正式评分服务；
- 不访问正式评价期观测流量；
- 不修改正式输入目录、训练目标包、清单、封印、冻结目录、旧评分代码或旧模型结果；
- 不重复生成已经消费一次性授权的正式完整输入。

只允许轻量只读核验。代码或正式文件未变化时，不重复完整测试、不重新读取全部531个原始来源、不重复逐值复算或独立审核。

### 资源规则

- 只允许串行运行；
- 使用操作类型对应的可复算峰值估计并乘1.25安全系数；
- 预计峰值扣除后，至少保留2 GiB可用物理内存和2 GiB Windows已提交内存余量；
- 涉及图形处理器时，另保留至少1 GiB图形处理器内存；
- 严格嵌套配对的冻结估计：
  - 主机峰值：`1,446,977,140`字节；
  - 主机最低可用量：`3,956,205,073`字节；
  - 图形处理器峰值：`3,984,998,448`字节；
  - 图形处理器最低可用量：`6,054,989,884`字节。
- 2026-08-04T12:33:25+08:00只读快照：可用物理内存`4,152,397,824`字节，已提交内存余量`18,397,204,480`字节，NVIDIA GeForce RTX 4070 Ti空闲`6,428 MiB`。当时三项门均通过，但物理内存只高于最低值约196 MB；该快照会变化，任何实际动作前必须重新采样。

### 严格嵌套成功标准

- 同一进程中的预测、损失、未裁剪和裁剪梯度、梯度范数、Adam状态、更新后参数和最终流式预测的绝对差与相对差均为0；
- 独立环境重放预测最大绝对差不超过`1e-6`，相对差为0；
- 30轮、每轮6,821次、总计204,630次优化更新完整；
- 训练样本数1,745,928；检查点固定为第10、20、30轮；
- 输入、协议、代码、环境、旧模型桥接、资源报告、授权与消费收据、运行封印和外部审核哈希全部一致；
- 正式评价观测读取数为0。

### 当前完整阶段的停止条件

若出现以下任一情况，立即停止且不覆盖证据：关键哈希漂移、Git工作区不干净、路径链接或Windows目录联接、意外临时文件或`.building`目录、已有但无效的前置报告、资源门失败、旧模型函数桥接预测不一致、读取训练目标或正式评价观测的越权行为、已有授权/消费/输出、授权缺失或已消费、同进程任一非零差异、独立重放超过`1e-6`、非有限值或子进程失败。失败或中断后不得自动重试，也不得复用已消费授权。

## 4. 已完成的有效方案和关键结果

### 4.1 版本08内部筛选：有效但不等于正式结果

连续多尺度历史气象候选在冻结的60流域内部确认设计中通过三随机数门槛，独立审核结论为实现和内部证据`PASS`，正式531流域泛化为`HOLD`：

- 随机数100：相对经典逐流域中位差`+0.011230`；相对同参数量控制`+0.017759`；胜率`38/60`；95%自助区间下界`+0.002521`；
- 三随机数集合：相对经典逐流域中位差`+0.015203`；相对同参数量控制`+0.003593`；胜率`42/60`；95%自助区间`[+0.006702, +0.022880]`；三组随机数方向均为正；
- 该证据只用于选择版本09的候选结构，不得宣称531流域正式有效。

### 4.2 正式531流域完整输入：最终审核通过

- 固定目录：`results/26_historical_band_experts/formal_v09/input_attempt_01`
- `seal.json` SHA-256：`a5a64e43312ac303bf03ea3840e2cf126563527c6b82b8b94035c34978c25b3a`
- 被封文件集合SHA-256：`c4252458c7c42ba2811795bf4e7ec046ab748a8cf67529eb85a68607029210ad`
- 一次性输入授权：`results/26_historical_band_experts/formal_v09/authorizations/formal_input_seal_authorization.json`
  - SHA-256：`43b883940d58787d25b1a64bf1cee6097d459f3f95e595d59bea740a94b446d0`
- 输入授权消费记录：`results/26_historical_band_experts/formal_v09/formal_input_seal_authorization_consumed.json`
  - SHA-256：`553cdbb8786735f7ac869982b4cb2a748b0f62e5241bd612fa59b0c69e871277`
- 训练目标：`results/26_historical_band_experts/formal_v09/inputs/training_targets.csv`
  - SHA-256：`6abadf7172f1c8ebd48122a8abf68985d7d4f94b8c894371270208eeb45f2ebb`
- 目标清单：`results/26_historical_band_experts/formal_v09/inputs/training_targets.manifest.json`
  - SHA-256：`3061d548fa0b9c81c8e3e25f0dbdd8cfbdb347aaea965ac6f6400c5f09da13e8`
- 完整输入外部审核：`results/26_historical_band_experts/formal_v09/input_attempt_01.external_audit.json`
  - SHA-256：`e18be463df4cc6fe6c21a1e39c675f77db3e8c833109c1e9cfb557e37a832cd6`
  - 状态：`complete_input_audit_passed`
- 可信训练目标外部审核：`results/26_historical_band_experts/formal_v09/input_attempt_01.trusted_source_external_audit.json`
  - SHA-256：`81e3658fe27e8f658e59d81015ce3d1b2a3baef11045a3e22bd76254ef5d8387`
  - 状态：`complete_trusted_training_target_audit`

封存事实：531流域；气象数组`531×10501×5`；静态属性`531×27`；训练目标`531×3288`，总计1,745,928；训练期1999-10-01至2008-09-30；正式评价期目标交集0；1,062个来源文件哈希差异0；完整复算比较27,880,155个气象值、14,337个静态值和1,745,928个目标值。

已知Maurer最低温度与最高温度在全部5,576,031个流域日完全相同。该问题已确认，按冻结协议原样保留，禁止事后修补。

### 4.3 严格训练和封闭前置入口代码

截至实现提交`a11d5bc4537e383643db7cca3ed0916f783ad060`，严格嵌套训练、训练后外部重放审核、阶段授权消费和封闭前置入口均已实现。前置入口无参数且固定路径，只能创建两份前置报告，不能创建训练授权、训练、预测或评分。配置和检查点从同一字节完成哈希与加载；实际桥接前重查实时主机和设备0资源门；报告发布前重核全部已消费预测输入；旧模型根固定解析到共享主仓库。

此前独立代码审核记录的结论为“代码实施阶段通过”，相关回归150项通过。本轮未重复测试，仓库中未找到单独保存的150项测试日志，因此该测试计数的证据来源是既有任务记录，不是本轮新生成的日志；代码或正式文件未变化时按规则不重复运行。

## 5. 影响后续判断的失败实验

### 版本05：分层高信息量历史结构，内部停止

60流域、随机数100下，候选相对经典256模型逐流域中位差`-0.039934`，相对320单元参数量控制`-0.036840`，相对简单历史拼接`-0.052774`，胜率`20/60`；四项门槛全部失败，因此没有运行随机数200和300。候选训练损失更低但内部验证更差，排除了“只要增加历史容量就会改善”的解释。

### 版本06：严格停用历史路径可以逐元素复现经典模型

60流域、30轮、18,000次更新和43,860条验证预测中，停用历史路径的嵌套控制与经典256模型最大预测差为0，活跃检查点张量和Adam状态逐元素相同。它排除了“新增但停用的模块必然破坏经典模型”的问题；版本05下降来自历史路径参与共同训练后的轨迹变化。

### 版本07：由远到近状态传递未达门槛

随机数100下，相对经典逐流域中位差`+0.001398`，相对参数量控制`-0.007735`，相对简单历史拼接`-0.005647`，胜率`32/60`；四项门槛全部失败，未运行随机数200和300。切断状态路径会降低训练后表现，但这是共同训练后的依赖诊断，不能解释为较早历史的因果贡献。

## 6. 已确认和已排除的问题

### 已确认

1. 旧八随机数经典集合中位纳什－萨特克利夫效率系数为`0.759225`，但只能作为历史评分参考，不能作为清洁同信息训练轨迹基线。
2. 旧训练归一化和损失尺度包含训练起点前269天，其中1999-01-05至1999-09-30属于正式评价期；正式版本09不得声称逐步复现旧训练轨迹。当前合法目标是桥接旧检查点的函数映射，并在新清洁训练合同中证明严格嵌套。
3. 原107流域留出集已被同一424/107划分评分7次并进入研究反馈，不能再称为秘密留出集。新107流域必须在三组预测全部封存后，由唯一评分进程使用一次256位随机值和三组预测哈希共同派生，不得重抽。
4. 冻结赛道规范文件存在字节散列/换行差异：清单SHA-256为`1beb31af1e7d1131370ffe6c3f829b897869599cb75dbd42917265da0e1a9c00`，Windows字节SHA-256为`8fb707cb5e2ec0f8edbf3f191f9ce836d259e8a31286466da63e6e62791388fb`，换行标准化SHA-256为`0439eb55cd059300eca9c90c20aaed1901cd8be5e9b556bd4ae2e4609a2f5d5e`。必须在评分授权前解决，但不得修改冻结文件。

### 已排除

- 正式输入中不存在正式评价期训练目标；
- 当前封闭前置入口不会打开或散列`targets.npy`，桥接使用不含训练目标的预测输入类型；
- 当前正式根目录没有意外`.building`、临时或部分文件；
- 版本06已排除停用历史模块本身造成经典模型偏离；
- 当前没有严格嵌套训练授权、消费记录或训练输出，不存在“已训练但未审核”的模糊状态。

### 仍无法确定

- 连续历史候选能否在531流域正式评价中超过两个清洁对照；
- 24次主训练的真实运行时间和真实峰值资源；
- 唯一正式评分最终为通过、暂缓还是拒绝；
- 严格嵌套真实531流域训练能否完成并通过独立重放。

## 7. 当前未完成事项、阻塞原因和最优先下一步

2026-08-04只读核验确认以下路径均不存在：

- `results/26_historical_band_experts/formal_v09/R09-NEST-S100.legacy_checkpoint_bridge_external_audit.json`
- `results/26_historical_band_experts/formal_v09/R09-NEST-S100.training_resource_preflight_external_audit.json`
- `results/26_historical_band_experts/formal_v09/authorizations/A09-NEST-01.authorization.json`
- `results/26_historical_band_experts/formal_v09/authorizations/A09-NEST-01.consumption.json`
- `results/26_historical_band_experts/formal_v09/strict_nesting/R09-NEST-S100`

阻塞原因不是代码缺失，而是用户尚未明确批准包含停止条件的完整严格嵌套阶段。最优先下一步是先完成第8节的只读检查；若无漂移，向用户一次性申请以下完整阶段，不拆成微步骤：运行封闭前置入口；两份报告和资源门通过后创建一次性训练授权；执行随机数100的531流域30轮严格嵌套训练；完成训练后独立审核；任一条件失败立即停止。该申请不包含24次主训练、正式预测或评分。

阶段授权所需的准确直接批准文本为：

> 批准版本09严格嵌套训练阶段；仅授权R09-NEST种子100的一次531流域30轮训练，不批准主实验训练、正式预测或评分。

不得把“继续”“恢复运行”或对其他阶段的批准解释成这段授权。

## 8. 新对话首先检查的文件和命令

先阅读：

1. `docs/plans/2026-08-04-historical-multiscale-formal-v09-strict-stage-handoff.md`
2. `src/26_historical_band_experts/configs/formal_v09_protocol.json`
3. `docs/superpowers/plans/2026-08-02-historical-multiscale-formal-v09-strict-prerequisite-entry.md`
4. `src/26_historical_band_experts/prepare_formal_strict_stage_v09.py`
5. `src/26_historical_band_experts/run_formal_strict_stage_v09.py`
6. `src/26_historical_band_experts/stage_authorization_v09.py`
7. `src/26_historical_band_experts/train_strict_formal_v09.py`
8. `src/26_historical_band_experts/audit_strict_formal_v09.py`

只读执行：

```powershell
$wt = 'G:\github\pycharm\projects\neuralhydrology\.worktrees\historical-band-experts-pilot'
Set-Location -LiteralPath $wt

git branch --show-current
git rev-parse HEAD
git status --short

Get-FileHash -Algorithm SHA256 -LiteralPath 'src\26_historical_band_experts\configs\formal_v09_protocol.json'
Get-FileHash -Algorithm SHA256 -LiteralPath 'results\26_historical_band_experts\formal_v09\input_attempt_01\seal.json'
Get-FileHash -Algorithm SHA256 -LiteralPath 'results\26_historical_band_experts\formal_v09\authorizations\formal_input_seal_authorization.json'
Get-FileHash -Algorithm SHA256 -LiteralPath 'results\26_historical_band_experts\formal_v09\formal_input_seal_authorization_consumed.json'
Get-FileHash -Algorithm SHA256 -LiteralPath 'results\26_historical_band_experts\formal_v09\inputs\training_targets.csv'
Get-FileHash -Algorithm SHA256 -LiteralPath 'results\26_historical_band_experts\formal_v09\inputs\training_targets.manifest.json'
Get-FileHash -Algorithm SHA256 -LiteralPath 'results\26_historical_band_experts\formal_v09\input_attempt_01.external_audit.json'
Get-FileHash -Algorithm SHA256 -LiteralPath 'results\26_historical_band_experts\formal_v09\input_attempt_01.trusted_source_external_audit.json'

$formal = 'results\26_historical_band_experts\formal_v09'
Get-ChildItem -LiteralPath $formal -Force -Recurse |
  Where-Object { $_.Name -like '*.building*' -or $_.Name -like '*.tmp' -or $_.Name -like '*.partial' }

Test-Path -LiteralPath "$formal\R09-NEST-S100.legacy_checkpoint_bridge_external_audit.json"
Test-Path -LiteralPath "$formal\R09-NEST-S100.training_resource_preflight_external_audit.json"
Test-Path -LiteralPath "$formal\authorizations\A09-NEST-01.authorization.json"
Test-Path -LiteralPath "$formal\authorizations\A09-NEST-01.consumption.json"
Test-Path -LiteralPath "$formal\strict_nesting\R09-NEST-S100"

$os = Get-CimInstance Win32_OperatingSystem
[pscustomobject]@{
  AvailablePhysicalBytes = [int64]$os.FreePhysicalMemory * 1KB
  CommitHeadroomBytes = ([int64]$os.FreeVirtualMemory) * 1KB
}
nvidia-smi --query-gpu=index,name,memory.total,memory.free --format=csv,noheader,nounits
```

没有明确完整阶段批准时，不得执行以下两个命令；它们只记录为获批后的固定入口：

```powershell
python src\26_historical_band_experts\prepare_formal_strict_stage_v09.py
python src\26_historical_band_experts\run_formal_strict_stage_v09.py
```

## 9. 可直接粘贴到新对话的下一轮任务提示词

```text
对话名称：历史连续多尺度气象模型正式版本09—严格嵌套阶段恢复

继续审查历史连续多尺度气象模型正式版本09。固定工作区为 G:\github\pycharm\projects\neuralhydrology\.worktrees\historical-band-experts-pilot。

首先完整读取 docs/plans/2026-08-04-historical-multiscale-formal-v09-strict-stage-handoff.md，并以现场只读核验为准。只检查分支、完整HEAD、Git状态、正式阶段授权和两份前置报告是否存在、正式目录是否有意外临时文件或.building目录、交接文档列出的关键SHA-256、可用物理内存、Windows已提交内存余量和设备0图形处理器空闲内存。代码和正式文件无变化时，不重复测试、不重新读取531个来源、不重复逐值复算或独立审核。

未经我对一个完整阶段另行明确批准，不得运行正式前置准备入口、不得创建训练授权、不得训练、不得生成正式预测、不得创建正式评分授权、不得抽取正式256位随机值、不得调用正式评分服务、不得访问正式评价观测，也不得修改正式输入、训练目标、清单、封印、冻结目录或旧评分代码。

若只读状态与交接一致，先给出具体结论、事实、未知和下一条件，然后只申请一个带明确停止条件的完整阶段：运行一次封闭前置入口生成旧模型桥接和真实资源报告；若均通过并再次通过实时资源门，则创建一次性严格嵌套授权，执行随机数100的531流域30轮严格嵌套训练，并完成训练后独立只读审核；任一条件失败即停止。该阶段不包含24次主训练、正式预测或评分。不要请求微步骤批准。
```
