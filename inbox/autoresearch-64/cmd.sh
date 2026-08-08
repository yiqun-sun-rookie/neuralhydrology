#!/bin/bash
set -o pipefail
ROOT=~/autoresearch64
VENV=$ROOT/.venv
source /data1/home/${USER}/miniconda3/etc/profile.d/conda.sh && conda activate nh_final

echo "=== BUILD A REAL ENVIRONMENT WITH THE FROZEN CLUSTER SET ==="
if [ -x "$VENV/bin/python" ] && "$VENV/bin/python" -c "import numpy,pandas,pyarrow" 2>/dev/null; then
  echo "venv already usable"
else
  rm -rf "$VENV"
  python -m venv "$VENV" 2>&1 | tail -3
  "$VENV/bin/python" -m pip install -q --upgrade pip 2>&1 | tail -2
  "$VENV/bin/python" -m pip install --only-binary=:all: \
    "numpy==1.26.4" "pandas==2.2.3" "pyarrow==17.0.0" psutil pytest 2>&1 | tail -6
fi

echo "=== WHAT A CLEAN INTERPRETER RESOLVES (this is exactly what the gate checks) ==="
env -u PYTHONPATH "$VENV/bin/python" -c "
import importlib.metadata as md
for n in ('numpy','pandas','pyarrow','psutil','pytest'):
    try: print('  %s: %s' % (n, md.version(n)))
    except Exception: print('  %s: MISSING' % n)
import numpy,pandas,pyarrow
print('  imported:', numpy.__version__, pandas.__version__, pyarrow.__version__)
"

echo "=== drop the abandoned PYTHONPATH-injection dirs ==="
rm -rf "$ROOT/.pylibs" "$ROOT/.pylibs_probe" "$ROOT/.pytools"
grep -q "^\.venv/" "$ROOT/.gitignore" || printf '.venv/\n' >> "$ROOT/.gitignore"
cd "$ROOT" && git add -A && git commit -q -m "real virtual environment for the frozen cluster dependency set" 2>&1 | tail -1
git log -1 --format="%h %s"

cd ~/hpc_mailbox || exit 1
mkdir -p outbox
echo "=== SUBMIT ==="
JID=$(sbatch --parsable inbox/autoresearch-64/run.slurm 2>&1)
echo "jobid=$JID"
for i in $(seq 1 200); do
    LEFT=$(squeue -j "$JID" -h -o "%i" 2>/dev/null | wc -l)
    [ $((i % 18)) -eq 0 ] && echo "t=$((i*10))s still running"
    [ "$LEFT" -eq 0 ] && break
    sleep 10
done
echo "=== RESULT ==="
sacct -j "$JID" -X --format=JobID%10,State%14,ExitCode%8,Elapsed%10 2>&1
cat outbox/slurm_${JID}.out 2>/dev/null | tail -55
echo "---- stderr ----"; cat outbox/slurm_${JID}.err 2>/dev/null | tail -10
rm -f outbox/slurm_${JID}.out outbox/slurm_${JID}.err
