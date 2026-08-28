#!/bin/bash
set -eo pipefail

ROOT="/data1/home/sunyiq/zhenjiang_d32_differentiable_ukf_20260828_r2"
PROJECT_ROOT="${ROOT}/run"
INPUT_DIR="${ROOT}/inputs/pre2024-v1"
ATTEMPT="${ROOT}/runs/smoke/ZHD32-DUKF-HPC-SMOKE-V1/attempt_001"
JOB_FILE="${ROOT}/jobs/smoke_job_id.txt"
JID="$(tr -d '\r\n' < "${JOB_FILE}")"
[[ "${JID}" =~ ^[0-9]+$ ]] || { echo "[FATAL] invalid smoke job identifier"; exit 1; }

parent_row="$(
  sacct -j "${JID}" -n -P \
    --format=JobIDRaw,State,ExitCode,ElapsedRaw,NodeList | \
    awk -F'|' -v id="${JID}" '$1 == id {print; exit}'
)"
[ -n "${parent_row}" ] || { echo "[FATAL] parent scheduler row is absent"; exit 1; }
IFS='|' read -r observed_job state exit_code elapsed_raw node_list <<< "${parent_row}"
[ "${observed_job}" = "${JID}" ] || { echo "[FATAL] scheduler job identity changed"; exit 1; }
[ "${state}" = "COMPLETED" ] || { echo "[FATAL] smoke scheduler state is ${state}"; exit 1; }
[ "${exit_code}" = "0:0" ] || { echo "[FATAL] smoke scheduler exit is ${exit_code}"; exit 1; }
[[ "${elapsed_raw}" =~ ^[0-9]+$ ]] || { echo "[FATAL] invalid elapsed seconds"; exit 1; }
[ "${elapsed_raw}" -gt 0 ] || { echo "[FATAL] elapsed seconds is zero"; exit 1; }
[ -n "${node_list}" ] || { echo "[FATAL] compute node is absent"; exit 1; }
[ "${node_list}" != "ngu002" ] || { echo "[FATAL] excluded node was used"; exit 1; }

echo "SCHEDULER_GATE=PASS|job=${JID}|state=${state}|exit=${exit_code}|elapsed_seconds=${elapsed_raw}|node=${node_list}"
sacct -j "${JID}" -P \
  --format=JobIDRaw,JobName,Partition,State,ExitCode,ElapsedRaw,NodeList,AllocTRES,MaxRSS

export PYTHONDONTWRITEBYTECODE=1
export MKL_THREADING_LAYER=GNU
export MKL_SERVICE_FORCE_INTEL=1
source "/data1/home/${USER}/miniconda3/etc/profile.d/conda.sh"
conda activate nh_final
cd "${PROJECT_ROOT}"
python -u scripts/modeling/zhenjiang_d32_gru_differentiable_ukf_runner_v1.py \
  --verify-output "${ATTEMPT}"

python - "${ATTEMPT}" "${INPUT_DIR}" "${elapsed_raw}" "${node_list}" <<'PY'
from pathlib import Path
import csv
import hashlib
import json
import math
import sys

attempt = Path(sys.argv[1]).resolve()
input_dir = Path(sys.argv[2]).resolve()
elapsed_raw = int(sys.argv[3])
node_list = sys.argv[4]

def require(condition, message):
    if not condition:
        raise SystemExit(message)

def load_json(name):
    return json.loads((attempt / name).read_text(encoding="utf-8"))

def load_csv(name):
    with (attempt / name).open("r", encoding="utf-8", newline="") as handle:
        return list(csv.DictReader(handle))

def integer(row, key):
    value = int(row[key])
    require(str(value) == row[key], f"{key} is not a canonical integer")
    return value

def finite_float(row, key, *, positive=False):
    value = float(row[key])
    require(math.isfinite(value), f"{key} is nonfinite")
    if positive:
        require(value > 0.0, f"{key} is not positive")
    return value

counters = {
    "test_target_rows_read": 0,
    "test_target_values_parsed": 0,
    "test_target_values_loaded": 0,
}

completion = load_json("completion_manifest.json")
require(completion.get("status") == "technical_pass", "completion status changed")
require(completion.get("file_count") == 12, "completion file count changed")

preflight = load_json("gpu_technical_preflight.json")
require(preflight.get("status") == "pass_technical_only", "graphics-processor preflight status changed")
require(preflight.get("device") == "cuda:0", "graphics-processor device changed")
require("RTX 3090" in preflight.get("device_name", ""), "graphics-processor model changed")
require(preflight.get("device_capability") == [8, 6], "graphics-processor capability changed")
require(preflight.get("base_batch_size") == 32, "graphics-processor batch size changed")
require(preflight.get("gradient_scalar_count") == 38, "preflight gradient count changed")
require(preflight.get("nonfinite_gradient_count") == 0, "preflight has nonfinite gradient")
require(preflight.get("zero_gradient_count") == 0, "preflight has zero gradient")
require(preflight.get("spectral_floor_mask") == [False, True], "spectral-floor mask changed")
require(type(preflight.get("peak_allocated_bytes")) is int and preflight["peak_allocated_bytes"] > 0, "peak memory is invalid")
require(preflight.get("backbone_state_sha256_before") == preflight.get("backbone_state_sha256_after"), "preflight changed frozen backbone")
preflight_seconds = preflight.get("forward_backward_seconds")
require(isinstance(preflight_seconds, (int, float)) and math.isfinite(preflight_seconds) and preflight_seconds > 0.0, "preflight time is invalid")

data = load_json("data_identity.json")
require(data.get("input_directory") == str(input_dir), "smoke input directory changed")
require(data.get("training_base_sample_count") == 46182, "training sample count changed")
require(data.get("validation_base_sample_count") == 8046, "validation sample count changed")
require(data.get("last_loaded_target_time_beijing") == "2023-12-31T23:00:00+08:00", "last loaded target time changed")
require(data.get("test_target_counters") == counters, "later target counters changed")
identities = data.get("input_content_identities")
require(isinstance(identities, list) and len(identities) == 13, "input content identity count changed")

physical = json.loads((input_dir / "pre2024_input_manifest.json").read_text(encoding="utf-8"))
require(physical.get("file_count") == 13, "physical input file count changed")
require(physical.get("maximum_target_time_beijing") == "2023-12-31T23:00:00+08:00", "physical maximum target time changed")
require(type(physical.get("later_target_bytes_requested")) is int and physical["later_target_bytes_requested"] == 0, "physical later-target counter changed")
physical_map = {
    row["path"]: (row["verification_scope"], row["byte_count"], row["sha256"])
    for row in physical["files"]
}
loaded_map = {
    row["relative_path"]: (row["verification_scope"], row["byte_count"], row["sha256"])
    for row in identities
}
require(loaded_map == physical_map, "loaded and physical input identities differ")

training = load_csv("training_history.csv")
require(len(training) == 1, "smoke training history is not one epoch")
history = training[0]
require(integer(history, "epoch") == 1, "smoke epoch changed")
require(integer(history, "training_base_sample_count") == 64, "smoke training sample count changed")
require(integer(history, "validation_base_sample_count") == 64, "smoke validation sample count changed")
require(integer(history, "training_valid_cell_count") == 44160, "smoke training cell count changed")
require(integer(history, "validation_valid_cell_count") == 44160, "smoke validation cell count changed")
finite_float(history, "training_mae_m")
finite_float(history, "validation_assimilation_mae_m")
finite_float(history, "validation_open_loop_mae_m")
epoch_seconds = finite_float(history, "epoch_seconds", positive=True)

gradients = load_csv("gradient_history.csv")
require(len(gradients) == 2, "smoke gradient history is not two batches")
for row in gradients:
    require(integer(row, "gradient_scalar_count") == 38, "training gradient count changed")
    require(integer(row, "nonfinite_gradient_count") == 0, "training has nonfinite gradient")
    require(integer(row, "zero_gradient_count") == 0, "training has zero gradient")
    for key in (
        "gradient_l2_before_clip",
        "gradient_max_abs_before_clip",
        "process_gradient_l2_before_clip",
        "observation_gradient_l2_before_clip",
        "clip_returned_l2",
    ):
        finite_float(row, key, positive=True)

selection = load_json("selection_validation_summary.json")
require(selection.get("status") == "technical_pass", "selection status changed")
require(selection.get("best_epoch") == 1 and selection.get("completed_epoch") == 1, "smoke selection epoch changed")
require(selection.get("development_selection_not_held_out") is True, "development-set disclosure changed")
require(selection.get("held_out_target_access") is False, "held-out target access changed")
require(selection.get("scientific_conclusion_authorized") is False, "scientific conclusion boundary changed")
require(selection.get("test_target_counters") == counters, "selection later-target counters changed")
require(selection.get("backbone_state_sha256_before") == selection.get("backbone_state_sha256_after"), "training changed frozen backbone")

run = load_json("run_identity.json")
require(run.get("experiment_id") == "ZHD32-DUKF-HPC-SMOKE-V1", "smoke experiment identity changed")
require(run.get("attempt_id") == "attempt_001", "smoke attempt identity changed")
require(run.get("run_type") == "technical_hpc_smoke", "smoke run type changed")
require(run.get("seed") == 17, "smoke seed changed")
require(run.get("completion_status") == "technical_pass", "smoke run completion changed")
require(run.get("authorization") == {"held_out_target_access": False, "scientific_conclusion": False, "paid_compute": True}, "smoke authorization changed")
environment = run.get("environment", {})
require(environment.get("device") == "cuda:0" and environment.get("cuda_available") is True, "run CUDA identity changed")
require("RTX 3090" in environment.get("cuda_device_name", ""), "run graphics-processor identity changed")
require(environment.get("cuda_device_capability") == [8, 6], "run device capability changed")
require(environment.get("deterministic_algorithms_enabled") is True, "deterministic algorithms are disabled")
require(environment.get("cudnn_benchmark") is False, "cuDNN benchmark is enabled")
require(environment.get("cudnn_deterministic") is True, "cuDNN deterministic mode is disabled")
require(environment.get("cuda_matmul_allow_tf32") is False, "matrix TensorFloat-32 is enabled")
require(environment.get("cudnn_allow_tf32") is False, "cuDNN TensorFloat-32 is enabled")
require(run.get("backbone_state_sha256_before") == run.get("backbone_state_sha256_after"), "run changed frozen backbone")

noise = load_json("best_noise_parameters.json")
process = noise.get("process_variances")
observation = noise.get("observation_variances")
require(isinstance(process, list) and len(process) == 32, "process-noise parameter count changed")
require(isinstance(observation, list) and len(observation) == 6, "observation-noise parameter count changed")
require(all(isinstance(value, (int, float)) and math.isfinite(value) and value > 0.0 for value in process + observation), "noise parameter is invalid")

per_epoch_batches = math.ceil(46182 / 32) + math.ceil(8046 / 32)
require(per_epoch_batches == 1696, "formal batch projection changed")
seconds_per_batch = max(epoch_seconds / 4.0, float(preflight_seconds))
one_time_seconds = max(0.0, elapsed_raw - epoch_seconds)
single_without_margin = one_time_seconds + seconds_per_batch * per_epoch_batches * 20
single_with_margin = single_without_margin * 1.25
require(single_with_margin <= 72.0 * 3600.0, "projected single-model wall time exceeds 72 hours")

report = {
    "gate": "PASS",
    "technical_only": True,
    "scientific_conclusion": False,
    "held_out_target_access": False,
    "scheduler_elapsed_seconds": elapsed_raw,
    "node": node_list,
    "epoch_seconds_for_four_batches": epoch_seconds,
    "preflight_forward_backward_seconds": float(preflight_seconds),
    "conservative_seconds_per_batch": seconds_per_batch,
    "formal_batches_per_epoch": per_epoch_batches,
    "maximum_epochs": 20,
    "margin_fraction": 0.25,
    "projected_single_model_hours_with_margin": single_with_margin / 3600.0,
    "projected_three_model_serial_hours_with_margin": 3.0 * single_with_margin / 3600.0,
    "completion_manifest_sha256": hashlib.sha256((attempt / "completion_manifest.json").read_bytes()).hexdigest(),
}
print("SMOKE_STRICT_GATE=PASS")
print(json.dumps(report, indent=2, sort_keys=True))
PY

for experiment_id in ZHD32-DUKF-S17-V1 ZHD32-DUKF-S29-V1 ZHD32-DUKF-S43-V1; do
  formal_attempt="${ROOT}/runs/formal/${experiment_id}/attempt_001"
  [ ! -e "${formal_attempt}" ] || { echo "[FATAL] formal attempt already exists: ${formal_attempt}"; exit 1; }
  [ ! -e "${formal_attempt}.partial" ] || { echo "[FATAL] partial formal attempt exists: ${formal_attempt}.partial"; exit 1; }
done
echo "FORMAL_OUTPUT_ABSENCE_GATE=PASS"
