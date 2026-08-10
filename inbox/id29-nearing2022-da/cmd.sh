#!/bin/bash
# ID29 seq=51: install the frozen closure protocol and submit the missing headline training condition.
set -eo pipefail

ROOT=/data1/home/sunyiq/nearing2022_da
PAYLOAD=/data1/home/sunyiq/hpc_mailbox/payload/id29-nearing2022-da/closure_v1.tar.gz
EXPECTED=ad03609ee6de5b4326db7faff07e3b7130d262ef432139b7e18d53f48f903320
CONFIG_REL=src/29_nearing2022_da_ar/configs/full_reproduction/time_split/autoregression/lead_1_holdout_0.5_seed_0.yml
SLURM_REL=src/29_nearing2022_da_ar/hpc/run_registered_training.slurm

echo "=== PAYLOAD ==="
echo "$EXPECTED  $PAYLOAD" | sha256sum -c -
tar -tzf "$PAYLOAD" | wc -l
tar -xzf "$PAYLOAD" -C "$ROOT"

echo "=== CONFIG PREFLIGHT ==="
test -f "$ROOT/$CONFIG_REL"
test -f "$ROOT/$SLURM_REL"
sha256sum "$ROOT/$CONFIG_REL" "$ROOT/$SLURM_REL"
source ~/miniconda3/etc/profile.d/conda.sh
conda activate nh_final
cd "$ROOT"
export PYTHONPATH="$ROOT${PYTHONPATH:+:$PYTHONPATH}"
python - <<'PY'
from pathlib import Path
from neuralhydrology.utils.config import Config
cfg = Config(Path('src/29_nearing2022_da_ar/configs/full_reproduction/time_split/autoregression/lead_1_holdout_0.5_seed_0.yml'))
assert cfg.epochs == 30
assert cfg.hidden_size == 256
assert cfg.lagged_features == {'QObs(mm/d)': [1]}
assert cfg.random_holdout_from_dynamic_features['QObs(mm/d)_shift1']['missing_fraction'] == 0.5
print('config_contract=PASS')
PY

echo "=== DUPLICATE GUARD ==="
mkdir -p "$ROOT/closure_20260810/logs"
existing=$(find "$ROOT/closure_20260810/time_split/autoregression" -mindepth 1 -maxdepth 1 -type d \
  -name 'nearing2022_full_time_autoregression_lead1_holdout0.5_seed0_*' -print 2>/dev/null | head -1 || true)
queued=$(squeue -h -u "$USER" -n N22-train -o '%i' | head -1 || true)
if [ -n "$existing" ] || [ -n "$queued" ]; then
  echo "existing_run=${existing:-none}"
  echo "queued_job=${queued:-none}"
  echo "submission=SKIPPED_DUPLICATE"
  exit 0
fi

echo "=== SUBMIT ==="
jid=$(sbatch --parsable --export=ALL,CONFIG_REL="$CONFIG_REL" "$ROOT/$SLURM_REL")
echo "job_id=$jid"
scontrol show job "$jid" | grep -E 'JobId=|JobState=|Partition=|Command=|WorkDir=' | head -20
