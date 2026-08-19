import sys
from pathlib import Path
from types import SimpleNamespace

import pandas as pd
import pytest


REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT / "src"))

import camels_switch_confirmation.registered_parameter_interaction as registered_runner  # noqa: E402
from camels_switch_confirmation.registered_parameter_interaction import (  # noqa: E402
    prepare_output_root,
    run_registered_parameter_design,
    write_arm_evidence,
)


def _g1_frame():
    return pd.DataFrame(
        {
            "basin_id": ["01022500"],
            "predicted_identifiable": [True],
            "r_min": [2.0],
            "nse_calibration_table": [0.8],
        }
    )


def _execution(status, records):
    failure = next(
        (record for record in records if record["run_status"] == "failed"),
        None,
    )
    return SimpleNamespace(
        records=records,
        execution_status=status,
        first_failure=failure,
        n_planned=2,
        n_submitted=len(records),
        n_cancelled_before_start=0,
        n_not_submitted_after_failure=max(0, 2 - len(records)),
        n_completed_after_stop=0,
    )


def test_prepare_output_root_refuses_existing_directory(tmp_path):
    output = tmp_path / "registered-output"
    output.mkdir()

    with pytest.raises(FileExistsError, match="output root already exists"):
        prepare_output_root(output)


def test_write_arm_evidence_handles_zero_success_records(tmp_path):
    arm_directory = tmp_path / "A"
    arm_directory.mkdir()
    records = [
        {
            "basin_id": "01022500",
            "seed": 0,
            "run_status": "failed",
            "error_message": "RuntimeError: boom",
            "arm_id": "A",
        }
    ]

    summary = write_arm_evidence(
        arm_directory=arm_directory,
        execution=_execution("failed_early", records),
        g1_frame=_g1_frame(),
        selected_seeds=(0, 1),
        metadata={"arm_id": "A"},
    )

    assert summary["scientific_aggregation_status"] == (
        "not_evaluated_incomplete_execution"
    )
    assert summary["basin_verdict_status"] == "not_evaluated_incomplete_execution"
    assert summary["n_success"] == 0
    assert summary["n_failed"] == 1
    verdicts = pd.read_csv(arm_directory / "g2_basin_verdicts.csv")
    assert list(verdicts.columns) == [
        "basin_id",
        "events_total",
        "events_passed",
        "verdict",
        "predicted_identifiable",
        "r_min",
        "nse_calibration_table",
    ]
    assert verdicts.empty


def test_write_arm_evidence_evaluates_only_complete_success(tmp_path):
    arm_directory = tmp_path / "C"
    arm_directory.mkdir()
    records = [
        {
            "basin_id": "01022500",
            "seed": seed,
            "run_status": "success",
            "error_message": "",
            "arm_id": "C",
            "n_events": 6,
            "n_events_passed": passed,
        }
        for seed, passed in ((0, 5), (1, 6))
    ]

    summary = write_arm_evidence(
        arm_directory=arm_directory,
        execution=_execution("complete", records),
        g1_frame=_g1_frame(),
        selected_seeds=(0, 1),
        metadata={"arm_id": "C"},
    )

    assert summary["scientific_aggregation_status"] == "evaluated_complete_design"
    assert summary["basin_verdict_status"] == "evaluated_two_design_seeds"
    verdicts = pd.read_csv(arm_directory / "g2_basin_verdicts.csv")
    assert verdicts.loc[0, "events_total"] == 12
    assert verdicts.loc[0, "events_passed"] == 11
    assert verdicts.loc[0, "verdict"] == "partial"


def test_registered_design_stops_before_later_arms_after_first_failure(
    tmp_path,
    monkeypatch,
):
    config_path = tmp_path / "config.json"
    config_path.write_text(
        """{
  "filter": {
    "q_scale": 3e-8,
    "q_structure": "lower_groundwater_state_only",
    "q_mode": "fixed",
    "q_state_multiplier": 1.0,
    "observation_variance_multiplier": 1.0
  },
  "seeds": {"design": [0, 1]},
  "inputs": {"parameter_table": "unused.csv", "g1_precheck_table": "unused.csv"}
}
""",
        encoding="utf-8",
    )
    output_root = tmp_path / "registered-output"
    arms = (
        {
            "arm_id": "A",
            "interaction_mode": "parameter_grouped",
            "parameter_state_mapping": "legacy_projection",
        },
        {
            "arm_id": "B",
            "interaction_mode": "full",
            "parameter_state_mapping": "legacy_projection",
        },
        {
            "arm_id": "C",
            "interaction_mode": "full",
            "parameter_state_mapping": "conservative_parfc",
        },
    )
    verified = SimpleNamespace(
        experiment_id="CAMELS_PARFC_STATE_INTERACTION_01_DESIGN12",
        configuration_status="registered_exploratory_design_not_validation_frozen",
        config_path=config_path,
        config_sha256="abc",
        basin_ids=("01022500",),
        data_root=tmp_path,
        output_root=output_root,
        arms=arms,
        registered_hashes={"config_sha256": "abc"},
        repo_root=tmp_path,
        configuration={
            "filter": {
                "q_scale": 3e-8,
                "q_structure": "lower_groundwater_state_only",
                "q_mode": "fixed",
                "q_state_multiplier": 1.0,
                "observation_variance_multiplier": 1.0,
            },
            "seeds": {"design": [0, 1]},
            "inputs": {
                "parameter_table": "unused.csv",
                "g1_precheck_table": "unused.csv",
            },
        },
    )
    monkeypatch.setattr(
        registered_runner,
        "verify_parameter_run_config",
        lambda *_args, **_kwargs: verified,
    )
    row = {"basin_id": "01022500", "sigma_obs": 0.1}
    monkeypatch.setattr(
        registered_runner,
        "_load_registered_rows",
        lambda *_args, **_kwargs: ([row], _g1_frame()),
    )
    failure_records = [
        {
            "task_index": 0,
            "basin_id": "01022500",
            "seed": 0,
            "arm_id": "A",
            "run_status": "failed",
            "error_message": "RuntimeError: boom",
        },
        {
            "task_index": 1,
            "basin_id": "01022500",
            "seed": 1,
            "arm_id": "A",
            "run_status": "not_submitted_after_failure",
            "error_message": "suppressed",
        },
    ]
    calls = []

    def fail_first_arm(**kwargs):
        calls.append(kwargs)
        return _execution("failed_early", failure_records)

    monkeypatch.setattr(registered_runner, "execute_fail_fast", fail_first_arm)

    summary = run_registered_parameter_design(config_path, "abc", workers=2)

    assert summary["execution_status"] == "failed_early"
    assert len(calls) == 1
    assert (output_root / "arms" / "A" / "g2_summary.json").is_file()
    assert not (output_root / "arms" / "B").exists()
    assert not (output_root / "arms" / "C").exists()
    assert (output_root / "runner_summary.json").is_file()


def test_registered_design_writes_root_failure_after_scheduler_exception(
    tmp_path,
    monkeypatch,
):
    config_path = tmp_path / "config.json"
    config_path.write_text("{}\n", encoding="utf-8")
    output_root = tmp_path / "registered-output"
    arms = (
        {
            "arm_id": "A",
            "interaction_mode": "parameter_grouped",
            "parameter_state_mapping": "legacy_projection",
        },
    )
    verified = SimpleNamespace(
        experiment_id="TEST",
        configuration_status="registered_exploratory_design_not_validation_frozen",
        config_path=config_path,
        config_sha256="abc",
        basin_ids=("01022500",),
        data_root=tmp_path,
        output_root=output_root,
        arms=arms,
        registered_hashes={"config_sha256": "abc"},
        repo_root=tmp_path,
        configuration={
            "filter": {
                "q_scale": 3e-8,
                "q_structure": "lower_groundwater_state_only",
                "q_mode": "fixed",
                "q_state_multiplier": 1.0,
                "observation_variance_multiplier": 1.0,
            },
            "seeds": {"design": [0, 1]},
            "inputs": {},
        },
    )
    monkeypatch.setattr(
        registered_runner,
        "verify_parameter_run_config",
        lambda *_args, **_kwargs: verified,
    )
    monkeypatch.setattr(
        registered_runner,
        "_load_registered_rows",
        lambda *_args, **_kwargs: (
            [{"basin_id": "01022500", "sigma_obs": 0.1}],
            _g1_frame(),
        ),
    )
    monkeypatch.setattr(
        registered_runner,
        "execute_fail_fast",
        lambda **_kwargs: (_ for _ in ()).throw(RuntimeError("pool creation failed")),
    )

    summary = run_registered_parameter_design(config_path, "abc", workers=2)

    assert summary["execution_status"] == "failed_early"
    assert summary["failure"]["error_type"] == "RuntimeError"
    assert "pool creation failed" in summary["failure"]["error_message"]
    persisted = pd.read_json(output_root / "runner_summary.json", typ="series")
    assert persisted["execution_status"] == "failed_early"
