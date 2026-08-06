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
| `default` | v1 遗留的 `inbox/cmd.sh` + `inbox/seq` | 2026-08-06 | 向后兼容保留，**新任务不要用** |
| `adv531` | ID05 对抗攻击 531 流域，`~/adv531` 部署 + smoke test | 2026-08-06 | 由另一会话使用中 |
| `probe` | 临时探测、环境体检 | 2026-08-06 | 谁都可以用，但结果可能被别人覆盖 |

**新开 channel 时请在此表加一行并提交**，避免撞名。

## 并发行为

- 不同 channel **并行**执行（最多 4 个）
- 同一 channel 内**串行**（前一条没跑完不会启动下一条）
- 单条命令超过 1 小时会被 `timeout` 杀掉，结果里会写 `### TIMEOUT`

## 注意

- push 前务必 `git pull --rebase`，多个 agent 同时推很常见
- 只改自己 channel 的文件，不要动 `inbox/<别人的channel>/`
- `runner2.sh` 只有在**没有任何 worker 在跑**时才会 `git reset --hard`，
  所以别人的任务跑到一半时你的 push 不会破坏它
