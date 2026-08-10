#!/bin/bash
# ID29 seq=149: expand the successful same-checkpoint author-v1.3 diagnostic from five to all 531 frozen basins.
set -eo pipefail

ROOT=/data1/home/sunyiq/nearing2022_da
DIAGNOSTIC_ROOT="$ROOT/results/29_nearing2022_da_ar/formal_closure/diagnostics"
SUBSET_FINAL="$DIAGNOSTIC_ROOT/author_v13_same_checkpoint_te100_first5"
SUBSET_RECEIPT="$SUBSET_FINAL/diagnostic_receipt.json"
SOURCE_SCRIPT="$DIAGNOSTIC_ROOT/author_v13_same_checkpoint_te100_first5_attempt2.slurm"
NEW_SCRIPT="$DIAGNOSTIC_ROOT/author_v13_same_checkpoint_te100_all531.slurm"
FULL_FINAL="$DIAGNOSTIC_ROOT/author_v13_same_checkpoint_te100_all531"

test "$(sacct -n -P -j 202504 --format=JobID,State,ExitCode | awk -F'|' '$1 == "202504" {print $2 "|" $3; exit}')" = "COMPLETED|0:0"
test -f "$SUBSET_RECEIPT"
test -f "$SOURCE_SCRIPT"
test ! -e "$NEW_SCRIPT"
test ! -e "$FULL_FINAL"

echo "=== FIVE-BASIN DECISION BOUNDARY ==="
python - "$SUBSET_RECEIPT" <<'PY'
import json
from pathlib import Path
import sys

receipt = json.loads(Path(sys.argv[1]).read_text(encoding='utf-8'))
if len(receipt['basins']) != 5 or len(receipt['comparisons']) != 5:
    raise ValueError('The completed subset receipt does not contain exactly five basins')
if not receipt['checkpoint_identical_to_registered_source']:
    raise ValueError('The completed subset did not use the registered checkpoint')
if not receipt['scaler_identical_to_registered_source']:
    raise ValueError('The completed subset did not use the registered scaler')
if not receipt['all_observation_arrays_bitwise_identical']:
    raise ValueError('The completed subset observations differ')
confirmed_paper_difference = 0.06215864532974047
payload = {
    'basins': len(receipt['basins']),
    'maximum_prediction_absolute_difference': receipt['maximum_prediction_absolute_difference'],
    'maximum_nse_absolute_difference': receipt['maximum_nse_absolute_difference'],
    'confirmed_paper_nse_difference': confirmed_paper_difference,
    'paper_to_subset_max_nse_difference_ratio': (
        confirmed_paper_difference / receipt['maximum_nse_absolute_difference']
    ),
    'boundary': 'five basins are insufficient to exclude a material evaluation difference over all 531 basins',
}
print(json.dumps(payload, sort_keys=True))
PY

TEMP_SCRIPT="$NEW_SCRIPT.preparing-$$"
test ! -e "$TEMP_SCRIPT"
python - "$SOURCE_SCRIPT" "$TEMP_SCRIPT" <<'PY'
from pathlib import Path
import sys

source = Path(sys.argv[1])
target = Path(sys.argv[2])
text = source.read_text(encoding='utf-8')
replacements = [
    ('#SBATCH --job-name=N22-author-v13-eval2\n', '#SBATCH --job-name=N22-author-v13-full\n', 1),
    ('#SBATCH --time=01:00:00\n', '#SBATCH --time=02:00:00\n', 1),
    ('author_v13_same_checkpoint_te100_first5', 'author_v13_same_checkpoint_te100_all531', 2),
    ('first5_basins.txt', 'all531_basins.txt', 4),
    ('selected = basins[:5]', 'selected = basins', 1),
    ('if len(selected) != 5 or len(set(selected)) != 5:',
     'if len(selected) != 531 or len(set(selected)) != 531:', 1),
    ("raise ValueError(f'Expected five unique frozen basins, found {selected}')",
     "raise ValueError(f'Expected 531 unique frozen basins, found {len(selected)}')", 1),
]
for old, new, expected in replacements:
    count = text.count(old)
    if count != expected:
        raise ValueError(f'Expected {expected} occurrences of {old!r}, found {count}')
    text = text.replace(old, new)
target.write_text(text, encoding='utf-8', newline='\n')
PY

bash -n "$TEMP_SCRIPT"
echo "=== FULL-COHORT SCRIPT DIFFERENCE ==="
diff -u "$SOURCE_SCRIPT" "$TEMP_SCRIPT" || true
mv "$TEMP_SCRIPT" "$NEW_SCRIPT"
SOURCE_SHA256=$(sha256sum "$SOURCE_SCRIPT" | awk '{print $1}')
NEW_SHA256=$(sha256sum "$NEW_SCRIPT" | awk '{print $1}')
JOB_ID=$(sbatch --parsable "$NEW_SCRIPT")
test -n "$JOB_ID"
echo "source_script=$SOURCE_SCRIPT"
echo "source_script_sha256=$SOURCE_SHA256"
echo "new_script=$NEW_SCRIPT"
echo "new_script_sha256=$NEW_SHA256"
echo "job_id=$JOB_ID"
scontrol show job -o "$JOB_ID"

echo "=== REGISTERED ARTIFACT SAFETY ==="
test "$(squeue -h -j 202293 -o '%i|%T|%r|%j')" = "202293|PENDING|JobHeldUser|N22-manifest"
test "$(squeue -h -j 202315 -o '%i|%T|%r|%j')" = "202315|PENDING|Dependency|N22-gate"
test ! -e "$ROOT/closure_20260810/aggregation/final_reproduction_gate.json"
test ! -e "$ROOT/closure_20260810/aggregation/final_reproduction_differences.csv"
