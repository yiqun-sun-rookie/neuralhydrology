#!/bin/bash
set -eo pipefail

TRAINING_ROOT="/data1/home/sunyiq/zhenjiang_d32_differentiable_ukf_20260828_r2"
EVALUATION_ROOT="/data1/home/sunyiq/zhenjiang_d32_differentiable_ukf_dev_eval_20260831"
INPUT_ROOT="${TRAINING_ROOT}/inputs/pre2024-v1"

printf 'QUERY_TIME=%s\n' "$(date --iso-8601=seconds)"
printf 'TRAINING_ROOT_EXISTS=%s\n' "$(test -d "${TRAINING_ROOT}" && echo true || echo false)"
printf 'INPUT_ROOT_EXISTS=%s\n' "$(test -d "${INPUT_ROOT}" && echo true || echo false)"
printf 'EVALUATION_ROOT_EXISTS=%s\n' "$(test -e "${EVALUATION_ROOT}" && echo true || echo false)"
sha256sum "${INPUT_ROOT}/pre2024_input_manifest.json"

echo '=== USER_QUEUE ==='
squeue -u "${USER}" -o '%i|%j|%T|%P|%N|%M|%l' || true
echo '=== RELEVANT_LOGIN_PROCESSES ==='
pgrep -af 'zhenjiang_d32_gru_differentiable_ukf|zhenjiang_d32_differentiable_ukf' || true

python - "${TRAINING_ROOT}" <<'PY'
from __future__ import annotations

import hashlib
import json
from pathlib import Path
import sys


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


training_root = Path(sys.argv[1]).resolve()
for experiment_id in (
    "ZHD32-DUKF-S17-V1",
    "ZHD32-DUKF-S29-V1",
    "ZHD32-DUKF-S43-V1",
):
    attempt = (
        training_root
        / "runs"
        / "formal"
        / experiment_id
        / "attempt_001"
    ).resolve()
    attempt.relative_to(training_root)
    if not attempt.is_dir():
        raise SystemExit(f"missing formal training attempt: {attempt}")
    paths = {
        name: attempt / name
        for name in (
            "completion_manifest.json",
            "run_identity.json",
            "selection_validation_summary.json",
            "data_identity.json",
            "best_noise_parameters.json",
            "frozen_config.json",
            "best_checkpoint.pt",
        )
    }
    if any(not path.is_file() for path in paths.values()):
        raise SystemExit(f"required identity file missing: {experiment_id}")
    manifest = json.loads(
        paths["completion_manifest.json"].read_text(encoding="utf-8")
    )
    if manifest.get("status") != "early_stopped_development_training":
        raise SystemExit(f"unexpected completion status: {experiment_id}")
    if manifest.get("file_count") != 12 or len(manifest.get("files", [])) != 12:
        raise SystemExit(f"unexpected completion file count: {experiment_id}")
    registered = {}
    for row in manifest["files"]:
        relative = Path(str(row["path"]))
        if relative.is_absolute() or ".." in relative.parts:
            raise SystemExit(f"invalid manifest path: {experiment_id}")
        artifact = (attempt / relative).resolve()
        artifact.relative_to(attempt)
        actual_hash = sha256(artifact)
        if artifact.stat().st_size != int(row["byte_count"]) or actual_hash != row["sha256"]:
            raise SystemExit(f"manifest identity mismatch: {artifact}")
        registered[relative.as_posix()] = {
            "byte_count": artifact.stat().st_size,
            "sha256": actual_hash,
        }
    if "best_checkpoint.pt" not in registered:
        raise SystemExit(f"best checkpoint absent from manifest: {experiment_id}")
    actual_files = {
        path.name for path in attempt.iterdir() if path.is_file()
    }
    expected_files = set(registered) | {"completion_manifest.json"}
    if actual_files != expected_files:
        raise SystemExit(f"formal file set mismatch: {experiment_id}")

    run_identity = json.loads(paths["run_identity.json"].read_text(encoding="utf-8"))
    selection = json.loads(
        paths["selection_validation_summary.json"].read_text(encoding="utf-8")
    )
    data_identity = json.loads(paths["data_identity.json"].read_text(encoding="utf-8"))
    noise = json.loads(
        paths["best_noise_parameters.json"].read_text(encoding="utf-8")
    )
    counters = {
        "test_target_rows_read": 0,
        "test_target_values_loaded": 0,
        "test_target_values_parsed": 0,
    }
    if selection.get("test_target_counters") != counters:
        raise SystemExit(f"selection target counter changed: {experiment_id}")
    if data_identity.get("test_target_counters") != counters:
        raise SystemExit(f"data target counter changed: {experiment_id}")
    if data_identity.get("last_loaded_target_time_beijing") != "2023-12-31T23:00:00+08:00":
        raise SystemExit(f"target boundary changed: {experiment_id}")
    if run_identity.get("experiment_id") != experiment_id:
        raise SystemExit(f"run identity mismatch: {experiment_id}")
    if selection.get("experiment_id") != experiment_id:
        raise SystemExit(f"selection identity mismatch: {experiment_id}")
    if noise.get("experiment_id") != experiment_id:
        raise SystemExit(f"noise identity mismatch: {experiment_id}")
    if len(noise.get("process_variances", [])) != 32:
        raise SystemExit(f"process variance count changed: {experiment_id}")
    if len(noise.get("observation_variances", [])) != 6:
        raise SystemExit(f"observation variance count changed: {experiment_id}")

    output = {
        "experiment_id": experiment_id,
        "attempt_directory": str(attempt),
        "manifest_status": manifest["status"],
        "manifest_file_count": manifest["file_count"],
        "completion_manifest_sha256": sha256(paths["completion_manifest.json"]),
        "required_file_identities": {
            name: {
                "byte_count": path.stat().st_size,
                "sha256": sha256(path),
            }
            for name, path in paths.items()
        },
        "run_identity": run_identity,
        "selection_validation_summary": selection,
        "data_identity": data_identity,
        "best_noise_parameters": noise,
    }
    print("TRAINING_OUTPUT_IDENTITY|" + json.dumps(output, sort_keys=True))
PY
