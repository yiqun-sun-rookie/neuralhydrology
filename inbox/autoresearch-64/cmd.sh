#!/bin/bash
set -o pipefail
ROOT=~/autoresearch64
BUNDLE=~/hpc_mailbox/inbox/autoresearch-64/payload/a64_update3.tar.gz
source /data1/home/${USER}/miniconda3/etc/profile.d/conda.sh && conda activate nh_final

echo "=== UPDATE CODE ==="
sha256sum "$BUNDLE" | head -1; echo "expected ef425e5700a414b53c552f88189b48135635035c95384aa96e29e8d2275bc52b"
rm -rf "$ROOT/src/unified_autoresearch"
tar xzf "$BUNDLE" -C "$ROOT" || { echo UNPACK_FAILED; exit 1; }

echo "=== INSTALL THE FROZEN CLUSTER SET INTO AN ISOLATED DIR ==="
if [ -d "$ROOT/.pylibs/numpy" ]; then echo "already installed"; else
  rm -rf "$ROOT/.pylibs" "$ROOT/.pylibs_probe"
  python -m pip install -q --only-binary=:all: --target "$ROOT/.pylibs"     "numpy==1.26.4" "pandas==2.2.3" "pyarrow==17.0.0" 2>&1 | tail -4
fi
PYTHONPATH="$ROOT/.pylibs" python -c "import numpy,pandas,pyarrow;print('isolated set:',numpy.__version__,pandas.__version__,pyarrow.__version__)"
grep -q "^\.pylibs" "$ROOT/.gitignore" || printf '.pylibs/\n.pylibs_probe/\n' >> "$ROOT/.gitignore"
cd "$ROOT" && git add -A && git commit -q -m "package update: frozen cluster dependency set" 2>&1 | tail -1
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
cat outbox/slurm_${JID}.out 2>/dev/null | tail -55
echo "---- stderr ----"; cat outbox/slurm_${JID}.err 2>/dev/null | tail -10
rm -f outbox/slurm_${JID}.out outbox/slurm_${JID}.err
