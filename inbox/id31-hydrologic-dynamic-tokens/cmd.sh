#!/usr/bin/env bash
set -eo pipefail

ROOT=/data1/home/sunyiq/id31_hydrologic_dynamic_tokens_20260828/repo
TARGET="$ROOT/src/hydrologic_dynamic_tokens/hpc/submit_gpu_resource_probe.slurm"
EVIDENCE_DIR="$ROOT/results/31_hydrologic_dynamic_tokens/_reports/patch_v02_seq12"
EXPECTED_NEW_SHA=2a2df8a54a3c38e5b356024c91188d5db5d64e14b96e899efb4a42928bf2607f
MEMBER=src/hydrologic_dynamic_tokens/hpc/submit_gpu_resource_probe.slurm

test -d "$ROOT/.git"
test -f "$TARGET"
test -d "$EVIDENCE_DIR/extracted"
test -f "$EVIDENCE_DIR/archive_members.txt"
test "$(sha256sum "$TARGET" | awk '{print $1}')" = "$EXPECTED_NEW_SHA"
test "$(wc -l < "$EVIDENCE_DIR/archive_members.txt")" -eq 1
grep -Fqx "$MEMBER" "$EVIDENCE_DIR/archive_members.txt"
test "$(sha256sum "$EVIDENCE_DIR/extracted/$MEMBER" | awk '{print $1}')" = "$EXPECTED_NEW_SHA"
bash -n "$TARGET"

source /data1/home/sunyiq/miniconda3/etc/profile.d/conda.sh
conda activate nh_final
cd "$ROOT"
python -m src.hydrologic_dynamic_tokens.scripts.audit_configs
python - <<'PY'
import json

from src.hydrologic_dynamic_tokens.scripts.run_development import capture_source_integrity

expected = "2a2df8a54a3c38e5b356024c91188d5db5d64e14b96e899efb4a42928bf2607f"
relative = "src/hydrologic_dynamic_tokens/hpc/submit_gpu_resource_probe.slurm"
snapshot = capture_source_integrity("DL01")
assert snapshot["implementation_files"][relative] == expected
print(json.dumps(snapshot, indent=2, sort_keys=True))
PY

echo "PATCH_V02_SEQ13_VERIFY_PASS"
