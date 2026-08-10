#!/bin/bash
# ID29 seq=64: install aggregation closure v5 and schedule independent comparison jobs.
set -eo pipefail

ROOT=/data1/home/sunyiq/nearing2022_da
PAYLOAD=/data1/home/sunyiq/hpc_mailbox/payload/id29-nearing2022-da/closure_v5.tar.gz
EXPECTED_PAYLOAD_SHA=9fb8b19813a5dcd8003f50f54e13fdff7a515fb605c71fbd2129975f0c647f7d
SCRIPT="$ROOT/src/29_nearing2022_da_ar/hpc/run_registered_aggregation.slurm"
AGGREGATOR="$ROOT/src/29_nearing2022_da_ar/scripts/aggregate_registered_results.py"
AUTHOR_TIME="$ROOT/src/29_nearing2022_da_ar/reference/author_time_split_statistics.pkl"
AUTHOR_PUB="$ROOT/src/29_nearing2022_da_ar/reference/author_pub_statistics.pkl"

echo "=== PAYLOAD ==="
echo "$EXPECTED_PAYLOAD_SHA  $PAYLOAD" | sha256sum -c -
echo "payload_members=$(tar -tzf "$PAYLOAD" | wc -l)"
tar -xzf "$PAYLOAD" -C "$ROOT"

echo "=== PREFLIGHT ==="
test -f "$SCRIPT"
test -f "$AGGREGATOR"
test -f "$AUTHOR_TIME"
test -f "$AUTHOR_PUB"
sha256sum "$SCRIPT" "$AGGREGATOR" "$AUTHOR_TIME" "$AUTHOR_PUB"
test "$(sha256sum "$AUTHOR_TIME" | cut -d' ' -f1)" = 74aac5b377973dc745336da1b1d6a22be3f03b3544b6ae85b4cede37106af0ee
test "$(sha256sum "$AUTHOR_PUB" | cut -d' ' -f1)" = 4d50b98b0e4f7d30974ba1fd606e4421b1a25178462e289f9a50bf28d94bcdbb
source ~/miniconda3/etc/profile.d/conda.sh
conda activate nh_final
cd "$ROOT"
export PYTHONPATH="$ROOT${PYTHONPATH:+:$PYTHONPATH}"
python "$AGGREGATOR" --help >/dev/null

if squeue -h -u "$USER" -n N22-agg-eval,N22-agg-hyper | grep -q .; then
  echo "Refusing duplicate aggregation submission" >&2
  squeue -u "$USER" -n N22-agg-eval,N22-agg-hyper
  exit 3
fi

echo "=== SUBMIT ==="
EVAL_AGG_JOB=$(sbatch --parsable --job-name=N22-agg-eval \
  --dependency=afterok:202222:202226:202216:202227 \
  --export=ALL,AGGREGATION_KIND=evaluations "$SCRIPT")
HYPER_AGG_JOB=$(sbatch --parsable --job-name=N22-agg-hyper \
  --dependency=afterok:202228 \
  --export=ALL,AGGREGATION_KIND=hyperparameters "$SCRIPT")
echo "evaluation_aggregation_job_id=$EVAL_AGG_JOB dependency=afterok:202222:202226:202216:202227"
echo "hyperparameter_aggregation_job_id=$HYPER_AGG_JOB dependency=afterok:202228"
squeue -j "$EVAL_AGG_JOB,$HYPER_AGG_JOB" -o '%.18i %.18j %.2t %.10M %.6D %R'
