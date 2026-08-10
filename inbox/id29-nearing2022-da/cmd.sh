#!/bin/bash
# ID29 seq=152: bounded full-cohort evaluator summary plus registered matrix refresh.
set -eo pipefail

ROOT=/data1/home/sunyiq/nearing2022_da
MAIN_JOBS=202214,202215,202216,202222,202226,202227,202228,202229,202230,202238,202293,202294,202315
JOB=202505
FINAL="$ROOT/results/29_nearing2022_da_ar/formal_closure/diagnostics/author_v13_same_checkpoint_te100_all531"
STDOUT="$ROOT/closure_20260810/logs/N22-author-v13-full_202505.out"
STDERR="$ROOT/closure_20260810/logs/N22-author-v13-full_202505.err"

source ~/miniconda3/etc/profile.d/conda.sh
conda activate nh_final

echo "=== ALL-531 AUTHOR V1.3 EVALUATOR ==="
sacct -n -P -j "$JOB" --format=JobID,JobName,State,ExitCode,Elapsed,Start,End,NodeList
STATE=$(sacct -n -P -j "$JOB" --format=JobID,State | awk -F'|' '$1 == "202505" {print $2; exit}')
test -n "$STATE"
echo "parent_state=$STATE"
if [ "$STATE" = COMPLETED ]; then
  test -f "$FINAL/diagnostic_receipt.json"
  test -f "$FINAL/test/model_epoch030/test_results.p"
  test -f "$STDOUT"
  test -f "$STDERR"
  echo "--- bounded diagnostic summary ---"
  python - "$FINAL/diagnostic_receipt.json" <<'PY'
import json
import sys
from pathlib import Path

import numpy as np

path = Path(sys.argv[1])
receipt = json.loads(path.read_text(encoding="utf-8"))
rows = receipt["comparisons"]
author = np.asarray([row["author_nse"] for row in rows], dtype=np.float64)
current = np.asarray([row["current_nse"] for row in rows], dtype=np.float64)
paired = author - current
absolute_paired = np.abs(paired)
mean_prediction_difference = np.asarray(
    [row["prediction_mean_absolute_difference"] for row in rows], dtype=np.float64
)
paper_median_nse = 0.5539548397064209
independent_current_median_nse = 0.6161134850361614
author_median = float(np.median(author))
current_median = float(np.median(current))
paper_gap = independent_current_median_nse - paper_median_nse
evaluation_shift_toward_paper = independent_current_median_nse - author_median

summary = {
    "schema": receipt.get("schema"),
    "basin_count": len(rows),
    "unique_basin_count": len({row["basin"] for row in rows}),
    "date_count_values": sorted({row["dates"] for row in rows}),
    "common_finite_prediction_count_values": sorted(
        {row["common_finite_predictions"] for row in rows}
    ),
    "all_observations_bitwise_identical": all(
        row["observation_bitwise_identical_equal_nan"] for row in rows
    ),
    "prediction_bitwise_identical_count": sum(
        bool(row["prediction_bitwise_identical_equal_nan"]) for row in rows
    ),
    "maximum_prediction_absolute_difference": float(
        max(row["prediction_max_absolute_difference"] for row in rows)
    ),
    "median_prediction_mean_absolute_difference": float(
        np.median(mean_prediction_difference)
    ),
    "maximum_prediction_mean_absolute_difference": float(
        np.max(mean_prediction_difference)
    ),
    "released_v13_evaluator_median_nse": author_median,
    "current_evaluator_median_nse_from_receipt": current_median,
    "difference_of_medians_released_minus_current": author_median - current_median,
    "median_of_paired_nse_differences_released_minus_current": float(np.median(paired)),
    "maximum_absolute_per_basin_nse_difference": float(np.max(absolute_paired)),
    "absolute_per_basin_nse_difference_quantiles": {
        str(q): float(np.quantile(absolute_paired, q))
        for q in (0.5, 0.9, 0.95, 0.99, 1.0)
    },
    "absolute_per_basin_nse_difference_threshold_counts": {
        str(threshold): int(np.sum(absolute_paired > threshold))
        for threshold in (1e-5, 1e-4, 1e-3, 1e-2, 2e-2)
    },
    "paper_reported_median_nse": paper_median_nse,
    "independent_current_median_nse": independent_current_median_nse,
    "independent_current_minus_paper": paper_gap,
    "evaluation_shift_toward_paper": evaluation_shift_toward_paper,
    "evaluation_shift_fraction_of_confirmed_paper_gap": evaluation_shift_toward_paper / paper_gap,
    "checkpoint_identical_to_registered_source": receipt["checkpoint_identical_to_registered_source"],
    "scaler_identical_to_registered_source": receipt["scaler_identical_to_registered_source"],
    "author_result_sha256": receipt["author_result_sha256"],
    "current_result_sha256": receipt["current_result_sha256"],
}
assert summary["basin_count"] == 531
assert summary["unique_basin_count"] == 531
assert summary["date_count_values"] == [3652]
assert summary["common_finite_prediction_count_values"] == [3652]
assert summary["all_observations_bitwise_identical"]
print(json.dumps(summary, indent=2, sort_keys=True))
PY
  echo "--- diagnostic artifact hashes ---"
  sha256sum "$FINAL/diagnostic_receipt.json" "$FINAL/test/model_epoch030/test_results.p" "$STDOUT" "$STDERR"
elif [[ "$STATE" =~ ^(FAILED|TIMEOUT|OUT_OF_MEMORY|NODE_FAIL|PREEMPTED|BOOT_FAIL|DEADLINE)$ ]]; then
  echo "--- diagnostic stdout tail ---"
  test -f "$STDOUT" && tail -160 "$STDOUT" || true
  echo "--- diagnostic stderr tail ---"
  test -f "$STDERR" && tail -160 "$STDERR" || true
else
  squeue -h -j "$JOB" -o '%i|%T|%M|%l|%R|%j'
  echo "--- diagnostic stdout tail if started ---"
  test -f "$STDOUT" && tail -c 32768 "$STDOUT" || true
  echo "--- diagnostic stderr tail if started ---"
  test -f "$STDERR" && tail -80 "$STDERR" || true
fi

echo "=== REGISTERED COMPLETE-ROLE COUNTS ==="
cd "$ROOT"
export PYTHONPATH="$ROOT${PYTHONPATH:+:$PYTHONPATH}"
python - <<'PY'
from collections import Counter
import json
from pathlib import Path
import sys

import pandas as pd

root = Path('/data1/home/sunyiq/nearing2022_da')
scripts = root / 'src/29_nearing2022_da_ar/scripts'
sys.path.insert(0, str(scripts))
from aggregate_registered_results import _registered_run
from prepare_evaluation_run import resolve_source_run
from verify_registered_closure import _metrics_path

registry_root = root / 'src/29_nearing2022_da_ar/registry'
training = pd.read_csv(registry_root / 'experiment_registry.csv', keep_default_na=False, dtype=str)
evaluations = pd.read_csv(registry_root / 'evaluation_registry.csv', keep_default_na=False, dtype=str)
hyper = pd.read_csv(registry_root / 'assimilation_hyperparameter_registry.csv', keep_default_na=False, dtype=str)

def complete(paths):
    return all(path.is_file() for path in paths)

training_done = Counter()
for _, row in training.iterrows():
    try:
        run = resolve_source_run(root, training, row['exp_id'])
        if complete([run / 'config.yml', run / 'model_epoch030.pt', run / 'output.log',
                     run / 'train_data/train_data_scaler.yml']):
            training_done[row['family']] += 1
    except (FileNotFoundError, KeyError, ValueError):
        pass

evaluation_done = Counter()
for _, row in evaluations.iterrows():
    try:
        run = _registered_run(root, training, row)
        result = run / row['result_file']
        reference = resolve_source_run(root, training, row['reference_exp_id']) / 'test/model_epoch030/test_results.p'
        if complete([run / 'config.yml', run / 'model_epoch030.pt', run / 'output.log', result,
                     _metrics_path(result), reference, _metrics_path(reference)]):
            evaluation_done[row['family']] += 1
    except (FileNotFoundError, KeyError, ValueError):
        pass

hyper_done = 0
for _, row in hyper.iterrows():
    try:
        run = Path(row['run_dir'])
        run = run if run.is_absolute() else root / run
        result = run / row['result_file']
        reference = resolve_source_run(root, training, row['source_exp_id']) / 'test/model_epoch030/test_results.p'
        if complete([run / 'config.yml', run / 'model_epoch030.pt', run / 'output.log', result,
                     _metrics_path(result), reference, _metrics_path(reference)]):
            hyper_done += 1
    except (FileNotFoundError, KeyError, ValueError):
        pass

print(json.dumps({
    'training_complete': sum(training_done.values()),
    'training_total': len(training),
    'training_by_family': dict(sorted(training_done.items())),
    'evaluation_complete': sum(evaluation_done.values()),
    'evaluation_total': len(evaluations),
    'evaluation_by_family': dict(sorted(evaluation_done.items())),
    'hyperparameter_complete': hyper_done,
    'hyperparameter_total': len(hyper),
}, sort_keys=True))
PY

echo "=== ACTIVE MAIN JOBS AND FAILURE STATES ==="
squeue -h -j "$MAIN_JOBS" -o '%i|%T|%M|%l|%R|%j' | sort
FAILURES=$(sacct -n -P -j "$MAIN_JOBS" --format=JobIDRaw,JobName,State,ExitCode | \
  awk -F'|' '$1 !~ /\./ && $3 ~ /^(FAILED|TIMEOUT|OUT_OF_MEMORY|NODE_FAIL|PREEMPTED|BOOT_FAIL|DEADLINE)/')
printf '%s\n' "$FAILURES"
test -z "$FAILURES"

echo "=== REGISTERED ARTIFACT SAFETY ==="
test "$(squeue -h -j 202293 -o '%i|%T|%r|%j')" = "202293|PENDING|JobHeldUser|N22-manifest"
test "$(squeue -h -j 202315 -o '%i|%T|%r|%j')" = "202315|PENDING|Dependency|N22-gate"
test ! -e "$ROOT/closure_20260810/aggregation/final_reproduction_gate.json"
test ! -e "$ROOT/closure_20260810/aggregation/final_reproduction_differences.csv"
