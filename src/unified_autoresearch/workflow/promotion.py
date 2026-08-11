"""Assess whether an automatic recommendation has independent scale evidence.

The assessor never opens prediction or target data. It keeps technical scale-up
evidence separate from evidence created prospectively after a recommendation was
frozen.
"""

from __future__ import annotations

import json
import re
from datetime import datetime
from pathlib import Path
from typing import Any

from unified_autoresearch.workflow.development_loop import _write_json_exclusive


POLICY_PATH = Path(__file__).resolve().parents[1] / "protocols" / "promotion_v1.json"
POLICY_FIELDS = {
    "schema_version",
    "equivalent_result_scope",
    "required_scale_basin_count",
    "required_scale_registered_run_count",
    "required_scale_score_report_count",
    "required_scale_runtime_count",
    "required_scale_seed",
    "required_runtime_source_file_count",
    "trusted_recommendation_timestamp_sources",
    "trusted_scale_start_timestamp_sources",
    "trusted_scale_evidence_timestamp_sources",
    "protected_boundary_fields",
}
RECORD_FIELDS = {
    "schema_version",
    "automatic_recommendation",
    "scale_validation",
    "identity_checks",
    "artifacts",
}
AUTOMATIC_FIELDS = {
    "experiment_id",
    "job_id",
    "candidate_id",
    "finalized_at",
    "timestamp_source",
}
SCALE_FIELDS = {
    "experiment_id",
    "job_id",
    "candidate_id",
    "basin_count",
    "seed",
    "started_at",
    "started_at_source",
    "evidence_created_at",
    "evidence_created_at_source",
    "result_available_during_proposal",
    "registered_run_count",
    "score_report_count",
    "runtime_count",
    "process_exit_codes",
    "normalized_exit_codes",
    "required_outputs_complete",
    "denied_event_count",
    "protected_boundaries",
}
IDENTITY_FIELDS = {
    "category_equal",
    "seed_equal",
    "dependencies_equal",
    "allowed_reads_equal",
    "outputs_equal",
    "runtime_source_hashes_equal",
    "runtime_source_file_count",
}
ARTIFACT_FIELDS = {
    "automatic_evidence_path",
    "automatic_evidence_sha256",
    "automatic_manifest_sha256",
    "scale_evidence_path",
    "scale_evidence_sha256",
    "scale_manifest_sha256",
}
SHA256_PATTERN = re.compile(r"[0-9a-f]{64}")


def _require_fields(value: Any, expected: set[str], label: str) -> dict[str, Any]:
    if not isinstance(value, dict) or set(value) != expected:
        raise ValueError(f"{label} fields do not match the frozen schema")
    return value


def _require_nonempty_string(value: Any, label: str) -> str:
    if not isinstance(value, str) or not value.strip():
        raise ValueError(f"{label} must be a non-empty string")
    return value


def _require_nonnegative_int(value: Any, label: str) -> int:
    if not isinstance(value, int) or isinstance(value, bool) or value < 0:
        raise ValueError(f"{label} must be a non-negative integer")
    return value


def _require_bool(value: Any, label: str) -> bool:
    if not isinstance(value, bool):
        raise ValueError(f"{label} must be Boolean")
    return value


def _parse_aware(value: Any, label: str) -> datetime:
    text = _require_nonempty_string(value, label)
    try:
        parsed = datetime.fromisoformat(text)
    except ValueError as error:
        raise ValueError(f"{label} must be an ISO-8601 timestamp") from error
    if parsed.tzinfo is None or parsed.utcoffset() is None:
        raise ValueError(f"{label} must be timezone-aware")
    return parsed


def _load_policy() -> dict[str, Any]:
    value = _require_fields(
        json.loads(POLICY_PATH.read_text(encoding="utf-8")), POLICY_FIELDS, "promotion policy"
    )
    if value["schema_version"] != "promotion_policy_v1":
        raise ValueError("promotion policy schema version is invalid")
    if (
        value["equivalent_result_scope"]
        != "same_candidate_seed_basin_set_protocols_and_runtime_sources_v1"
    ):
        raise ValueError("promotion policy equivalent-result scope is invalid")
    for name in (
        "required_scale_basin_count",
        "required_scale_registered_run_count",
        "required_scale_score_report_count",
        "required_scale_runtime_count",
        "required_runtime_source_file_count",
        "required_scale_seed",
    ):
        _require_nonnegative_int(value[name], f"promotion policy {name}")
    for name in (
        "trusted_recommendation_timestamp_sources",
        "trusted_scale_start_timestamp_sources",
        "trusted_scale_evidence_timestamp_sources",
        "protected_boundary_fields",
    ):
        if (
            not isinstance(value[name], list)
            or not value[name]
            or any(not isinstance(item, str) or not item for item in value[name])
            or len(set(value[name])) != len(value[name])
        ):
            raise ValueError(f"promotion policy {name} is invalid")
    return value


def _validate_record(record: Any, policy: dict[str, Any]) -> tuple[dict[str, Any], ...]:
    value = _require_fields(record, RECORD_FIELDS, "promotion evidence record")
    if value["schema_version"] != "promotion_evidence_record_v1":
        raise ValueError("promotion evidence record schema version is invalid")
    automatic = _require_fields(
        value["automatic_recommendation"], AUTOMATIC_FIELDS, "automatic recommendation"
    )
    scale = _require_fields(value["scale_validation"], SCALE_FIELDS, "scale validation")
    identity = _require_fields(value["identity_checks"], IDENTITY_FIELDS, "identity checks")
    artifacts = _require_fields(value["artifacts"], ARTIFACT_FIELDS, "artifacts")
    boundaries = _require_fields(
        scale["protected_boundaries"],
        set(policy["protected_boundary_fields"]),
        "protected boundaries",
    )

    for group, names in (
        (automatic, ("experiment_id", "job_id", "candidate_id", "timestamp_source")),
        (
            scale,
            (
                "experiment_id",
                "job_id",
                "candidate_id",
                "started_at_source",
                "evidence_created_at_source",
            ),
        ),
    ):
        for name in names:
            _require_nonempty_string(group[name], name)
    for name in (
        "basin_count",
        "seed",
        "registered_run_count",
        "score_report_count",
        "runtime_count",
        "denied_event_count",
    ):
        _require_nonnegative_int(scale[name], f"scale validation {name}")
    for name in IDENTITY_FIELDS - {"runtime_source_file_count"}:
        _require_bool(identity[name], f"identity check {name}")
    _require_nonnegative_int(identity["runtime_source_file_count"], "runtime source file count")
    _require_bool(scale["result_available_during_proposal"], "result availability flag")
    for name in policy["protected_boundary_fields"]:
        _require_bool(boundaries[name], f"protected boundary {name}")

    for name in ("process_exit_codes", "normalized_exit_codes"):
        if not isinstance(scale[name], list) or any(
            not isinstance(item, int) or isinstance(item, bool) for item in scale[name]
        ):
            raise ValueError(f"scale validation {name} must be an integer list")
    outputs = scale["required_outputs_complete"]
    if not isinstance(outputs, list) or any(not isinstance(item, bool) for item in outputs):
        raise ValueError("scale validation required_outputs_complete must be a Boolean list")

    for name in ("automatic_evidence_path", "scale_evidence_path"):
        _require_nonempty_string(artifacts[name], f"artifact {name}")
    for name in ARTIFACT_FIELDS - {"automatic_evidence_path", "scale_evidence_path"}:
        if not isinstance(artifacts[name], str) or SHA256_PATTERN.fullmatch(artifacts[name]) is None:
            raise ValueError(f"artifact {name} must be a lowercase SHA-256 digest")

    finalized_at = _parse_aware(automatic["finalized_at"], "recommendation finalized_at")
    started_at = _parse_aware(scale["started_at"], "scale validation started_at")
    evidence_created_at = _parse_aware(
        scale["evidence_created_at"], "scale validation evidence_created_at"
    )
    return value, automatic, scale, identity, boundaries, finalized_at, started_at, evidence_created_at


def assess_promotion(record: dict[str, Any]) -> dict[str, Any]:
    """Return separate technical and prospective promotion decisions."""
    policy = _load_policy()
    (
        _,
        automatic,
        scale,
        identity,
        boundaries,
        finalized_at,
        started_at,
        evidence_created_at,
    ) = _validate_record(record, policy)

    technical_failures: list[str] = []
    if automatic["candidate_id"] != scale["candidate_id"]:
        technical_failures.append("candidate identifiers differ")
    if scale["basin_count"] != policy["required_scale_basin_count"]:
        technical_failures.append("scale validation basin count is invalid")
    if scale["seed"] != policy["required_scale_seed"] or not identity["seed_equal"]:
        technical_failures.append("candidate seeds differ")
    for name, message in (
        ("category_equal", "candidate categories differ"),
        ("dependencies_equal", "candidate dependencies differ"),
        ("allowed_reads_equal", "candidate allowed-read declarations differ"),
        ("outputs_equal", "candidate output declarations differ"),
        ("runtime_source_hashes_equal", "runtime source hashes differ"),
    ):
        if not identity[name]:
            technical_failures.append(message)
    if identity["runtime_source_file_count"] != policy["required_runtime_source_file_count"]:
        technical_failures.append("runtime source file count is invalid")
    for name, policy_name, message in (
        (
            "registered_run_count",
            "required_scale_registered_run_count",
            "scale validation registered-run count is invalid",
        ),
        (
            "score_report_count",
            "required_scale_score_report_count",
            "scale validation score-report count is invalid",
        ),
        (
            "runtime_count",
            "required_scale_runtime_count",
            "scale validation runtime count is invalid",
        ),
    ):
        if scale[name] != policy[policy_name]:
            technical_failures.append(message)
    runtime_count = policy["required_scale_runtime_count"]
    if (
        len(scale["process_exit_codes"]) != runtime_count
        or any(code != 0 for code in scale["process_exit_codes"])
    ):
        technical_failures.append("scale validation process exits are not all zero")
    if (
        len(scale["normalized_exit_codes"]) != runtime_count
        or any(code != 0 for code in scale["normalized_exit_codes"])
    ):
        technical_failures.append("scale validation normalized exits are not all zero")
    if (
        len(scale["required_outputs_complete"]) != runtime_count
        or not all(scale["required_outputs_complete"])
    ):
        technical_failures.append("scale validation output contracts are incomplete")
    if scale["denied_event_count"] != 0:
        technical_failures.append("scale validation contains denied access events")
    if any(boundaries.values()):
        technical_failures.append("scale validation crossed a protected boundary")

    prospective_failures: list[str] = []
    if automatic["timestamp_source"] not in policy["trusted_recommendation_timestamp_sources"]:
        prospective_failures.append("automatic recommendation timestamp source is not trusted")
    if scale["started_at_source"] not in policy["trusted_scale_start_timestamp_sources"]:
        prospective_failures.append("scale validation start timestamp source is not trusted")
    if (
        scale["evidence_created_at_source"]
        not in policy["trusted_scale_evidence_timestamp_sources"]
    ):
        prospective_failures.append("scale evidence timestamp source is not trusted")
    if started_at < finalized_at:
        prospective_failures.append(
            "scale validation started before the recommendation was finalized"
        )
    elif started_at == finalized_at:
        prospective_failures.append(
            "scale validation did not start after the recommendation was finalized"
        )
    if evidence_created_at < finalized_at:
        prospective_failures.append(
            "scale evidence was created before the recommendation was finalized"
        )
    elif evidence_created_at == finalized_at:
        prospective_failures.append(
            "scale evidence was not created after the recommendation was finalized"
        )
    if evidence_created_at < started_at:
        prospective_failures.append("scale evidence was created before scale validation started")
    # This flag covers any already-known result with the same candidate, seed,
    # basin set, protocols, and runtime sources, not only the current job identifier.
    if scale["result_available_during_proposal"]:
        prospective_failures.append(
            "scale result was available during proposal or development selection"
        )

    technical_gate = "PASS" if not technical_failures else "HOLD"
    prospective_gate = "PASS" if not prospective_failures else "HOLD"
    return {
        "schema_version": "promotion_assessment_v1",
        "automatic_experiment_id": automatic["experiment_id"],
        "scale_experiment_id": scale["experiment_id"],
        "candidate_id": automatic["candidate_id"],
        "technical_scaleup_gate": technical_gate,
        "prospective_independence_gate": prospective_gate,
        "promotion_decision": (
            "PASS" if technical_gate == "PASS" and prospective_gate == "PASS" else "HOLD"
        ),
        "technical_failures": technical_failures,
        "prospective_failures": prospective_failures,
    }


def write_promotion_audit(record: dict[str, Any], output_path: str | Path) -> dict[str, Any]:
    """Validate first and write one immutable promotion audit without overwriting."""
    value = {
        "schema_version": "promotion_audit_v1",
        "record": record,
        "assessment": assess_promotion(record),
    }
    _write_json_exclusive(Path(output_path), value)
    return value
