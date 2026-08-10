#!/bin/bash
# ID29 seq=146: monitor the isolated author-v1.3 evaluator and refresh registered complete-role counts.
set -eo pipefail

ROOT=/data1/home/sunyiq/nearing2022_da
MAIN_JOBS=202214,202215,202216,202222,202226,202227,202228,202229,202230,202238,202293,202294,202315
DIAGNOSTIC_JOB=202503
DIAGNOSTIC_FINAL="$ROOT/results/29_nearing2022_da_ar/formal_closure/diagnostics/author_v13_same_checkpoint_te100_first5"
DIAGNOSTIC_STDOUT="$ROOT/closure_20260810/logs/N22-author-v13-eval_202503.out"
DIAGNOSTIC_STDERR="$ROOT/closure_20260810/logs/N22-author-v13-eval_202503.err"

echo "=== ISOLATED AUTHOR V1.3 EVALUATOR JOB ==="
sacct -n -P -j "$DIAGNOSTIC_JOB" --format=JobID,JobName,State,ExitCode,Elapsed,Start,End,NodeList
STATE=$(sacct -n -P -j "$DIAGNOSTIC_JOB" --format=JobID,State | awk -F'|' '$1 == "202503" {print $2; exit}')
test -n "$STATE"
echo "parent_state=$STATE"
if [ "$STATE" = COMPLETED ]; then
  test -f "$DIAGNOSTIC_FINAL/diagnostic_receipt.json"
  test -f "$DIAGNOSTIC_FINAL/test/model_epoch030/test_results.p"
  test -f "$DIAGNOSTIC_STDOUT"
  test -f "$DIAGNOSTIC_STDERR"
  echo "--- diagnostic receipt ---"
  cat "$DIAGNOSTIC_FINAL/diagnostic_receipt.json"
  echo "--- diagnostic artifact hashes ---"
  sha256sum "$DIAGNOSTIC_FINAL/diagnostic_receipt.json" \
    "$DIAGNOSTIC_FINAL/test/model_epoch030/test_results.p" "$DIAGNOSTIC_STDOUT" "$DIAGNOSTIC_STDERR"
elif [[ "$STATE" =~ ^(FAILED|TIMEOUT|OUT_OF_MEMORY|NODE_FAIL|PREEMPTED|BOOT_FAIL|DEADLINE)$ ]]; then
  echo "--- diagnostic stdout tail ---"
  test -f "$DIAGNOSTIC_STDOUT" && tail -120 "$DIAGNOSTIC_STDOUT" || true
  echo "--- diagnostic stderr tail ---"
  test -f "$DIAGNOSTIC_STDERR" && tail -120 "$DIAGNOSTIC_STDERR" || true
else
  squeue -h -j "$DIAGNOSTIC_JOB" -o '%i|%T|%M|%l|%R|%j'
  echo "--- diagnostic stdout tail if started ---"
  test -f "$DIAGNOSTIC_STDOUT" && tail -40 "$DIAGNOSTIC_STDOUT" || true
  echo "--- diagnostic stderr tail if started ---"
  test -f "$DIAGNOSTIC_STDERR" && tail -40 "$DIAGNOSTIC_STDERR" || true
fi

echo "=== REGISTERED COMPLETE-ROLE COUNTS ==="
source ~/miniconda3/etc/profile.d/conda.sh
conda activate nh_final
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
