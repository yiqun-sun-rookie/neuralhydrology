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
| `autoresearch-64` | 统一自动科研纵向：64 流域数据底座 + 单候选运行 | 2026-08-08 | 工作目录 `~/autoresearch64`，不碰 `~/neuralhydrology` 与 `~/adv531` |
| `camels-g2-design` | CAMELS-US 531 流域参数切换辨认第二阶段冻结前探索性设计运行 | 2026-08-08 | 工作目录 `~/camels_g2_design_20260808`；只用设计种子 0/1，不碰 `~/neuralhydrology` 的 git 状态或其他实验 |
| `id29-nearing2022-da` | 复现 Nearing 2022 变分同化 vs 自回归（CAMELS-US 531，三条臂） | 2026-08-08 | 由 Claude 会话占用；落点待定，**不碰 `~/neuralhydrology`** |

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
