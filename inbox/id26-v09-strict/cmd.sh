#!/bin/bash
# id26-v09-strict seq=63 : verify the completed training audit and submit state diagnostics once.
set -euo pipefail
export LC_ALL=C
ROOT=/data1/home/sunyiq/v09_strict
AUDIT_PARENT=$ROOT/audit_v09
AUDIT_REPO=$AUDIT_PARENT/neuralhydrology
TRAIN_REPO=$ROOT/codetest/neuralhydrology
STRICT_REPO=$ROOT/neuralhydrology
FORMAL_ROOT=$TRAIN_REPO/results/26_historical_band_experts/formal_v09
TRAINING_JOBID_FILE=$AUDIT_PARENT/training_audit_attempt_03_jobid.txt
STATE_JOBID_FILE=$AUDIT_PARENT/state_diagnostics_jobid.txt
REPORT=$FORMAL_ROOT/training_external_audit.json
EXPECTED_REPORT_SHA=af6e424d6b88f53f5ad51f2ea76c4bfeb4a8bce408363c5909e952ec3ff80d9b
export PATH=$ROOT/gitenv/bin:$PATH

echo "=== A TRAINING AUDIT PASS GATE ==="
TRAINING_JID=$(tr -d '[:space:]' < "$TRAINING_JOBID_FILE")
test "$TRAINING_JID" = 202777
IFS='|' read -r TRAINING_STATE TRAINING_EXIT TRAINING_ELAPSED <<< "$(sacct -n -X -j "$TRAINING_JID" --starttime 2026-08-12 --format=State,ExitCode,Elapsed -P)"
echo "training_audit_jobid=$TRAINING_JID state=$TRAINING_STATE exit_code=$TRAINING_EXIT elapsed=$TRAINING_ELAPSED"
test "$TRAINING_STATE" = COMPLETED
test "$TRAINING_EXIT" = 0:0
test -f "$REPORT"
set -- $(sha256sum "$REPORT")
echo "training_external_audit_sha256=$1"
test "$1" = "$EXPECTED_REPORT_SHA"

python - "$REPORT" <<'PY'
import json
import sys
from pathlib import Path

data = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
runs = data.get("runs", [])
coverage = data.get("coverage", {})
assert data.get("status") == "complete_training_audit"
assert coverage.get("audited_runs") == 24
assert coverage.get("expected_runs") == 24
assert coverage.get("passed_runs") == 24
assert len(runs) == 24
assert data.get("training_progress", {}).get("completed_run_count") == 24
assert sum(len(run.get("checkpoints", [])) for run in runs) == 72
assert sum(run.get("nonfinite_tensor_count", 0) for run in runs) == 0
assert data.get("all_checkpoint_tensors_finite") is True
assert data.get("formal_evaluation_observation_reads") == 0
assert data.get("formal_period_predictions_generated") is False
assert data.get("official_score_called") is False
assert data.get("validation_metrics_computed") is False
assert data.get("source_context", {}).get("training_git_commit") == "bb519b8b9980725ac1d5f4e298d76ae80ea2c58d"
assert data.get("audit_source_context", {}).get("git_commit") == "880a066d4b775e76a2e9b0358c393666c8737c6b"
assert data.get("audit_source_context", {}).get("tracked_source_clean") is True
pre_seal = data.get("pre_seal_evidence", {})
assert pre_seal.get("canonical_four_workload_resource_preflight_report_present") is False
assert "canonical_four_workload_resource_preflight_report_missing" in pre_seal.get("known_blockers", [])
print("training_audit_gate=passed runs=24 checkpoints=72 nonfinite=0 prohibited_reads=0 predictions=false scoring=false")
print("pre_seal_evidence=missing_canonical_four_workload_resource_preflight_report")
PY

echo "=== B FROZEN AND OUTPUT PRECONDITIONS ==="
TRAIN_HEAD=$(git -C "$TRAIN_REPO" rev-parse HEAD)
STRICT_HEAD=$(git -C "$STRICT_REPO" rev-parse HEAD)
AUDIT_HEAD=$(git -C "$AUDIT_REPO" rev-parse HEAD)
echo "training_head=$TRAIN_HEAD"
echo "strict_head=$STRICT_HEAD"
echo "audit_head=$AUDIT_HEAD"
test "$TRAIN_HEAD" = bb519b8b9980725ac1d5f4e298d76ae80ea2c58d
test "$STRICT_HEAD" = f94183209bf44ed6e672e1c23f98020905804e6d
test "$AUDIT_HEAD" = 880a066d4b775e76a2e9b0358c393666c8737c6b
test -z "$(git -C "$AUDIT_REPO" status --porcelain --untracked-files=all)"
test ! -e "$STATE_JOBID_FILE"
test ! -e "$FORMAL_ROOT/state_diagnostics"
test ! -e "$FORMAL_ROOT/state_diagnostics.building"
test ! -e "$FORMAL_ROOT/state_diagnostics_external_audit.json"
test ! -e "$FORMAL_ROOT/training_seal.json"

echo "=== C SUBMIT STATE DIAGNOSTICS ==="
STATE_JID=$(sbatch --parsable "$AUDIT_REPO/src/26_historical_band_experts/hpc/state_diagnostics_formal_v09.slurm")
printf '%s\n' "$STATE_JID" > "$STATE_JOBID_FILE"
echo "STATE_DIAGNOSTICS_JOBID=$STATE_JID"
squeue -j "$STATE_JID" -o '%.12i %.18j %.10T %.12M %.24R' || true
echo "=== END ==="
