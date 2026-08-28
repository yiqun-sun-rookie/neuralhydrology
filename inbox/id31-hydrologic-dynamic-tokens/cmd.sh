#!/usr/bin/env bash
set -euo pipefail

ROOT=/data1/home/sunyiq/id31_hydrologic_dynamic_tokens_20260828/repo
PAYLOAD="$HOME/hpc_mailbox/payload/id31-hydrologic-dynamic-tokens/id31_gpu_probe_cuda_device_patch_20260828_v02.tar.gz"
TARGET="$ROOT/src/hydrologic_dynamic_tokens/hpc/submit_gpu_resource_probe.slurm"
EVIDENCE_DIR="$ROOT/results/31_hydrologic_dynamic_tokens/_reports/patch_v02_seq12"
EXPECTED_PAYLOAD_SHA=716fbd597a3652105f598675199f8308f0fa0eed751eafc5ccfbc628cc4b0e3d
EXPECTED_OLD_SHA=cb20fd38e05d4d5881f64b5e11cc0ef4ad18de4565c7a7ef685f314777cab3b3
EXPECTED_NEW_SHA=2a2df8a54a3c38e5b356024c91188d5db5d64e14b96e899efb4a42928bf2607f
MEMBER=src/hydrologic_dynamic_tokens/hpc/submit_gpu_resource_probe.slurm

test -d "$ROOT/.git"
test -f "$PAYLOAD"
test -f "$TARGET"
test ! -e "$EVIDENCE_DIR"
mkdir -p "$EVIDENCE_DIR/extracted"

test "$(sha256sum "$PAYLOAD" | awk '{print $1}')" = "$EXPECTED_PAYLOAD_SHA"
test "$(sha256sum "$TARGET" | awk '{print $1}')" = "$EXPECTED_OLD_SHA"
tar -tzf "$PAYLOAD" | tee "$EVIDENCE_DIR/archive_members.txt"
test "$(wc -l < "$EVIDENCE_DIR/archive_members.txt")" -eq 1
grep -Fqx "$MEMBER" "$EVIDENCE_DIR/archive_members.txt"
tar -xzf "$PAYLOAD" -C "$EVIDENCE_DIR/extracted"

NEW_SOURCE="$EVIDENCE_DIR/extracted/$MEMBER"
test -f "$NEW_SOURCE"
test ! -L "$NEW_SOURCE"
test "$(sha256sum "$NEW_SOURCE" | awk '{print $1}')" = "$EXPECTED_NEW_SHA"

TEMP_TARGET="$ROOT/src/hydrologic_dynamic_tokens/hpc/.submit_gpu_resource_probe.slurm.seq12.tmp"
test ! -e "$TEMP_TARGET"
install -m 0644 "$NEW_SOURCE" "$TEMP_TARGET"
test "$(sha256sum "$TEMP_TARGET" | awk '{print $1}')" = "$EXPECTED_NEW_SHA"
mv -f "$TEMP_TARGET" "$TARGET"
test "$(sha256sum "$TARGET" | awk '{print $1}')" = "$EXPECTED_NEW_SHA"
bash -n "$TARGET"

source /data1/home/sunyiq/miniconda3/etc/profile.d/conda.sh
conda activate nh_final
cd "$ROOT"
python -m src.hydrologic_dynamic_tokens.scripts.audit_configs
python - <<'PY'
import json

from src.hydrologic_dynamic_tokens.scripts.run_development import capture_source_integrity

print(json.dumps(capture_source_integrity("DL01"), indent=2, sort_keys=True))
PY

echo "PATCH_V02_SEQ12_PASS"
