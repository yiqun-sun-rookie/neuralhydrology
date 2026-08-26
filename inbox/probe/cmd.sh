#!/bin/bash
set -o pipefail
echo "=== RECOVER tukf23 result_4 from staging ==="
cd ~/hpc_mailbox || exit 1
git fetch -q origin "+hpc-mailbox:refs/remotes/origin/hpc-mailbox" && \
git reset -q --hard refs/remotes/origin/hpc-mailbox && \
mkdir -p outbox/kalmannet-tukf23 && \
cp -f ~/.hpc_mailbox_staging/kalmannet-tukf23/result_4.txt outbox/kalmannet-tukf23/ && \
git add outbox/kalmannet-tukf23 && \
git commit -q -m "mailbox[kalmannet-tukf23]: result seq=4 (recovered from staging)" && \
git push -q origin HEAD:hpc-mailbox && echo RECOVERED || echo RECOVER_FAILED
