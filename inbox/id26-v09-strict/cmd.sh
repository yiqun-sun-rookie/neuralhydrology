#!/bin/bash
# id26-v09-strict seq=49 : read-only summary of 24 formal run manifests and seals.
export LC_ALL=C
FORMAL=/data1/home/sunyiq/v09_strict/codetest/neuralhydrology/results/26_historical_band_experts/formal_v09
export FORMAL
python - <<'PY'
import hashlib
import json
import math
import os
import re
import statistics
from pathlib import Path

root = Path(os.environ["FORMAL"])
seeds = [100, 200, 300, 400, 500, 600, 700, 800]
families = {
    "classic": {
        "family": "B09-CLASSIC",
        "variant": "classic_lstm_256_clean",
        "trainable_parameters": 297217,
    },
    "capacity": {
        "family": "B09-CAPACITY",
        "variant": "classic_lstm_369_capacity",
        "trainable_parameters": 595198,
    },
    "continuous": {
        "family": "E09-CONTINUOUS",
        "variant": "continuous_multiscale_history",
        "trainable_parameters": 596737,
    },
}
checkpoint_epochs = [10, 20, 30]
checkpoint_files = ["checkpoint_epoch010.pt", "checkpoint_epoch020.pt", "checkpoint_epoch030.pt"]
hash_pattern = re.compile(r"^[0-9a-f]{64}$")


def file_sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def canonical_sha256(value):
    payload = json.dumps(
        value,
        sort_keys=True,
        separators=(",", ":"),
        ensure_ascii=False,
        allow_nan=False,
    ).encode("utf-8")
    return hashlib.sha256(payload).hexdigest()


def require(condition, message, errors):
    if not condition:
        errors.append(message)


expected_manifest_paths = sorted(
    str(Path(family_dir) / ("seed_%d" % seed) / "manifest.json")
    for family_dir in families
    for seed in seeds
)
discovered_manifest_paths = sorted(
    str(path.relative_to(root))
    for path in root.glob("*/seed_*/manifest.json")
    if path.is_file()
)
global_errors = []
missing_manifests = sorted(set(expected_manifest_paths) - set(discovered_manifest_paths))
unexpected_manifests = sorted(set(discovered_manifest_paths) - set(expected_manifest_paths))
require(not missing_manifests, "missing expected manifests: %s" % missing_manifests, global_errors)
require(not unexpected_manifests, "unexpected manifests: %s" % unexpected_manifests, global_errors)

run_rows = []
cross_records = {}
input_bindings = []
for family_dir, expected in families.items():
    for seed in seeds:
        run_id = "%s-S%d" % (expected["family"], seed)
        run_dir = root / family_dir / ("seed_%d" % seed)
        manifest_path = run_dir / "manifest.json"
        seal_path = run_dir / "seal.json"
        errors = []
        manifest = {}
        seal = {}
        actual_manifest_sha256 = None
        first_loss = None
        last_loss = None
        loss_delta = None
        awake_step = None
        first_gate_gradient_norm = None
        first_gate_absolute_maximum = None
        first_history_encoder_gradient_norm = None
        permutation_hashes = []
        dropout_binding = None

        if manifest_path.is_file():
            try:
                manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
                actual_manifest_sha256 = file_sha256(manifest_path)
            except Exception as exc:
                errors.append("manifest parse failed: %s" % exc)
        else:
            errors.append("manifest.json is missing")

        if manifest:
            require(manifest.get("schema") == "historical_multiscale_formal_v09_main_run_v1",
                    "manifest schema mismatch", errors)
            require(manifest.get("status") == "formal_training_complete",
                    "manifest status mismatch", errors)
            require(manifest.get("formal_execution") is True,
                    "formal_execution is not true", errors)
            require(manifest.get("variant") == expected["variant"],
                    "variant mismatch", errors)
            require(manifest.get("seed") == seed, "seed mismatch", errors)
            require(manifest.get("epochs") == 30, "epoch count mismatch", errors)
            require(manifest.get("batch_size") == 256, "batch size mismatch", errors)
            require(manifest.get("training_samples") == 1745928,
                    "training sample count mismatch", errors)
            require(manifest.get("trainable_parameters") == expected["trainable_parameters"],
                    "trainable parameter count mismatch", errors)
            require(manifest.get("optimizer_steps_per_epoch") == 6821,
                    "optimizer steps per epoch mismatch", errors)
            require(manifest.get("optimizer_steps_total") == 204630,
                    "total optimizer step count mismatch", errors)
            require(manifest.get("checkpoint_epochs") == checkpoint_epochs,
                    "checkpoint epochs mismatch", errors)
            require(manifest.get("checkpoint_files") == checkpoint_files,
                    "checkpoint file list mismatch", errors)
            require(manifest.get("validation_metrics_computed") is False,
                    "validation metrics were computed", errors)
            require(manifest.get("formal_evaluation_observation_reads") == 0,
                    "formal evaluation observations were read", errors)
            require(manifest.get("formal_period_predictions_generated") is False,
                    "formal-period predictions were generated", errors)

            epoch_trace = manifest.get("epoch_trace")
            require(isinstance(epoch_trace, list) and len(epoch_trace) == 30,
                    "epoch trace length mismatch", errors)
            if isinstance(epoch_trace, list) and len(epoch_trace) == 30:
                require([row.get("epoch") for row in epoch_trace] == list(range(1, 31)),
                        "epoch trace numbering mismatch", errors)
                require(all(row.get("optimizer_steps") == 6821 for row in epoch_trace),
                        "epoch trace optimizer step mismatch", errors)
                expected_learning_rates = [0.001] * 10 + [0.0005] * 10 + [0.0001] * 10
                require([row.get("learning_rate") for row in epoch_trace] == expected_learning_rates,
                        "learning-rate schedule mismatch", errors)
                losses = [row.get("mean_training_loss") for row in epoch_trace]
                finite_losses = all(
                    isinstance(value, (int, float)) and math.isfinite(float(value))
                    for value in losses
                )
                require(finite_losses, "training loss contains a non-finite value", errors)
                if finite_losses:
                    first_loss = float(losses[0])
                    last_loss = float(losses[-1])
                    loss_delta = last_loss - first_loss
                    require(last_loss < first_loss,
                            "last-epoch mean training loss is not below first-epoch mean", errors)
                permutation_hashes = [row.get("permutation_sha256") for row in epoch_trace]
                require(all(isinstance(value, str) and hash_pattern.fullmatch(value)
                            for value in permutation_hashes),
                        "epoch permutation hash is invalid", errors)

            input_binding = manifest.get("input_bindings")
            required_input_keys = {
                "input_seal_sha256",
                "input_external_audit_sha256",
                "trusted_source_audit_sha256",
            }
            require(isinstance(input_binding, dict)
                    and set(input_binding) == required_input_keys
                    and all(isinstance(value, str) and hash_pattern.fullmatch(value)
                            for value in input_binding.values()),
                    "input bindings are incomplete or invalid", errors)
            if isinstance(input_binding, dict):
                input_bindings.append(input_binding)

            dropout_binding = manifest.get("dropout_rng_binding")
            expected_dropout_seed = seed * 1000003 + 900001
            require(isinstance(dropout_binding, dict)
                    and dropout_binding.get("dropout_seed") == expected_dropout_seed
                    and isinstance(dropout_binding.get("cpu_state_sha256"), str)
                    and hash_pattern.fullmatch(dropout_binding.get("cpu_state_sha256", ""))
                    and isinstance(dropout_binding.get("cuda_state_sha256"), str)
                    and hash_pattern.fullmatch(dropout_binding.get("cuda_state_sha256", "")),
                    "dropout random-state binding is invalid", errors)

            health_trace = manifest.get("history_health_trace")
            awake_step = manifest.get("history_encoder_first_nonzero_gradient_step")
            if family_dir == "continuous":
                require(isinstance(health_trace, list) and len(health_trace) >= 2,
                        "history health trace is missing", errors)
                if isinstance(health_trace, list) and health_trace:
                    first = health_trace[0]
                    first_gate_gradient_norm = first.get("gate_gradient_norm")
                    first_gate_absolute_maximum = first.get("gate_absolute_maximum")
                    first_history_encoder_gradient_norm = first.get("history_encoder_gradient_norm")
                    require(first.get("step") == 1, "first health record is not step 1", errors)
                    require(first_gate_absolute_maximum == 0.0,
                            "history gates are not exactly zero at step 1", errors)
                    require(first_history_encoder_gradient_norm == 0.0,
                            "history encoder gradient is not exactly zero at step 1", errors)
                    require(isinstance(first_gate_gradient_norm, (int, float))
                            and math.isfinite(float(first_gate_gradient_norm))
                            and float(first_gate_gradient_norm) > 0.0,
                            "history gate gradient is not finite and positive at step 1", errors)
                    require(first.get("gate_gradients_present") is True
                            and first.get("history_encoder_gradients_present") is True,
                            "history gradients are not recorded as present at step 1", errors)
                require(isinstance(awake_step, int) and 1 < awake_step <= 3,
                        "history encoder did not wake by step 3", errors)
            else:
                require(health_trace == [], "recent-only model recorded history health", errors)
                require(awake_step is None, "recent-only model recorded a history wake step", errors)

        actual_file_names = sorted(
            path.name for path in run_dir.iterdir() if path.is_file()
        ) if run_dir.is_dir() else []
        expected_actual_file_names = sorted(checkpoint_files + ["manifest.json", "seal.json"])
        require(actual_file_names == expected_actual_file_names,
                "run directory flat-file inventory mismatch", errors)
        for checkpoint_name in checkpoint_files:
            checkpoint_path = run_dir / checkpoint_name
            require(checkpoint_path.is_file() and checkpoint_path.stat().st_size > 0,
                    "%s is missing or empty" % checkpoint_name, errors)

        if seal_path.is_file():
            try:
                seal = json.loads(seal_path.read_text(encoding="utf-8"))
            except Exception as exc:
                errors.append("seal parse failed: %s" % exc)
        else:
            errors.append("seal.json is missing")

        if seal:
            require(seal.get("schema") == "historical_multiscale_formal_v09_main_run_seal_v1",
                    "seal schema mismatch", errors)
            require(seal.get("status") == "sealed", "seal status mismatch", errors)
            require(seal.get("manifest_sha256") == actual_manifest_sha256,
                    "seal manifest hash does not match manifest bytes", errors)
            sealed_files = seal.get("sealed_files")
            require(isinstance(sealed_files, list), "sealed file inventory is invalid", errors)
            if isinstance(sealed_files, list):
                require(seal.get("sealed_files_sha256") == canonical_sha256(sealed_files),
                        "sealed inventory canonical hash mismatch", errors)
                by_name = {
                    item.get("relative_path"): item
                    for item in sealed_files
                    if isinstance(item, dict)
                }
                require(set(by_name) == set(checkpoint_files + ["manifest.json"]),
                        "sealed inventory names mismatch", errors)
                for relative_name, item in by_name.items():
                    path = run_dir / relative_name
                    require(path.is_file(), "sealed file is missing: %s" % relative_name, errors)
                    if path.is_file():
                        require(item.get("size_bytes") == path.stat().st_size,
                                "sealed size mismatch: %s" % relative_name, errors)
                    require(isinstance(item.get("sha256"), str)
                            and hash_pattern.fullmatch(item.get("sha256", "")),
                            "sealed hash format invalid: %s" % relative_name, errors)
                if "manifest.json" in by_name:
                    require(by_name["manifest.json"].get("sha256") == actual_manifest_sha256,
                            "sealed manifest inventory hash mismatch", errors)

        run_rows.append({
            "run_id": run_id,
            "relative_path": str(run_dir.relative_to(root)),
            "passed": not errors,
            "errors": errors,
            "manifest_sha256": actual_manifest_sha256,
            "first_epoch_mean_training_loss": first_loss,
            "last_epoch_mean_training_loss": last_loss,
            "last_minus_first_training_loss": loss_delta,
            "history_encoder_first_nonzero_gradient_step": awake_step,
            "step1_gate_absolute_maximum": first_gate_absolute_maximum,
            "step1_gate_gradient_norm": first_gate_gradient_norm,
            "step1_history_encoder_gradient_norm": first_history_encoder_gradient_norm,
        })
        cross_records.setdefault(seed, {})[family_dir] = {
            "permutation_hashes": permutation_hashes,
            "dropout_binding": dropout_binding,
        }

cross_run_errors = []
same_seed_permutation = {}
same_seed_dropout = {}
for seed in seeds:
    group = cross_records.get(seed, {})
    complete = set(group) == set(families)
    permutations = [group[name]["permutation_hashes"] for name in families if name in group]
    dropouts = [group[name]["dropout_binding"] for name in families if name in group]
    same_seed_permutation[str(seed)] = (
        complete and len(permutations) == 3 and permutations[0] == permutations[1] == permutations[2]
    )
    same_seed_dropout[str(seed)] = (
        complete and len(dropouts) == 3 and dropouts[0] == dropouts[1] == dropouts[2]
    )
    require(same_seed_permutation[str(seed)],
            "seed %d permutation hashes differ across model families" % seed,
            cross_run_errors)
    require(same_seed_dropout[str(seed)],
            "seed %d dropout bindings differ across model families" % seed,
            cross_run_errors)

input_binding_payloads = {
    json.dumps(value, sort_keys=True, separators=(",", ":"))
    for value in input_bindings
}
all_input_bindings_identical = len(input_bindings) == 24 and len(input_binding_payloads) == 1
require(all_input_bindings_identical,
        "the 24 manifests do not share one complete input binding",
        cross_run_errors)

family_summary = {}
for family_dir, expected in families.items():
    family_rows = [
        row for row in run_rows
        if row["run_id"].startswith(expected["family"] + "-")
    ]
    deltas = [
        row["last_minus_first_training_loss"]
        for row in family_rows
        if row["last_minus_first_training_loss"] is not None
    ]
    family_summary[expected["family"]] = {
        "run_count": len(family_rows),
        "passed_count": sum(row["passed"] for row in family_rows),
        "loss_decrease_count": sum(
            row["last_minus_first_training_loss"] is not None
            and row["last_minus_first_training_loss"] < 0.0
            for row in family_rows
        ),
        "median_last_minus_first_training_loss": (
            statistics.median(deltas) if deltas else None
        ),
    }

transient_building = sorted(str(path.relative_to(root)) for path in root.glob("*/seed_*.building"))
failed_directories = sorted(str(path.relative_to(root)) for path in root.glob("*/seed_*.failed"))
failure_record_present = (root / "training_attempt_01.failure.json").is_file()
require(not transient_building, "building directories remain: %s" % transient_building, global_errors)
require(not failed_directories, "failed directories exist: %s" % failed_directories, global_errors)
require(not failure_record_present, "training failure record exists", global_errors)

all_errors = list(global_errors) + list(cross_run_errors)
for row in run_rows:
    all_errors.extend("%s: %s" % (row["run_id"], value) for value in row["errors"])

continuous_rows = [
    row for row in run_rows if row["run_id"].startswith("E09-CONTINUOUS-")
]
continuous_gate_gradient_norms = [
    row["step1_gate_gradient_norm"]
    for row in continuous_rows
    if row["step1_gate_gradient_norm"] is not None
]
report = {
    "schema": "historical_multiscale_formal_v09_read_only_manifest_summary_v1",
    "status": "PASS" if not all_errors else "FAIL",
    "scope": {
        "manifest_bytes_hashed": True,
        "seal_structure_and_recorded_sizes_checked": True,
        "checkpoint_presence_and_nonzero_size_checked": True,
        "checkpoint_payload_sha256_recomputed": False,
        "formal_evaluation_observations_read": False,
        "predictions_generated": False,
    },
    "coverage": {
        "expected_runs": 24,
        "discovered_runs": len(discovered_manifest_paths),
        "run_pass_count": sum(row["passed"] for row in run_rows),
        "missing_manifests": missing_manifests,
        "unexpected_manifests": unexpected_manifests,
        "building_directories": transient_building,
        "failed_directories": failed_directories,
        "failure_record_present": failure_record_present,
    },
    "cross_run_checks": {
        "all_24_input_bindings_identical": all_input_bindings_identical,
        "same_seed_epoch_permutations_identical_across_families": same_seed_permutation,
        "same_seed_dropout_bindings_identical_across_families": same_seed_dropout,
    },
    "continuous_history_checks": {
        "run_count": len(continuous_rows),
        "wake_steps": [
            row["history_encoder_first_nonzero_gradient_step"]
            for row in continuous_rows
        ],
        "step1_gate_gradient_norm_min": (
            min(continuous_gate_gradient_norms) if continuous_gate_gradient_norms else None
        ),
        "step1_gate_gradient_norm_max": (
            max(continuous_gate_gradient_norms) if continuous_gate_gradient_norms else None
        ),
    },
    "family_summary": family_summary,
    "per_run": run_rows,
    "errors": all_errors,
}
print(json.dumps(report, indent=2, sort_keys=True, allow_nan=False))
PY
