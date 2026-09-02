# 信箱 channel 登记表

多个任务/会话同时用这个信箱时，**每个任务必须占用自己的 channel**，
否则会互相覆盖 `inbox/cmd.sh`（v1 的单通道设计已废弃）。

## 目录约定

```
inbox/<channel>/cmd.sh      你要执行的命令
inbox/<channel>/seq         递增的序号（纯数字，无结尾换行）
outbox/<channel>/result_<seq>.txt   结果
```

## 起 channel 名的规矩

用**任务标识**，不要用 `test` / `tmp` / `my` 这种谁都可能撞的名字。推荐格式：

- `id05-adversarial`
- `id18-lstm-fair`
- `id07-hydroagent`
- `probe`（临时探测、一次性问题）

## 已登记的 channel

| `id30-modern-moe-execution` | CAMELS-US 现代因果注意力模型与稀疏混合专家模型的安全数据构建、资源探针和开发期训练 | 2026-08-27 | 独立落点 `/data1/home/sunyiq/id30_modern_transformer_moe_20260827`；仅操作本通道和该目录，不碰 `~/neuralhydrology`、封存评估答案、其他通道或既有实验 |

| channel | 用途 | 登记时间 | 备注 |
|---|---|---|---|
| `default` | v1 遗留的 `inbox/cmd.sh` + `inbox/seq` | 2026-08-06 | **当前被 ID05 对抗攻击任务占用**（`~/adv531`，已跑到 seq=15）。该任务建议迁到 `inbox/adv531/`，迁移前别人不要碰 |
| `a02` | nature_1st 论文实验 A02（目标时刻流量 × 6 种子配对） | 2026-08-06 | 由 Claude 会话占用，包落点 `~/nature_1st_a02`；结果 tar 走 `outbox/a02/` |
| `probe` | 临时探测、环境体检 | 2026-08-06 | 谁都可以用，但结果可能被别人覆盖 |
| `id26-v09-strict` | ID26 历史连续多尺度 v09 严格嵌套阶段（本地内存争用下不可靠，评估迁 HPC） | 2026-08-07 | 由 Claude 会话占用；计划落点 `~/v09_strict`，**不碰 `~/neuralhydrology`**（那里有 78 个未提交文件） |
| `nature1st-hrrr` | nature_1st 小时流量预报战役：HRRR 预报气象可行性探测 | 2026-08-07 | 由 Claude 会话占用；**只读探测阶段**，落点未定，绝不碰 `a02` / `default` / `id26-v09-strict` |
| `id17-film-gate` | ID17 实体感知闸门：EA-LSTM vs FiLM-LSTM 多折多种子 PUB 对比 | 2026-08-05 | 由 Claude 会话占用；计划落点 `~/id17_film_gate`（`~/neuralhydrology` 的本地 clone），**不碰 `~/neuralhydrology` 的 git 状态**（78 个未提交文件），不碰其他 channel |
| `id18-loss-arm` | ID18 目标函数响应独立确认实验 | 2026-08-09 | 落点 `/data1/home/sunyiq/id18_e04_20260809`；不碰 `~/neuralhydrology` 的 Git 状态或其他实验 |
| `id18-weight-merge` | ID18 同种子目标专门化长短期记忆网络参数冲突消解筛选 | 2026-08-26 | 使用 Trim-Elect-Sign-and-Merge 完整方法及移除符号选举的关键消融；只使用物理排除 1989-10-01 至 1999-09-30 的24流域执行包；独立落点 `/data1/home/sunyiq/id18_ties_merge_20260826`；不碰 `~/neuralhydrology` 的 Git 状态、既有实验或其他通道 |
| `autoresearch-64` | 统一自动科研纵向：64 流域数据底座 + 单候选运行 | 2026-08-08 | 工作目录 `~/autoresearch64`，不碰 `~/neuralhydrology` 与 `~/adv531` |
| `camels-g2-design` | CAMELS-US 531 流域参数切换辨认第二阶段冻结前探索性设计运行 | 2026-08-08 | 工作目录 `~/camels_g2_design_20260808`；只用设计种子 0/1，不碰 `~/neuralhydrology` 的 git 状态或其他实验 |
| `id29-nearing2022-da` | 复现 Nearing 2022 变分同化 vs 自回归（CAMELS-US 531，三条臂） | 2026-08-08 | 由 Claude 会话占用；落点待定，**不碰 `~/neuralhydrology`** |
| `kalmannet-tukf06` | Kalmannet 逐状态过程噪声与量测噪声的有界采样搜索和反向传播公平比较 | 2026-08-09 | 计划落点 `/data1/home/sunyiq/kalmannet_tukf06_20260809`；只操作本通道和该独立目录，不碰 `~/neuralhydrology` 的 Git 状态及其他实验 |
| `id23-dlimm` | ID23 深度学习交互多模型（DL-IMM）：H19 预报证据层复现与模型加厚训练 | 2026-08-18 | 由 Claude 会话占用；落点 `~/id23_dlimm`（独立浅克隆），**不碰 `~/neuralhydrology`** 与其他 channel |
| `zhenjiang-stage-r2` | 大通水位事件稳定性覆盖不足第二次技术独立审核迁移 | 2026-08-19 | 独立落点 `/data1/home/sunyiq/zhenjiang_stage_direction_r2_20260819`；仅中央处理器、禁止图形处理器/训练/预测包/目标/误差访问，不碰 `~/neuralhydrology`、其他通道或实验。**该迁移已失败停用，落点与 `outbox/zhenjiang-stage-r2/` 作为失败证据冻结保留，不清理、不续跑** |
| `zhenjiang-oyv-qual` | 镇江—江阴跨年份样本外验证：超算运行环境资格认定（合成数据烟测，不含任何真实站点数据） | 2026-08-19 | 由 Claude 会话占用；独立落点 `/data1/home/sunyiq/zhenjiang_oyv_qual_20260819`；**不碰** `zhenjiang-stage-r2` 的落点与结果、`~/neuralhydrology`、其他通道或实验 |
| `kalmannet-tukf19` | 八状态水文模型滚动起点正式比较的超算迁移、训练、核验与取回 | 2026-08-23 | 独立落点 `/data1/home/sunyiq/kalmannet_tukf19_20260823`；仅操作本通道和该目录，不碰 `~/neuralhydrology`、其他通道、其他实验或既有证据 |
| `kalmannet-tukf20` | 八状态水文模型在每日状态更新内部联合学习水文参数与滤波噪声的正式比较 | 2026-08-24 | 独立落点 `/data1/home/sunyiq/kalmannet_tukf20_20260824`；仅操作本通道和该目录，不碰原超算仓库、其他通道、旧实验或旧证据 |
| `kalmannet-daily-camels` | CAMELS 日尺度原生卡尔曼网络恢复与小规模训练冒烟 | 2026-08-24 | 独立落点 `/data1/home/sunyiq/kalmannet_daily_camels_20260824`；先独立显卡探针，探针通过前不训练；不碰小时尺度、其他通道、旧实验或旧证据 |
| `zhenjiang-oyv-n4` | 镇江六站四目标站观测条件阶梯（南京、徐六泾）：1440 次训练与预登记预测判定 | 2026-08-25 | 由 Claude 会话占用；落点 `/data1/home/sunyiq/zhenjiang_oyv_v1/`（沿用 OYV 部署包，新子目录 `n4_tasks/`）；**不碰** `tasks/`、`ladder_tasks/`、`independent_audit*/`、`ladder_audit/` 等已冻结产物，不碰 `~/neuralhydrology`、其他通道或其他会话的作业 |
| `zhenjiang-latent-da` | 镇江六站共享抽象潜在状态门控循环单元与 KalmanNet 数据同化：独立部署、烟测和后续冻结训练 | 2026-08-27 | 独立落点 `/data1/home/sunyiq/zhenjiang_latent_da_20260827`；先只读探测与短时烟测，不读取留出年份目标作模型选择，不碰 `zhenjiang_oyv_v1` 既有结果、`~/neuralhydrology`、其他通道或其他实验 |
| `zhenjiang-d32-diff-ukf` | 镇江六站32维门控循环单元可微无迹卡尔曼滤波：隔离的2017—2023数据、图形处理器烟测和三模型开发训练 | 2026-08-28 | 独立落点 `/data1/home/sunyiq/zhenjiang_d32_differentiable_ukf_20260828`；禁止读取2024年及以后目标，不覆盖既有目录/任务，不碰 `~/neuralhydrology`、其他通道或其他实验 |
| `id30-modern-moe-audit` | CAMELS-US 现代因果 Transformer 与稀疏混合专家实验的远程数据和既有模型只读盘点 | 2026-08-27 | 只读检查 `/data1/home/sunyiq/neuralhydrology` 的数据目录、配置、检查点、内部验证产物和作业状态；不读取封存评估答案，不改远程仓库，不提交训练，不碰其他通道或实验 |
| `id30-modern-moe-audit-aux` | CAMELS-US 现代因果 Transformer 与稀疏混合专家远程盘点的辅助只读通道 | 2026-08-27 | 主通道在首次回执后静默延迟时，仅执行限深的目录和检查点查询；不读取结果内容，不改远程仓库，不提交训练，不碰其他通道或实验 |
| `id30-modern-moe-checkpoints` | CAMELS-US 现代因果 Transformer 与稀疏混合专家盘点中的现有长短期记忆网络检查点核对 | 2026-08-27 | 两个已用盘点通道在首次回执后均未释放；本通道仅精确统计三个已发现结果根的检查点、配置和缩放器，不打开模型或结果载荷，不改远程仓库，不提交训练 |
| `kalmannet-tukf25` | 反向切分新抽27流域四臂正式验证：部署、锚点门、训练阵列、封条单次开封读出与取回 | 2026-08-31 | 独立落点 `/data1/home/sunyiq/kalmannet_tukf25_20260831`；仅操作本通道和该目录，不碰 `~/neuralhydrology`、其他通道、其他实验或既有证据 |
| `kalmannet-tukf26` | 训练年份探针：正向切分 2 年对 6.4 年，联合学习过拟合是否随数据量收窄 | 2026-08-31 | 独立落点 `/data1/home/sunyiq/kalmannet_tukf26_20260831`；仅操作本通道和该目录，不碰 `~/neuralhydrology`、其他通道、其他实验或既有证据 |
| `kalmannet-tukf27` | 开环隔离探针：同一套参数学习机制去掉每日同化直接学，2×2 定位病灶 | 2026-09-01 | 独立落点 `/data1/home/sunyiq/kalmannet_tukf27_20260901`；仅操作本通道和该目录，不碰 `~/neuralhydrology`、其他通道、其他实验或既有证据 |
| `kalmannet-tukf09-455` | 全对角噪声无迹卡尔曼滤波与三个随机种子长短期记忆网络的455流域修订实验：隔离部署、训练与核验 | 2026-08-31 | 独立落点 `/data1/home/sunyiq/kalmannet_tukf09_455_basin_zero_validation_target_variance_revision_v1_20260831`；仅操作本通道和该目录，不覆盖原456流域实验，不碰 `~/neuralhydrology`、其他通道、其他实验或既有证据；正式评价仍受独立门禁约束 |
| `id29-transferable-noise` | 可迁移滤波噪声线(拟 ID29):反归一化对照(52 开发流域 52×52 绝对噪声互借)与 391 保留流域追加 4 个手拍网格臂;纯 CPU 滤波 | 2026-09-02 | 独立落点 `/data1/home/sunyiq/id29_transferable_noise_20260902`;仅操作本通道与该目录,只读引用 `~/neuralhydrology/data/camels_us`(符号链接),不碰 `~/neuralhydrology` 的 Git 状态、其他通道、其他实验或既有证据;作业日志写入落点不写信箱 |

**迁移方法**（`default` → 自己的 channel，随时可做，不影响正在跑的）：

```bash
mkdir -p inbox/<新channel>
git mv inbox/cmd.sh inbox/<新channel>/cmd.sh
echo -n "<当前seq>" > inbox/<新channel>/seq
git rm inbox/seq
```

注意新 channel 的 seq 要么延续旧编号，要么从 1 开始都行——
判重是按 `outbox/<channel>/result_<seq>.txt` 是否存在，各 channel 独立。

**新开 channel 时请在此表加一行并提交**，避免撞名。

## 并发行为

- 不同 channel **并行**执行，默认上限 **16 个**
- 同一 channel 内**串行**（前一条没跑完不会启动下一条）
- 单条命令超过 **2 小时**会被 `timeout` 杀掉，结果里会写 `### TIMEOUT`

需要更高并发，启动时覆盖：

```bash
( cd ~/hpc_mailbox && MAX_WORKERS=32 nohup bash runner2.sh > runner2.log 2>&1 & )
```

**并发能开大的前提**：`cmd.sh` 只做轻量操作（git / sacct / squeue / 文件检查 /
`sleep` 等作业完成）。这些几乎不占 CPU。
**登录节点禁止跑计算**（平台明令），真正的计算一律 `sbatch` 交给计算节点。
如果有人在 `cmd.sh` 里跑 CPU 密集的东西，并发开大会拖垮登录节点、影响所有用户。

## 注意

- push 前务必 `git pull --rebase`，多个 agent 同时推很常见
- 只改自己 channel 的文件，不要动 `inbox/<别人的channel>/`
- `runner2.sh` 只有在**没有任何 worker 在跑**时才会 `git reset --hard`，
  所以别人的任务跑到一半时你的 push 不会破坏它
| `nature1st-attr-swap` | nature_1st 属性来源替换实验（12 项美国专有属性 vs 13 项 HydroATLAS 全球属性，对照组与实验组各一次 40 轮训练） | 2026-08-19 | 由 Claude 会话占用；落点 `/data1/home/sunyiq/nature_1st`，**不碰** `~/nature_1st_a02`、`~/neuralhydrology` 与其他通道 |
| `kuwei-paired-recal` | laos_forecast 库尾流域成对降雨处理重新率定（两种降雨输入各自率定 17 参数 × 3 种子 = 6 次，纯单线程 CPU，无需 GPU） | 2026-08-25 | 由 Claude 会话占用；只碰自己的 channel 与自建落点，**不碰** `~/neuralhydrology`、`~/nature_1st` 及其他通道 |
| `kuwei-recal-aux` | 同上任务的辅助只读通道（主通道 `kuwei-paired-recal` 卡住时用来查作业状态，不写任何东西） | 2026-08-25 | 由同一 Claude 会话占用 |
| `kalmannet-tukf23` | TUKF23 真实流域四方式正式实验：CPU 分区探测与部署 | 2026-08-26 | 由 Claude 会话占用；计划落点 `/data1/home/sunyiq/kalmannet_tukf23_20260826`；只操作本通道与该独立目录，不碰 `~/neuralhydrology` 的 Git 状态及其他实验 |
| `kalmannet-tukf24` | TUKF24 预报时段拉长第二步：1–10 日损失重训部署 | 2026-08-27 | 由 Claude 会话占用；落点 `/data1/home/sunyiq/kalmannet_tukf24_20260827`；只操作本通道与该独立目录，不碰 TUKF23 落点、`~/neuralhydrology` 的 Git 状态及其他实验 |
| `id30-modern-moe-status-refresh` | CAMELS-US 现代因果 Transformer 与稀疏混合专家种子100顺序链的只读状态刷新 | 2026-08-28 | 仅查询隔离落点 `/data1/home/sunyiq/id30_modern_transformer_moe_20260827/repo` 的既有作业、开发期登记和内部验证产物；不提交作业、不修改远程文件、不访问封存评估答案 |
| `id31-hydrologic-dynamic-tokens` | CAMELS-US 基于允许气象输入自适应划分连续时间词元的因果 Transformer：隔离部署、图形处理器资源探针和开发期公平对照 | 2026-08-28 | 独立落点 `/data1/home/sunyiq/id31_hydrologic_dynamic_tokens_20260828`；仅使用 ID30 已审计的候选安全气象与监督数据包；先探针后训练；不修改 ID30、不访问封存评估、不调用正式评分服务 |
| `kuwei-jdl-seedbatch` | laos_forecast 库尾滤波学习的学习随机数扩充批：先跑锚点分解诊断，再跑固定起点 × 三条学习路线 × 多个学习随机数的稳定性批（纯单线程 CPU，无需 GPU） | 2026-08-31 | 由 Claude 会话占用；独立落点 `/data1/home/sunyiq/kuwei_jdl_seedbatch_20260831`；**不碰** `~/kuwei_paired`（既有门禁作业证据）、`~/neuralhydrology`、`~/nature_1st`、`~/zhenjiang_*`、`~/kalmannet_*`、`~/id3*` 及其他通道 |
| `kalmannet-daily-perbasin` | 日尺度 CAMELS 三个逐流域 KalmanNet 开发期试点：只读资源核查、隔离部署、严格串行训练与开发期核验 | 2026-09-01 | 独立落点前缀 `/data1/home/sunyiq/kalmannet_daily_camels_per_basin_pilots_20260901`；不访问正式评价，不碰其他通道、作业、实验或既有证据 |
| `zhenjiang-six-source-four-target-ukf` | 镇江六个实时观测来源、四个内部预报目标的共享32维门控循环单元可微无迹卡尔曼滤波重新训练与2023冻结开发评价 | 2026-09-01 | 独立落点 `/data1/home/sunyiq/zhenjiang_six_source_four_target_differentiable_ukf_20260901_r1`；只操作本通道与该新建目录，旧镇江目录和通道只读，不复制大通或吴淞口未来目标，不访问2024年及以后目标，不碰 `~/neuralhydrology`、其他通道、作业或实验 |
| `kalmannet-wrr-lr-boundary` | 《水资源研究》论文学习率上边界核查：本地原批次继续运行，超算只重复本地已完成的学习率0.01作为公共核验 | 2026-09-01 | 独立落点 `/data1/home/sunyiq/kalmannet_wrr_lr_boundary_20260901`；超算不得运行其他学习率，不读取保留测试集，不碰 `~/neuralhydrology`、其他通道、作业、实验或既有证据 |
| `kalmannet-tukf09-455-monitor` | 455 流域修订实验新版超算运行依赖下载的只读辅助监控 | 2026-09-01 | 只读取 v2r5 独立落点的进程、文件计数、字节数和下游零输出门控；不写实验目录、不提交或结束作业、不访问正式评价、不触碰主通道或其他实验 |
| `id23-r-pert` | ID23 噪声轴观测噪声(R)扰动稳健性检验:A0 平价门 + A1/A1m/A2/A3/A4 五臂 | 2026-09-02 | 由 Claude 会话占用;独立落点 `/data1/home/sunyiq/id23_r_perturbation`,作业名前缀 `r_pert_*`;**不碰 `~/neuralhydrology` 的 git 状态**、不碰 `id23-dlimm` 或任何其他通道;⛔ 禁用 `scancel -u` 等账号级批量取消 |
| `kalmannet-wrr-hp-extension` | 《水资源研究》论文超参数扩展（Hamid 第 20 条）：2025 网格 60 个检查点在本地同代码重评；超算只训练 0.01 以上学习率所需的同代码锚点与新格点、两类边界探针和种子复制 | 2026-09-02 | 独立落点 `/data1/home/sunyiq/kalmannet_wrr_hp_extension_20260902`；只操作本通道与该目录，旧落点 `kalmannet_wrr_lr_boundary_20260901` 只读；不读取保留测试集，不碰 `~/neuralhydrology`、`~/kalmannet`、`~/knet_project` 内容、其他通道、作业、实验或既有证据；⛔ 禁用账号级批量取消 |
