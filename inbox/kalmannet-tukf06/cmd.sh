#!/usr/bin/env bash
set -eo pipefail

TARGET=/data1/home/sunyiq/kalmannet_tukf06_20260809/retry2
SOURCE="$TARGET/source"
OUTPUT="$TARGET/results/tukf06_full_diagonal_search_head_to_head_v1"
SELECTION_JOB=202136
AUDIT_JOB=202143
SELECTION_MANIFEST_SHA=63160e786c2b6b07bbb144766deda8bdc29c86d889dbeb8a0f81d468623bc8c3
SELECTION_SEAL_SHA=9151f439e110a679802739eadd7a21857ab396e824ce3c4ea01052b6c611e35a
EVALUATION_SLURM_SHA=a0c1c44568c597d79af53acf504156fe11014fd68af45e50320ef0092a66c9e3
EVALUATION_PYTHON_SHA=63092093913addfef7103894b32b481eb09c353980e414d86ba385ea3b1fad8f

echo "=== IMMUTABLE SELECTION AND AUDIT ACCOUNTING ==="
sacct -j "$SELECTION_JOB,$AUDIT_JOB" --format=JobID%18,JobName%20,Partition%10,NodeList%12,State%18,ExitCode%8,Elapsed%10,TotalCPU%12,MaxRSS%12
for job in "$SELECTION_JOB" "$AUDIT_JOB"; do
  state=$(sacct -j "$job" -X -n -o State | awk 'NF {print $1; exit}')
  exit_code=$(sacct -j "$job" -X -n -o ExitCode | awk 'NF {print $1; exit}')
  if [[ "$state" != "COMPLETED" || "$exit_code" != "0:0" ]]; then
    echo "prerequisite job gate failed: job=$job state=$state exit_code=$exit_code" >&2
    exit 101
  fi
done

for path in \
  "$OUTPUT/evaluation" \
  "$OUTPUT/evaluation_summary.json" \
  "$OUTPUT/evaluation_manifest.sha256.json" \
  "$OUTPUT/evaluation_failed.json"; do
  if [[ -e "$path" ]]; then
    echo "historical evaluation artifact already exists: $path" >&2
    exit 102
  fi
done

test "$(sha256sum "$OUTPUT/selection_manifest.sha256.json" | awk '{print $1}')" = "$SELECTION_MANIFEST_SHA"
test "$(sha256sum "$OUTPUT/selection.sealed.json" | awk '{print $1}')" = "$SELECTION_SEAL_SHA"
test "$(sha256sum "$SOURCE/hpc/tukf06_full_diagonal/submit_evaluation_cpu.slurm" | awk '{print $1}')" = "$EVALUATION_SLURM_SHA"
test "$(sha256sum "$SOURCE/scripts/evaluate_tukf06_full_diagonal_head_to_head.py" | awk '{print $1}')" = "$EVALUATION_PYTHON_SHA"

python - "$OUTPUT" "$SELECTION_MANIFEST_SHA" <<'PY'
import hashlib
import json
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
expected_manifest_sha = sys.argv[2]

def read_json(name):
    return json.loads((root / name).read_text(encoding='utf-8'))

def sha(name):
    return hashlib.sha256((root / name).read_bytes()).hexdigest()

seal = read_json('selection.sealed.json')
manifest = read_json('selection_manifest.sha256.json')
summary = read_json('selection_summary.json')
assert sha('selection_manifest.sha256.json') == expected_manifest_sha
assert seal == {
    'experiment_id': 'TUKF06_FULL_DIAGONAL_SEARCH_HEAD_TO_HEAD_V1',
    'status': 'SELECTED_SEALED',
    'basin_count': 21,
    'selection_manifest_sha256': expected_manifest_sha,
    'evaluation_period_read': False,
}
assert manifest['status'] == 'SELECTION_COMPLETE'
assert manifest['evaluation_period_read'] is False
assert summary['status'] == 'SELECTION_COMPLETE'
assert summary['basin_count'] == summary['requested_basin_count'] == 21
assert summary['evaluation_period_read'] is False
assert summary['failures'] == []
print('PRE_EVALUATION_SELECTION_GATE_PASS basins=21 evaluation_period_read=false')
PY

audit_stdout="$TARGET/audit/selection-audit-${AUDIT_JOB}.out"
audit_stderr="$TARGET/audit/selection-audit-${AUDIT_JOB}.err"
test -f "$audit_stdout" -a -f "$audit_stderr"
if [[ -s "$audit_stderr" ]]; then
  echo "successful audit has nonempty stderr" >&2
  exit 103
fi
grep -F '"status": "SELECTION_AUDIT_PASS"' "$audit_stdout"
grep -F '"evaluation_period_read": false' "$audit_stdout"
grep -F '"finite_json_and_arrays": true' "$audit_stdout"
grep -F 'TUKF06_SELECTION_READ_ONLY_AUDIT_PASS' "$audit_stdout"

existing=$(squeue -h -u "$USER" -n tukf06-eval -o '%i %T' | head -n 1)
if [[ -n "$existing" ]]; then
  echo "a TUKF06 historical-evaluation job already exists: $existing" >&2
  exit 104
fi

evaluation_job=$(sbatch --parsable "$SOURCE/hpc/tukf06_full_diagonal/submit_evaluation_cpu.slurm")
evaluation_job=${evaluation_job%%;*}
echo "TUKF06_HISTORICAL_EVALUATION_SUBMITTED job_id=$evaluation_job"
scontrol show job "$evaluation_job"
