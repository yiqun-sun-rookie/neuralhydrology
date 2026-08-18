#!/bin/bash
# =============================================================================
# HPC 信箱守护进程 v2 —— 多任务并发版
#
# 相比 v1 的改变：
#   1. 多 channel 隔离：inbox/<channel>/{cmd.sh,seq} -> outbox/<channel>/result_<seq>.txt
#      不同任务/会话用不同 channel，互不覆盖。
#   2. 并发：不同 channel 的任务后台并行跑（默认上限 16，可用 MAX_WORKERS 覆盖），
#      一个 channel 里等 12 分钟的作业不再阻塞其他 channel。
#      同一 channel 内严格串行。
#      ⚠️ 并发的前提是 cmd.sh 只做轻量事（git/sacct/sleep 等作业）。
#         登录节点禁止跑计算，真正的计算一律 sbatch。
#   3. 结果先写 git 工作区之外的 staging，push 时才拷进来
#      —— 避免主循环的 `git reset --hard` 把正在写的结果冲掉。
#   4. push 用锁串行化，避免多个 worker 同时 push 打架。
#   5. 自我保护：启动时把自己复制到 $HOME/.hpc_runner_active.sh 再 exec，
#      这样 `git reset --hard` 覆盖仓库里的 runner2.sh 不会影响运行中的进程。
#   6. 向后兼容：旧的 inbox/cmd.sh + inbox/seq 被当作 channel "default"。
#
# 启动：
#   ( cd ~/hpc_mailbox && nohup bash runner2.sh > runner2.log 2>&1 & )
# 停止：
#   pkill -f "hpc_runner_active.sh"; pkill -f "bash runner2.sh"
# =============================================================================
# 【不要加 set -u】两个原因：
#   1. HPC 是 CentOS 7 / bash 4.2。set -u 下展开空关联数组
#      （${!arr[@]} / ${#arr[@]}）会报 unbound variable 直接退出，
#      而且不同 bash 版本行为不一致（4.4 修了一部分，5.x 又不同），
#      靠版本判断等于赌博。本脚本全程用 ${VAR:-default}，不需要 -u。
#   2. set -u 还会让 conda activate 静默退出（见 HPC_PLAYBOOK 铁律 2）。
set -o pipefail

MAILBOX_DIR="${MAILBOX_DIR:-$HOME/hpc_mailbox}"
STAGING="${STAGING:-$HOME/.hpc_mailbox_staging}"
LOCKDIR="${LOCKDIR:-$HOME/.hpc_mailbox_pushlock}"
ACTIVE_COPY="$HOME/.hpc_runner_active.sh"
BRANCH="hpc-mailbox"
POLL_INTERVAL="${POLL_INTERVAL:-20}"
# 并发上限。worker 在登录节点上几乎只做 git / sacct / sleep（等 sbatch），
# 不吃 CPU，所以可以开大。真正的串行点是 push 锁，每次 push 只占几秒。
# 需要更多就启动时覆盖：MAX_WORKERS=32 bash runner2.sh
MAX_WORKERS="${MAX_WORKERS:-16}"
WORKER_TIMEOUT="${WORKER_TIMEOUT:-7200}"   # 单个任务最长 2 小时，防卡死
# 【必须】所有 git 网络操作都要有超时。2026-08-18 教训：仓库文件多到触发 git auto-gc，
# 老 git(1.8.3.1) + 并行存储上打包极慢，无超时的 fetch 会永久卡死主循环，
# 表现为"进程活着、日志不长、远端不动"，极难排查。
GIT_TIMEOUT="${GIT_TIMEOUT:-120}"

# ---- 自我保护：从 git 工作区外的副本运行 ----
if [ "${HPC_RUNNER_DETACHED:-0}" != "1" ]; then
    cp -f "$MAILBOX_DIR/runner2.sh" "$ACTIVE_COPY" 2>/dev/null || \
    cp -f "$0" "$ACTIVE_COPY" 2>/dev/null
    export HPC_RUNNER_DETACHED=1
    exec bash "$ACTIVE_COPY"
fi

cd "$MAILBOX_DIR" || { echo "[FATAL] cannot cd $MAILBOX_DIR"; exit 1; }
mkdir -p "$STAGING"

# 关掉 git 自动打包：仓库里结果文件多，auto-gc 在并行存储上会卡死 fetch（见 GIT_TIMEOUT 注释）
git config gc.auto 0 2>/dev/null
git config gc.autoDetach false 2>/dev/null

echo "=========================================="
echo "[$(date)] mailbox runner v2 started"
echo "[INFO] dir=$MAILBOX_DIR staging=$STAGING"
echo "[INFO] host=$(hostname) pid=$$ workers<=$MAX_WORKERS interval=${POLL_INTERVAL}s"
echo "[INFO] running from detached copy: $ACTIVE_COPY"
echo "=========================================="

# ---- push 锁（mkdir 是原子操作）----
acquire_lock () {
    local tries=0
    while ! mkdir "$LOCKDIR" 2>/dev/null; do
        tries=$((tries+1))
        # 锁超过 5 分钟视为陈旧，强行接管
        if [ -d "$LOCKDIR" ] && [ "$tries" -gt 150 ]; then
            echo "[WARN] stale push lock, taking over"
            rm -rf "$LOCKDIR"; continue
        fi
        sleep 2
    done
}
release_lock () { rm -rf "$LOCKDIR"; }

# ---- worker：执行某个 channel 的一条命令 ----
run_channel () {
    local CH="$1" SEQ="$2" CMD_SRC="$3"
    local WDIR="$STAGING/$CH"
    mkdir -p "$WDIR"

    # 把命令拷出 git 工作区再执行，避免主循环 reset 时把它换掉
    cp -f "$CMD_SRC" "$WDIR/cmd_${SEQ}.sh" 2>/dev/null || return
    local OUT="$WDIR/result_${SEQ}.txt"

    {
        echo "### channel=$CH seq=$SEQ"
        echo "### host=$(hostname)"
        echo "### started=$(date -Iseconds)"
        echo "### ---------- output ----------"
    } > "$OUT"

    timeout "$WORKER_TIMEOUT" bash "$WDIR/cmd_${SEQ}.sh" >> "$OUT" 2>&1
    local RC=$?
    [ $RC -eq 124 ] && echo "### TIMEOUT after ${WORKER_TIMEOUT}s" >> "$OUT"

    {
        echo "### ---------- end ----------"
        echo "### exit_code=$RC"
        echo "### finished=$(date -Iseconds)"
    } >> "$OUT"

    push_result "$CH" "$SEQ"
    rm -f "$WDIR/cmd_${SEQ}.sh"
    echo "[$(date)] done channel=$CH seq=$SEQ rc=$RC"
}

# ---- 只负责把 staging 里已有的结果推上去（可反复重试，不重跑命令）----
push_result () {
    local CH="$1" SEQ="$2"
    local OUT="$STAGING/$CH/result_${SEQ}.txt"
    [ -f "$OUT" ] || return
    acquire_lock
    cd "$MAILBOX_DIR"
    timeout $GIT_TIMEOUT git fetch -q origin "+${BRANCH}:refs/remotes/origin/${BRANCH}" 2>/dev/null
    timeout 60 git reset -q --hard "refs/remotes/origin/${BRANCH}" 2>/dev/null
    mkdir -p "outbox/$CH"
    cp -f "$OUT" "outbox/$CH/result_${SEQ}.txt"
    git add -A outbox
    git commit -q -m "mailbox[$CH]: result seq=$SEQ" 2>/dev/null
    if ! timeout $GIT_TIMEOUT git push -q origin "$BRANCH" 2>/dev/null; then
        # 推不动时先把散落的 outbox 改动收进来再 rebase（防 SLURM 日志边写边长挡住 rebase）
        git add -A outbox && git commit -q -m "mailbox: stray outbox files" 2>/dev/null
        timeout $GIT_TIMEOUT git pull --rebase -q origin "$BRANCH" 2>/dev/null
        timeout $GIT_TIMEOUT git push -q origin "$BRANCH" 2>/dev/null \
            || echo "[ERROR] push failed: $CH/$SEQ (result kept in staging, will retry push only)"
    fi
    release_lock
}

declare -A RUNNING   # channel -> pid

while true; do
    # 回收已结束的 worker（无 set -u，空数组展开是安全的）
    for CH in "${!RUNNING[@]}"; do
        kill -0 "${RUNNING[$CH]}" 2>/dev/null || unset "RUNNING[$CH]"
    done

    # 只有在没有 worker 在跑时才 reset（否则会动到别人的文件）
    if [ ${#RUNNING[@]} -eq 0 ]; then
        acquire_lock
        timeout $GIT_TIMEOUT git fetch -q origin "+${BRANCH}:refs/remotes/origin/${BRANCH}" 2>/dev/null
        timeout 60 git reset -q --hard "refs/remotes/origin/${BRANCH}" 2>/dev/null
        release_lock
    else
        timeout $GIT_TIMEOUT git fetch -q origin "+${BRANCH}:refs/remotes/origin/${BRANCH}" 2>/dev/null
    fi

    # 扫描所有 channel：inbox/<ch>/seq，外加向后兼容的 inbox/seq
    CHANNELS=""
    for d in inbox/*/; do
        [ -f "${d}seq" ] && [ -f "${d}cmd.sh" ] && CHANNELS="$CHANNELS ${d%/}"
    done
    [ -f inbox/seq ] && [ -f inbox/cmd.sh ] && CHANNELS="$CHANNELS inbox"

    for CHDIR in $CHANNELS; do
        CH=$(basename "$CHDIR")
        [ "$CHDIR" = "inbox" ] && CH="default"

        SEQ=$(cat "$CHDIR/seq" 2>/dev/null | tr -d '[:space:]')
        [ -z "$SEQ" ] && continue
        [ -f "outbox/$CH/result_${SEQ}.txt" ] && continue          # 已跑过且已推送
        [ "$CH" = "default" ] && [ -f "outbox/result_${SEQ}.txt" ] && continue  # v1 遗留位置
        [ -n "${RUNNING[$CH]:-}" ] && continue                     # 该 channel 正在跑
        [ ${#RUNNING[@]} -ge "$MAX_WORKERS" ] && continue          # 并发已满

        # 【关键】staging 里已有结果 = 命令跑过但 push 失败（如 DNS 断）。
        # 只重试推送，绝不重跑命令 —— 否则网络故障会把 sbatch 反复执行。
        if [ -f "$STAGING/$CH/result_${SEQ}.txt" ]; then
            echo "[$(date)] --- retry push only: channel=$CH seq=$SEQ ---"
            push_result "$CH" "$SEQ" &
            RUNNING[$CH]=$!
            continue
        fi

        echo "[$(date)] --- start channel=$CH seq=$SEQ ---"
        run_channel "$CH" "$SEQ" "$CHDIR/cmd.sh" &
        RUNNING[$CH]=$!
    done

    sleep "$POLL_INTERVAL"
done
