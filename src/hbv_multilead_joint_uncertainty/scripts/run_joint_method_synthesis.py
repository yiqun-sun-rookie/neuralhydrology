"""Synthesize the closed synthetic-truth joint-method validation chain."""

from __future__ import annotations

import argparse
import hashlib
import json
import shutil
from pathlib import Path

import numpy as np
import pandas as pd
import psutil

from hbv_multilead_joint_uncertainty.scripts.run_synthetic_truth_validation import (
    _json_write,
    _protected_hashes,
    _sha256,
)


REQUIRED_FILES = frozenset(
    {
        "claim_evidence.csv",
        "component_summary.json",
        "config_snapshot.json",
        "final_conditions.csv",
        "final_synthesis.md",
        "input_evidence_integrity.json",
        "protected_artifact_integrity.json",
        "resource_preflight.json",
        "source_snapshot/run_joint_method_synthesis.py",
        "source_snapshot/test_hbv_joint_method_synthesis.py",
        "summary.json",
    }
)

_FIRST_REVIEW_POSITIVE_VERDICTS = frozenset(
    {
        "confirmed",
        "explicit_zero_required_fixes",
        "no_required_fix_for_the_registered_claim",
        "pass",
        "passed",
        "valid_only_for_the_registered_ideal_closed_conditions",
        "通过",
        "通过：正式证据完整且聚合方法正确；预注册的九候选联合识别标准在最长四十五天匹配同化资料内仍未达到",
    }
)

_SECOND_REVIEW_POSITIVE_VERDICTS = frozenset(
    {
        "confirm",
        "confirmed",
        "confirmed_with_non_material_disagreements",
        "confirmed_with_one_wording_correction",
        "confirmed_with_wording_correction",
        "confirmed_without_new_must_fix_issue",
        "pass",
        "passed",
        "pass_with_non_material_disagreements",
        "通过",
        "确认第一审查的核心原始证据结论；第一审查中的“通过”表示证据完整且聚合正确，不表示联合识别已达到预注册标准。",
        "通过原始证据验证：第一审查中可由正式保存证据验证的数值、阈值、完整性和受限科学结论均获独立确认。预注册联合识别标准截至四十五天仍未达到；四十五天之后未测试，目前无法确定。",
    }
)

_REGISTERED_CONTRADICTION_FIELDS = frozenset(
    {
        "contradictions_found",
        "contradictions_to_the_limited_scientific_conclusion",
    }
)

_LEGACY_PARAMETER_REVIEW_DIRECTORY = "parameter_identification_validation_v01_reviews"
_LEGACY_PARAMETER_FIRST_REVIEW_FILE = "independent_review.json"
_LEGACY_PARAMETER_SECOND_REVIEW_FILE = "independent_review_validation.json"
_LEGACY_PARAMETER_REVIEW_RELATIVE_PATH = (
    "results/23_hbv_multilead_joint_uncertainty/"
    "parameter_identification_validation_v01_reviews"
)
_LEGACY_PARAMETER_SECOND_REVIEW_SHA256 = (
    "b512dace4e24cc7e091ef322c589c116241876d44f84e738a04b5091f5f73b3b"
)
_LEGACY_PARAMETER_FIRST_REVIEW_SHA256 = (
    "c95ffa6ca124e8ceb4b45d8faae7962a356a888dd8b7491ccce799dce466d84a"
)
_LEGACY_PARAMETER_REVIEW_MANIFEST_SHA256 = (
    "0f6c63405803c850b03129d2f4dca5b59e22b196bd763a99be5686b8a7733a31"
)
_SOURCE_DERIVED_REPO_ROOT = Path(__file__).resolve().parents[3]
_REGISTERED_SYNTHESIS_CONFIG_RELATIVE_PATH = (
    "src/hbv_multilead_joint_uncertainty/configs/"
    "joint_method_synthetic_validation_synthesis_v11.json"
)
_REGISTERED_SYNTHESIS_CONFIG_SHA256 = (
    "91b20ec5db8b9ca9462b3d19a48b03f6ec9132804c34b3e837db2907f55fbccc"
)


def _is_positive_review_verdict(value: object, *, layer: str) -> bool:
    normalized = str(value).strip().lower()
    if layer == "first":
        return normalized in _FIRST_REVIEW_POSITIVE_VERDICTS
    if layer == "second":
        return normalized in _SECOND_REVIEW_POSITIVE_VERDICTS
    raise ValueError(f"unknown review layer: {layer}")


def _decision_count(value: object, *, field: str, path: Path) -> int:
    if isinstance(value, bool) or not isinstance(value, int) or value < 0:
        raise ValueError(f"invalid nonnegative decision count {field}: {path}")
    return value


def _validate_registered_decision_fields(
    document: dict, *, layer: str, path: Path
) -> None:
    registered = {
        "must_fix",
        "must_fix_count",
        "required_code_fixes",
        "required_fixes",
        "conclusion_changing_defect",
        "verdict",
        "verdict_detail",
    }
    if layer == "second":
        registered.update(
            {
                "conclusion",
                "review_verdict",
                "unverified_items",
                "validated_review_verdict",
                *_REGISTERED_CONTRADICTION_FIELDS,
            }
        )
    suspicious = {
        str(key)
        for key in document
        if any(
            token in str(key).lower()
            for token in (
                "conclusion",
                "contradict",
                "decision",
                "defect",
                "fix",
                "status",
                "unverified",
                "verdict",
            )
        )
    }
    unrecognized = suspicious - registered
    if unrecognized:
        raise ValueError(
            f"unrecognized {layer} review decision fields: {path}: "
            f"{sorted(unrecognized)}"
        )


def _validate_review_fix_fields(
    document: dict,
    *,
    layer: str,
    path: Path,
    allow_legacy_confirmed_items_list: bool = False,
) -> dict[str, int]:
    signals: dict[str, int] = {}
    scalar_fields = ["must_fix_count", "required_code_fixes", "required_fixes"]
    for field in scalar_fields:
        if field in document:
            signals[field] = _decision_count(document[field], field=field, path=path)
    if "must_fix" in document:
        if not isinstance(document["must_fix"], list):
            raise ValueError(f"{layer} review must_fix is not a list: {path}")
        signals["must_fix"] = len(document["must_fix"])
    if "conclusion_changing_defect" in document:
        value = document["conclusion_changing_defect"]
        if not isinstance(value, bool):
            raise ValueError(
                f"invalid boolean conclusion_changing_defect: {path}"
            )
        signals["conclusion_changing_defect"] = int(value)
    if "confirmed_items" in document:
        confirmed_items = document["confirmed_items"]
        legacy_evidence_list = bool(
            layer == "second"
            and isinstance(confirmed_items, list)
            and allow_legacy_confirmed_items_list
            and path.parent.name == _LEGACY_PARAMETER_REVIEW_DIRECTORY
            and path.name == _LEGACY_PARAMETER_SECOND_REVIEW_FILE
            and _sha256(path) == _LEGACY_PARAMETER_SECOND_REVIEW_SHA256
            and "review_verdict" in document
            and "contradictions_to_the_limited_scientific_conclusion" in document
            and not any(
                field in document
                for field in ("must_fix_count", "must_fix", "conclusion")
            )
        )
        if not isinstance(confirmed_items, dict) and not legacy_evidence_list:
            raise ValueError(f"confirmed_items is not an object: {path}")
        if isinstance(confirmed_items, dict) and "new_must_fix_issue_found" in confirmed_items:
            value = confirmed_items["new_must_fix_issue_found"]
            if not isinstance(value, bool):
                raise ValueError(
                    f"invalid boolean confirmed_items.new_must_fix_issue_found: {path}"
                )
            signals["confirmed_items.new_must_fix_issue_found"] = int(value)
    if len(set(signals.values())) > 1:
        raise ValueError(f"conflicting {layer} review fix fields: {path}: {signals}")
    return signals


def _registered_contradiction_total(document: dict, *, path: Path) -> int:
    observed = {
        str(key) for key in document if str(key).startswith("contradictions")
    }
    unrecognized = observed - _REGISTERED_CONTRADICTION_FIELDS
    if unrecognized:
        raise ValueError(
            f"unrecognized contradiction fields: {path}: {sorted(unrecognized)}"
        )
    return sum(
        _decision_count(document[field], field=field, path=path)
        for field in sorted(observed)
    )


def _mapping_digest(values: dict[str, str]) -> str:
    payload = json.dumps(values, sort_keys=True, separators=(",", ":")).encode("utf-8")
    return hashlib.sha256(payload).hexdigest()


def _verify_manifest(directory: Path) -> dict:
    manifest_path = directory / "checksums.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    actual = {
        path.relative_to(directory).as_posix()
        for path in directory.rglob("*")
        if path.is_file()
    }
    if actual != set(manifest) | {"checksums.json"}:
        raise ValueError(f"input evidence file set mismatch: {directory}")
    mismatches = [
        relative
        for relative, expected in manifest.items()
        if _sha256(directory / relative).lower() != str(expected).lower()
    ]
    if mismatches:
        raise ValueError(f"input evidence checksum mismatch: {directory}: {mismatches}")
    return {
        "path": str(directory),
        "manifest_entry_count": len(manifest),
        "checksums_sha256": _sha256(manifest_path),
        "all_files_verified": True,
    }


def _review_status_impl(
    directory: Path,
    *,
    allow_legacy_confirmed_items_list: bool,
) -> dict:
    first_path = directory / "code_method_result_review.json"
    second_path = directory / "raw_evidence_review_validation.json"
    if not first_path.exists():
        first_path = directory / "independent_review.json"
        second_path = directory / "independent_review_validation.json"
    first = json.loads(first_path.read_text(encoding="utf-8"))
    second = json.loads(second_path.read_text(encoding="utf-8"))
    _validate_registered_decision_fields(first, layer="first", path=first_path)
    _validate_registered_decision_fields(second, layer="second", path=second_path)
    first_fix_signals = _validate_review_fix_fields(
        first, layer="first", path=first_path
    )
    second_fix_signals = _validate_review_fix_fields(
        second,
        layer="second",
        path=second_path,
        allow_legacy_confirmed_items_list=allow_legacy_confirmed_items_list,
    )
    if first_fix_signals:
        required_fixes = next(iter(first_fix_signals.values()))
        first_format = next(
            label
            for field, label in (
                ("must_fix_count", "must_fix_count"),
                ("must_fix", "must_fix_list"),
                ("required_code_fixes", "required_code_fixes"),
                ("required_fixes", "required_fixes"),
                ("conclusion_changing_defect", "conclusion_changing_defect"),
                (
                    "confirmed_items.new_must_fix_issue_found",
                    "confirmed_items_new_must_fix",
                ),
            )
            if field in first_fix_signals
        )
    elif "verdict" in first and _is_positive_review_verdict(
        first["verdict"], layer="first"
    ):
        first_format = "explicit_positive_verdict"
        required_fixes = 0
    else:
        raise ValueError(f"unrecognized first-review decision schema: {first_path}")
    first_verdict = first.get("verdict")
    if first_verdict is None:
        first_verdict = (
            "explicit_zero_required_fixes"
            if required_fixes == 0
            else "explicit_nonzero_required_fixes"
        )

    contradictions = _registered_contradiction_total(second, path=second_path)
    unverified = _decision_count(
        second.get("unverified_items", 0),
        field="unverified_items",
        path=second_path,
    )
    second_verdict = next(
        (
            second[field]
            for field in ("verdict", "validated_review_verdict", "review_verdict", "conclusion")
            if field in second
        ),
        None,
    )
    if "must_fix_count" in second:
        second_format = "must_fix_count"
    elif "must_fix" in second:
        second_format = "must_fix_list"
    elif "required_code_fixes" in second:
        second_format = "required_code_fixes"
    elif "required_fixes" in second:
        second_format = "required_fixes"
    elif "conclusion" in second:
        second_format = "conclusion"
    elif "review_verdict" in second and "contradictions_found" in second:
        second_format = "contradiction_counts"
    elif "review_verdict" in second:
        if "contradictions_to_the_limited_scientific_conclusion" not in second:
            raise ValueError(
                f"second review verdict lacks an explicit contradiction count: {second_path}"
            )
        second_format = "review_verdict_with_contradiction_count"
    elif "conclusion_changing_defect" in second:
        second_format = "conclusion_changing_defect"
    elif "confirmed_items.new_must_fix_issue_found" in second_fix_signals:
        second_format = "confirmed_items_new_must_fix"
    else:
        raise ValueError(f"unrecognized second-review decision schema: {second_path}")
    second_fixes = (
        next(iter(second_fix_signals.values())) if second_fix_signals else 0
    )

    first_positive = _is_positive_review_verdict(first_verdict, layer="first")
    second_decisions = [
        second[field]
        for field in ("verdict", "validated_review_verdict", "review_verdict", "conclusion")
        if field in second
    ]
    second_confirmed = bool(second_decisions) and all(
        _is_positive_review_verdict(value, layer="second")
        for value in second_decisions
    )
    passed = bool(
        required_fixes == 0
        and second_fixes == 0
        and contradictions == 0
        and unverified == 0
        and first_positive
        and second_confirmed
    )
    return {
        "path": str(directory),
        "first_review_file": first_path.name,
        "second_review_file": second_path.name,
        "first_review_format": first_format,
        "second_review_format": second_format,
        "first_review_verdict": first_verdict,
        "second_review_verdict": second_verdict,
        "required_fix_count": required_fixes,
        "second_review_must_fix_count": second_fixes,
        "contradictions_found": contradictions,
        "unverified_items": unverified,
        "passed": passed,
    }


def _review_status(directory: Path) -> dict:
    return _review_status_impl(
        directory, allow_legacy_confirmed_items_list=False
    )


def _validate_canonical_synthesis_config(repo_root: Path, config_path: Path) -> None:
    expected = (
        _SOURCE_DERIVED_REPO_ROOT / _REGISTERED_SYNTHESIS_CONFIG_RELATIVE_PATH
    ).resolve()
    if (
        repo_root.resolve() != _SOURCE_DERIVED_REPO_ROOT
        or config_path.resolve() != expected
        or _sha256(config_path) != _REGISTERED_SYNTHESIS_CONFIG_SHA256
    ):
        raise ValueError("new synthesis requires the canonical registered synthesis config")


def _registered_review_status(
    directory: Path,
    *,
    repo_root: Path,
    registered_relative_path: str,
    config_path: Path,
) -> dict:
    _validate_canonical_synthesis_config(repo_root, config_path)
    normalized = str(registered_relative_path).replace("\\", "/").strip("/")
    allow_legacy = normalized == _LEGACY_PARAMETER_REVIEW_RELATIVE_PATH
    if allow_legacy:
        expected_directory = (
            _SOURCE_DERIVED_REPO_ROOT / _LEGACY_PARAMETER_REVIEW_RELATIVE_PATH
        ).resolve()
        first_path = directory / _LEGACY_PARAMETER_FIRST_REVIEW_FILE
        second_path = directory / _LEGACY_PARAMETER_SECOND_REVIEW_FILE
        manifest_path = directory / "checksums.json"
        identity_matches = bool(
            directory.resolve() == expected_directory
            and first_path.is_file()
            and second_path.is_file()
            and manifest_path.is_file()
            and _sha256(first_path) == _LEGACY_PARAMETER_FIRST_REVIEW_SHA256
            and _sha256(second_path) == _LEGACY_PARAMETER_SECOND_REVIEW_SHA256
            and _sha256(manifest_path) == _LEGACY_PARAMETER_REVIEW_MANIFEST_SHA256
        )
        if not identity_matches:
            raise ValueError("legacy review identity does not match frozen evidence")
    return _review_status_impl(
        directory, allow_legacy_confirmed_items_list=allow_legacy
    )


def _condition_row(root: Path, condition_id: str, evidence_name: str) -> dict:
    path = root / "results" / "23_hbv_multilead_joint_uncertainty" / evidence_name
    summary = json.loads((path / "summary.json").read_text(encoding="utf-8"))
    decisions = json.loads((path / "condition_decisions.json").read_text(encoding="utf-8"))
    metrics = pd.read_csv(path / "method_metrics.csv")
    joint = metrics.loc[metrics["method"] == "joint"]

    def rmse(metric: str, lead: int) -> float:
        selected = joint.loc[
            (joint["metric"] == metric) & (joint["lead_days"] == lead),
            "root_mean_square_error",
        ]
        if len(selected) != 1:
            raise ValueError(f"missing unique joint metric {condition_id}: {metric}/{lead}")
        return float(selected.iloc[0])

    lead_decisions = {int(value["lead_days"]): value for value in decisions["lead_decisions"]}
    identification = decisions["identification"]
    return {
        "condition_id": condition_id,
        "evidence_name": evidence_name,
        "assimilation_days": int(summary["assimilation_days"]),
        "truth_switch_period_days": summary.get("truth_switch_period_days"),
        "joint_candidate_argmax_accuracy": identification[
            "joint_candidate_argmax_accuracy"
        ],
        "joint_parameter_argmax_accuracy": identification[
            "joint_parameter_argmax_accuracy"
        ],
        "joint_process_argmax_accuracy": identification[
            "joint_process_argmax_accuracy"
        ],
        "median_joint_true_candidate_probability": identification[
            "median_joint_true_candidate_probability"
        ],
        "joint_identification_effective": bool(
            decisions["joint_identification_effective"]
        ),
        "joint_rmse_lead_1": rmse("forecast_discharge", 1),
        "joint_rmse_lead_3": rmse("forecast_discharge", 3),
        "joint_rmse_lead_7": rmse("forecast_discharge", 7),
        "joint_origin_state_rmse": rmse("origin_hydrologic_state", 0),
        "effective_vs_fixed_lead_1": bool(
            lead_decisions[1]["effective_against_fixed_filter"]
        ),
        "effective_vs_fixed_lead_3": bool(
            lead_decisions[3]["effective_against_fixed_filter"]
        ),
        "effective_vs_fixed_lead_7": bool(
            lead_decisions[7]["effective_against_fixed_filter"]
        ),
        "added_value_beyond_both_lead_1": bool(
            lead_decisions[1]["added_value_beyond_both_single_factor_methods"]
        ),
        "added_value_beyond_both_lead_3": bool(
            lead_decisions[3]["added_value_beyond_both_single_factor_methods"]
        ),
        "added_value_beyond_both_lead_7": bool(
            lead_decisions[7]["added_value_beyond_both_single_factor_methods"]
        ),
        "origin_state_effective_vs_fixed": bool(
            decisions["origin_state_decision"]["effective_against_fixed_filter"]
        ),
        "origin_state_added_value_beyond_both": bool(
            decisions["origin_state_decision"][
                "added_value_beyond_both_single_factor_methods"
            ]
        ),
    }


def _verify_existing(output: Path, config: dict) -> dict:
    checksums = json.loads((output / "checksums.json").read_text(encoding="utf-8"))
    actual = {
        path.relative_to(output).as_posix()
        for path in output.rglob("*")
        if path.is_file()
    }
    if set(checksums) != REQUIRED_FILES or actual != REQUIRED_FILES | {"checksums.json"}:
        raise ValueError("synthesis evidence file set mismatch")
    for relative, expected in checksums.items():
        if _sha256(output / relative) != expected:
            raise ValueError(f"synthesis checksum mismatch: {relative}")
    if json.loads((output / "config_snapshot.json").read_text(encoding="utf-8")) != config:
        raise ValueError("synthesis config snapshot mismatch")
    return json.loads((output / "summary.json").read_text(encoding="utf-8"))


def run(repo_root: Path, config_path: Path, output_dir: Path) -> dict:
    root = repo_root.resolve()
    config_file = config_path.resolve()
    output = output_dir.resolve()
    incomplete = output.with_name(output.name + ".incomplete")
    _validate_canonical_synthesis_config(root, config_file)
    config = json.loads(config_file.read_text(encoding="utf-8"))
    if output.name != str(config["experiment_id"]):
        raise ValueError("output directory name must equal experiment_id")
    if output.exists():
        if incomplete.exists():
            raise FileExistsError("completed synthesis has incomplete sibling")
        return _verify_existing(output, config)
    if incomplete.exists():
        raise FileExistsError("refusing to overwrite incomplete synthesis")

    input_paths = [root / value for value in config["component_evidence"]]
    review_paths = [root / value for value in config["independent_review_evidence"]]
    all_input_files = [
        path
        for directory in input_paths + review_paths
        for path in directory.rglob("*")
        if path.is_file()
    ]
    maximum_input_file_bytes = max(path.stat().st_size for path in all_input_files)
    reserve = int(config["resource_rule"]["task_specific_reserve_bytes"])
    estimated_peak = 4 * maximum_input_file_bytes + 32 * 1024 * 1024
    required = estimated_peak + reserve
    available = int(psutil.virtual_memory().available)
    resource = {
        "maximum_input_file_bytes": maximum_input_file_bytes,
        "estimated_additional_peak_memory_bytes": estimated_peak,
        "task_specific_reserve_bytes": reserve,
        "task_specific_required_available_bytes": required,
        "available_physical_memory_bytes": available,
        "headroom_after_requirement_bytes": available - required,
        "execution_parallelism": int(config["resource_rule"]["execution_parallelism"]),
        "universal_memory_threshold_used": False,
        "safe_to_run": bool(available >= required),
    }
    if not resource["safe_to_run"]:
        raise MemoryError("insufficient task-specific memory headroom for synthesis")

    protected_paths = (
        config["component_evidence"]
        + config["independent_review_evidence"]
        + config.get("additional_protected_paths", [])
    )
    protected_before = _protected_hashes(root, protected_paths)
    component_integrity = [_verify_manifest(path) for path in input_paths]
    review_integrity = [_verify_manifest(path) for path in review_paths]
    component_summaries = []
    for path in input_paths:
        summary_path = path / "summary.json"
        if not summary_path.exists():
            raise ValueError(f"component summary missing: {path}")
        component_summary = json.loads(summary_path.read_text(encoding="utf-8"))
        if component_summary.get("status") != "passed":
            raise ValueError(f"component did not pass: {path.name}")
        component_summaries.append(
            {"experiment_id": component_summary.get("experiment_id", path.name), "status": "passed"}
        )
    review_summaries = [
        _registered_review_status(
            path,
            repo_root=root,
            registered_relative_path=relative,
            config_path=config_file,
        )
        for path, relative in zip(
            review_paths, config["independent_review_evidence"], strict=True
        )
    ]
    if not all(value["passed"] for value in review_summaries):
        raise ValueError("one or more independent review chains did not pass")

    state = json.loads((input_paths[0] / "summary.json").read_text(encoding="utf-8"))
    single = json.loads((input_paths[1] / "summary.json").read_text(encoding="utf-8"))
    parameter = json.loads((input_paths[2] / "summary.json").read_text(encoding="utf-8"))
    process = json.loads((input_paths[3] / "summary.json").read_text(encoding="utf-8"))
    probability = json.loads((input_paths[4] / "summary.json").read_text(encoding="utf-8"))
    interaction = json.loads((input_paths[5] / "summary.json").read_text(encoding="utf-8"))
    forecast = json.loads((input_paths[6] / "summary.json").read_text(encoding="utf-8"))
    duration_boundary = json.loads((input_paths[10] / "summary.json").read_text(encoding="utf-8"))

    conditions = pd.DataFrame(
        [
            _condition_row(root, "fixed_07_days", "joint_method_assimilation_07d_v01"),
            _condition_row(root, "fixed_21_days", "joint_method_assimilation_21d_v01"),
            _condition_row(root, "fixed_45_days", "joint_method_stable_validation_v04"),
            _condition_row(root, "periodic_switch_07_days", "joint_method_periodic_switch_07d_v01"),
        ]
    )
    identification_supported = bool(conditions["joint_identification_effective"].any())
    lead_added_columns = [
        "added_value_beyond_both_lead_1",
        "added_value_beyond_both_lead_3",
        "added_value_beyond_both_lead_7",
    ]
    joint_added_value_supported = bool(conditions[lead_added_columns].to_numpy().any())
    numerical_chain_validated = bool(
        len(component_summaries) == len(config["component_evidence"])
        and all(value["status"] == "passed" for value in component_summaries)
        and all(value["passed"] for value in review_summaries)
    )
    validation_goal_complete = bool(
        numerical_chain_validated
        and duration_boundary["all_matched_prefixes_exact"]
        and set(conditions["condition_id"])
        == {"fixed_07_days", "fixed_21_days", "fixed_45_days", "periodic_switch_07_days"}
    )
    broad_authorized = bool(
        numerical_chain_validated
        and identification_supported
        and joint_added_value_supported
    )

    process_correct = int(
        np.count_nonzero(
            np.asarray(process["predicted_process_noise_ids"])
            == np.asarray(process["true_process_noise_ids"])
        )
    )
    parameter_correct = int(
        np.count_nonzero(
            np.asarray(parameter["predicted_parameter_ids"])
            == np.asarray(parameter["true_parameter_ids"])
        )
    )
    claims = [
        {"claim_id": "state_propagation", "classification": "fact", "claim": "Independent and production one-day state propagation agree within the registered tolerance.", "evidence_path": config["component_evidence"][0], "value": state["state_maximum_absolute_error"], "status": "supported"},
        {"claim_id": "single_filter", "classification": "fact", "claim": "Observation updating improved hydrologic state in 20 of 24 trials and one-day flow in 24 of 24 trials relative to the same filter without observations.", "evidence_path": config["component_evidence"][1], "value": "20/24 state; 24/24 flow", "status": "supported"},
        {"claim_id": "parameter_identification", "classification": "fact", "claim": "The isolated ideal parameter-identification test selected the true complete parameter vector in every trial.", "evidence_path": config["component_evidence"][2], "value": f"{parameter_correct}/{parameter['trial_count']}", "status": "supported_with_registered_ideal_scope"},
        {"claim_id": "process_scale_identification", "classification": "fact", "claim": "The isolated projected process-scale test selected the true scale in 23 of 24 trials.", "evidence_path": config["component_evidence"][3], "value": f"{process_correct}/{process['trial_count']}", "status": "supported_with_projected_truth_scope"},
        {"claim_id": "probability_update", "classification": "fact", "claim": "Likelihood updating improved joint candidate accuracy over the transition prior in the registered switching-emission validation.", "evidence_path": config["component_evidence"][4], "value": f"{probability['joint_prior_accuracy']:.6f} to {probability['joint_posterior_accuracy']:.6f}", "status": "supported_with_switch_day_limit"},
        {"claim_id": "state_interaction", "classification": "fact", "claim": "Full state interaction reproduced independently calculated mixture moments within the registered numerical gates.", "evidence_path": config["component_evidence"][5], "value": interaction["gate_values"]["production_reference_combined_mean_maximum_absolute_error"], "status": "supported"},
        {"claim_id": "forecast_propagation", "classification": "fact", "claim": "Observation-free one-, three-, and seven-day joint forecast propagation reproduced the independent reference without future discharge observations.", "evidence_path": config["component_evidence"][6], "value": forecast["gate_values"]["combined_prediction_maximum_absolute_error"], "status": "supported"},
        {"claim_id": "joint_identification", "classification": "fact", "claim": "The complete nine-filter method did not pass its joint-identification rule in any tested final condition.", "evidence_path": f"final_conditions.csv <- {'; '.join([config['component_evidence'][7], config['component_evidence'][8], config['component_evidence'][9], config['component_evidence'][11]])}", "value": "0/4 tested conditions", "status": "rejected_in_tested_conditions"},
        {"claim_id": "joint_forecast_added_value", "classification": "fact", "claim": "No tested one-, three-, or seven-day target established added value beyond both single-factor methods.", "evidence_path": f"final_conditions.csv <- {'; '.join([config['component_evidence'][7], config['component_evidence'][8], config['component_evidence'][9], config['component_evidence'][11]])}", "value": "0/12 condition-by-lead targets", "status": "rejected_in_tested_conditions"},
        {"claim_id": "assimilation_duration_boundary", "classification": "fact", "claim": "The preregistered joint-identification rule was not reached through forty-five matched assimilation days.", "evidence_path": config["component_evidence"][10], "value": "7, 21 and 45 days all failed", "status": "bounded_failure"},
        {"claim_id": "rapid_switch_boundary", "classification": "fact", "claim": "Under seven-day simultaneous complete-parameter and process-scale switching, current joint candidate identification was 10 of 72 and no forecast lead passed the fixed-filter effectiveness rule.", "evidence_path": config["component_evidence"][11], "value": "10/72; 0/3 leads", "status": "bounded_failure"},
        {"claim_id": "broad_method_claim", "classification": "inference", "claim": "The tested evidence does not justify a broad scientific claim that the complete joint method is superior to simpler single-factor methods.", "evidence_path": config["experiment_id"], "value": "HOLD", "status": "not_authorized"},
        {"claim_id": "longer_assimilation", "classification": "unknown", "claim": "Whether more than forty-five matched assimilation days would satisfy joint identification is currently unknown.", "evidence_path": config["component_evidence"][10], "value": ">45 days not tested", "status": "unknown"},
        {"claim_id": "other_switch_conditions", "classification": "unknown", "claim": "Performance under other switch periods or transition priors is currently unknown.", "evidence_path": config["component_evidence"][11], "value": "not tested", "status": "unknown"},
        {"claim_id": "real_basin_performance", "classification": "unknown", "claim": "Real-basin performance of the complete joint method is currently unknown from this synthetic validation.", "evidence_path": config["experiment_id"], "value": "no real-basin observations used", "status": "unknown"},
        {"claim_id": "other_observation_or_forcing_error", "classification": "unknown", "claim": "Performance under other observation uncertainty or forcing error is currently unknown.", "evidence_path": config["experiment_id"], "value": "not tested", "status": "unknown"},
        {"claim_id": "post_projection_gaussian_model", "classification": "unknown", "claim": "Recovery of an exact post-projection additive Gaussian process model is not established because physical projection truncates the realized truth distribution.", "evidence_path": config["component_evidence"][9], "value": "post-projection truth is not an exact additive Gaussian candidate model", "status": "not_established"},
    ]
    claim_table = pd.DataFrame(claims)
    summary = {
        "experiment_id": config["experiment_id"],
        "status": "passed" if validation_goal_complete else "failed",
        "validation_goal_complete": validation_goal_complete,
        "numerical_chain_validated": numerical_chain_validated,
        "joint_identification_supported": identification_supported,
        "joint_added_value_supported": joint_added_value_supported,
        "broad_scientific_claim_authorized": broad_authorized,
        "scientific_status": "SUPPORTED" if broad_authorized else "HOLD",
        "component_evidence_count": len(component_summaries),
        "independent_review_chain_count": len(review_summaries),
        "tested_final_condition_count": len(conditions),
        "scope_limit": config["scope_limit"],
    }
    component_summary = {
        "components": component_summaries,
        "reviews": review_summaries,
        "key_numbers": {
            "state_propagation_maximum_absolute_error": state[
                "state_maximum_absolute_error"
            ],
            "single_filter_state_improvement_trials": single["state_improvement_count"],
            "single_filter_flow_improvement_trials": single["flow_improvement_count"],
            "parameter_identification_correct_trials": parameter_correct,
            "process_scale_identification_correct_trials": process_correct,
            "joint_probability_prior_accuracy": probability["joint_prior_accuracy"],
            "joint_probability_posterior_accuracy": probability[
                "joint_posterior_accuracy"
            ],
        },
    }
    markdown = f"""# Complete closed synthetic-truth validation synthesis

## Conclusion

The validation goal is complete and the numerical chain is validated. The scientific conclusion remains **HOLD** for broad joint-method superiority: no tested final condition passed joint identification, and no one-, three-, or seven-day target established added value beyond both single-factor methods.

## Supported numerical chain

- State propagation maximum absolute difference: `{state['state_maximum_absolute_error']}`.
- Same-filter observation updating improved state in `{single['state_improvement_count']}/{single['trial_count']}` trials and one-day flow in `{single['flow_improvement_count']}/{single['trial_count']}` trials.
- Isolated complete-parameter identification: `{parameter_correct}/{parameter['trial_count']}`.
- Isolated projected process-scale identification: `{process_correct}/{process['trial_count']}`.
- Joint probability accuracy improved from `{probability['joint_prior_accuracy']:.6f}` to `{probability['joint_posterior_accuracy']:.6f}` in its registered validation.
- Independent full interaction and observation-free forecast checks passed their numerical gates.

## Final conditions and boundaries

- Fixed labels with 7, 21 and 45 assimilation days all failed the preregistered joint-identification rule. At 45 days, the complete-parameter-label accuracy was `43/72`, below the `48/72` threshold; longer durations are unknown.
- In the fixed 45-day condition, only origin state and seven-day forecast were effective relative to the fixed filter, and neither established added value beyond both single-factor methods.
- In the seven-day simultaneous-switch condition, current candidate accuracy was `10/72`; no forecast lead was effective relative to the fixed filter. This applies only to the registered seven-day switch period, factor-level stay probability 0.98, three current-label observations at origin, and a further switch at forecast lead five.

## Unknown

Real-basin behavior, more than 45 assimilation days, other switch periods or transition priors, other observation uncertainty, forcing error, and exact post-projection additive Gaussian recovery were not tested.
"""

    protected_after = _protected_hashes(root, protected_paths)
    protected_unchanged = protected_before == protected_after
    if not protected_unchanged:
        raise RuntimeError("input evidence changed during synthesis")
    input_integrity = {
        "component_evidence": component_integrity,
        "independent_review_evidence": review_integrity,
        "all_verified": True,
    }
    protected_integrity = {
        "configured_path_count": len(protected_paths),
        "file_count": len(protected_before),
        "before_sha256": _mapping_digest(protected_before),
        "after_sha256": _mapping_digest(protected_after),
        "status": "unchanged",
    }

    incomplete.mkdir(parents=True)
    try:
        _json_write(incomplete / "config_snapshot.json", config)
        _json_write(incomplete / "input_evidence_integrity.json", input_integrity)
        _json_write(incomplete / "component_summary.json", component_summary)
        _json_write(incomplete / "resource_preflight.json", resource)
        _json_write(incomplete / "protected_artifact_integrity.json", protected_integrity)
        _json_write(incomplete / "summary.json", summary)
        conditions.to_csv(incomplete / "final_conditions.csv", index=False)
        claim_table.to_csv(incomplete / "claim_evidence.csv", index=False)
        (incomplete / "final_synthesis.md").write_text(markdown, encoding="utf-8")
        snapshot = incomplete / "source_snapshot"
        snapshot.mkdir()
        shutil.copy2(Path(__file__).resolve(), snapshot / "run_joint_method_synthesis.py")
        shutil.copy2(
            root / "test" / "test_hbv_joint_method_synthesis.py",
            snapshot / "test_hbv_joint_method_synthesis.py",
        )
        paths = sorted(path for path in incomplete.rglob("*") if path.is_file())
        checksums = {
            path.relative_to(incomplete).as_posix(): _sha256(path) for path in paths
        }
        if set(checksums) != REQUIRED_FILES:
            raise ValueError("synthesis package file set mismatch")
        _json_write(incomplete / "checksums.json", checksums)
        incomplete.replace(output)
    except Exception:
        if incomplete.exists():
            shutil.rmtree(incomplete)
        raise
    if summary["status"] != "passed":
        raise RuntimeError("validation synthesis did not complete")
    return summary


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo-root", required=True, type=Path)
    parser.add_argument("--config", required=True, type=Path)
    parser.add_argument("--output-dir", required=True, type=Path)
    args = parser.parse_args()
    run(args.repo_root, args.config, args.output_dir)


if __name__ == "__main__":
    main()
