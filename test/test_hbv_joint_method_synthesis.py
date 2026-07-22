import json
import sys
from pathlib import Path

import pandas as pd
import pytest


REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT / "src"))

from hbv_multilead_joint_uncertainty.scripts.run_joint_method_synthesis import (  # noqa: E402
    _review_status,
    run,
)


def _write_review_pair(
    directory: Path, first: dict, second: dict
) -> None:
    directory.mkdir()
    (directory / "code_method_result_review.json").write_text(
        json.dumps(first), encoding="utf-8"
    )
    (directory / "raw_evidence_review_validation.json").write_text(
        json.dumps(second), encoding="utf-8"
    )


def test_review_status_rejects_first_verdict_containing_pass_as_substring(tmp_path):
    review_dir = tmp_path / "bypass_review"
    _write_review_pair(
        review_dir,
        {"verdict": "bypass"},
        {"must_fix_count": 0, "verdict": "confirmed"},
    )

    with pytest.raises(ValueError, match="unrecognized first-review decision schema"):
        _review_status(review_dir)


def test_review_status_does_not_confirm_second_verdict_by_substring(tmp_path):
    review_dir = tmp_path / "unconfirmed_review"
    _write_review_pair(
        review_dir,
        {"must_fix_count": 0, "verdict": "PASS"},
        {"must_fix_count": 0, "verdict": "unconfirmed"},
    )

    assert _review_status(review_dir)["passed"] is False


def test_review_status_rejects_unregistered_contradiction_counter(tmp_path):
    review_dir = tmp_path / "invented_contradiction_counter"
    _write_review_pair(
        review_dir,
        {"must_fix_count": 0, "verdict": "PASS"},
        {"review_verdict": "confirmed", "contradictions_passenger": 0},
    )

    with pytest.raises(ValueError, match="unrecognized second review decision fields"):
        _review_status(review_dir)


@pytest.mark.parametrize("layer", ["first", "second"])
def test_review_status_rejects_zero_count_hiding_nonempty_must_fix_list(
    tmp_path, layer
):
    first = {"must_fix_count": 0, "must_fix": [], "verdict": "PASS"}
    second = {"must_fix_count": 0, "must_fix": [], "verdict": "confirmed"}
    if layer == "first":
        first["must_fix"] = ["hidden defect"]
    else:
        second["must_fix"] = ["hidden defect"]
    review_dir = tmp_path / f"conflicting_{layer}_fix_fields"
    _write_review_pair(review_dir, first, second)

    with pytest.raises(ValueError, match="conflicting .* review fix fields"):
        _review_status(review_dir)


@pytest.mark.parametrize("field", ["required_fixes", "required_code_fixes"])
def test_review_status_rejects_conflicting_second_fix_counter(tmp_path, field):
    review_dir = tmp_path / f"conflicting_second_{field}"
    _write_review_pair(
        review_dir,
        {"must_fix_count": 0, "verdict": "PASS"},
        {"must_fix_count": 0, field: 1, "verdict": "confirmed"},
    )

    with pytest.raises(ValueError, match="conflicting second review fix fields"):
        _review_status(review_dir)


def test_review_status_does_not_ignore_conflicting_second_verdicts(tmp_path):
    review_dir = tmp_path / "conflicting_second_verdicts"
    _write_review_pair(
        review_dir,
        {"must_fix_count": 0, "verdict": "PASS"},
        {
            "must_fix_count": 0,
            "verdict": "confirmed",
            "review_verdict": "not_confirmed",
        },
    )

    assert _review_status(review_dir)["passed"] is False


@pytest.mark.parametrize(
    "field", ["must_fix_passenger", "contradiction_passenger", "hidden_defect", "unverified_passenger"]
)
def test_review_status_rejects_unregistered_decision_field(tmp_path, field):
    review_dir = tmp_path / f"invented_{field}"
    _write_review_pair(
        review_dir,
        {"must_fix_count": 0, "verdict": "PASS"},
        {
            "must_fix_count": 0,
            field: 0,
            "verdict": "confirmed",
        },
    )

    with pytest.raises(ValueError, match="unrecognized second review decision fields"):
        _review_status(review_dir)


def test_review_status_rejects_unregistered_first_status_field(tmp_path):
    review_dir = tmp_path / "invented_first_status"
    _write_review_pair(
        review_dir,
        {"must_fix_count": 0, "verdict": "PASS", "status": "FAIL"},
        {"must_fix_count": 0, "verdict": "confirmed"},
    )

    with pytest.raises(ValueError, match="unrecognized first review decision fields"):
        _review_status(review_dir)


@pytest.mark.parametrize(
    "field", ["status_passenger", "decision_passenger", "review_status", "scientific_decision"]
)
@pytest.mark.parametrize("layer", ["first", "second"])
def test_review_status_rejects_unregistered_status_or_decision_variants(
    tmp_path, field, layer
):
    first = {"must_fix_count": 0, "verdict": "PASS"}
    second = {"must_fix_count": 0, "verdict": "confirmed"}
    (first if layer == "first" else second)[field] = "PASS"
    review_dir = tmp_path / f"invented_{layer}_{field}"
    _write_review_pair(review_dir, first, second)

    with pytest.raises(
        ValueError, match=f"unrecognized {layer} review decision fields"
    ):
        _review_status(review_dir)


def test_review_status_uses_standalone_conclusion_changing_defect(tmp_path):
    review_dir = tmp_path / "standalone_conclusion_changing_defect"
    _write_review_pair(
        review_dir,
        {"conclusion_changing_defect": True, "verdict": "PASS"},
        {"must_fix_count": 0, "verdict": "confirmed"},
    )

    assert _review_status(review_dir)["passed"] is False


def test_review_status_uses_standalone_nested_new_must_fix(tmp_path):
    review_dir = tmp_path / "standalone_nested_new_must_fix"
    _write_review_pair(
        review_dir,
        {"must_fix_count": 0, "verdict": "PASS"},
        {
            "review_verdict": "confirmed",
            "contradictions_found": 0,
            "confirmed_items": {"new_must_fix_issue_found": True},
        },
    )

    assert _review_status(review_dir)["passed"] is False


def test_review_status_uses_first_standalone_nested_new_must_fix(tmp_path):
    review_dir = tmp_path / "first_standalone_nested_new_must_fix"
    _write_review_pair(
        review_dir,
        {
            "verdict": "PASS",
            "confirmed_items": {"new_must_fix_issue_found": True},
        },
        {"must_fix_count": 0, "verdict": "confirmed"},
    )

    assert _review_status(review_dir)["passed"] is False


def test_review_status_uses_second_standalone_conclusion_changing_defect(tmp_path):
    review_dir = tmp_path / "second_standalone_conclusion_changing_defect"
    _write_review_pair(
        review_dir,
        {"must_fix_count": 0, "verdict": "PASS"},
        {"conclusion_changing_defect": True, "verdict": "confirmed"},
    )

    assert _review_status(review_dir)["passed"] is False


def test_review_status_uses_nested_new_must_fix_in_conclusion_schema(tmp_path):
    review_dir = tmp_path / "conclusion_nested_new_must_fix"
    _write_review_pair(
        review_dir,
        {"must_fix_count": 0, "verdict": "PASS"},
        {
            "conclusion": "confirmed",
            "confirmed_items": {"new_must_fix_issue_found": True},
        },
    )

    assert _review_status(review_dir)["passed"] is False


@pytest.mark.parametrize("value", ["true", 1, None])
def test_review_status_rejects_non_boolean_nested_new_must_fix(tmp_path, value):
    review_dir = tmp_path / f"invalid_nested_new_must_fix_{value}"
    _write_review_pair(
        review_dir,
        {"must_fix_count": 0, "verdict": "PASS"},
        {
            "conclusion": "confirmed",
            "confirmed_items": {"new_must_fix_issue_found": value},
        },
    )

    with pytest.raises(
        ValueError, match="invalid boolean confirmed_items.new_must_fix_issue_found"
    ):
        _review_status(review_dir)


def test_review_status_rejects_non_object_confirmed_items_in_count_schema(tmp_path):
    review_dir = tmp_path / "non_object_confirmed_items"
    _write_review_pair(
        review_dir,
        {"must_fix_count": 0, "verdict": "PASS"},
        {"must_fix_count": 0, "verdict": "confirmed", "confirmed_items": []},
    )

    with pytest.raises(ValueError, match="confirmed_items is not an object"):
        _review_status(review_dir)


@pytest.mark.parametrize(
    "directory_name",
    ["arbitrary_legacy_shape", "parameter_identification_validation_v01_reviews"],
)
def test_review_status_rejects_unbound_legacy_confirmed_items_list(
    tmp_path, directory_name
):
    review_dir = tmp_path / directory_name
    review_dir.mkdir()
    (review_dir / "independent_review.json").write_text(
        json.dumps({"required_code_fixes": 0, "verdict": "PASS"}),
        encoding="utf-8",
    )
    (review_dir / "independent_review_validation.json").write_text(
        json.dumps(
            {
                "review_verdict": "confirmed_with_one_wording_correction",
                "confirmed_items": [],
                "contradictions_to_the_limited_scientific_conclusion": 0,
            }
        ),
        encoding="utf-8",
    )

    with pytest.raises(ValueError, match="confirmed_items is not an object"):
        _review_status(review_dir)


def test_review_status_rejects_byte_identical_legacy_copy_outside_registered_path(
    tmp_path,
):
    source = (
        REPO_ROOT
        / "results"
        / "23_hbv_multilead_joint_uncertainty"
        / "parameter_identification_validation_v01_reviews"
    )
    copied = tmp_path / source.name
    copied.mkdir()
    for filename in ("independent_review.json", "independent_review_validation.json"):
        (copied / filename).write_bytes((source / filename).read_bytes())

    with pytest.raises(ValueError, match="confirmed_items is not an object"):
        _review_status(copied)


def test_direct_review_status_never_authorizes_legacy_list():
    relative = (
        "results/23_hbv_multilead_joint_uncertainty/"
        "parameter_identification_validation_v01_reviews"
    )

    with pytest.raises(ValueError, match="confirmed_items is not an object"):
        _review_status(REPO_ROOT / relative)


def test_review_status_rejects_spoofed_repo_root_for_byte_identical_legacy_copy(
    tmp_path,
):
    relative = (
        "results/23_hbv_multilead_joint_uncertainty/"
        "parameter_identification_validation_v01_reviews"
    )
    source = REPO_ROOT / relative
    fake_root = tmp_path / "fake_repo"
    copied = fake_root / relative
    copied.mkdir(parents=True)
    for filename in ("independent_review.json", "independent_review_validation.json"):
        (copied / filename).write_bytes((source / filename).read_bytes())

    with pytest.raises(TypeError, match="unexpected keyword argument"):
        _review_status(
            copied,
            repo_root=fake_root,
            registered_relative_path=relative,
        )


def test_run_rejects_external_copy_of_registered_config(tmp_path):
    canonical = (
        REPO_ROOT
        / "src"
        / "hbv_multilead_joint_uncertainty"
        / "configs"
        / "joint_method_synthetic_validation_synthesis_v11.json"
    )
    copied = tmp_path / canonical.name
    copied.write_bytes(canonical.read_bytes())
    output = tmp_path / "joint_method_synthetic_validation_synthesis_v11"

    with pytest.raises(ValueError, match="canonical registered synthesis config"):
        run(REPO_ROOT, copied, output)


@pytest.mark.parametrize("append_whitespace", [False, True])
def test_existing_output_does_not_bypass_registered_config_identity(
    tmp_path, append_whitespace
):
    canonical = (
        REPO_ROOT
        / "src"
        / "hbv_multilead_joint_uncertainty"
        / "configs"
        / "joint_method_synthetic_validation_synthesis_v11.json"
    )
    copied = tmp_path / canonical.name
    payload = canonical.read_bytes() + (b" " if append_whitespace else b"")
    copied.write_bytes(payload)
    existing = (
        REPO_ROOT
        / "results"
        / "23_hbv_multilead_joint_uncertainty"
        / "joint_method_synthetic_validation_synthesis_v11"
    )

    with pytest.raises(ValueError, match="canonical registered synthesis config"):
        run(REPO_ROOT, copied, existing)


def test_existing_output_does_not_bypass_source_derived_repo_root(tmp_path):
    canonical = (
        REPO_ROOT
        / "src"
        / "hbv_multilead_joint_uncertainty"
        / "configs"
        / "joint_method_synthetic_validation_synthesis_v11.json"
    )
    existing = (
        REPO_ROOT
        / "results"
        / "23_hbv_multilead_joint_uncertainty"
        / "joint_method_synthetic_validation_synthesis_v11"
    )

    with pytest.raises(ValueError, match="canonical registered synthesis config"):
        run(tmp_path / "fake_repo", canonical, existing)


def test_review_status_rejects_zero_count_hiding_conclusion_changing_defect(tmp_path):
    review_dir = tmp_path / "hidden_conclusion_changing_defect"
    _write_review_pair(
        review_dir,
        {
            "must_fix_count": 0,
            "conclusion_changing_defect": True,
            "verdict": "PASS",
        },
        {"must_fix_count": 0, "verdict": "confirmed"},
    )

    with pytest.raises(ValueError, match="conflicting first review fix fields"):
        _review_status(review_dir)


def test_review_status_rejects_zero_count_hiding_nested_new_must_fix(tmp_path):
    review_dir = tmp_path / "hidden_nested_new_must_fix"
    _write_review_pair(
        review_dir,
        {"must_fix_count": 0, "verdict": "PASS"},
        {
            "must_fix_count": 0,
            "verdict": "confirmed",
            "confirmed_items": {"new_must_fix_issue_found": True},
        },
    )

    with pytest.raises(ValueError, match="conflicting second review fix fields"):
        _review_status(review_dir)


def test_synthesis_separates_completed_validation_from_negative_scientific_result(tmp_path):
    config = (
        REPO_ROOT
        / "src"
        / "hbv_multilead_joint_uncertainty"
        / "configs"
        / "joint_method_synthetic_validation_synthesis_v11.json"
    )
    output = tmp_path / "joint_method_synthetic_validation_synthesis_v11"

    summary = run(REPO_ROOT, config, output)

    assert summary["status"] == "passed"
    assert summary["validation_goal_complete"] is True
    assert summary["numerical_chain_validated"] is True
    assert summary["joint_identification_supported"] is False
    assert summary["joint_added_value_supported"] is False
    assert summary["broad_scientific_claim_authorized"] is False
    assert summary["scientific_status"] == "HOLD"
    conditions = pd.read_csv(output / "final_conditions.csv")
    assert conditions["condition_id"].tolist() == [
        "fixed_07_days",
        "fixed_21_days",
        "fixed_45_days",
        "periodic_switch_07_days",
    ]
    claims = pd.read_csv(output / "claim_evidence.csv")
    assert set(claims["classification"]) == {"fact", "inference", "unknown"}
    assert {
        "other_observation_or_forcing_error",
        "post_projection_gaussian_model",
    }.issubset(set(claims["claim_id"]))
    for claim_id in ("joint_identification", "joint_forecast_added_value"):
        row = claims.loc[claims["claim_id"] == claim_id].iloc[0]
        assert row["status"] == "rejected_in_tested_conditions"
        assert "final_conditions.csv" in row["evidence_path"]
    components = json.loads((output / "component_summary.json").read_text(encoding="utf-8"))
    old_format_names = {
        "process_noise_identification_validation_v02_reviews",
        "model_probability_validation_v02_reviews",
        "state_interaction_validation_v02_reviews",
    }
    old_format_reviews = [
        value
        for value in components["reviews"]
        if Path(value["path"]).name in old_format_names
    ]
    assert len(old_format_reviews) == 3
    assert all(value["first_review_format"] == "must_fix_list" for value in old_format_reviews)
    assert all(value["second_review_format"] == "conclusion" for value in old_format_reviews)
    assert all(value["first_review_verdict"] is not None for value in old_format_reviews)
    assert all(value["second_review_verdict"] is not None for value in old_format_reviews)
    assert (output / "final_synthesis.md").is_file()
    resource = json.loads((output / "resource_preflight.json").read_text(encoding="utf-8"))
    assert resource["safe_to_run"] is True
    assert resource["execution_parallelism"] == 1
