#!/bin/bash
set -euo pipefail

ROOT=/data1/home/sunyiq/autoresearch64
MAILBOX=/data1/home/sunyiq/hpc_mailbox
PYTHON="$ROOT/.venv/bin/python"
AUTO="$ROOT/runs/unified_autoresearch/automatic_rehearsal_8x3_20260811_seq59"
AUTO_EVIDENCE="$AUTO/evidence/REHEARSAL_EVIDENCE.json"
AUTO_MANIFEST="$AUTO/evidence/MANIFEST.sha256"
BASE="$MAILBOX/inbox/autoresearch-64/hbv_lite_64_reproduction_seq48.slurm"
DERIVED="$MAILBOX/inbox/autoresearch-64/hbv_lite_64_prospective_seq62.slurm"
RECEIPT_DIR="$ROOT/registries/unified_autoresearch"
RECEIPT="$RECEIPT_DIR/hbv_lite_64_prospective_seq62_recommendation.json"
ATTEMPT="$ROOT/runs/unified_autoresearch/hbv_lite_64_prospective_confirmation_20260811_seq62"
EXPECTED_AUTO_EVIDENCE_SHA256=7bb8d23ea03b0cffc0390c4fb6993fd2f6449cc65a47d1674771971a241a723e
EXPECTED_AUTO_MANIFEST_SHA256=c000f729125676a4adc7a2097f38bacda4873a5fa10dcbafc13082734abd5a46

test -f "$AUTO_EVIDENCE"
test -f "$AUTO_MANIFEST"
test -f "$BASE"
test ! -e "$DERIVED"
test ! -e "$RECEIPT"
test ! -e "$ATTEMPT"
test "$(sha256sum "$AUTO_EVIDENCE" | awk '{print $1}')" = "$EXPECTED_AUTO_EVIDENCE_SHA256"
test "$(sha256sum "$AUTO_MANIFEST" | awk '{print $1}')" = "$EXPECTED_AUTO_MANIFEST_SHA256"
(cd "$AUTO" && sha256sum -c evidence/MANIFEST.sha256 >/dev/null)

mkdir -p "$RECEIPT_DIR"
"$PYTHON" - "$RECEIPT" "$AUTO_EVIDENCE" "$AUTO_MANIFEST" <<'PY_RECEIPT'
import hashlib
import json
import os
import sys
from datetime import datetime
from pathlib import Path

receipt_path = Path(sys.argv[1])
automatic_evidence_path = Path(sys.argv[2])
automatic_manifest_path = Path(sys.argv[3])

def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()

value = {
    "schema_version": "immutable_recommendation_receipt_v1",
    "receipt_id": "hbv_lite_64_prospective_seq62_recommendation",
    "finalized_at": datetime.now().astimezone().isoformat(timespec="seconds"),
    "timestamp_source": "immutable_registry_receipt",
    "automatic_experiment_id": "automatic_rehearsal_8x3_20260811_seq59",
    "automatic_job_id": "202556",
    "recommended_candidate_id": "hbv-lite-calibrated-v1",
    "automatic_evidence_path": str(automatic_evidence_path),
    "automatic_evidence_sha256": sha256(automatic_evidence_path),
    "automatic_manifest_path": str(automatic_manifest_path),
    "automatic_manifest_sha256": sha256(automatic_manifest_path),
    "planned_scale_experiment_id": "hbv_lite_64_prospective_confirmation_20260811_seq62",
    "planned_candidate_count": 1,
    "planned_basin_count": 64,
    "seed": 29,
    "result_available_during_proposal": False,
    "sealed_final_evaluation_read_or_scored": False,
    "fair_benchmark_scoring_program_run": False,
    "formal_basin_search_run": False,
    "baseline_outperformance_claimed": False,
}
descriptor = os.open(receipt_path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o444)
with os.fdopen(descriptor, "w", encoding="utf-8", newline="\n") as stream:
    json.dump(value, stream, indent=2, sort_keys=True)
    stream.write("\n")
    stream.flush()
    os.fsync(stream.fileno())
PY_RECEIPT

RECEIPT_SHA256=$(sha256sum "$RECEIPT" | awk '{print $1}')
RECOMMENDATION_FINALIZED_AT=$("$PYTHON" -c 'import json,sys; print(json.load(open(sys.argv[1], encoding="utf-8"))["finalized_at"])' "$RECEIPT")

"$PYTHON" - "$BASE" "$DERIVED" "$RECEIPT" "$RECEIPT_SHA256" <<'PY_DERIVE'
import hashlib
import os
import sys
from pathlib import Path

base_path = Path(sys.argv[1])
derived_path = Path(sys.argv[2])
receipt_path = sys.argv[3]
receipt_sha256 = sys.argv[4]
text = base_path.read_text(encoding="utf-8")

replacements = {
    "#SBATCH -J a64-hbv64-io": "#SBATCH -J a64-hbv64-pro",
    'ATTEMPT="$RUNS/hbv_lite_64_hpc_reproduction_20260810_seq48"': 'ATTEMPT="$RUNS/hbv_lite_64_prospective_confirmation_20260811_seq62"',
    'git commit -q -m "Immutable sequence 48 test snapshot"': 'git commit -q -m "Immutable sequence 62 prospective snapshot"',
    '"experiment_id": "hbv_lite_64_hpc_reproduction_20260810_seq48"': '"experiment_id": "hbv_lite_64_prospective_confirmation_20260811_seq62"',
    'restricted 64-basin development reproduction after complete Linux gate; one predeclared candidate': 'prospective 64-basin development confirmation after immutable recommendation receipt; one predeclared candidate',
}
for old, new in replacements.items():
    if text.count(old) != 1:
        raise SystemExit(f"expected exactly one template match: {old!r}")
    text = text.replace(old, new)

after_redirect = 'exec > "$EVIDENCE/JOB_STDOUT.txt" 2> "$EVIDENCE/JOB_STDERR.txt"\n'
receipt_block = f'''\
\n+echo "=== VERIFY IMMUTABLE RECOMMENDATION RECEIPT ==="
PROMOTION_RECEIPT={receipt_path!r}
EXPECTED_PROMOTION_RECEIPT_SHA256={receipt_sha256!r}
test "$(sha256sum "$PROMOTION_RECEIPT" | awk '{{print $1}}')" = "$EXPECTED_PROMOTION_RECEIPT_SHA256"
cp --no-clobber "$PROMOTION_RECEIPT" "$EVIDENCE/PROMOTION_RECEIPT.json"
test "$(sha256sum "$EVIDENCE/PROMOTION_RECEIPT.json" | awk '{{print $1}}')" = "$EXPECTED_PROMOTION_RECEIPT_SHA256"
'''
if text.count(after_redirect) != 1:
    raise SystemExit("job-output redirect insertion point is not unique")
text = text.replace(after_redirect, after_redirect + receipt_block)

before_manifest = 'echo "=== FINALIZE COMPLETE ATTEMPT MANIFEST ==="\n'
timing_block = '''\
echo "=== WRITE IMMUTABLE PROSPECTIVE TIMING RECEIPT ==="
"$PYTHON" - "$EVIDENCE/PROMOTION_TIMING.json" "$EVIDENCE/PROMOTION_RECEIPT.json" "$EVIDENCE/REPRODUCTION_SUMMARY.json" <<'PY_TIMING'
import hashlib
import json
import os
import sys
from datetime import datetime
from pathlib import Path

output_path = Path(sys.argv[1])
recommendation_path = Path(sys.argv[2])
summary_path = Path(sys.argv[3])

def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()

recommendation = json.loads(recommendation_path.read_text(encoding="utf-8"))
summary = json.loads(summary_path.read_text(encoding="utf-8"))
value = {
    "schema_version": "immutable_scale_evidence_receipt_v1",
    "recommendation_finalized_at": recommendation["finalized_at"],
    "recommendation_timestamp_source": recommendation["timestamp_source"],
    "recommendation_receipt_sha256": sha256(recommendation_path),
    "scale_experiment_id": summary["experiment_id"],
    "scale_job_id": summary["job_id"],
    "scale_evidence_created_at": datetime.now().astimezone().isoformat(timespec="seconds"),
    "scale_evidence_timestamp_source": "immutable_manifest_receipt",
    "scale_summary_sha256": sha256(summary_path),
    "result_available_during_proposal": False,
}
descriptor = os.open(output_path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o444)
with os.fdopen(descriptor, "w", encoding="utf-8", newline="\n") as stream:
    json.dump(value, stream, indent=2, sort_keys=True)
    stream.write("\n")
    stream.flush()
    os.fsync(stream.fileno())
print(json.dumps(value, sort_keys=True))
PY_TIMING
'''
if text.count(before_manifest) != 1:
    raise SystemExit("manifest insertion point is not unique")
text = text.replace(before_manifest, timing_block + before_manifest)

descriptor = os.open(derived_path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o444)
with os.fdopen(descriptor, "w", encoding="utf-8", newline="\n") as stream:
    stream.write(text)
    stream.flush()
    os.fsync(stream.fileno())
print(hashlib.sha256(text.encode("utf-8")).hexdigest())
PY_DERIVE

DERIVED_SHA256=$(sha256sum "$DERIVED" | awk '{print $1}')
JOB_ID=$(sbatch --parsable "$DERIVED")

echo "GO prospective_confirmation_submitted=true"
echo "recommendation_finalized_at=$RECOMMENDATION_FINALIZED_AT"
echo "recommendation_receipt=$RECEIPT"
echo "recommendation_receipt_sha256=$RECEIPT_SHA256"
echo "derived_slurm=$DERIVED"
echo "derived_slurm_sha256=$DERIVED_SHA256"
echo "job_id=$JOB_ID"
squeue -j "$JOB_ID" -o '%.18i %.20j %.12T %.10M %.10l %.20R'
