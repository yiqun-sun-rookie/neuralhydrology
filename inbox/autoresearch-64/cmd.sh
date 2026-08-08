#!/bin/bash
set -o pipefail
ROOT=~/autoresearch64
BUNDLE=~/hpc_mailbox/inbox/autoresearch-64/payload/a64_update.tar.gz
echo "=== UPDATE CODE ==="
sha256sum "$BUNDLE" | head -1
echo "expected b38524556aa9e5d19e5d205ffd4ef84900449ec4cb5b3dac814bf1d674e7c7b0"
rm -rf "$ROOT/src/unified_autoresearch"
tar xzf "$BUNDLE" -C "$ROOT" || { echo "UNPACK_FAILED"; exit 1; }
cd "$ROOT" && git add -A && git commit -q -m "update unified_autoresearch package" 2>&1 | tail -1
git log -1 --format="%h %s"

cd ~/hpc_mailbox || exit 1
mkdir -p outbox
echo "=== SUBMIT ==="
JID=$(sbatch --parsable inbox/autoresearch-64/run.slurm 2>&1)
echo "jobid=$JID"
for i in $(seq 1 150); do
    LEFT=$(squeue -j "$JID" -h -o "%i" 2>/dev/null | wc -l)
    [ $((i % 12)) -eq 0 ] && echo "t=$((i*10))s still running"
    [ "$LEFT" -eq 0 ] && break
    sleep 10
done
echo "=== RESULT ==="
sacct -j "$JID" -X --format=JobID%10,State%14,ExitCode%8,Elapsed%10 2>&1
cat outbox/slurm_${JID}.out 2>/dev/null | tail -70
echo "---- stderr ----"; cat outbox/slurm_${JID}.err 2>/dev/null | tail -12
rm -f outbox/slurm_${JID}.out outbox/slurm_${JID}.err
