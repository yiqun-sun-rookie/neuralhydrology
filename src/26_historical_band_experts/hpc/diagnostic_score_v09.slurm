#!/usr/bin/env bash
#SBATCH -J v09diagscore
#SBATCH -p hgpu2
#SBATCH -N 1
#SBATCH -n 1
#SBATCH --cpus-per-task=4
#SBATCH -t 00:30:00
#SBATCH -o /data1/home/sunyiq/v09_strict/logs/diagnostic_score_%j.out
#SBATCH -e /data1/home/sunyiq/v09_strict/logs/diagnostic_score_%j.err
# No --gres: this is a pure CPU job. Never write --mem on this platform.

set -eo pipefail
set +u
source /data1/home/sunyiq/miniconda3/etc/profile.d/conda.sh
conda activate nh_final
set -u
export MKL_THREADING_LAYER=GNU
export MKL_SERVICE_FORCE_INTEL=1

ROOT=/data1/home/sunyiq/v09_strict
PREDICT_REPO=$ROOT/predict_v09/neuralhydrology
FORMAL_ROOT=$ROOT/codetest/neuralhydrology/results/26_historical_band_experts/formal_v09
PREDICTIONS_ROOT=$FORMAL_ROOT/predictions

# The answer key and every diagnostic output live OUTSIDE the formal result root, so the
# sealed training area never contains evaluation observations or a diagnostic verdict.
SCORING_ROOT=$ROOT/diagnostic_scoring
ANSWER_KEY=$SCORING_ROOT/track0_forcing_only_obs_eval.parquet
OUTPUT=$SCORING_ROOT/diagnostic_score.json

export PYTHONPATH=$PREDICT_REPO:$PREDICT_REPO/src/26_historical_band_experts:${PYTHONPATH:-}

test -d "$PREDICTIONS_ROOT"
test -f "$PREDICTIONS_ROOT/manifest.json"
test -f "$ANSWER_KEY"
test ! -e "$OUTPUT"
test "$(git -C "$PREDICT_REPO" status --porcelain --untracked-files=all)" = ""

echo "score_commit=$(git -C "$PREDICT_REPO" rev-parse HEAD) node=$(hostname) start=$(date -Iseconds)"
echo "answer_key_sha256=$(sha256sum "$ANSWER_KEY" | cut -d' ' -f1)"

python -u "$PREDICT_REPO/src/26_historical_band_experts/diagnostic_score_v09.py" \
  --predictions-root "$PREDICTIONS_ROOT" \
  --answer-key "$ANSWER_KEY" \
  --output "$OUTPUT"

echo "end=$(date -Iseconds)"
