#!/usr/bin/env bash
set -Eeuo pipefail

RUN_ROOT="/data1/home/sunyiq/kalmannet_daily_camels_knet_a38_a800_train1_20260828"
EXPERIMENT_ID="DAILY_CAMELS_KNET_FIXED_FULL_TRAINING_COVERAGE_EPOCH40_TO80_RESUME_STEP_MONOTONICITY_DIAGNOSTIC_V1_20260828_A38"
RUN_DIR="${RUN_ROOT}/runs/${EXPERIMENT_ID}"
SUMMARY="${RUN_DIR}/result_summary.json"
HISTORY="${RUN_DIR}/epoch_history.json"
RESULT80="/data1/home/sunyiq/hpc_mailbox/outbox/kalmannet-daily-camels/result_80.txt"
EXPECTED_RESULT80_SHA256="2446ca2fab69bbdbc98c47e083f4d0a8ad6a86d1a01b684d1f0d7d95582c1589"
EXPECTED_RESULT80_SIZE="7398611"
EXPECTED_SUMMARY_SHA256="e26b4e83af12bb2ec7d5031c9ca371ff0065aa159b73ebf489bccca4f0b23a01"
EXPECTED_SUMMARY_SIZE="7307287"
EXPECTED_HISTORY_SHA256="2b0a5987c925edb42eb7189d3ddf4fd111c9fc5e55087d3c7d7eb55abdd40517"
EXPECTED_HISTORY_SIZE="7513499"

sha256_file() {
  sha256sum "$1" | awk '{print $1}'
}

require_safe_regular_file() {
  local path="$1"
  local resolved
  [[ -f "$path" && ! -L "$path" ]] || { echo "safe diagnostic input is absent or symbolic: $path" >&2; exit 41; }
  resolved="$(readlink -f -- "$path")"
  case "$resolved" in
    "${RUN_DIR}/result_summary.json"|"${RUN_DIR}/epoch_history.json") ;;
    *) echo "safe diagnostic input resolved outside the fixed allow-list: $resolved" >&2; exit 41 ;;
  esac
}

[[ -f "$RESULT80" && ! -L "$RESULT80" ]] || { echo "sequence 80 receipt is absent or symbolic" >&2; exit 41; }
[[ "$(sha256_file "$RESULT80")" == "$EXPECTED_RESULT80_SHA256" ]] || { echo "sequence 80 receipt hash differs" >&2; exit 41; }
[[ "$(stat -c '%s' "$RESULT80")" == "$EXPECTED_RESULT80_SIZE" ]] || { echo "sequence 80 receipt size differs" >&2; exit 41; }
grep -Fxq '### channel=kalmannet-daily-camels seq=80' "$RESULT80" || { echo "sequence 80 receipt header differs" >&2; exit 41; }
grep -Fxq 'independently recomputed global training gate differs' "$RESULT80" || { echo "sequence 80 failure identity differs" >&2; exit 41; }
grep -Fxq '### exit_code=1' "$RESULT80" || { echo "sequence 80 exit code differs" >&2; exit 41; }
grep -Fxq "${HISTORY}|size=${EXPECTED_HISTORY_SIZE}|sha256=${EXPECTED_HISTORY_SHA256}" "$RESULT80" || { echo "sequence 80 epoch-history inventory identity differs" >&2; exit 41; }
grep -Fxq "${SUMMARY}|size=${EXPECTED_SUMMARY_SIZE}|sha256=${EXPECTED_SUMMARY_SHA256}" "$RESULT80" || { echo "sequence 80 result-summary inventory identity differs" >&2; exit 41; }

require_safe_regular_file "$SUMMARY"
require_safe_regular_file "$HISTORY"
[[ "$(sha256_file "$SUMMARY")" == "$EXPECTED_SUMMARY_SHA256" && "$(stat -c '%s' "$SUMMARY")" == "$EXPECTED_SUMMARY_SIZE" ]] || { echo "fixed result summary identity differs" >&2; exit 41; }
[[ "$(sha256_file "$HISTORY")" == "$EXPECTED_HISTORY_SHA256" && "$(stat -c '%s' "$HISTORY")" == "$EXPECTED_HISTORY_SIZE" ]] || { echo "fixed epoch history identity differs" >&2; exit 41; }

printf 'SEQ81_A38_GLOBAL_GATE_DIAGNOSTIC_INPUT summary_sha256=%s summary_size=%s history_sha256=%s history_size=%s result80_sha256=%s\n' \
  "$EXPECTED_SUMMARY_SHA256" "$EXPECTED_SUMMARY_SIZE" \
  "$EXPECTED_HISTORY_SHA256" "$EXPECTED_HISTORY_SIZE" \
  "$EXPECTED_RESULT80_SHA256"

python3 - "$SUMMARY" "$HISTORY" "$EXPERIMENT_ID" <<'PY'
import json
import math
import sys
from pathlib import Path

summary_path = Path(sys.argv[1])
history_path = Path(sys.argv[2])
expected_experiment_id = sys.argv[3]

summary = json.loads(summary_path.read_text(encoding="utf-8"))
history = json.loads(history_path.read_text(encoding="utf-8"))
if summary.get("experiment_id") != expected_experiment_id:
    raise SystemExit("diagnostic result experiment identity differs")
if summary.get("status") != "TRAINING_COMPLETE_GATE_PASS":
    raise SystemExit("diagnostic result status differs")
if not isinstance(history, list) or len(history) != 81:
    raise SystemExit("diagnostic epoch history length differs")
if [row.get("epoch") for row in history] != list(range(81)):
    raise SystemExit("diagnostic epoch sequence differs")

training = summary.get("training", {})
objective_key = "checkpoint_selection_objective_728_origins_without_warmup"
objectives = [float(row[objective_key]) for row in history]
if not all(math.isfinite(value) and value >= 0.0 for value in objectives):
    raise SystemExit("diagnostic objective sequence is non-finite")

global_best_epoch = min(range(81), key=lambda epoch: objectives[epoch])
global_best_objective = objectives[global_best_epoch]
overall_improvement = objectives[0] - global_best_objective
declared_improvement = float(training.get("objective_improvement"))
best_row_parameter = history[global_best_epoch].get("parameter_sha256")
last_row_parameter = history[-1].get("parameter_sha256")

conditions = {
    "overall_improvement_gt_1e_6": overall_improvement > 1.0e-6,
    "declared_improvement_exact": declared_improvement == overall_improvement,
    "parameter_hash_changed_true": training.get("parameter_hash_changed") is True,
    "best_parameter_matches_history": training.get("best_parameter_sha256") == best_row_parameter,
    "last_parameter_matches_history": training.get("last_parameter_sha256") == last_row_parameter,
    "best_parameter_differs_epoch_zero": training.get("best_parameter_sha256") != training.get("epoch_zero_parameter_sha256"),
    "best_better_than_strict_zero_each_lead_true": training.get("best_better_than_strict_zero_gain_each_lead") is True,
}

ledger = summary.get("access_ledger", {})
evaluation_access = {
    key: ledger.get(key)
    for key in (
        "evaluation_array_reads",
        "evaluation_metric_count",
        "evaluation_output_count",
        "evaluation_prediction_count",
    )
}

report = {
    "schema_version": "daily_camels_knet_a38_global_gate_diagnostic_v1",
    "experiment_id": summary.get("experiment_id"),
    "global_best_epoch": global_best_epoch,
    "global_best_objective": global_best_objective,
    "epoch_zero_objective": objectives[0],
    "overall_improvement_recomputed": overall_improvement,
    "overall_improvement_declared": declared_improvement,
    "overall_improvement_difference_declared_minus_recomputed": declared_improvement - overall_improvement,
    "declared_best_epoch": training.get("best_epoch"),
    "declared_best_parameter_sha256": training.get("best_parameter_sha256"),
    "history_best_parameter_sha256": best_row_parameter,
    "declared_last_parameter_sha256": training.get("last_parameter_sha256"),
    "history_last_parameter_sha256": last_row_parameter,
    "epoch_zero_parameter_sha256": training.get("epoch_zero_parameter_sha256"),
    "conditions": conditions,
    "failed_condition_names": sorted(name for name, passed in conditions.items() if not passed),
    "evaluation_access": evaluation_access,
    "all_evaluation_access_zero": all(value == 0 for value in evaluation_access.values()),
}
print("SEQ81_A38_GLOBAL_GATE_DIAGNOSTIC " + json.dumps(report, sort_keys=True, separators=(",", ":")))
if report["failed_condition_names"] == []:
    raise SystemExit("sequence 81 expected at least one failing global-gate subcondition")
if not report["all_evaluation_access_zero"]:
    raise SystemExit("sequence 81 evaluation access is not zero")
PY

echo 'SEQ81_A38_GLOBAL_GATE_DIAGNOSTIC_COMPLETE'
