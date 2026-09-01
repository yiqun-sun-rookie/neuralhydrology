#!/bin/bash
set -o pipefail

ROOT="/data1/home/sunyiq/zhenjiang_six_source_four_target_differentiable_ukf_20260901_r2"
R1_STAGING="/data1/home/sunyiq/zhenjiang_six_source_four_target_differentiable_ukf_20260901_r1.staging"
IDS_CSV="217803,217804,217805,217806,217807,217808,217809,217810"
IDS_SPACE="217803 217804 217805 217806 217807 217808 217809 217810"

printf '=== SNAPSHOT_TIME ===\n'
date -Is

printf '=== SQUEUE ===\n'
squeue -j "${IDS_CSV}" -o '%i|%j|%T|%P|%N|%M|%l|%R' || true

printf '=== START_ESTIMATE ===\n'
squeue --start -j '217809' -o '%i|%j|%T|%S|%R' 2>&1 || true

printf '=== PRIORITY_DETAIL ===\n'
sprio -j '217809' 2>&1 || true

printf '=== SACCT ===\n'
sacct -j "${IDS_CSV}" --format=JobIDRaw,JobName,State,ExitCode,Elapsed,Start,End,NodeList -P -n || true

printf '=== SCONTROL_DEPENDENCIES ===\n'
for job_id in ${IDS_SPACE}; do
  scontrol show job -o "${job_id}" 2>&1 | sed -n 's/.*JobId=\([^ ]*\).*JobState=\([^ ]*\).*Reason=\([^ ]*\).*Dependency=\([^ ]*\).*/JOB|\1|STATE=\2|REASON=\3|DEPENDENCY=\4/p' || true
done

printf '=== REGISTERED_OUTPUTS_AND_FAILURE_EVIDENCE ===\n'
for seed in 17 29 43; do
  for relative in \
    "runs/base_smoke/s${seed}/attempt_001" \
    "runs/base/s${seed}/attempt_001" \
    "runs/observation_head_smoke/s${seed}/attempt_001" \
    "runs/observation_head/s${seed}/attempt_001" \
    "runs/filter_real_batch_smoke/s${seed}/attempt_001" \
    "runs/filter/s${seed}/attempt_001"
  do
    path="${ROOT}/${relative}"
    if [ -d "${path}" ]; then
      printf 'PUBLISHED|%s\n' "${path}"
      for evidence in "${path}/completion_manifest.json" "${path}/failure.json" "${path}/failure_manifest.json"; do
        [ -f "${evidence}" ] || continue
        stat -c 'FILE|%n|bytes=%s|mtime=%y' "${evidence}" || true
        tail -n 80 "${evidence}" || true
      done
    elif [ -d "${path}.partial" ]; then
      printf 'PARTIAL|%s\n' "${path}.partial"
      find "${path}.partial" -maxdepth 1 -type f -printf 'PARTIAL_FILE|%f|bytes=%s|mtime=%TY-%Tm-%TdT%TH:%TM:%TS%Tz\n' 2>/dev/null | sort || true
    else
      printf 'ABSENT|%s\n' "${path}"
    fi
  done
done
for relative in \
  "runs/development_evaluation_smoke/attempt_001" \
  "evidence/development_2023/evaluation/attempt_001" \
  "evidence/development_2023/independent_audit/attempt_001"
do
  path="${ROOT}/${relative}"
  if [ -d "${path}" ]; then
    printf 'PUBLISHED|%s\n' "${path}"
    for evidence in "${path}/completion_manifest.json" "${path}/failure.json" "${path}/failure_manifest.json"; do
      [ -f "${evidence}" ] || continue
      stat -c 'FILE|%n|bytes=%s|mtime=%y' "${evidence}" || true
      tail -n 80 "${evidence}" || true
    done
  elif [ -d "${path}.partial" ]; then
    printf 'PARTIAL|%s\n' "${path}.partial"
    find "${path}.partial" -maxdepth 1 -type f -printf 'PARTIAL_FILE|%f|bytes=%s|mtime=%TY-%Tm-%TdT%TH:%TM:%TS%Tz\n' 2>/dev/null | sort || true
  else
    printf 'ABSENT|%s\n' "${path}"
  fi
done

printf '=== BASE_OUTPUT_DEEP_VERIFICATION ===\n'
python - "${ROOT}" <<'PY' || true
from __future__ import annotations

import hashlib
import json
from pathlib import Path
import sys

root = Path(sys.argv[1])
expected_names = {
    "best_checkpoint.pt",
    "last_checkpoint.pt",
    "run_identity.json",
    "training_history.json",
    "completion_manifest.json",
}
for seed in (17, 29, 43):
    final = root / f"runs/base/s{seed}/attempt_001"
    partial = Path(f"{final}.partial")
    print(
        "BASE_PATH_STATE"
        f"|seed={seed}|final={str(final.is_dir()).lower()}"
        f"|partial={str(partial.exists()).lower()}"
    )
    if not final.is_dir():
        continue
    entries = sorted(final.rglob("*"))
    files = [path for path in entries if path.is_file() and not path.is_symlink()]
    links = [path for path in entries if path.is_symlink()]
    directories = [path for path in entries if path.is_dir() and path != final]
    relative_names = {path.relative_to(final).as_posix() for path in files}
    print(
        "BASE_FILE_SET"
        f"|seed={seed}|ordinary_files={len(files)}|links={len(links)}"
        f"|subdirectories={len(directories)}"
        f"|exact={str(relative_names == expected_names).lower()}"
        f"|names={','.join(sorted(relative_names))}"
    )
    manifest_path = final / "completion_manifest.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    registered = manifest.get("files", {})
    all_registered_match = True
    for path in files:
        relative = path.relative_to(final).as_posix()
        digest = hashlib.sha256(path.read_bytes()).hexdigest()
        row = registered.get(relative)
        matches = (
            relative == "completion_manifest.json"
            or (
                isinstance(row, dict)
                and row.get("byte_count") == path.stat().st_size
                and row.get("sha256") == digest
            )
        )
        if relative != "completion_manifest.json":
            all_registered_match = all_registered_match and matches
        print(
            "BASE_FILE"
            f"|seed={seed}|name={relative}|bytes={path.stat().st_size}"
            f"|sha256={digest}|registered_match={str(matches).lower()}"
        )
    print(
        "BASE_MANIFEST_CHECK"
        f"|seed={seed}|status={manifest.get('status')}"
        f"|registered_files={len(registered)}"
        f"|all_registered_match={str(all_registered_match).lower()}"
    )
    identity = json.loads((final / "run_identity.json").read_text(encoding="utf-8"))
    audit = identity.get("data_access_audit", {})
    periods = audit.get("target_rows_by_period", {})
    forbidden_fields = (
        "development_feature_bytes_read",
        "development_feature_rows_parsed",
        "development_feature_values_loaded",
        "development_target_bytes_read",
        "development_target_rows_parsed",
        "development_target_values_loaded",
        "heldout_target_bytes_read",
        "heldout_target_rows_parsed",
        "heldout_target_values_loaded",
        "boundary_target_bytes_read",
        "boundary_target_rows_parsed",
        "boundary_target_values_loaded",
    )
    forbidden_values = {name: audit.get(name) for name in forbidden_fields}
    forbidden_zero = all(type(value) is int and value == 0 for value in forbidden_values.values())
    total_prefix_bytes = sum(audit.get("bytes_read_by_path", {}).values())
    print(
        "BASE_IDENTITY"
        f"|seed={seed}|task_id={identity.get('task_id')}|stage={identity.get('stage')}"
        f"|registered_output_path={identity.get('registered_output_path')}"
        f"|registry_sha256={identity.get('registry_sha256')}"
        f"|input_manifest_sha256={identity.get('training_selection_input_manifest_sha256')}"
    )
    print(
        "BASE_ACCESS_AUDIT"
        f"|seed={seed}|opened_paths={len(audit.get('opened_paths', []))}"
        f"|prefix_bytes={total_prefix_bytes}"
        f"|target_rows_by_period={json.dumps(periods, sort_keys=True, separators=(',', ':'))}"
        f"|astronomical_tide_model_open_count={audit.get('astronomical_tide_model_open_count')}"
        f"|forbidden_counters_integer_zero={str(forbidden_zero).lower()}"
    )
PY

printf '=== FILTER_OUTPUT_DEEP_VERIFICATION ===\n'
python - "${ROOT}" <<'PY' || true
from __future__ import annotations

import hashlib
import json
from pathlib import Path
import sys

root = Path(sys.argv[1])
expected_names = {
    "best_filter_checkpoint.pt",
    "last_filter_checkpoint.pt",
    "run_identity.json",
    "training_history.json",
    "gradient_history.json",
    "summary.json",
    "completion_manifest.json",
}
for seed in (17, 29, 43):
    final = root / f"runs/filter/s{seed}/attempt_001"
    partial = Path(f"{final}.partial")
    print(
        "FILTER_PATH_STATE"
        f"|seed={seed}|final={str(final.is_dir()).lower()}"
        f"|partial={str(partial.exists()).lower()}"
    )
    if not final.is_dir():
        continue
    entries = sorted(final.rglob("*"))
    files = [path for path in entries if path.is_file() and not path.is_symlink()]
    links = [path for path in entries if path.is_symlink()]
    directories = [path for path in entries if path.is_dir() and path != final]
    relative_names = {path.relative_to(final).as_posix() for path in files}
    print(
        "FILTER_FILE_SET"
        f"|seed={seed}|ordinary_files={len(files)}|links={len(links)}"
        f"|subdirectories={len(directories)}"
        f"|exact={str(relative_names == expected_names).lower()}"
        f"|names={','.join(sorted(relative_names))}"
    )
    manifest_path = final / "completion_manifest.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    registered_rows = manifest.get("files", [])
    registered = {
        row.get("path"): row for row in registered_rows if isinstance(row, dict)
    }
    all_registered_match = True
    for path in files:
        relative = path.relative_to(final).as_posix()
        digest = hashlib.sha256(path.read_bytes()).hexdigest()
        row = registered.get(relative)
        matches = (
            relative == "completion_manifest.json"
            or (
                isinstance(row, dict)
                and row.get("byte_count") == path.stat().st_size
                and row.get("sha256") == digest
            )
        )
        if relative != "completion_manifest.json":
            all_registered_match = all_registered_match and matches
        print(
            "FILTER_FILE"
            f"|seed={seed}|name={relative}|bytes={path.stat().st_size}"
            f"|sha256={digest}|registered_match={str(matches).lower()}"
        )
    print(
        "FILTER_MANIFEST_CHECK"
        f"|seed={seed}|status={manifest.get('status')}"
        f"|registered_files={len(registered_rows)}"
        f"|verified_artifact_count={manifest.get('verified_artifact_count')}"
        f"|all_registered_match={str(all_registered_match).lower()}"
    )
    identity = json.loads((final / "run_identity.json").read_text(encoding="utf-8"))
    audit = identity.get("data_access_audit", {})
    forbidden_fields = (
        "development_feature_bytes_read",
        "development_feature_rows_parsed",
        "development_feature_values_loaded",
        "development_target_bytes_read",
        "development_target_rows_parsed",
        "development_target_values_loaded",
        "heldout_target_bytes_read",
        "heldout_target_rows_parsed",
        "heldout_target_values_loaded",
        "boundary_target_bytes_read",
        "boundary_target_rows_parsed",
        "boundary_target_values_loaded",
    )
    forbidden_zero = all(
        type(audit.get(name)) is int and audit.get(name) == 0
        for name in forbidden_fields
    )
    summary = json.loads((final / "summary.json").read_text(encoding="utf-8"))
    history = json.loads((final / "training_history.json").read_text(encoding="utf-8"))
    epochs = history.get("epochs", [])
    print(
        "FILTER_IDENTITY"
        f"|seed={seed}|task_id={identity.get('task_id')}"
        f"|base_checkpoint_sha256={identity.get('base_checkpoint_sha256')}"
        f"|observation_head_sha256={identity.get('observation_head_sha256')}"
        f"|registry_sha256={identity.get('registry_sha256')}"
        f"|input_manifest_sha256={identity.get('training_selection_input_manifest_sha256')}"
        f"|training_samples={identity.get('training_sample_count')}"
        f"|selection_samples={identity.get('selection_sample_count')}"
    )
    print(
        "FILTER_ACCESS_AUDIT"
        f"|seed={seed}|opened_paths={len(audit.get('opened_paths', []))}"
        f"|prefix_bytes={sum(audit.get('bytes_read_by_path', {}).values())}"
        f"|target_rows_by_period={json.dumps(audit.get('target_rows_by_period', {}), sort_keys=True, separators=(',', ':'))}"
        f"|astronomical_tide_model_open_count={audit.get('astronomical_tide_model_open_count')}"
        f"|forbidden_counters_integer_zero={str(forbidden_zero).lower()}"
    )
    print(
        "FILTER_SUMMARY"
        f"|seed={seed}|status={summary.get('status')}"
        f"|best_epoch={summary.get('best_epoch')}"
        f"|best_selection_mae_m={summary.get('best_selection_mae_m')}"
        f"|completed_epoch={summary.get('completed_epoch')}"
        f"|history_epochs={len(epochs)}"
        f"|training_cells_per_base_sample={summary.get('training_cells_per_base_sample')}"
        f"|station_specific_checkpoint_count={summary.get('station_specific_checkpoint_count')}"
    )
PY

printf '=== DEVELOPMENT_EVALUATION_DEEP_VERIFICATION ===\n'
python - "${ROOT}" <<'PY' || true
from __future__ import annotations

import csv
import hashlib
import json
import math
from pathlib import Path
import sys


def load_json(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


def load_csv(path: Path):
    with path.open("r", encoding="utf-8", newline="") as handle:
        return list(csv.DictReader(handle))


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def compact(value) -> str:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


def as_bool(value) -> bool:
    if isinstance(value, bool):
        return value
    return str(value).strip().lower() == "true"


root = Path(sys.argv[1])
evaluation = root / "evidence/development_2023/evaluation/attempt_001"
evaluation_partial = Path(f"{evaluation}.partial")
audit_directory = root / "evidence/development_2023/independent_audit/attempt_001"
audit_partial = Path(f"{audit_directory}.partial")
print(
    "EVAL_PATH_STATE"
    f"|final={str(evaluation.is_dir()).lower()}"
    f"|partial={str(evaluation_partial.exists()).lower()}"
)
print(
    "INDEPENDENT_AUDIT_PATH_STATE"
    f"|final={str(audit_directory.is_dir()).lower()}"
    f"|partial={str(audit_partial.exists()).lower()}"
)

if evaluation.is_dir():
    expected_names = {
        "development_access_started.json",
        "future_sufficient_statistics.csv",
        "analysis_observation_sufficient_statistics.csv",
        "analysis_target_sufficient_statistics.csv",
        "state_difference_sufficient_statistics.csv",
        "base_qualification_sufficient_statistics.csv",
        "observation_head_qualification_sufficient_statistics.csv",
        "base_observation_head_qualification.json",
        "observation_dependency_perturbation_evidence.npz",
        "base_and_three_branch_forecast_metrics.csv",
        "source_target_lead_metrics.csv",
        "source_target_window_metrics.csv",
        "six_source_four_target_gain_matrix.csv",
        "internal_four_by_four_gain_matrix.csv",
        "boundary_to_internal_gain_matrix.csv",
        "analysis_realtime_observation_diagnostics.csv",
        "analysis_target_space_gain_matrix.csv",
        "forecast_movement_matrix.csv",
        "reciprocal_direction_summary.csv",
        "bootstrap_summary.json",
        "development_gate_decision.json",
        "sufficient_grid_identity.json",
        "state_difference_diagnostics.csv",
        "completion_manifest.json",
    }
    entries = sorted(evaluation.rglob("*"))
    files = [path for path in entries if path.is_file() and not path.is_symlink()]
    links = [path for path in entries if path.is_symlink()]
    directories = [path for path in entries if path.is_dir() and path != evaluation]
    names = {path.relative_to(evaluation).as_posix() for path in files}
    print(
        "EVAL_FILE_SET"
        f"|ordinary_files={len(files)}|links={len(links)}"
        f"|subdirectories={len(directories)}|exact={str(names == expected_names).lower()}"
        f"|names={','.join(sorted(names))}"
    )
    manifest_path = evaluation / "completion_manifest.json"
    manifest = load_json(manifest_path)
    registered_rows = manifest.get("files", [])
    registered = {
        row.get("name"): row for row in registered_rows if isinstance(row, dict)
    }
    registered_set_exact = set(registered) == names - {"completion_manifest.json"}
    registered_match = True
    for name, row in sorted(registered.items()):
        path = evaluation / name
        matches = bool(
            path.is_file()
            and not path.is_symlink()
            and path.stat().st_size == row.get("byte_count")
            and digest(path) == row.get("sha256")
        )
        registered_match = registered_match and matches
        print(
            "EVAL_FILE"
            f"|name={name}|bytes={path.stat().st_size if path.is_file() else None}"
            f"|sha256={digest(path) if path.is_file() else None}"
            f"|registered_match={str(matches).lower()}"
        )
    access = manifest.get("development_data_access_audit", {})
    forbidden_fields = (
        "heldout_target_bytes_read",
        "heldout_target_rows_parsed",
        "heldout_target_values_loaded",
        "boundary_target_bytes_read",
        "boundary_target_rows_parsed",
        "boundary_target_values_loaded",
    )
    forbidden_zero = all(
        type(access.get(name)) is int and access.get(name) == 0
        for name in forbidden_fields
    )
    artifact_identities = manifest.get("frozen_artifact_identities", [])
    frozen_paths = {
        value
        for row in artifact_identities
        if isinstance(row, dict)
        for key, value in row.items()
        if key.endswith("_path") and isinstance(value, str)
    }
    print(
        "EVAL_MANIFEST_CHECK"
        f"|status={manifest.get('status')}"
        f"|manifest_sha256={digest(manifest_path)}"
        f"|file_count_excluding_manifest={manifest.get('file_count_excluding_manifest')}"
        f"|registered_files={len(registered_rows)}"
        f"|registered_set_exact={str(registered_set_exact).lower()}"
        f"|all_registered_match={str(registered_match).lower()}"
        f"|synthetic_test_mode={manifest.get('synthetic_test_mode')}"
        f"|real_target_loader_present={manifest.get('real_target_loader_present')}"
        f"|development_loader_call_count={manifest.get('development_loader_call_count')}"
        f"|development_dataset_instance_count={manifest.get('development_dataset_instance_count')}"
        f"|seed_evaluation_count={manifest.get('seed_evaluation_count')}"
        f"|development_access_started_before_loader={manifest.get('development_access_started_before_loader')}"
        f"|dependency_evidence_contains_target_values={manifest.get('dependency_evidence_contains_target_values')}"
        f"|held_out_2024_target_access_count={manifest.get('held_out_2024_target_access_count')}"
        f"|boundary_future_target_access_count={manifest.get('boundary_future_target_access_count')}"
        f"|frozen_seed_identity_count={len(artifact_identities)}"
        f"|frozen_unique_artifact_path_count={len(frozen_paths)}"
    )
    print(
        "EVAL_ACCESS_AUDIT"
        f"|opened_paths={len(access.get('opened_paths', []))}"
        f"|development_feature_rows_parsed={access.get('development_feature_rows_parsed')}"
        f"|development_target_rows_parsed={access.get('development_target_rows_parsed')}"
        f"|astronomical_tide_model_open_count={access.get('astronomical_tide_model_open_count')}"
        f"|target_rows_by_period={compact(access.get('target_rows_by_period', {}))}"
        f"|forbidden_counters_integer_zero={str(forbidden_zero).lower()}"
        f"|forbidden_period_rows_integer_zero={str(all(type(access.get('target_rows_by_period', {}).get(name)) is int and access.get('target_rows_by_period', {}).get(name) == 0 for name in ('heldout_or_later', 'boundary_target'))).lower()}"
    )
    marker = load_json(evaluation / "development_access_started.json")
    print(
        "EVAL_ACCESS_MARKER"
        f"|status={marker.get('status')}|claimed_at_utc={marker.get('claimed_at_utc')}"
        f"|frozen_artifact_count={marker.get('frozen_artifact_count')}"
        f"|held_out_2024_target_access_authorized={marker.get('held_out_2024_target_access_authorized')}"
        f"|boundary_future_target_access_authorized={marker.get('boundary_future_target_access_authorized')}"
        f"|sha256_matches_manifest={str(digest(evaluation / 'development_access_started.json') == manifest.get('development_access_marker_sha256')).lower()}"
    )
    qualification = load_json(evaluation / "base_observation_head_qualification.json")
    print(
        "QUALIFICATION_SUMMARY"
        f"|passed={qualification.get('passed')}"
        f"|gates={compact(qualification.get('gates', {}))}"
        f"|target_pooled_count={len(qualification.get('target_pooled_results', []))}"
        f"|observation_pooled_count={len(qualification.get('observation_head_pooled_results', []))}"
        f"|target_seed_diagnostic_count={len(qualification.get('target_seed_results', []))}"
        f"|observation_seed_diagnostic_count={len(qualification.get('observation_head_seed_results', []))}"
        f"|design_diagnostic_count={len(qualification.get('observation_head_design_diagnostics', []))}"
    )
    for row in qualification.get("target_pooled_results", []):
        print("QUALIFICATION_TARGET|" + compact(row))
    for row in qualification.get("observation_head_pooled_results", []):
        print("QUALIFICATION_OBSERVATION_HEAD|" + compact(row))
    for row in qualification.get("observation_head_design_diagnostics", []):
        print("QUALIFICATION_OBSERVATION_HEAD_DESIGN|" + compact(row))
    observation_rows = load_csv(evaluation / "analysis_realtime_observation_diagnostics.csv")
    print(f"ANALYSIS_UPDATE_ROW_COUNT|count={len(observation_rows)}")
    for row in observation_rows:
        print("ANALYSIS_UPDATE|" + compact(row))
    decision = load_json(evaluation / "development_gate_decision.json")
    forecast = decision.get("forecast_direction_decision", {})
    print(
        "DEVELOPMENT_GATE_DECISION"
        f"|status={decision.get('status')}"
        f"|identity_gate_pass={decision.get('identity_gate_pass')}"
        f"|base_observation_head_qualification_pass={decision.get('base_observation_head_qualification_pass')}"
        f"|analysis_observation_update_pass={decision.get('analysis_observation_update_pass')}"
        f"|self_forecast_gate_pass={decision.get('self_forecast_gate_pass')}"
        f"|cross_station_gate_pass={decision.get('cross_station_gate_pass')}"
        f"|cross_station_status={decision.get('cross_station_status')}"
        f"|forecast_direction_gate_pass={decision.get('forecast_direction_gate_pass')}"
        f"|practical_magnitude_gate={decision.get('practical_magnitude_gate')}"
    )
    print("FORECAST_DIRECTION_GATES|" + compact(forecast.get("gates", {})))
    for row in forecast.get("self_cells", []):
        print("SELF_FORECAST_GATE_CELL|" + compact(row))
    for row in forecast.get("adjacent_directions", []):
        print("ADJACENT_DIRECTION_GATE_CELL|" + compact(row))
    matrix_rows = load_csv(evaluation / "six_source_four_target_gain_matrix.csv")
    matrix_keys = {
        (int(row["source_index"]), int(row["target_index"])) for row in matrix_rows
    }
    expected_matrix_keys = {(source, target) for source in range(6) for target in range(4)}
    expected_self_keys = {(1, 0), (2, 1), (3, 2), (4, 3)}
    matrix_self_keys = {
        (int(row["source_index"]), int(row["target_index"]))
        for row in matrix_rows if as_bool(row.get("is_self"))
    }
    matrix_internal_cross_count = sum(
        1 for row in matrix_rows
        if int(row["source_index"]) in range(1, 5) and not as_bool(row.get("is_self"))
    )
    matrix_boundary_count = sum(
        1 for row in matrix_rows if as_bool(row.get("is_boundary_source"))
    )
    matrix_numeric_consistency = all(
        math.isclose(float(row["measurement_update_gain_mm"]), 1000.0 * float(row["measurement_update_gain_m"]), rel_tol=1e-10, abs_tol=1e-9)
        and math.isclose(float(row["total_gain_m"]), float(row["base_mae_m"]) - float(row["updated_mae_m"]), rel_tol=1e-10, abs_tol=1e-12)
        and math.isclose(float(row["covariance_propagation_gain_m"]) + float(row["measurement_update_gain_m"]), float(row["total_gain_m"]), rel_tol=1e-10, abs_tol=1e-12)
        and (
            float(row["prior_mae_m"]) == 0.0
            or math.isclose(float(row["measurement_update_relative_gain_percent"]), 100.0 * float(row["measurement_update_gain_m"]) / float(row["prior_mae_m"]), rel_tol=1e-10, abs_tol=1e-9)
        )
        for row in matrix_rows
    )
    matrix_contract = bool(
        len(matrix_rows) == 24
        and len(matrix_keys) == 24
        and matrix_keys == expected_matrix_keys
        and matrix_self_keys == expected_self_keys
        and matrix_internal_cross_count == 12
        and matrix_boundary_count == 8
        and all(row.get("scope") == "pooled_three_seeds" for row in matrix_rows)
        and all(row.get("window_name") == "post_update_1_to_6" for row in matrix_rows)
        and matrix_numeric_consistency
    )
    print(
        "GAIN_MATRIX_ROW_COUNT"
        f"|count={len(matrix_rows)}|unique_key_count={len(matrix_keys)}"
        f"|self_count={len(matrix_self_keys)}|internal_cross_count={matrix_internal_cross_count}"
        f"|boundary_count={matrix_boundary_count}|numeric_consistency={str(matrix_numeric_consistency).lower()}"
        f"|contract={str(matrix_contract).lower()}"
    )
    for row in matrix_rows:
        print("GAIN_MATRIX_CELL|" + compact(row))
    bootstrap = load_json(evaluation / "bootstrap_summary.json")
    bootstrap_cells = bootstrap.get("cell_summaries", [])
    bootstrap_keys = {
        (int(row["source_index"]), int(row["target_index"])) for row in bootstrap_cells
    }
    matrix_lookup = {
        (int(row["source_index"]), int(row["target_index"])): row for row in matrix_rows
    }
    bootstrap_interval_order = all(
        float(row["measurement_gain_two_sided_95_lower_m"])
        <= float(row["measurement_gain_two_sided_95_upper_m"])
        for row in bootstrap_cells
    )
    bootstrap_matrix_match = all(
        key in matrix_lookup
        and math.isclose(
            float(row["point_measurement_update_gain_m"]),
            float(matrix_lookup[key]["measurement_update_gain_m"]),
            rel_tol=1e-10,
            abs_tol=1e-12,
        )
        for key, row in {
            (int(value["source_index"]), int(value["target_index"])): value
            for value in bootstrap_cells
        }.items()
    )
    cross_bootstrap_rows = [row for row in bootstrap_cells if not as_bool(row.get("is_self"))]
    bootstrap_holm_contract = bool(
        len(cross_bootstrap_rows) == 20
        and all(
            all(name in row for name in ("holm_family", "holm_adjusted_one_sided_p_value", "holm_reject_at_0_05", "direction_stable_support"))
            for row in cross_bootstrap_rows
        )
    )
    bootstrap_contract = bool(
        len(bootstrap_cells) == 24
        and len(bootstrap_keys) == 24
        and bootstrap_keys == matrix_keys
        and bootstrap_interval_order
        and bootstrap_matrix_match
        and bootstrap_holm_contract
        and bootstrap.get("cross_20_macro", {}).get("cell_count") == 20
        and bootstrap.get("internal_12_macro", {}).get("cell_count") == 12
        and bootstrap.get("boundary_8_macro", {}).get("cell_count") == 8
        and len(bootstrap.get("target_column_cross_macros", [])) == 4
    )
    print(
        "BOOTSTRAP_CONSISTENCY"
        f"|cell_count={len(bootstrap_cells)}|unique_key_count={len(bootstrap_keys)}"
        f"|interval_order={str(bootstrap_interval_order).lower()}"
        f"|matrix_point_gain_match={str(bootstrap_matrix_match).lower()}"
        f"|holm_cross_cell_contract={str(bootstrap_holm_contract).lower()}"
        f"|contract={str(bootstrap_contract).lower()}"
    )
    print("BOOTSTRAP_SAMPLING|" + compact(bootstrap.get("sampling", {})))
    for name in ("cross_20_macro", "internal_12_macro", "boundary_8_macro"):
        print("BOOTSTRAP_MACRO|key=" + name + "|" + compact(bootstrap.get(name, {})))
    for row in bootstrap.get("target_column_cross_macros", []):
        print("BOOTSTRAP_TARGET_COLUMN|" + compact(row))
    for row in bootstrap.get("cell_summaries", []):
        print("BOOTSTRAP_CELL|" + compact(row))
    window_rows = load_csv(evaluation / "source_target_window_metrics.csv")
    selected_self_seed_rows = [
        row for row in window_rows
        if row.get("window_name") == "post_update_1_to_6"
        and row.get("scope") in {"seed_17", "seed_29", "seed_43"}
        and row.get("is_self", "").lower() == "true"
    ]
    print(f"SELF_SEED_WINDOW_ROW_COUNT|count={len(selected_self_seed_rows)}")
    for row in selected_self_seed_rows:
        print("SELF_SEED_WINDOW|" + compact(row))
    reciprocal_rows = load_csv(evaluation / "reciprocal_direction_summary.csv")
    print(f"RECIPROCAL_DIRECTION_ROW_COUNT|count={len(reciprocal_rows)}")
    for row in reciprocal_rows:
        print("RECIPROCAL_DIRECTION|" + compact(row))
    decision_gates = forecast.get("gates", {})
    self_gate_reconstructed = all(bool(row.get("pass")) for row in forecast.get("self_cells", [])) and len(forecast.get("self_cells", [])) == 4
    cross_gate_reconstructed = bool(decision_gates) and all(
        bool(value) for name, value in decision_gates.items() if name != "four_self_cells_pass"
    )
    analysis_gate_reconstructed = len(observation_rows) == 6 and all(as_bool(row.get("pass")) for row in observation_rows)
    decision_consistency = bool(
        decision.get("self_forecast_gate_pass") == self_gate_reconstructed
        and decision.get("cross_station_gate_pass") == cross_gate_reconstructed
        and decision.get("forecast_direction_gate_pass") == (self_gate_reconstructed and cross_gate_reconstructed)
        and decision.get("analysis_observation_update_pass") == analysis_gate_reconstructed
        and decision.get("base_observation_head_qualification_pass") == qualification.get("passed")
        and len(qualification.get("target_pooled_results", [])) == 4
        and len(qualification.get("observation_head_pooled_results", [])) == 6
    )
    print(
        "DEVELOPMENT_DECISION_CONSISTENCY"
        f"|self_gate_reconstructed={str(self_gate_reconstructed).lower()}"
        f"|cross_gate_reconstructed={str(cross_gate_reconstructed).lower()}"
        f"|analysis_gate_reconstructed={str(analysis_gate_reconstructed).lower()}"
        f"|contract={str(decision_consistency).lower()}"
    )

if audit_directory.is_dir():
    entries = sorted(audit_directory.rglob("*"))
    files = [path for path in entries if path.is_file() and not path.is_symlink()]
    links = [path for path in entries if path.is_symlink()]
    directories = [path for path in entries if path.is_dir() and path != audit_directory]
    names = {path.relative_to(audit_directory).as_posix() for path in files}
    print(
        "INDEPENDENT_AUDIT_FILE_SET"
        f"|ordinary_files={len(files)}|links={len(links)}|subdirectories={len(directories)}"
        f"|exact={str(names == {'completion_manifest.json', 'independent_audit_report.json'}).lower()}"
        f"|names={','.join(sorted(names))}"
    )
    audit_manifest_path = audit_directory / "completion_manifest.json"
    audit_report_path = audit_directory / "independent_audit_report.json"
    audit_manifest = load_json(audit_manifest_path)
    audit_report = load_json(audit_report_path)
    rows = audit_manifest.get("files", [])
    row = rows[0] if len(rows) == 1 and isinstance(rows[0], dict) else {}
    report_hash = digest(audit_report_path)
    evaluation_manifest_hash = (
        digest(evaluation / "completion_manifest.json") if evaluation.is_dir() else None
    )
    print(
        "INDEPENDENT_AUDIT_MANIFEST_CHECK"
        f"|status={audit_manifest.get('status')}"
        f"|manifest_sha256={digest(audit_manifest_path)}"
        f"|file_count_excluding_manifest={audit_manifest.get('file_count_excluding_manifest')}"
        f"|report_name={row.get('name')}"
        f"|report_bytes_match={str(row.get('byte_count') == audit_report_path.stat().st_size).lower()}"
        f"|report_sha256={report_hash}"
        f"|report_sha256_match={str(row.get('sha256') == report_hash).lower()}"
        f"|evaluation_manifest_sha256={audit_manifest.get('evaluation_manifest_sha256')}"
        f"|evaluation_manifest_sha256_match={str(audit_manifest.get('evaluation_manifest_sha256') == evaluation_manifest_hash).lower()}"
        f"|held_out_2024_target_access_count={audit_manifest.get('held_out_2024_target_access_count')}"
        f"|boundary_future_target_access_count={audit_manifest.get('boundary_future_target_access_count')}"
    )
    print(
        "INDEPENDENT_AUDIT_REPORT"
        f"|status={audit_report.get('status')}"
        f"|evaluation_manifest_sha256={audit_report.get('evaluation_manifest_sha256')}"
        f"|evaluation_manifest_sha256_match={str(audit_report.get('evaluation_manifest_sha256') == evaluation_manifest_hash).lower()}"
        f"|manifest_file_count={audit_report.get('manifest_file_count')}"
        f"|future_sufficient_row_count={audit_report.get('future_sufficient_row_count')}"
        f"|source_target_lead_row_count={audit_report.get('source_target_lead_row_count')}"
        f"|bootstrap_repeat_count={audit_report.get('bootstrap_repeat_count')}"
        f"|holm_internal_direction_count={audit_report.get('holm_internal_direction_count')}"
        f"|holm_boundary_direction_count={audit_report.get('holm_boundary_direction_count')}"
        f"|exact_key_boolean_and_count_mismatch_count={audit_report.get('exact_key_boolean_and_count_mismatch_count')}"
        f"|float64_numeric_mismatch_count={audit_report.get('float64_numeric_mismatch_count')}"
        f"|main_metrics_module_imported={audit_report.get('main_metrics_module_imported')}"
        f"|base_observation_head_qualification_reconstructed={audit_report.get('base_observation_head_qualification_reconstructed')}"
    )
    print(
        "INDEPENDENT_AUDIT_DEPENDENCY_PERTURBATION|"
        + compact(audit_report.get("dependency_perturbation_audit", {}))
    )
PY

printf '=== FAILED_DEVELOPMENT_ATTEMPT_FORENSICS ===\n'
python - "${ROOT}" <<'PY' || true
from __future__ import annotations

import hashlib
import json
from pathlib import Path
import sys


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def compact(value) -> str:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


root = Path(sys.argv[1])
partial = root / "evidence/development_2023/evaluation/attempt_001.partial"
evaluation = root / "evidence/development_2023/evaluation/attempt_001"
audit = root / "evidence/development_2023/independent_audit/attempt_001"
audit_partial = Path(f"{audit}.partial")
print(
    "FAILED_ATTEMPT_PATH_STATE"
    f"|partial={str(partial.is_dir()).lower()}"
    f"|evaluation_final={str(evaluation.exists()).lower()}"
    f"|audit_final={str(audit.exists()).lower()}"
    f"|audit_partial={str(audit_partial.exists()).lower()}"
)
if partial.is_dir():
    entries = sorted(partial.rglob("*"))
    files = [path for path in entries if path.is_file() and not path.is_symlink()]
    links = [path for path in entries if path.is_symlink()]
    directories = [path for path in entries if path.is_dir() and path != partial]
    print(
        "FAILED_ATTEMPT_FILE_SET"
        f"|ordinary_files={len(files)}"
        f"|links={len(links)}"
        f"|subdirectories={len(directories)}"
        f"|names={','.join(path.relative_to(partial).as_posix() for path in files)}"
    )
    for path in files:
        relative = path.relative_to(partial).as_posix()
        print(
            "FAILED_ATTEMPT_FILE"
            f"|name={relative}|bytes={path.stat().st_size}|sha256={digest(path)}"
        )
    marker = partial / "development_access_started.json"
    if marker.is_file():
        print("FAILED_ATTEMPT_MARKER_JSON|" + compact(json.loads(marker.read_text(encoding="utf-8"))))

for label, path in (
    (
        "DEPLOYED_EVALUATION_SCRIPT",
        root / "run/scripts/analysis/zhenjiang_six_source_four_target_d32_gru_ukf_development_evaluation_v1.py",
    ),
    (
        "DEPLOYED_REGISTRY",
        root / "run/docs/records/ZHENJIANG_SIX_SOURCE_FOUR_TARGET_D32_GRU_DIFFERENTIABLE_UKF_V1_REGISTRY.json",
    ),
    ("FAILED_JOB_STDOUT", root / "logs/development-2023-217810.out"),
    ("FAILED_JOB_STDERR", root / "logs/development-2023-217810.err"),
):
    if path.is_file():
        print(
            f"FORENSIC_ARTIFACT|label={label}|path={path}"
            f"|bytes={path.stat().st_size}|sha256={digest(path)}"
        )
    else:
        print(f"FORENSIC_ARTIFACT_MISSING|label={label}|path={path}")
PY

printf '=== LOG_TAILS_AND_ERROR_SCAN ===\n'
for job_id in ${IDS_SPACE}; do
  for file in "${ROOT}/logs/"*"${job_id}"*.out "${ROOT}/logs/"*"${job_id}"*.err; do
    [ -f "${file}" ] || continue
    stat -c 'LOG|%n|bytes=%s|mtime=%y' "${file}" || true
    tail -n 60 "${file}" || true
    printf '%s\n' "--- ERROR_SCAN ${file}"
    grep -nEi 'traceback|fatal|failed|error|exception|cuda out of memory|no such file|assertionerror|runtimeerror|nan|inf' "${file}" | tail -n 30 || true
  done
done

printf '=== SAFETY_SENTINELS ===\n'
if [ -d "${R1_STAGING}" ]; then
  stat -c 'R1_STAGING_PRESERVED=true|type=%F|bytes=%s|mtime=%y|path=%n' "${R1_STAGING}" || true
else
  echo 'R1_STAGING_PRESERVED=false'
fi
[ -d "${ROOT}" ] && echo 'R2_ROOT_PRESENT=true' || echo 'R2_ROOT_PRESENT=false'
python - "${ROOT}" <<'PY' || true
from __future__ import annotations
import json
from pathlib import Path
import sys

root = Path(sys.argv[1])
registry = json.loads(
    (root / "run/docs/records/ZHENJIANG_SIX_SOURCE_FOUR_TARGET_D32_GRU_DIFFERENTIABLE_UKF_V1_REGISTRY.json").read_text(encoding="utf-8")
)
input_manifest = json.loads(
    (root / "inputs/pre2024-four-target-v1/four_target_input_manifest.json").read_text(encoding="utf-8")
)
heldout_authorized = registry["authorization"]["heldout_2024_target_access_authorized"]
boundary_bytes = input_manifest["boundary_target_bytes_read"]
heldout_bytes = input_manifest["heldout_2024_target_bytes_read"]
later_bytes = input_manifest["later_than_2023_bytes_read"]
print(f"HELDOUT_2024_TARGET_ACCESS_AUTHORIZED={str(heldout_authorized).lower()}")
print(f"BOUNDARY_TARGET_BYTES_READ={boundary_bytes}")
print(f"HELDOUT_2024_TARGET_BYTES_READ={heldout_bytes}")
print(f"LATER_THAN_2023_BYTES_READ={later_bytes}")
if heldout_authorized is False and boundary_bytes == heldout_bytes == later_bytes == 0:
    print("TARGET_ACCESS_SAFETY_CHECK=PASS")
else:
    print("TARGET_ACCESS_SAFETY_CHECK=VIOLATION")
PY

printf '=== SNAPSHOT_END ===\n'
date -Is
exit 0
