#!/bin/bash
# =============================================================================
# HPC 侧信箱守护进程
#
# 作用：轮询 GitHub 上的 hpc-mailbox 分支，发现新的 inbox/cmd.sh 就执行，
#       把输出写进 outbox/result_<seq>.txt 并推回去。
#
# 启动（在 HPC 登录节点上，只需跑一次）：
#   cd ~/hpc_mailbox && nohup bash runner.sh > runner.log 2>&1 &
#
# 停止：
#   pkill -f 'bash runner.sh'
#
# 注意：
#   - HPC 的 git 是 1.8.3.1，不支持 `git -C`，所以全靠 cd
#   - 只在登录节点做 git 操作和轻量命令；重活必须 sbatch（平台铁律）
#   - 这个循环会执行 inbox/cmd.sh 里的任意内容，等于把执行权交给了
#     能往这个分支 push 的人。不用时请 pkill 掉。
# =============================================================================
set -u

MAILBOX_DIR="${MAILBOX_DIR:-$HOME/hpc_mailbox}"
BRANCH="hpc-mailbox"
POLL_INTERVAL="${POLL_INTERVAL:-20}"

cd "$MAILBOX_DIR" || { echo "[FATAL] cannot cd $MAILBOX_DIR"; exit 1; }

echo "=========================================="
echo "[$(date)] mailbox runner started"
echo "[INFO] dir=$MAILBOX_DIR branch=$BRANCH interval=${POLL_INTERVAL}s"
echo "[INFO] host=$(hostname) pid=$$"
echo "=========================================="

# 不再用"启动基线"判重 —— 那会吞掉启动前就已存在的第一条命令。
# 改为：只要 outbox/result_<seq>.txt 不存在，就说明这条还没跑过。
LAST=""

while true; do
    # 【关键】HPC 的 git 是 1.8.3.1：`git fetch origin <branch>` 只写 FETCH_HEAD，
    # 不会更新 refs/remotes/origin/<branch>，导致 reset 永远回到旧 commit。
    # 必须写全 refspec 并加 + 强制更新。
    git fetch -q origin "+${BRANCH}:refs/remotes/origin/${BRANCH}" 2>/dev/null
    git reset -q --hard "refs/remotes/origin/${BRANCH}" 2>/dev/null

    SEQ=""
    [ -f inbox/seq ] && SEQ=$(cat inbox/seq 2>/dev/null)

    if [ -n "$SEQ" ] && [ "$SEQ" != "$LAST" ] && [ ! -f "outbox/result_${SEQ}.txt" ] && [ -f inbox/cmd.sh ]; then
        echo "[$(date)] --- running seq=$SEQ ---"
        mkdir -p outbox

        {
            echo "### seq=$SEQ"
            echo "### host=$(hostname)"
            echo "### started=$(date -Iseconds)"
            echo "### ---------- output ----------"
        } > "outbox/result_${SEQ}.txt"

        bash inbox/cmd.sh >> "outbox/result_${SEQ}.txt" 2>&1
        RC=$?

        {
            echo "### ---------- end ----------"
            echo "### exit_code=$RC"
            echo "### finished=$(date -Iseconds)"
        } >> "outbox/result_${SEQ}.txt"

        git add -A outbox
        git commit -q -m "mailbox: result seq=$SEQ (rc=$RC)" 2>/dev/null

        if ! git push -q origin "$BRANCH" 2>/dev/null; then
            echo "[WARN] push rejected, rebasing and retrying"
            git pull --rebase -q origin "$BRANCH" 2>/dev/null
            git push -q origin "$BRANCH" 2>/dev/null \
                && echo "[OK] pushed after rebase" \
                || echo "[ERROR] push failed twice, will retry next round"
        fi

        echo "[$(date)] --- done seq=$SEQ rc=$RC ---"
        LAST="$SEQ"
    fi

    sleep "$POLL_INTERVAL"
done
