#!/bin/bash
# ID29 seq=147: preserve failed job 202503 and submit a minimal Matplotlib-submodule import repair.
set -eo pipefail

ROOT=/data1/home/sunyiq/nearing2022_da
DIAGNOSTIC_ROOT="$ROOT/results/29_nearing2022_da_ar/formal_closure/diagnostics"
OLD_SCRIPT="$DIAGNOSTIC_ROOT/author_v13_same_checkpoint_te100_first5.slurm"
NEW_SCRIPT="$DIAGNOSTIC_ROOT/author_v13_same_checkpoint_te100_first5_attempt2.slurm"
FINAL="$DIAGNOSTIC_ROOT/author_v13_same_checkpoint_te100_first5"
FAILED_WORK="$FINAL.preparing-202503"
FAILED_STDOUT="$ROOT/closure_20260810/logs/N22-author-v13-eval_202503.out"
FAILED_STDERR="$ROOT/closure_20260810/logs/N22-author-v13-eval_202503.err"

test "$(sacct -n -P -j 202503 --format=JobID,State,ExitCode | awk -F'|' '$1 == "202503" {print $2 "|" $3; exit}')" = "FAILED|1:0"
test -f "$OLD_SCRIPT"
test ! -e "$NEW_SCRIPT"
test ! -e "$FINAL"
test -d "$FAILED_WORK"
test -f "$FAILED_STDOUT"
test -f "$FAILED_STDERR"

echo "=== PRESERVED ATTEMPT 1 EVIDENCE ==="
sha256sum "$OLD_SCRIPT" "$FAILED_STDOUT" "$FAILED_STDERR" \
  "$FAILED_WORK/config.yml" "$FAILED_WORK/model_epoch030.pt" \
  "$FAILED_WORK/train_data/train_data_scaler.yml" "$FAILED_WORK/first5_basins.txt"

TEMP_SCRIPT="$NEW_SCRIPT.preparing-$$"
test ! -e "$TEMP_SCRIPT"
python - "$OLD_SCRIPT" "$TEMP_SCRIPT" <<'PY'
from pathlib import Path
import sys

source = Path(sys.argv[1])
target = Path(sys.argv[2])
text = source.read_text(encoding='utf-8')
job_old = '#SBATCH --job-name=N22-author-v13-eval\n'
job_new = '#SBATCH --job-name=N22-author-v13-eval2\n'
shim_old = """import matplotlib as mpl

if not hasattr(mpl.axes, '_subplots'):
    mpl.axes._subplots = types.SimpleNamespace(Axes=mpl.axes.Axes)
"""
shim_new = """import matplotlib as mpl
import matplotlib.axes as mpl_axes

if not hasattr(mpl_axes, '_subplots'):
    mpl_axes._subplots = types.SimpleNamespace(Axes=mpl_axes.Axes)
"""
if text.count(job_old) != 1:
    raise ValueError(f'Expected one job-name block, found {text.count(job_old)}')
if text.count(shim_old) != 1:
    raise ValueError(f'Expected one compatibility block, found {text.count(shim_old)}')
text = text.replace(job_old, job_new).replace(shim_old, shim_new)
target.write_text(text, encoding='utf-8', newline='\n')
PY

bash -n "$TEMP_SCRIPT"
echo "=== EXACT SCRIPT DIFFERENCE ==="
diff -u "$OLD_SCRIPT" "$TEMP_SCRIPT" || true
mv "$TEMP_SCRIPT" "$NEW_SCRIPT"
OLD_SHA256=$(sha256sum "$OLD_SCRIPT" | awk '{print $1}')
NEW_SHA256=$(sha256sum "$NEW_SCRIPT" | awk '{print $1}')
test "$OLD_SHA256" != "$NEW_SHA256"
JOB_ID=$(sbatch --parsable "$NEW_SCRIPT")
test -n "$JOB_ID"
echo "old_script=$OLD_SCRIPT"
echo "old_script_sha256=$OLD_SHA256"
echo "new_script=$NEW_SCRIPT"
echo "new_script_sha256=$NEW_SHA256"
echo "repair=explicitly import matplotlib.axes before restoring its removed _subplots annotation namespace"
echo "job_id=$JOB_ID"
scontrol show job -o "$JOB_ID"

test "$(squeue -h -j 202293 -o '%i|%T|%r|%j')" = "202293|PENDING|JobHeldUser|N22-manifest"
test "$(squeue -h -j 202315 -o '%i|%T|%r|%j')" = "202315|PENDING|Dependency|N22-gate"
test ! -e "$ROOT/closure_20260810/aggregation/final_reproduction_gate.json"
test ! -e "$ROOT/closure_20260810/aggregation/final_reproduction_differences.csv"
