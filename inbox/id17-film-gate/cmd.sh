#!/bin/bash
# FIX: /tmp is node-local — the eval job on the compute node cannot see login4's /tmp files.
# Regenerate the need-evals list into the SHARED filesystem and resubmit.
set -o pipefail
cd ~/id17_film_gate || exit 1
source /data1/home/${USER}/miniconda3/etc/profile.d/conda.sh 2>/dev/null || source $HOME/miniconda3/etc/profile.d/conda.sh 2>/dev/null
conda activate nh_final >/dev/null 2>&1

echo "=== A. STATUS OF THE BROKEN JOB 202559 ==="
sacct -j 202559 -X --format=JobID%12,State%12,ExitCode%8,Elapsed%10 2>&1
scancel 202559 2>/dev/null; echo "(cancelled if still queued)"

echo "=== B. REGENERATE NEED-EVALS INTO SHARED FS ==="
mkdir -p _sel
python - <<'PY'
import re, glob, json
from pathlib import Path
need = []
for rd in sorted(glob.glob('runs/gate_*_fold*_seed*_*')):
    vals = {}
    for line in open(Path(rd)/'output.log', encoding='utf-8', errors='ignore'):
        m = re.search(r'Epoch (\d+) average validation loss.*?NSE: ([0-9.]+)', line)
        if m: vals[int(m.group(1))] = float(m.group(2))
    eps = [e for e in (10, 20, 30) if (Path(rd)/f'model_epoch{e:03d}.pt').is_file() and e in vals]
    sel = max(eps, key=lambda e: vals[e], default=None)
    if sel and not glob.glob(f"{rd}/test/model_epoch{sel:03d}/*_metrics.csv"):
        need.append([rd, sel])
json.dump(need, open('_sel/need_evals.json', 'w'))
print(f"need {len(need)} evals -> _sel/need_evals.json")
PY

echo "=== C. RESUBMIT WITH SHARED-FS PATH ==="
cat > _sel/sel_evals.slurm <<'SL'
#!/usr/bin/env bash
#SBATCH -J id17-sel2
#SBATCH -p hgpu2p
#SBATCH -N 1
#SBATCH -n 1
#SBATCH --cpus-per-task=4
#SBATCH --gres=gpu:1
#SBATCH --exclude=ngu002
#SBATCH -t 06:00:00
#SBATCH -o /data1/home/sunyiq/id17_film_gate/logs/17_entity_awareness_hypernet/sel2-%j.out
#SBATCH -e /data1/home/sunyiq/id17_film_gate/logs/17_entity_awareness_hypernet/sel2-%j.err
set -eo pipefail
source /data1/home/${USER}/miniconda3/etc/profile.d/conda.sh || source $HOME/miniconda3/etc/profile.d/conda.sh
conda activate nh_final || { echo CONDA_FAILED; exit 1; }
export MKL_THREADING_LAYER=GNU
export MKL_SERVICE_FORCE_INTEL=1
cd ${SLURM_SUBMIT_DIR}
export PYTHONPATH=$(pwd):$PYTHONPATH
python - <<'PYIN'
import json, subprocess
for rd, ep in json.load(open('_sel/need_evals.json')):
    print(f"[EVAL] {rd} ep{ep}", flush=True)
    subprocess.run(['python', '-u', '-m', 'neuralhydrology.nh_run', 'evaluate',
                    '--run-dir', rd, '--epoch', str(ep), '--period', 'test', '--gpu', '0'], check=True)
print("[SEL-EVALS DONE]")
PYIN
SL
JID=$(sbatch --parsable _sel/sel_evals.slurm 2>&1)
echo "eval_jobid=$JID"
sleep 20
sacct -j "$JID" -X --format=JobID%12,State%12,NodeList%9 2>&1
