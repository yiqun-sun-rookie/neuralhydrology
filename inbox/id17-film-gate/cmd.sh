#!/bin/bash
# Validation-selected checkpoint analysis: parse inline full-validation medians from training
# logs (free), pick each cell's best epoch among {10,20,30}, submit evals only for missing
# test@selected, and ship per-basin metrics CSVs back through the outbox.
set -o pipefail
cd ~/id17_film_gate || exit 1
source /data1/home/${USER}/miniconda3/etc/profile.d/conda.sh 2>/dev/null || source $HOME/miniconda3/etc/profile.d/conda.sh 2>/dev/null
conda activate nh_final >/dev/null 2>&1

echo "=== A. PARSE VALIDATION CURVES FROM TRAINING LOGS (all 107 val basins, logged every 5 ep) ==="
python - <<'PY'
import re, glob, json
from pathlib import Path
table = {}
for rd in sorted(glob.glob('runs/gate_*_fold*_seed*_*')):
    cell = re.match(r'runs/(gate_\w+?)_\d{4}_\d{4}_\d{4}_ep30', rd)
    name = cell.group(1) if cell else Path(rd).name
    vals = {}
    for line in open(Path(rd)/'output.log', encoding='utf-8', errors='ignore'):
        m = re.search(r'Epoch (\d+) average validation loss.*?NSE: ([0-9.]+)', line)
        if m:
            vals[int(m.group(1))] = float(m.group(2))
    ckpt_eps = [e for e in (10, 20, 30) if (Path(rd)/f'model_epoch{e:03d}.pt').is_file()]
    sel = max((e for e in ckpt_eps if e in vals), key=lambda e: vals[e], default=None)
    table[name] = {'run_dir': rd, 'val': {str(k): v for k, v in sorted(vals.items())}, 'selected_ep': sel}
    v = table[name]['val']
    print(f"{name}: val@10={v.get('10','?')} val@20={v.get('20','?')} val@30={v.get('30','?')} -> SELECT ep{sel}")
json.dump(table, open('/tmp/id17_selection.json', 'w'))
need = [(t['run_dir'], t['selected_ep']) for t in table.values()
        if t['selected_ep'] and not glob.glob(f"{t['run_dir']}/test/model_epoch{t['selected_ep']:03d}/*_metrics.csv")]
json.dump(need, open('/tmp/id17_need_evals.json', 'w'))
print(f"\ncells needing a test eval at selected epoch: {len(need)}")
for rd, ep in need: print(f"  {rd} @ ep{ep}")
PY

echo "=== B. SUBMIT EVAL JOB IF NEEDED ==="
NEED=$(python -c "import json;print(len(json.load(open('/tmp/id17_need_evals.json'))))")
if [ "$NEED" -gt 0 ]; then
  cat > /tmp/id17_sel_evals.slurm <<'SL'
#!/usr/bin/env bash
#SBATCH -J id17-sel
#SBATCH -p hgpu2p
#SBATCH -N 1
#SBATCH -n 1
#SBATCH --cpus-per-task=4
#SBATCH --gres=gpu:1
#SBATCH --exclude=ngu002
#SBATCH -t 06:00:00
#SBATCH -o /data1/home/sunyiq/id17_film_gate/logs/17_entity_awareness_hypernet/sel-%j.out
#SBATCH -e /data1/home/sunyiq/id17_film_gate/logs/17_entity_awareness_hypernet/sel-%j.err
set -eo pipefail
source /data1/home/${USER}/miniconda3/etc/profile.d/conda.sh || source $HOME/miniconda3/etc/profile.d/conda.sh
conda activate nh_final || { echo CONDA_FAILED; exit 1; }
export MKL_THREADING_LAYER=GNU
export MKL_SERVICE_FORCE_INTEL=1
cd ${SLURM_SUBMIT_DIR}
export PYTHONPATH=$(pwd):$PYTHONPATH
python - <<'PYIN'
import json, subprocess
for rd, ep in json.load(open('/tmp/id17_need_evals.json')):
    print(f"[EVAL] {rd} ep{ep}", flush=True)
    subprocess.run(['python', '-u', '-m', 'neuralhydrology.nh_run', 'evaluate',
                    '--run-dir', rd, '--epoch', str(ep), '--period', 'test', '--gpu', '0'], check=True)
print("[SEL-EVALS DONE]")
PYIN
SL
  JID=$(cd ~/id17_film_gate && sbatch --parsable /tmp/id17_sel_evals.slurm 2>&1)
  echo "eval_jobid=$JID"
else
  echo "no evals needed — selection analysis can run immediately"
fi

echo "=== C. SHIP PER-BASIN METRICS CSVs VIA OUTBOX ==="
M=~/hpc_mailbox/outbox/id17-film-gate/metrics
mkdir -p "$M"
N=0
for rd in runs/gate_*_fold*_seed*_*; do
  cell=$(basename "$rd" | sed 's/_2026.*//')
  for ep in 010 020 030; do
    f=$(ls "$rd/test/model_epoch$ep/"*_metrics.csv 2>/dev/null | head -1)
    [ -n "$f" ] && cp "$f" "$M/${cell}_ep${ep}.csv" && N=$((N+1))
  done
done
echo "shipped $N csv files"
ls "$M" | head -5
