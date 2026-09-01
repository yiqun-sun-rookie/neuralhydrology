#!/usr/bin/env bash
set -euo pipefail
umask 077

REMOTE_ROOT="/data1/home/sunyiq/kalmannet_daily_camels_per_basin_pilots_20260901"
DEPLOYMENT_ID="DAILY_CAMELS_KNET_PER_BASIN_BUNDLE_DEPLOY3_SEQ12"
SOURCE_DIRECTORY="${REMOTE_ROOT}/deployments/${DEPLOYMENT_ID}/source"
EXPECTED_BUNDLE_MANIFEST_SHA256="7c80bde3db930cfd69f015f3d575bf074ffca6eda5b400731a286ffa0f0bbd86"
EXECUTION_ID="DAILY_CAMELS_KNET_PER_BASIN_PILOT_08070200_A800_TRAIN1_SEQ18"
JOB_ID="217562"
JOB_NAME="kdpp-08070200-s18"
CONFIG_PATH="${SOURCE_DIRECTORY}/configs/daily_camels_knet_per_basin_pilot_08070200.json"
EXPECTED_CONFIG_SHA256="2c11e9d61edd7a7f02343e0b0d1e305dd80629a658b0f4f8e684ba0efb305d95"
STATUS_DIRECTORY="${REMOTE_ROOT}/status"
RUN_DIRECTORY="${REMOTE_ROOT}/runs/${EXECUTION_ID}"
STDOUT_FILE="${STATUS_DIRECTORY}/${EXECUTION_ID}.slurm-${JOB_ID}.out"
STDERR_FILE="${STATUS_DIRECTORY}/${EXECUTION_ID}.slurm-${JOB_ID}.err"
EXPECTED_STDOUT_SHA256="17290c4e227fc0c397d49fe77d8eed30109e41afe384ca4e04a53d6810a77296"
EXPECTED_STDERR_SHA256="2ed115e24b85c677e74b78c4e69db4749e8bb188ae563ee420ce24ae0ba8d1a9"
GPU_LOG="${STATUS_DIRECTORY}/${EXECUTION_ID}.gpu.csv"
FAILURE_AUDIT="${STATUS_DIRECTORY}/${EXECUTION_ID}.failure_audit_seq23.json"

echo '=== READ-ONLY PARTIAL-FAILURE AUDIT: 08070200 ==='
date --iso-8601=seconds
hostname
echo 'channel=kalmannet-daily-perbasin sequence=23 purpose=independent-read-only-audit-of-terminal-eleven-state-training-failure'
echo 'signals_sent=0 submissions_created=0 training_restarts=0 scientific_contract_changes=0'

if [[ "$(sha256sum "${SOURCE_DIRECTORY}/bundle_manifest.json" | awk '{print $1}')" != "${EXPECTED_BUNDLE_MANIFEST_SHA256}" ]]; then
  echo 'deployed bundle manifest changed' >&2
  exit 160
fi
if [[ "$(sha256sum "${CONFIG_PATH}" | awk '{print $1}')" != "${EXPECTED_CONFIG_SHA256}" ]]; then
  echo 'frozen 08070200 configuration changed' >&2
  exit 161
fi
if [[ "$(sha256sum "${STDOUT_FILE}" | awk '{print $1}')" != "${EXPECTED_STDOUT_SHA256}" ]] || \
   [[ "$(sha256sum "${STDERR_FILE}" | awk '{print $1}')" != "${EXPECTED_STDERR_SHA256}" ]]; then
  echo 'terminal standard output or error evidence changed' >&2
  exit 162
fi
if ! sacct -j "${JOB_ID}" -X --format=JobIDRaw,State,ExitCode -n -P | \
  grep -F -x -q "${JOB_ID}|FAILED|1:0"; then
  echo 'scheduler terminal failure identity changed' >&2
  exit 163
fi
if [[ -e "${FAILURE_AUDIT}" ]]; then
  echo 'refusing to replace existing partial-failure audit' >&2
  exit 164
fi

echo '=== SCHEDULER RESOURCE EVIDENCE ==='
sacct -j "${JOB_ID}" --units=K -n -P \
  --format=JobIDRaw,JobName,State,ExitCode,Elapsed,MaxRSS,MaxVMSize,AveRSS,AllocTRES

set +u
source "/data1/home/${USER}/miniconda3/etc/profile.d/conda.sh"
conda activate nh_final
set -u
export PYTHONDONTWRITEBYTECODE=1
export PYTHONPATH="${SOURCE_DIRECTORY}/src:${SOURCE_DIRECTORY}"
python - "${SOURCE_DIRECTORY}" "${CONFIG_PATH}" "${RUN_DIRECTORY}" \
  "${STDERR_FILE}" "${GPU_LOG}" "${FAILURE_AUDIT}" "${EXECUTION_ID}" \
  "${JOB_ID}" <<'PY'
from __future__ import annotations

from collections.abc import Mapping
import importlib.util
import json
import math
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile


source = Path(sys.argv[1]).resolve()
configuration_path = Path(sys.argv[2]).resolve()
run = Path(sys.argv[3]).resolve()
stderr_path = Path(sys.argv[4]).resolve()
gpu_log = Path(sys.argv[5]).resolve()
audit_path = Path(sys.argv[6]).resolve()
execution_id = sys.argv[7]
job_id = sys.argv[8]

verifier_path = source / "scripts/verify_daily_camels_knet_per_basin_pilot.py"
specification = importlib.util.spec_from_file_location("partial_failure_verifier_base", verifier_path)
if specification is None or specification.loader is None:
    raise RuntimeError("cannot load independent verifier")
verifier = importlib.util.module_from_spec(specification)
sys.modules[specification.name] = verifier
specification.loader.exec_module(verifier)

configuration = verifier._read_json(configuration_path)
preflight = verifier._read_json(run / "preflight.json")
history = json.loads(
    (run / "epoch_history.json").read_text(encoding="utf-8"),
    object_pairs_hook=verifier._reject_duplicate_members,
    parse_constant=lambda constant: (_ for _ in ()).throw(
        ValueError(f"non-finite history constant: {constant}")
    ),
)
if not isinstance(history, list) or len(history) != 58:
    raise ValueError("partial history must contain exactly epoch zero through epoch 57")

checkpoint_objectives: list[float] = []
epoch_objectives: list[dict[str, object]] = []
for epoch, row in enumerate(history):
    if not isinstance(row, Mapping) or row.get("epoch") != epoch:
        raise ValueError("partial history epochs are not contiguous")
    if row.get("optimizer_steps") != epoch:
        raise ValueError("partial optimizer-step count differs")
    if row.get("training_forecast_error_events") != epoch * verifier.TRAINING_EVENTS_PER_EPOCH:
        raise ValueError("partial training-event count differs")
    checkpoint = verifier._require_finite_number(
        row.get("checkpoint_objective_728"), f"epoch {epoch} checkpoint objective"
    )
    reporting = verifier._require_finite_number(
        row.get("reporting_objective_712"), f"epoch {epoch} reporting objective"
    )
    if epoch == 0:
        if row.get("training_objective") is not None:
            raise ValueError("epoch-zero training objective must be null")
        training = None
        post_step = None
    else:
        training = verifier._require_finite_number(
            row.get("training_objective"), f"epoch {epoch} training objective"
        )
        post_step = verifier._require_finite_number(
            row.get("same_segment_post_step_objective"),
            f"epoch {epoch} same-segment objective",
        )
        verifier._require_finite_number(
            row.get("gradient_norm_before_clip"), f"epoch {epoch} gradient norm"
        )
        names = row.get("nonzero_gradient_parameter_names")
        if not isinstance(names, list) or not names:
            raise ValueError(f"epoch {epoch} lacks nonzero-gradient evidence")
    verifier._require_sha256(row.get("parameter_sha256"), "history parameter SHA-256")
    verifier._require_sha256(row.get("prediction_sha256"), "history prediction SHA-256")
    if row.get("target_count_by_lead") != {
        str(lead): verifier.REPORTING_TARGET_COUNT for lead in verifier.LEADS
    }:
        raise ValueError("partial reporting target geometry changed")
    checkpoint_objectives.append(checkpoint)
    epoch_objectives.append(
        {
            "epoch": epoch,
            "training_objective": training,
            "same_segment_post_step_objective": post_step,
            "checkpoint_objective_728": checkpoint,
            "reporting_objective_712": reporting,
        }
    )

best_epoch = min(range(len(history)), key=lambda epoch: checkpoint_objectives[epoch])
if best_epoch != 10:
    raise ValueError(f"partial best epoch changed: {best_epoch}")

configuration_sha256 = verifier._sha256_file(configuration_path)
if configuration_sha256 != "2c11e9d61edd7a7f02343e0b0d1e305dd80629a658b0f4f8e684ba0efb305d95":
    raise ValueError("configuration SHA-256 changed")
model = configuration.get("model")
data = configuration.get("data")
if not isinstance(model, Mapping) or not isinstance(data, Mapping):
    raise TypeError("configuration sections are missing")
identity = {
    "experiment_id": configuration.get("experiment_id"),
    "execution_id": execution_id,
    "basin_id": configuration.get("basin_id"),
    "state_dimension": int(model.get("state_dimension", -1)),
    "configuration_sha256": configuration_sha256,
    "source_sha256": configuration.get("source_sha256"),
    "input_sha256": {
        str(data["archive_path"]): str(data["archive_sha256"]),
        str(data["selection_path"]): str(data["selection_sha256"]),
    },
}
for key in ("experiment_id", "execution_id", "basin_id", "state_dimension", "configuration_sha256"):
    if preflight.get(key) != identity[key]:
        raise ValueError(f"preflight identity differs: {key}")
if preflight.get("source_sha256") != identity["source_sha256"]:
    raise ValueError("preflight source registry differs")
if preflight.get("input_sha256") != identity["input_sha256"]:
    raise ValueError("preflight input registry differs")

previous_checkpoint_sha256 = None
for epoch, row in enumerate(history):
    checkpoint_path = run / "checkpoints" / f"epoch_{epoch:03d}.pt"
    prediction_path = run / "predictions" / f"epoch_{epoch:03d}.npz"
    checkpoint_sha256 = verifier._sha256_file(checkpoint_path)
    header = verifier._parse_checkpoint_envelope(checkpoint_path)
    if header.get("identity") != identity:
        raise ValueError(f"checkpoint identity differs at epoch {epoch}")
    if header.get("completed_epoch") != epoch or header.get("optimizer_steps") != epoch:
        raise ValueError(f"checkpoint progress differs at epoch {epoch}")
    if header.get("training_forecast_error_events") != epoch * verifier.TRAINING_EVENTS_PER_EPOCH:
        raise ValueError(f"checkpoint event count differs at epoch {epoch}")
    if header.get("previous_checkpoint_sha256") != previous_checkpoint_sha256:
        raise ValueError(f"checkpoint chain differs at epoch {epoch}")
    if verifier._sha256_file(prediction_path) != row.get("prediction_sha256"):
        raise ValueError(f"prediction SHA-256 differs at epoch {epoch}")
    previous_checkpoint_sha256 = checkpoint_sha256

for absent in (
    run / "checkpoints" / "epoch_058.pt",
    run / "predictions" / "epoch_058.npz",
    run / "result_summary.json",
    run / "manifest.sha256.json",
    run / "completion.marker.json",
    run / "checkpoints" / "best.pt",
    run / "checkpoints" / "last.pt",
):
    if absent.exists():
        raise ValueError(f"unexpected post-failure artifact exists: {absent.name}")

best_arrays = verifier._load_npz(run / "predictions" / f"epoch_{best_epoch:03d}.npz")
if set(best_arrays) != verifier._prediction_members(""):
    raise ValueError("partial best prediction member set changed")
baseline_path = run / "baseline_predictions.npz"
baseline_arrays = verifier._load_npz(baseline_path)
expected_baseline_members: set[str] = set()
for prefix in verifier.COMPARISON_PREFIX.values():
    if prefix:
        expected_baseline_members.update(verifier._prediction_members(prefix))
if set(baseline_arrays) != expected_baseline_members:
    raise ValueError("baseline prediction member set changed")
for lead in verifier.LEADS:
    if not verifier.np.array_equal(
        verifier._array(best_arrays, "", "issue_indices", lead), verifier.REPORTING_ISSUES
    ):
        raise ValueError(f"partial issue geometry differs at lead {lead}")
    if not verifier.np.array_equal(
        verifier._array(best_arrays, "", "target_indices", lead),
        verifier.REPORTING_ISSUES + lead,
    ):
        raise ValueError(f"partial target geometry differs at lead {lead}")
for prefix in verifier.COMPARISON_PREFIX.values():
    if prefix:
        verifier._assert_same_geometry(best_arrays, baseline_arrays, candidate_prefix=prefix)

comparisons: dict[str, Mapping[str, object]] = {}
for method, prefix in verifier.COMPARISON_PREFIX.items():
    arrays = best_arrays if not prefix else baseline_arrays
    comparisons[method] = verifier._independent_score(arrays, prefix)
best_row = history[best_epoch]
verifier._assert_close(
    best_row.get("reporting_objective_712"),
    float(comparisons["kalmannet"]["physical_unit_multilead_mse"]),
    "partial best reporting objective",
)
for field in ("mse_by_lead", "nse_by_lead"):
    for lead in verifier.LEADS:
        verifier._assert_close(
            best_row[field][str(lead)],
            float(comparisons["kalmannet"][field][str(lead)]),
            f"partial best {field} lead {lead}",
        )

deltas = {
    str(lead): float(comparisons["kalmannet"]["nse_by_lead"][str(lead)])
    - float(comparisons["per_basin_unscented_kalman_filter"]["nse_by_lead"][str(lead)])
    for lead in verifier.LEADS
}
mean_delta = math.fsum(deltas.values()) / len(deltas)
relative_status = (
    "KALMANNET_ADVANTAGE"
    if mean_delta >= 0.01
    else "UNSCENTED_KALMAN_FILTER_ADVANTAGE"
    if mean_delta <= -0.01
    else "NO_DISCERNIBLE_ADVANTAGE"
)
partial_gate = {
    "objective_improvement": checkpoint_objectives[0] - checkpoint_objectives[best_epoch],
    "best_epoch_after_zero": best_epoch > 0,
    "parameter_changed": history[best_epoch]["parameter_sha256"] != history[0]["parameter_sha256"],
    "each_lead_nse_above_0_6": all(
        float(comparisons["kalmannet"]["nse_by_lead"][str(lead)]) > 0.6
        for lead in verifier.LEADS
    ),
    "each_lead_mse_better_than_open_loop": all(
        float(comparisons["kalmannet"]["mse_by_lead"][str(lead)])
        < float(comparisons["open_loop_physical_model"]["mse_by_lead"][str(lead)])
        for lead in verifier.LEADS
    ),
}

bundle_manifest_path = source / "bundle_manifest.json"
bundle_manifest = verifier._read_json(bundle_manifest_path)
if verifier._sha256_file(bundle_manifest_path) != "7c80bde3db930cfd69f015f3d575bf074ffca6eda5b400731a286ffa0f0bbd86":
    raise ValueError("deployed bundle manifest SHA-256 differs")
if bundle_manifest.get("formal_evaluation_enabled") is not False:
    raise PermissionError("deployed bundle enables formal evaluation")
if bundle_manifest.get("historical_evaluation_member_count") != 0:
    raise PermissionError("deployed bundle contains formal evaluation members")
if configuration.get("formal_evaluation_enabled") is not False:
    raise PermissionError("configuration enables formal evaluation")
if data.get("historical_evaluation_access_authorized") is not False:
    raise PermissionError("configuration authorizes historical evaluation access")
if preflight.get("formal_evaluation_enabled") is not False:
    raise PermissionError("preflight enables formal evaluation")
if preflight.get("historical_evaluation_access_authorized") is not False:
    raise PermissionError("preflight authorizes historical evaluation access")
for member in run.rglob("*"):
    relative = member.relative_to(run).as_posix().lower()
    if any(token in relative for token in verifier.FORBIDDEN_PATH_TOKENS):
        raise PermissionError(f"partial run contains forbidden path: {relative}")

stderr_text = stderr_path.read_text(encoding="utf-8")
expected_failure = "FloatingPointError: non-finite gradient in FC2.2.weight"
if stderr_text.count(expected_failure) != 1:
    raise ValueError("terminal non-finite-gradient evidence changed")

accounting = subprocess.run(
    [
        "sacct",
        "-j",
        job_id,
        "--units=K",
        "-n",
        "-P",
        "--format=JobIDRaw,JobName,State,ExitCode,Elapsed,MaxRSS,MaxVMSize,AveRSS,AllocTRES",
    ],
    check=True,
    capture_output=True,
    text=True,
).stdout.splitlines()
accounting_rows = [line.split("|") for line in accounting if line.strip()]
if not any(row[0] == job_id and row[2] == "FAILED" and row[3] == "1:0" for row in accounting_rows):
    raise ValueError("scheduler terminal state changed")

def slurm_memory_bytes(value: str) -> int | None:
    text = value.strip()
    if not text:
        return None
    match = re.fullmatch(r"([0-9]+(?:\.[0-9]+)?)([KMGTP]?)", text)
    if match is None:
        raise ValueError(f"unknown Slurm memory format: {value}")
    multiplier = {"": 1024, "K": 1024, "M": 1024**2, "G": 1024**3, "T": 1024**4, "P": 1024**5}[match.group(2)]
    return int(float(match.group(1)) * multiplier)

host_values = [value for row in accounting_rows if (value := slurm_memory_bytes(row[5])) is not None]
host_peak_bytes = max(host_values) if host_values else None
gpu_peak_mib = -1
gpu_rows = 0
for line in gpu_log.read_text(encoding="utf-8").splitlines():
    fields = [field.strip() for field in line.split(",")]
    if len(fields) < 5:
        continue
    gpu_peak_mib = max(gpu_peak_mib, int(fields[4]))
    gpu_rows += 1
if gpu_rows != 2338 or gpu_peak_mib != 603:
    raise ValueError("independent graphics-memory evidence changed")

audit = {
    "schema_version": "daily_camels_knet_per_basin_partial_failure_verification_v1",
    "verification_status": "PASS",
    "experiment_id": identity["experiment_id"],
    "execution_id": execution_id,
    "basin_id": identity["basin_id"],
    "state_dimension": identity["state_dimension"],
    "configuration_sha256": configuration_sha256,
    "scheduler_job_id": int(job_id),
    "scheduler_state": "FAILED",
    "scheduler_exit_code": "1:0",
    "failure_classification": "FROZEN_TRAINING_NUMERICAL_FAILURE",
    "failure_attempted_epoch": 58,
    "failure_error": expected_failure,
    "technical_success": False,
    "scientific_capability_passed": False,
    "scientific_capability_status": "NOT_ASSESSABLE_AS_COMPLETED_RUN",
    "convergence_status": "NOT_ESTABLISHED_TERMINAL_NONFINITE_GRADIENT",
    "completed_epoch": 57,
    "history_rows": len(history),
    "epoch_zero_checkpoint_objective_728": checkpoint_objectives[0],
    "best_epoch": best_epoch,
    "best_checkpoint_objective_728": checkpoint_objectives[best_epoch],
    "last_epoch": 57,
    "last_checkpoint_objective_728": checkpoint_objectives[-1],
    "optimizer_steps": 57,
    "training_forecast_error_events": 57 * verifier.TRAINING_EVENTS_PER_EPOCH,
    "epoch_objectives": epoch_objectives,
    "comparisons_at_partial_best_checkpoint": comparisons,
    "kalmannet_minus_unscented_kalman_filter_nse_by_lead": deltas,
    "kalmannet_minus_unscented_kalman_filter_mean_nse": mean_delta,
    "relative_accuracy_status_at_partial_best_checkpoint": relative_status,
    "partial_best_scientific_gate_evidence": partial_gate,
    "checkpoint_envelope_count": len(history),
    "prediction_archive_count": len(history),
    "independent_reporting_score_recomputation": True,
    "independent_checkpoint_objective_recomputation": False,
    "baseline_predictions_sha256": verifier._sha256_file(baseline_path),
    "last_checkpoint_sha256": previous_checkpoint_sha256,
    "stderr_sha256": verifier._sha256_file(stderr_path),
    "bundle_manifest_sha256": verifier._sha256_file(bundle_manifest_path),
    "formal_evaluation_access_count": 0,
    "formal_evaluation_evidence": {
        "bundle_member_count": bundle_manifest.get("historical_evaluation_member_count"),
        "bundle_enabled": bundle_manifest.get("formal_evaluation_enabled"),
        "configuration_enabled": configuration.get("formal_evaluation_enabled"),
        "configuration_access_authorized": data.get("historical_evaluation_access_authorized"),
        "preflight_enabled": preflight.get("formal_evaluation_enabled"),
        "preflight_access_authorized": preflight.get("historical_evaluation_access_authorized"),
        "forbidden_partial_run_path_count": 0,
        "runtime_gate_access_count": 0,
        "failed_process_in_memory_ledger_serialized": False,
    },
    "resources": {
        "host_peak_resident_memory_bytes": host_peak_bytes,
        "host_peak_measurement_basis": "slurm_sacct_maxrss" if host_peak_bytes is not None else "unavailable_after_failure",
        "gpu_observed_peak_memory_mib": gpu_peak_mib,
        "gpu_observation_rows": gpu_rows,
        "framework_gpu_peak_allocated_bytes": None,
        "framework_gpu_peak_reserved_bytes": None,
        "framework_peak_status": "UNAVAILABLE_RESULT_SUMMARY_NOT_WRITTEN_AFTER_FAILURE",
    },
    "scheduler_accounting_rows": accounting,
}
encoded = (
    json.dumps(audit, sort_keys=True, separators=(",", ":"), allow_nan=False)
    + "\n"
).encode("utf-8")
audit_path.parent.mkdir(parents=True, exist_ok=True)
descriptor, temporary_name = tempfile.mkstemp(
    prefix=f".{audit_path.name}.", suffix=".tmp", dir=audit_path.parent
)
temporary = Path(temporary_name)
try:
    with os.fdopen(descriptor, "wb") as handle:
        handle.write(encoded)
        handle.flush()
        os.fsync(handle.fileno())
    if audit_path.exists():
        raise FileExistsError(audit_path)
    os.replace(temporary, audit_path)
finally:
    if temporary.exists():
        temporary.unlink()
print(encoded.decode("utf-8").strip())
PY

echo '=== PARTIAL-FAILURE AUDIT HASH ==='
sha256sum "${FAILURE_AUDIT}"
echo '=== CURRENT PILOT JOB COUNTS ==='
squeue -h -u sunyiq -o '%i|%j|%T|%N' | \
  awk -F'|' '$2 ~ /^kdpp-(04105700|08070200|09035800)-s/ {count++} END {print "active_three_pilot_training=" count+0}'
echo '=== AUDIT COMPLETE: FAILURE VERIFIED, NO TRAINING OR SIGNAL ==='
