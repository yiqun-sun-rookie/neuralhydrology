# HPC 无缝操作手册（给 AI agent）

**这份文档教你（Claude / 其他 agent）如何在不打扰用户的情况下在河海大学 HPC 上执行命令。**

- 知识库（分区、坑、规章）在 [`HPC_PLAYBOOK.md`](HPC_PLAYBOOK.md)，本文只讲**怎么操作**。
- 建成日期 2026-08-06，通道实测可用。**v2 多通道并发版已于 17:00 实测验证**：
  两个 channel 同一秒启动、互不阻塞（一个 45s sleep，另一个跑 6 分 18 秒的 GPU 作业），
  结果各自正确回传。
- 一句话原理：**堡垒机挡死了一切直连自动化，所以改成让 HPC 主动来 GitHub 取命令。**

---

## 0. 三十秒速览

```
你(本地) --push--> GitHub[hpc-mailbox 分支] <--每20s pull-- HPC 上的 runner2.sh
                                            --push 结果-->
```

**⚠️ 多个任务/会话会同时用这个信箱。你必须用自己的 channel，否则会覆盖别人的命令。**

| 你要做的 | 位置 |
|---|---|
| 选一个 channel 名 | 见 `CHANNELS.md` 登记表，别撞名 |
| 写命令 | `.worktrees/hpc-mailbox/inbox/<channel>/cmd.sh` |
| 触发 | 递增 `inbox/<channel>/seq`，然后 `git pull --rebase` + `git push` |
| 取结果 | 轮询 `outbox/<channel>/result_<seq>.txt` |
| 延迟 | 20 秒一轮 |

不同 channel **并行**执行（默认上限 16），同一 channel 内串行。
所以别人那个等 12 分钟的作业不会挡住你。

并发能开大是因为 worker 在登录节点上只做轻量事（git / sacct / `sleep` 等作业）。
**你的 `cmd.sh` 里绝不能跑计算**——平台明令禁止登录节点跑计算，
而且并发下会拖垮登录节点、影响所有用户。计算一律 `sbatch`。

**用户唯一需要参与的**：会话开始时登录一次 HPC（OTP 在手机上，无法自动化）。
如果 runner 已经在跑，连这一步都不需要。

---

## 1. 开工前：先确认通道活着

**不要假设通道是通的。** 先跑健康检查（纯本地，不需要用户）：

```bash
cd /g/github/pycharm/projects/neuralhydrology/.worktrees/hpc-mailbox && \
git fetch origin hpc-mailbox -q && \
git log --oneline -3 origin/hpc-mailbox && \
echo "--- last result files ---" && \
git ls-tree -r --name-only origin/hpc-mailbox | grep outbox/
```

看 `outbox/result_*.txt` 的最大编号 N，然后发一条探针（见第 2 节）用 `seq=N+1`。
**60 秒内没有 `result_<N+1>.txt` 回来 = runner 没在跑**，跳到第 6 节。

### 如果 worktree 不存在（新克隆的仓库 / 被清理过）

```bash
cd /g/github/pycharm/projects/neuralhydrology && \
git fetch origin hpc-mailbox && \
git worktree add .worktrees/hpc-mailbox hpc-mailbox
```

---

## 2. 发一条命令（标准流程）

### 第 0 步：占一个 channel

先读 `.worktrees/hpc-mailbox/CHANNELS.md`，挑一个**没被占用**的名字，
用任务标识（如 `id05-adversarial`、`id18-lstm-fair`），别用 `test`/`tmp` 这种会撞的。
然后在表里加一行、连同你的第一条命令一起提交。

```bash
mkdir -p inbox/<你的channel> outbox/<你的channel>
```

**绝不要**改 `inbox/<别人的channel>/` 里的任何东西，也不要动遗留的
`inbox/cmd.sh` / `inbox/seq`（那是 v1 的 `default` channel）。

### 第 1 步：写命令

编辑 `.worktrees/hpc-mailbox/inbox/<你的channel>/cmd.sh`。
它会在 **HPC 登录节点**上以 bash 执行，工作目录是 `~/hpc_mailbox`。

```bash
#!/bin/bash
# 说明这一轮要干什么
echo "=== SECTION A ==="
<你的命令>
echo "=== SECTION B ==="
<你的命令>
```

**写法要求**：

- 用 `=== 小节名 ===` 分段，结果回来时好读
- 每条命令自带 `2>&1`，或整体依赖 runner 的重定向（runner 已经 `>> ... 2>&1`）
- **绝不要**写交互式命令（`read`、`vim`、`top`）——没有 TTY，会挂住
- **绝不要**在这里跑计算（平台明令禁止登录节点跑计算），要算就 `sbatch`
- 长输出记得 `| head -N`，结果文件会进 git

### 第 2 步：递增 seq 并推送

```bash
cd /g/github/pycharm/projects/neuralhydrology/.worktrees/hpc-mailbox && \
CH=<你的channel> && \
printf '<N+1>' > inbox/$CH/seq && \
git add inbox/$CH CHANNELS.md && \
git -c core.autocrlf=false commit -q -m "mailbox[$CH]: seq=<N+1> <干什么>" && \
git pull --rebase -q origin hpc-mailbox && \
git push -q origin hpc-mailbox && \
echo "PUSHED $CH seq=$(cat inbox/$CH/seq)"
```

**用 `git add inbox/$CH` 而不是 `git add -A`** —— 后者会把别人 channel 的
临时改动一起提交进去。

**三个必须**：

| 必须 | 为什么 |
|---|---|
| `printf` 而不是 `echo` | 不能有结尾换行，否则 seq 比较会出错 |
| `-c core.autocrlf=false` | Windows 端会把 LF 转 CRLF，传到 HPC 直接 `ExitCode 127` |
| `git pull --rebase` 在 push 前 | HPC 会往同一分支推结果，不 rebase 必被拒 |

`.gitattributes` 里已有 `* text=auto eol=lf` 兜底，但显式加 `-c core.autocrlf=false` 更稳。

### 第 3 步：取结果

```bash
cd /g/github/pycharm/projects/neuralhydrology/.worktrees/hpc-mailbox && \
CH=<你的channel>; N=<N+1>
for i in $(seq 1 10); do
  git fetch origin hpc-mailbox -q 2>/dev/null
  if git ls-tree -r --name-only FETCH_HEAD 2>/dev/null | grep -q "outbox/$CH/result_$N.txt"; then
    echo "=== ARRIVED (poll $i) ==="; break
  fi
  echo "poll $i ..."; sleep 10
done
git show FETCH_HEAD:outbox/$CH/result_$N.txt | head -100
```

**注意 Bash 工具有 2 分钟超时**。轮询超过 11 次会被打断——这不是失败，
再发一次取结果的命令即可。作业类任务（`sbatch` + 等待）通常要轮询好几轮。

---

## 3. 提交计算作业（sbatch）

⚠️ **提交作业会消耗机时，平台是有偿使用的。除非用户明确同意，不要自己提交。**
只读探测（`sinfo`/`sacct`/`ls`/`cat`）不需要问。

模板 —— 在 `cmd.sh` 里提交 + 等待 + 收结果，一轮拿到全部：

```bash
#!/bin/bash
cd ~/hpc_mailbox || exit 1
mkdir -p outbox

echo "=== SUBMIT ==="
JID=$(sbatch --parsable inbox/your_job.slurm 2>&1)
echo "jobid=$JID"

echo "=== WAIT (max 10 min) ==="
for i in $(seq 1 60); do
    LEFT=$(squeue -u "$USER" -h -o "%i" 2>/dev/null | wc -l)
    [ $((i % 3)) -eq 0 ] && echo "t=${i}0s left=$LEFT"
    [ "$LEFT" -eq 0 ] && break
    sleep 10
done

echo "=== RESULT ==="
sacct -j "$JID" -X --format=JobID%10,JobName%14,NodeList%9,State%14,ExitCode%8,Elapsed%10
cat outbox/slurm_${JID}.out 2>/dev/null | tail -40

rm -f outbox/slurm_*.out outbox/slurm_*.err   # 别让日志进 git
```

配套的 `.slurm` 文件也放 `inbox/`，日志输出指向
`/data1/home/sunyiq/hpc_mailbox/outbox/`（**必须绝对路径**）。

现成可复用的例子：`inbox/node_test.slurm`（GPU 节点健康测试）。

### SLURM 脚本骨架

完整版见 [`HPC_PLAYBOOK.md`](HPC_PLAYBOOK.md) 第 4 节。最小可用：

```bash
#!/usr/bin/env bash
#SBATCH -J <name>
#SBATCH -p hgpu2p
#SBATCH -N 1
#SBATCH -n 1
#SBATCH --cpus-per-task=4
#SBATCH --gres=gpu:1
#SBATCH --exclude=ngu002
#SBATCH -t 06:00:00
#SBATCH -o /data1/home/sunyiq/hpc_mailbox/outbox/slurm_%j.out
#SBATCH -e /data1/home/sunyiq/hpc_mailbox/outbox/slurm_%j.err
# 绝不写 --mem

set -eo pipefail                      # 不能带 -u，会杀死 conda activate

source /data1/home/${USER}/miniconda3/etc/profile.d/conda.sh || \
source $HOME/miniconda3/etc/profile.d/conda.sh
conda activate nh_final || { echo "CONDA_FAILED"; exit 1; }

export MKL_THREADING_LAYER=GNU
export MKL_SERVICE_FORCE_INTEL=1

cd ${SLURM_SUBMIT_DIR}
export PYTHONPATH=$(pwd):$PYTHONPATH

python -u <script> <args>             # 直接 python，不套 srun
```

---

## 4. 环境事实速查（2026-08-06 实测）

| 项 | 值 |
|---|---|
| 主机 / 用户 | `hpcbh.hhu.edu.cn` / `sunyiq`，登录节点 `login4` |
| 项目路径 | `~/neuralhydrology` = `/data1/home/sunyiq/neuralhydrology` |
| 信箱路径 | `~/hpc_mailbox` |
| conda 环境 | **`nh_final`** = Python 3.11.13 + torch 2.4.0 |
| GPU | RTX 3090 24GB，驱动 580.76.05 |
| 存储 | `/data1` 954T，已用 62%，余 364T |
| git 版本 | **1.8.3.1**（很老，见下） |
| 仓库分支 | `migration/reorg-v1`，remote 已改 SSH |

### 分区

| 分区 | 节点 | GPU/节点 | 备注 |
|---|---|---|---|
| **`hgpu2p`** | ngu[001-002,004-008,010-011] | 2 | **主力**，9 节点常有 8 个空闲 |
| `hgpu8` | ngu[201-203] | 8 | 常年满载，排队久 |
| `hgpu4` | ngu[101-104] | 4 | ngu103 已 down |
| `hgpu2` | ngu[003,009] | 2 | |
| `hcpu48` | icn[201-264] | 无 | 默认分区，16 个节点 down |

**所有分区 `TIMELIMIT=infinite`**，时长自己定。
**计费按实际申请核数**（`billing=4,cpu=4`），不是整节点。

### 坏节点

**`ngu002`** —— CUDA 初始化失败（只认到 1 张卡）。`sinfo` 仍报 `idle`。
加 `--exclude=ngu002`。

⚠️ **`sinfo` 不体检 GPU**。要确认某节点是否可用，必须真跑一个 CUDA 任务
（复用 `inbox/node_test.slurm`，每节点 20–40 秒）。

### 网络：**都通，但很慢**

| 目标 | 状态 | 实测耗时 |
|---|---|---|
| GitHub SSH (22) | ✅ 通 | 快 |
| GitHub HTTPS (443) | ✅ 通 | **TLS 握手 11s**，总 11.7s |
| `git ls-remote` (HTTPS) | ✅ 成功 | — |
| pypi.org | ✅ 通 | **20s** |
| `pip download` | ✅ **成功** | — |
| gitee / ghproxy 镜像 | ❌ 不通 | — |

conda 已配清华镜像（`~/.condarc`），装包走那边更快。

> ⚠️ **超时不要设短。** 本文档一度写着"HTTPS 不通 / pypi 不通"，
> 那是用 `timeout 10~12` 探测得出的误判——网络只是慢，不是断。
> **在这台机器上探测网络，超时至少给 30 秒**，否则会把"慢"读成"不通"，
> 进而放弃本来可用的通道。

SSH remote 仍然推荐（比 HTTPS 快得多），但不是必需。

### bash 4.2 的坑

**脚本里不要用 `set -u`**。CentOS 7 的 bash 4.2 在 `-u` 下展开空数组
（`${!arr[@]}` / `${#arr[@]}`）会报 `unbound variable` 直接退出，
且各 bash 版本行为不一致，没法靠版本判断兼容。
用 `set -o pipefail`，变量写 `${VAR:-default}`。
（`-u` 还会杀掉 `conda activate`，见 PLAYBOOK 铁律 2。）

### git 1.8.3.1 不支持的语法

| 不能用 | 替代 |
|---|---|
| `git -C <dir>` | 先 `cd` |
| `git branch --show-current` | `git rev-parse --abbrev-ref HEAD` |
| `git switch` / `git restore` | `git checkout` |
| `git worktree` | 不可用 |
| `git fetch origin <branch>` | **静默失败**（只写 FETCH_HEAD）→ 必须 `git fetch origin "+<b>:refs/remotes/origin/<b>"` |

---

## 5. 排错

### 作业失败先看 ExitCode

| ExitCode | 含义 | 查什么 |
|---|---|---|
| `127` | command not found | **CRLF 换行** 或 conda 没激活导致 `python` 不存在 |
| `1` | 程序自己抛异常 | 看 `.err`，是代码问题 |
| `2` | （本项目约定）CUDA 初始化失败 | 换节点，加 `--exclude` |
| `NODE_FAIL` | 真的节点故障 | 少见 |

```bash
sacct -j <JOBID> --format=JobID,State,ExitCode,NodeList,AllocTRES,Elapsed
```

### 作业秒挂且完全没有日志

三个原因，按概率排：
1. CRLF 换行 → `sed -i 's/\r$//' <script>`
2. `-o` 指向的目录不存在 → `mkdir -p`
3. 写了 `--mem` → 删掉

### push 被拒（non-fast-forward）

HPC 推了结果，你落后了。`git pull --rebase origin hpc-mailbox` 再 push。
如果 rebase 报 "cannot pull with rebase: You have unstaged changes"，
先 `git add -A && git commit`。

### 结果一直不回来

按顺序排查：
1. `seq` 是否真的递增了？（`git show origin/hpc-mailbox:inbox/seq`）
2. `outbox/result_<seq>.txt` 是否已存在？runner 按这个判重，存在就不重跑
3. 命令里是否有交互式/阻塞操作？
4. runner 死了 → 第 6 节

---

## 6. runner 死了怎么办（需要用户参与）

**这是唯一必须打扰用户的情况。** 判据：推了新 seq，60 秒以上没有结果文件。

给用户这段话和命令：

> 需要你在 HPC 窗口里粘一条命令重启信箱守护进程。如果窗口已经关了，
> 先在 WSL 终端里 `ssh hpc` 重新登录（静态密码+手机 6 位动态码连着输，
> 中间不加空格；然后在菜单里选登录节点）。

```bash
pgrep -af "hpc_runner_active" || ( cd ~/hpc_mailbox && nohup bash runner2.sh > runner2.log 2>&1 & ) ; sleep 6; pgrep -af "hpc_runner_active"; tail -10 ~/hpc_mailbox/runner2.log
```

**括号不能省** —— `&` 必须只作用于子 shell，否则整条命令链被后台化，
用户一中断就把 runner 带走了。

**进程名是 `hpc_runner_active`（不是 `runner2.sh`）** —— v2 启动后会
`exec` 到 `~/.hpc_runner_active.sh` 这个 git 工作区外的副本，
免得主循环的 `git reset --hard` 覆盖正在执行的脚本文件。

如果连 `~/hpc_mailbox` 都不存在（换了机器 / 被删）：

```bash
git clone --depth 1 --branch hpc-mailbox --single-branch git@github.com:yiqun-sun-rookie/neuralhydrology.git ~/hpc_mailbox && cd ~/hpc_mailbox && git config user.email "yiqun.sun.hydro.gee@gmail.com" && git config user.name "yiqun.sun" && ( nohup bash runner.sh > runner.log 2>&1 & ) ; sleep 6; tail -8 runner.log
```

停止 runner：`pkill -f "bash runner.sh"`

---

## 7. 边界：什么必须先问用户

| 动作 | 是否要问 |
|---|---|
| 只读探测（`sinfo`/`sacct`/`squeue`/`ls`/`cat`/`df`） | ❌ 不用问 |
| `git pull` / 查看仓库状态 | ❌ 不用问 |
| **`sbatch` 提交作业**（消耗机时，平台有偿） | ✅ **必须问** |
| **删除 / 覆盖 HPC 上的文件**（尤其 `results/`、模型权重） | ✅ **必须问** |
| 改 `~/neuralhydrology` 的 git 状态（checkout / reset / 提交） | ✅ **必须问**（HPC 上有 78 个未提交文件） |
| 装软件、改 conda 环境 | ✅ **必须问**（且 pypi 不通，多半做不到） |
| `scancel` 别人的或用户正在跑的作业 | ✅ **必须问** |

**另外两条硬规矩**：

- **禁止在登录节点跑计算**（平台明令）。信箱的 `cmd.sh` 只能做轻量操作，
  重活一律 `sbatch`。
- **不要碰用户的 ControlMaster 会话**。特别是不要用 `ssh -tt` 复用 master——
  会抢走 TTY 把用户踢下线（已实际发生过）。要独立连接必须
  `-o ControlPath=none`，但那样需要密码，做不到。

---

## 8. 一个完整例子

用户说"看看 531 那批结果跑完没有"：

```bash
# 1. 查当前 seq
cd /g/github/pycharm/projects/neuralhydrology/.worktrees/hpc-mailbox
git fetch origin hpc-mailbox -q
git ls-tree -r --name-only origin/hpc-mailbox | grep outbox/   # 假设最大是 result_6
```

```bash
# 2. 写命令
cat > inbox/cmd.sh <<'EOF'
#!/bin/bash
echo "=== SUMMARY FILES ==="
ls -la ~/neuralhydrology/results/10_global_conceptual_model_benchmark/camels_us_531_repro_v01/summary/ 2>&1 | head -20
echo "=== ROW COUNTS ==="
wc -l ~/neuralhydrology/results/10_global_conceptual_model_benchmark/camels_us_531_repro_v01/summary/*.csv 2>&1 | tail -5
echo "=== RECENT JOBS ==="
sacct -S 2026-04-01 -X --format=JobID%10,JobName%16,State%12,Elapsed%10 2>&1 | head -15
EOF
```

```bash
# 3. 推送
printf '7' > inbox/seq && git add -A && \
git -c core.autocrlf=false commit -q -m "mailbox: seq=7 check 531 results" && \
git pull --rebase -q origin hpc-mailbox && git push -q origin hpc-mailbox && echo PUSHED
```

```bash
# 4. 取结果
for i in $(seq 1 8); do
  git fetch origin hpc-mailbox -q 2>/dev/null
  git ls-tree -r --name-only FETCH_HEAD 2>/dev/null | grep -q "outbox/result_7.txt" && { echo ARRIVED; break; }
  sleep 10
done
git show FETCH_HEAD:outbox/result_7.txt | head -60
```

---

## 附：文件位置

| 什么 | 在哪 |
|---|---|
| 本手册 | `docs/hpc/HPC_AGENT_GUIDE.md` |
| 知识库（分区/坑/规章/官方手册对照） | `docs/hpc/HPC_PLAYBOOK.md` |
| 官方用户手册 PDF | `docs/hpc/reference/河海大学高性能计算平台用户手册V4.1.pdf` |
| 本地信箱 worktree | `.worktrees/hpc-mailbox/`（分支 `hpc-mailbox`） |
| HPC 侧信箱 | `~/hpc_mailbox/` |
| 守护脚本 | 信箱分支的 `runner.sh` |
| 可复用的节点体检作业 | 信箱分支的 `inbox/node_test.slurm` |
