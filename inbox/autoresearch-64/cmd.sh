#!/bin/bash
set -o pipefail
ROOT=~/autoresearch64
BUNDLE=~/hpc_mailbox/inbox/autoresearch-64/payload/a64_update2.tar.gz
echo "=== UPDATE CODE ==="
sha256sum "$BUNDLE" | head -1
echo "expected a186eea99647528557e0795ca04e155466bba917bd011de59e25390236ffcc92"
rm -rf "$ROOT/src/unified_autoresearch"
tar xzf "$BUNDLE" -C "$ROOT" || { echo UNPACK_FAILED; exit 1; }
cd "$ROOT" && git add -A && git commit -q -m "package update: old-git compatible status invocation" 2>&1 | tail -1
git log -1 --format="%h %s"

echo "=== INSTALL pytest INTO AN ISOLATED DIR (nh_final untouched) ==="
source /data1/home/${USER}/miniconda3/etc/profile.d/conda.sh && conda activate nh_final
if [ -d "$ROOT/.pytools/pytest" ]; then echo "already present"; else
  python -m pip install -q --target "$ROOT/.pytools" pytest 2>&1 | tail -4
fi
ls "$ROOT/.pytools" 2>/dev/null | head -5
grep -q "^\.pytools/" "$ROOT/.gitignore" || printf '.pytools/\n' >> "$ROOT/.gitignore"
cd "$ROOT" && git add .gitignore && git commit -q -m "ignore the isolated test tooling directory" 2>&1 | tail -1

echo "=== SANITY: git status form now works on git 1.8.3.1 ==="
cd "$ROOT" && git status --porcelain -z --untracked-files=all >/dev/null 2>&1 && echo "porcelain OK (rc=0)" || echo "porcelain STILL FAILING"

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
cat outbox/slurm_${JID}.out 2>/dev/null | tail -60
echo "---- stderr ----"; cat outbox/slurm_${JID}.err 2>/dev/null | tail -12
rm -f outbox/slurm_${JID}.out outbox/slurm_${JID}.err
