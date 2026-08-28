#!/usr/bin/env bash
set -eo pipefail

SOURCE=/data1/home/sunyiq/id30_modern_transformer_moe_20260827/repo
TARGET=/data1/home/sunyiq/id31_hydrologic_dynamic_tokens_20260828
STAGE=/data1/home/sunyiq/.id31_hydrologic_dynamic_tokens_20260828.staging_seq2

test -d "$SOURCE/.git"
test ! -e "$TARGET"
test -d "$STAGE/repo/.git"
test -f "$STAGE/repo/neuralhydrology/modelzoo/hydrologic_dynamic_token_transformer.py"
test -f "$STAGE/repo/neuralhydrology/modelzoo/hydrologic_dynamic_tokenizer.py"
test -f "$STAGE/repo/src/hydrologic_dynamic_tokens/scripts/run_development.py"
test -L "$STAGE/repo/data/camels_us_track0_development_forcing_v01"
test -L "$STAGE/repo/data/camels_us_track0_supervision_v01"

cd "$STAGE/repo"
test "$(readlink -f data/camels_us_track0_development_forcing_v01)" = \
  "$SOURCE/data/camels_us_track0_development_forcing_v01"
test "$(readlink -f data/camels_us_track0_supervision_v01)" = \
  "$SOURCE/data/camels_us_track0_supervision_v01"
test -d logs/31_hydrologic_dynamic_tokens
test -d results/31_hydrologic_dynamic_tokens/_reports
test -d results/31_hydrologic_dynamic_tokens/_gpu_resource_probes

source /data1/home/sunyiq/miniconda3/etc/profile.d/conda.sh
conda activate nh_final
export MKL_THREADING_LAYER=GNU
export OMP_NUM_THREADS=1
export MKL_NUM_THREADS=1

python -m src.hydrologic_dynamic_tokens.scripts.audit_configs
python - <<'PY'
import json
from src.hydrologic_dynamic_tokens.scripts.run_development import capture_source_integrity

print(json.dumps(capture_source_integrity("DL01"), indent=2, sort_keys=True))
PY
bash -n src/hydrologic_dynamic_tokens/hpc/submit_gpu_resource_probe.slurm
bash -n src/hydrologic_dynamic_tokens/hpc/submit_development_experiment.slurm

cd /data1/home/sunyiq
mv "$STAGE" "$TARGET"
test -d "$TARGET/repo/.git"
test -d "$TARGET/repo/logs/31_hydrologic_dynamic_tokens"
echo "ID31_DEPLOYMENT_PASS"
