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

| channel | 用途 | 登记时间 | 备注 |
|---|---|---|---|
| `default` | v1 遗留的 `inbox/cmd.sh` + `inbox/seq` | 2026-08-06 | **当前被 ID05 对抗攻击任务占用**（`~/adv531`，已跑到 seq=15）。该任务建议迁到 `inbox/adv531/`，迁移前别人不要碰 |
| `a02` | nature_1st 论文实验 A02（目标时刻流量 × 6 种子配对） | 2026-08-06 | 由 Claude 会话占用，包落点 `~/nature_1st_a02`；结果 tar 走 `outbox/a02/` |
| `probe` | 临时探测、环境体检 | 2026-08-06 | 谁都可以用，但结果可能被别人覆盖 |
| `id26-v09-strict` | ID26 历史连续多尺度 v09 严格嵌套阶段（本地内存争用下不可靠，评估迁 HPC） | 2026-08-07 | 由 Claude 会话占用；计划落点 `~/v09_strict`，**不碰 `~/neuralhydrology`**（那里有 78 个未提交文件） |
| `nature1st-hrrr` | nature_1st 小时流量预报战役：HRRR 预报气象可行性探测 | 2026-08-07 | 由 Claude 会话占用；**只读探测阶段**，落点未定，绝不碰 `a02` / `default` / `id26-v09-strict` |
| `id17-film-gate` | ID17 实体感知闸门：EA-LSTM vs FiLM-LSTM 多折多种子 PUB 对比 | 2026-08-05 | 由 Claude 会话占用；计划落点 `~/id17_film_gate`（`~/neuralhydrology` 的本地 clone），**不碰 `~/neuralhydrology` 的 git 状态**（78 个未提交文件），不碰其他 channel |
| `id18-loss-arm` | ID18 目标函数响应独立确认实验 | 2026-08-09 | 落点 `/data1/home/sunyiq/id18_e04_20260809`；不碰 `~/neuralhydrology` 的 Git 状态或其他实验 |
| `id18-weight-merge` | ID18 同种子同轮次长短期记忆网络检查点插值筛选 | 2026-08-26 | 先做只读资格审计；仅在安全数据清单证明物理排除 1989-10-01 至 1999-09-30 后，才可使用独立落点 `/data1/home/sunyiq/id18_weight_merge_20260826` 提交作业；不碰 `~/neuralhydrology` 的 Git 状态、既有实验或其他通道 |
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
