import json
from pathlib import Path

import pytest


MODULE_ROOT = Path(__file__).resolve().parents[1]
CURRENT_AUDIT_PATH = MODULE_ROOT / "evidence" / "AUTOMATIC_REHEARSAL_PROMOTION_AUDIT_20260811.json"


def _record() -> dict:
    return {
        "schema_version": "promotion_evidence_record_v1",
        "automatic_recommendation": {
            "experiment_id": "automatic-eight-basin-example",
            "job_id": "200001",
            "candidate_id": "candidate-v1",
            "finalized_at": "2026-08-11T10:00:00+08:00",
            "timestamp_source": "immutable_registry_receipt",
        },
        "scale_validation": {
            "experiment_id": "scale-validation-example",
            "job_id": "200002",
            "candidate_id": "candidate-v1",
            "basin_count": 64,
            "seed": 29,
            "started_at": "2026-08-11T10:05:00+08:00",
            "started_at_source": "slurm_accounting",
            "evidence_created_at": "2026-08-11T10:20:00+08:00",
            "evidence_created_at_source": "immutable_manifest_receipt",
            "result_available_during_proposal": False,
            "registered_run_count": 4,
            "score_report_count": 2,
            "runtime_count": 4,
            "process_exit_codes": [0, 0, 0, 0],
            "normalized_exit_codes": [0, 0, 0, 0],
            "required_outputs_complete": [True, True, True, True],
            "denied_event_count": 0,
            "protected_boundaries": {
                "sealed_final_evaluation_read_or_scored": False,
                "fair_benchmark_scoring_program_run": False,
                "formal_basin_search_run": False,
                "baseline_outperformance_claimed": False,
            },
        },
        "identity_checks": {
            "category_equal": True,
            "seed_equal": True,
            "dependencies_equal": True,
            "allowed_reads_equal": True,
            "outputs_equal": True,
            "runtime_source_hashes_equal": True,
            "runtime_source_file_count": 9,
        },
        "artifacts": {
            "automatic_evidence_path": "/evidence/automatic.json",
            "automatic_evidence_sha256": "a" * 64,
            "automatic_manifest_sha256": "b" * 64,
            "scale_evidence_path": "/evidence/scale.json",
            "scale_evidence_sha256": "c" * 64,
            "scale_manifest_sha256": "d" * 64,
        },
    }


def test_fresh_post_recommendation_scale_validation_passes_both_gates():
    from unified_autoresearch.workflow.promotion import assess_promotion

    result = assess_promotion(_record())

    assert result["technical_scaleup_gate"] == "PASS"
    assert result["prospective_independence_gate"] == "PASS"
    assert result["promotion_decision"] == "PASS"
    assert result["technical_failures"] == []
    assert result["prospective_failures"] == []


def test_historical_scale_result_is_technical_pass_but_prospective_hold():
    from unified_autoresearch.workflow.promotion import assess_promotion

    record = _record()
    record["automatic_recommendation"].update(
        finalized_at="2026-08-11T12:24:21+08:00",
        timestamp_source="filesystem_mtime",
    )
    record["scale_validation"].update(
        started_at="2026-08-10T17:38:49+08:00",
        evidence_created_at="2026-08-10T18:01:00+08:00",
        evidence_created_at_source="filesystem_mtime",
        result_available_during_proposal=True,
    )

    result = assess_promotion(record)

    assert result["technical_scaleup_gate"] == "PASS"
    assert result["prospective_independence_gate"] == "HOLD"
    assert result["promotion_decision"] == "HOLD"
    assert set(result["prospective_failures"]) == {
        "automatic recommendation timestamp source is not trusted",
        "scale evidence timestamp source is not trusted",
        "scale validation started before the recommendation was finalized",
        "scale evidence was created before the recommendation was finalized",
        "scale result was available during proposal or development selection",
    }


def test_later_retry_is_not_independent_when_an_equivalent_result_is_already_known():
    from unified_autoresearch.workflow.promotion import assess_promotion

    record = _record()
    record["scale_validation"]["result_available_during_proposal"] = True

    result = assess_promotion(record)

    assert result["technical_scaleup_gate"] == "PASS"
    assert result["prospective_independence_gate"] == "HOLD"
    assert result["promotion_decision"] == "HOLD"
    assert result["prospective_failures"] == [
        "scale result was available during proposal or development selection"
    ]


@pytest.mark.parametrize(
    ("mutate", "failure"),
    [
        (
            lambda record: record["scale_validation"].update(candidate_id="other-candidate"),
            "candidate identifiers differ",
        ),
        (
            lambda record: record["identity_checks"].update(runtime_source_hashes_equal=False),
            "runtime source hashes differ",
        ),
        (
            lambda record: record["scale_validation"].update(denied_event_count=1),
            "scale validation contains denied access events",
        ),
        (
            lambda record: record["scale_validation"].update(
                required_outputs_complete=[True, True, True, False]
            ),
            "scale validation output contracts are incomplete",
        ),
        (
            lambda record: record["scale_validation"]["protected_boundaries"].update(
                formal_basin_search_run=True
            ),
            "scale validation crossed a protected boundary",
        ),
    ],
)
def test_technical_mismatch_forces_overall_hold(mutate, failure):
    from unified_autoresearch.workflow.promotion import assess_promotion

    record = _record()
    mutate(record)

    result = assess_promotion(record)

    assert result["technical_scaleup_gate"] == "HOLD"
    assert result["promotion_decision"] == "HOLD"
    assert failure in result["technical_failures"]


def test_timezone_naive_timestamp_is_rejected():
    from unified_autoresearch.workflow.promotion import assess_promotion

    record = _record()
    record["automatic_recommendation"]["finalized_at"] = "2026-08-11T10:00:00"

    with pytest.raises(ValueError, match="timezone-aware"):
        assess_promotion(record)


def test_equal_timestamps_do_not_count_as_post_recommendation_evidence():
    from unified_autoresearch.workflow.promotion import assess_promotion

    record = _record()
    record["scale_validation"].update(
        started_at=record["automatic_recommendation"]["finalized_at"],
        evidence_created_at=record["automatic_recommendation"]["finalized_at"],
    )

    result = assess_promotion(record)

    assert result["prospective_independence_gate"] == "HOLD"
    assert result["promotion_decision"] == "HOLD"
    assert "scale validation did not start after the recommendation was finalized" in result[
        "prospective_failures"
    ]
    assert "scale evidence was not created after the recommendation was finalized" in result[
        "prospective_failures"
    ]


def test_unknown_record_field_is_rejected():
    from unified_autoresearch.workflow.promotion import assess_promotion

    record = _record()
    record["unexpected"] = True

    with pytest.raises(ValueError, match="fields"):
        assess_promotion(record)


def test_promotion_audit_is_created_exclusively(tmp_path):
    from unified_autoresearch.workflow.promotion import write_promotion_audit

    output_path = tmp_path / "audit.json"
    value = write_promotion_audit(_record(), output_path)

    assert json.loads(output_path.read_text(encoding="utf-8")) == value
    assert value["schema_version"] == "promotion_audit_v1"
    assert value["assessment"]["promotion_decision"] == "PASS"
    with pytest.raises(FileExistsError):
        write_promotion_audit(_record(), output_path)


def test_current_hpc_comparison_is_recorded_as_technical_pass_and_prospective_hold():
    from unified_autoresearch.workflow.promotion import assess_promotion

    value = json.loads(CURRENT_AUDIT_PATH.read_text(encoding="utf-8"))

    assert value["assessment"] == assess_promotion(value["record"])
    assert value["assessment"]["technical_scaleup_gate"] == "PASS"
    assert value["assessment"]["prospective_independence_gate"] == "HOLD"
    assert value["assessment"]["promotion_decision"] == "HOLD"
