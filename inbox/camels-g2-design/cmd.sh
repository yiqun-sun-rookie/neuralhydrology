#!/bin/bash
set -eo pipefail

ROOT="$HOME/camels_g2_design_20260808"
REPO="$ROOT/repo"
PAYLOAD="$HOME/hpc_mailbox/inbox/camels-g2-design/payload"
BRANCH="codex/camels-rising-half-recal"
EXPECTED_COMMIT="61e938b3a89f648e460a20e6f03e005bdc9fca4a"
SMOKE_TAG="smoke1_widebank_q1e7_s01_20260808"

echo "=== GUARDS ==="
date -Is
if [ -e "$ROOT" ]; then
  echo "FATAL isolated root already exists: $ROOT"
  exit 20
fi
if squeue -u "$USER" -h -o '%j' | grep -Fxq 'camg2smk'; then
  echo "FATAL smoke job name already present"
  exit 21
fi

echo "=== CREATE ISOLATED CHECKOUT ==="
mkdir -p "$ROOT/logs"
git clone -q --branch "$BRANCH" --single-branch \
  git@github.com:yiqun-sun-rookie/neuralhydrology.git "$REPO"
cd "$REPO"
ACTUAL_COMMIT=$(git rev-parse HEAD)
ACTUAL_BRANCH=$(git rev-parse --abbrev-ref HEAD)
echo "commit=$ACTUAL_COMMIT branch=$ACTUAL_BRANCH"
[ "$ACTUAL_COMMIT" = "$EXPECTED_COMMIT" ] || { echo "FATAL commit mismatch"; exit 22; }
[ "$ACTUAL_BRANCH" = "$BRANCH" ] || { echo "FATAL branch mismatch"; exit 23; }

echo "=== INSTALL READ-ONLY INPUT LINKS AND COPIES ==="
[ -d "$HOME/neuralhydrology/data/camels_us" ] || { echo "FATAL shared data missing"; exit 24; }
[ ! -e "$REPO/data" ] || { echo "FATAL clone unexpectedly contains data path"; exit 25; }
ln -s "$HOME/neuralhydrology/data" "$REPO/data"
mkdir -p \
  "$REPO/results/10_global_conceptual_model_benchmark/camels_us_531_repro_v01/summary" \
  "$REPO/results/23_camels_switch_confirmation/g1_precheck_v01"
cp "$PAYLOAD/hbv_lite_cma_rising_local_full.csv" \
  "$REPO/results/10_global_conceptual_model_benchmark/camels_us_531_repro_v01/summary/"
cp "$PAYLOAD/g1_precheck.csv" "$PAYLOAD/g1_precheck.metadata.json" \
  "$REPO/results/23_camels_switch_confirmation/g1_precheck_v01/"

echo "=== INPUT HASHES ==="
echo '577b12fcb8e1a7a7a607995f0011dbda38a199ee68f3636732b80a3356c16be6  results/10_global_conceptual_model_benchmark/camels_us_531_repro_v01/summary/hbv_lite_cma_rising_local_full.csv' | sha256sum -c -
echo '3443ba601434dd30b43c3b5e8a9b838fc666cc394077700ddd4d3e7158b3ee73  results/23_camels_switch_confirmation/g1_precheck_v01/g1_precheck.csv' | sha256sum -c -
echo 'f71777f76869a8e1d3bd268ec01614bc5a51a815c0dfbceaf9447c608d022c5b  results/23_camels_switch_confirmation/g1_precheck_v01/g1_precheck.metadata.json' | sha256sum -c -

echo "=== SOURCE CONTRACT ==="
source /data1/home/${USER}/miniconda3/etc/profile.d/conda.sh || source "$HOME/miniconda3/etc/profile.d/conda.sh"
conda activate nh_final
export PYTHONPATH="$REPO/src:$REPO:${PYTHONPATH:-}"
python - <<'PY'
from src.camels_switch_confirmation.bank import FC_FACTORS
from src.camels_switch_confirmation.g1_precheck import N_SEEDS, ROTATION, WINDOW_DAYS
from src.camels_switch_confirmation.g2_switch_confirmation import PROCESS_VARIANCE_SCALE
assert FC_FACTORS == (1.0, 0.5, 2.0), FC_FACTORS
assert N_SEEDS == 2, N_SEEDS
assert ROTATION == (0, 1, 2, 0, 2, 1, 0), ROTATION
assert WINDOW_DAYS == 1260, WINDOW_DAYS
print('fc_factors', FC_FACTORS)
print('n_seeds', N_SEEDS)
print('rotation', ROTATION)
print('window_days', WINDOW_DAYS)
print('module_default_q_scale', PROCESS_VARIANCE_SCALE)
PY

cat > "$ROOT/submit_smoke.slurm" <<'SLURM'
#!/usr/bin/env bash
#SBATCH -J camg2smk
#SBATCH -p hgpu2p
#SBATCH -N 1
#SBATCH -n 1
#SBATCH --cpus-per-task=2
#SBATCH --exclude=ngu002
#SBATCH -t 00:20:00
#SBATCH -o /data1/home/sunyiq/camels_g2_design_20260808/logs/smoke-%j.out
#SBATCH -e /data1/home/sunyiq/camels_g2_design_20260808/logs/smoke-%j.err

set -eo pipefail
source /data1/home/${USER}/miniconda3/etc/profile.d/conda.sh || source "$HOME/miniconda3/etc/profile.d/conda.sh"
conda activate nh_final || { echo "CONDA_FAILED"; exit 1; }
export MKL_THREADING_LAYER=GNU
export MKL_SERVICE_FORCE_INTEL=1
export OMP_NUM_THREADS=1
export MKL_NUM_THREADS=1
export OPENBLAS_NUM_THREADS=1
export NUMEXPR_NUM_THREADS=1

ROOT="$HOME/camels_g2_design_20260808"
REPO="$ROOT/repo"
TAG="smoke1_widebank_q1e7_s01_20260808"
OUT="$REPO/results/23_camels_switch_confirmation/g2_switch_confirmation_v01_${TAG}"
cd "$REPO"
export PYTHONPATH="$REPO/src:$REPO:${PYTHONPATH:-}"

echo "=== SMOKE PREFLIGHT ==="
echo "job=$SLURM_JOB_ID node=$(hostname) commit=$(git rev-parse HEAD)"
[ ! -e "$OUT" ] || { echo "FATAL smoke output exists"; exit 30; }
[ -d data/camels_us ] || { echo "FATAL data missing"; exit 31; }
python -c "from src.camels_switch_confirmation.g2_switch_confirmation import main; print('IMPORT_OK')"

echo "=== SMOKE RUN ==="
python -u -X utf8 -m src.camels_switch_confirmation.g2_switch_confirmation \
  --limit 1 --workers 2 --q-scale 1e-7 --out-tag "$TAG"

echo "=== SMOKE VALIDATION ==="
python - <<'PY'
import json
from pathlib import Path
import numpy as np
import pandas as pd
root = Path('results/23_camels_switch_confirmation/g2_switch_confirmation_v01_smoke1_widebank_q1e7_s01_20260808')
summary = json.loads((root / 'g2_summary.json').read_text(encoding='utf-8'))
events = pd.read_csv(root / 'g2_events.csv')
files = sorted((root / 'probs').glob('*.npz'))
assert summary['n_tasks'] == 2, summary
assert summary['n_success'] == 2, summary
assert summary['n_failed'] == 0, summary
assert len(events) == 2, len(events)
assert int(events['truth_clip_count'].sum()) == 0
assert int(events['n_events'].sum()) == 12
assert len(files) == 2, len(files)
for path in files:
    with np.load(path) as data:
        assert np.isfinite(data['probabilities']).all(), path
        assert data['probabilities'].shape == (1260, 3), (path, data['probabilities'].shape)
print('SMOKE_VALIDATED tasks=2 events=12 clips=0 prob_files=2')
PY
scontrol show job "$SLURM_JOB_ID"
SLURM
sed -i 's/\r$//' "$ROOT/submit_smoke.slurm"
chmod 700 "$ROOT/submit_smoke.slurm"

echo "=== SUBMIT SMOKE ==="
JID=$(sbatch --parsable "$ROOT/submit_smoke.slurm")
echo "jobid=$JID"
printf '%s\n' "smoke_job_id=$JID" "source_commit=$ACTUAL_COMMIT" > "$ROOT/run_manifest.txt"

echo "=== WAIT SMOKE ==="
for i in $(seq 1 60); do
  if ! squeue -j "$JID" -h 2>/dev/null | grep -q .; then
    break
  fi
  [ $((i % 6)) -eq 0 ] && echo "waited_seconds=$((i * 5))"
  sleep 5
done

echo "=== SMOKE ACCOUNTING ==="
sacct -j "$JID" -X --format=JobID%12,JobName%14,Partition%10,NodeList%10,State%14,ExitCode%8,Elapsed%10,MaxRSS%12
echo "=== SMOKE STDOUT ==="
tail -80 "$ROOT/logs/smoke-${JID}.out" 2>/dev/null || true
echo "=== SMOKE STDERR ==="
tail -40 "$ROOT/logs/smoke-${JID}.err" 2>/dev/null || true

STATE=$(sacct -j "$JID" -X -n -o State | head -1 | tr -d '[:space:]')
EXIT_CODE=$(sacct -j "$JID" -X -n -o ExitCode | head -1 | tr -d '[:space:]')
[ "$STATE" = "COMPLETED" ] || { echo "FATAL smoke state=$STATE"; exit 40; }
[ "$EXIT_CODE" = "0:0" ] || { echo "FATAL smoke exit=$EXIT_CODE"; exit 41; }
grep -q 'SMOKE_VALIDATED tasks=2 events=12 clips=0 prob_files=2' "$ROOT/logs/smoke-${JID}.out" \
  || { echo "FATAL smoke validation marker missing"; exit 42; }
echo "SMOKE_GATE_PASS jobid=$JID"
