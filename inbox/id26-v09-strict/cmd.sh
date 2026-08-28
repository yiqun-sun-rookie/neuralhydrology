#!/bin/bash
# id26-v09-strict seq=68: gate and submit independent state-diagnostics replay audit attempt 01 exactly once.
set -o pipefail
export LC_ALL=C

ROOT=/data1/home/sunyiq/v09_strict
AUDIT_PARENT=$ROOT/audit_v09
AUDIT_REPO=$AUDIT_PARENT/neuralhydrology
TRAIN_REPO=$ROOT/codetest/neuralhydrology
FORMAL_ROOT=$TRAIN_REPO/results/26_historical_band_experts/formal_v09
STATE_ROOT=$FORMAL_ROOT/state_diagnostics
REPORT=$FORMAL_ROOT/state_diagnostics_external_audit.json
SLURM=$AUDIT_REPO/src/26_historical_band_experts/hpc/audit_state_diagnostics_formal_v09.slurm
STATE_JOBID=211643
AUDIT_JOBID_FILE=$AUDIT_PARENT/state_diagnostics_audit_attempt_01_jobid.txt
EXPECTED_COMMIT=d69d2a7af509b141c7e8361f49f6fdeceed963af
EXPECTED_STATE_MANIFEST_SHA256=4df6c29afee9df2d36af8a8a99bea40ab6b66103c4696470fa13a2fbf868e77d

fail() {
  echo "FATAL: $*" >&2
  exit 1
}

echo "=== A IMMUTABLE PREFLIGHT ==="
test -d "$AUDIT_REPO/.git" || fail "independent audit repository is missing"
AUDIT_HEAD=$(cd "$AUDIT_REPO" && git rev-parse HEAD) || fail "cannot read independent audit HEAD"
AUDIT_DIRTY=$(cd "$AUDIT_REPO" && git status --porcelain --untracked-files=all) || fail "cannot read independent audit status"
echo "audit_head=$AUDIT_HEAD"
test "$AUDIT_HEAD" = "$EXPECTED_COMMIT" || fail "independent audit commit drift"
test -z "$AUDIT_DIRTY" || fail "independent audit repository is dirty"
test -f "$SLURM" || fail "independent replay Slurm script is missing"
test -f "$STATE_ROOT/manifest.json" || fail "completed state-diagnostics manifest is missing"
test ! -e "$REPORT" || fail "independent replay report already exists; refusing duplicate submission"
test ! -e "$AUDIT_JOBID_FILE" || fail "independent replay job-id file already exists; refusing duplicate submission"

STATE_RECORD=$(sacct -X -n -j "$STATE_JOBID" --starttime 2026-08-25 --format=JobIDRaw,State,ExitCode -P 2>&1 | awk -F'|' -v id="$STATE_JOBID" '$1 == id {print $2 "|" $3; exit}')
echo "state_job=$STATE_JOBID|$STATE_RECORD"
test "$STATE_RECORD" = "COMPLETED|0:0" || fail "state-diagnostics scheduler gate is not COMPLETED|0:0"

STATE_MANIFEST_SHA256=$(sha256sum "$STATE_ROOT/manifest.json" | awk '{print $1}') || fail "cannot hash state-diagnostics manifest"
echo "state_manifest_sha256=$STATE_MANIFEST_SHA256"
test "$STATE_MANIFEST_SHA256" = "$EXPECTED_STATE_MANIFEST_SHA256" || fail "state-diagnostics manifest SHA-256 drift"

python - "$STATE_ROOT" <<'PY' || exit 1
import json
import sys
from pathlib import Path

root = Path(sys.argv[1])
manifest = json.loads((root / "manifest.json").read_text(encoding="utf-8"))
expected = {
    "schema": "historical_multiscale_formal_v09_state_diagnostics_root_v1",
    "status": "state_diagnostics_complete",
    "seed_count": 8,
    "seeds": list(range(100, 801, 100)),
    "training_target_reads": 0,
    "formal_evaluation_observation_reads": 0,
    "recent_path_executed": False,
    "flow_head_executed": False,
    "formal_period_predictions_generated": False,
    "official_score_called": False,
}
for key, value in expected.items():
    if type(manifest.get(key)) is not type(value) or manifest.get(key) != value:
        raise SystemExit(f"state-diagnostics gate failed: {key}={manifest.get(key)!r}")
children = manifest.get("children")
if not isinstance(children, list) or len(children) != 8:
    raise SystemExit("state-diagnostics gate failed: child count")
if sum(int(child.get("array_count", 0)) for child in children) != 64:
    raise SystemExit("state-diagnostics gate failed: array count")
for child in children:
    child_manifest = root / child["relative_path"] / "manifest.json"
    data = json.loads(child_manifest.read_text(encoding="utf-8"))
    if len(data.get("arrays", {})) != 8:
        raise SystemExit(f"state-diagnostics gate failed: {child_manifest}")
print("state_diagnostics_gate=PASS|seeds=8|arrays=64|prohibited_reads=0|predictions=false|score=false")
PY

echo "=== B SUBMIT INDEPENDENT REPLAY ==="
SUBMIT_OUTPUT=$(sbatch "$SLURM" 2>&1)
SUBMIT_STATUS=$?
printf '%s\n' "$SUBMIT_OUTPUT"
test "$SUBMIT_STATUS" -eq 0 || fail "sbatch returned nonzero status $SUBMIT_STATUS"
AUDIT_JOBID=$(printf '%s\n' "$SUBMIT_OUTPUT" | sed -n 's/^Submitted batch job \([0-9][0-9]*\)$/\1/p' | tail -n 1)
test -n "$AUDIT_JOBID" || fail "sbatch did not return an exact Submitted batch job record"
printf '%s' "$AUDIT_JOBID" > "$AUDIT_JOBID_FILE" || fail "cannot persist independent replay job id"
echo "audit_jobid=$AUDIT_JOBID"
echo "audit_jobid_file=$AUDIT_JOBID_FILE"

echo "=== C IMMEDIATE SCHEDULER SNAPSHOT ==="
squeue -j "$AUDIT_JOBID" -o '%.12i %.18j %.12T %.12M %.24R' 2>&1 || true
sacct -X -j "$AUDIT_JOBID" --starttime 2026-08-28 --format=JobIDRaw,JobName,State,ExitCode,Elapsed,Start,End,NodeList -P 2>&1 || true
echo "=== END ==="
