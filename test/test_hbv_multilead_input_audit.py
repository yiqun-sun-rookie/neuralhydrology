import sys
from pathlib import Path

import numpy as np


REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT / "src"))

from hbv_multilead_joint_uncertainty.contracts import load_base_config  # noqa: E402
from hbv_multilead_joint_uncertainty.input_audit import (  # noqa: E402
    audit_basin_inputs,
    audit_evaluation_discharge,
    load_discharge_period,
    load_forcing_period,
    load_frozen_calibration_discharge,
)
from hbv_multilead_joint_uncertainty.basins import audit_temperature_pair  # noqa: E402
import hbv_multilead_joint_uncertainty.input_audit as input_audit_module  # noqa: E402
from hydroagent.data_loading import load_camels_basin  # noqa: E402
from hbv_multilead_joint_uncertainty.scripts.freeze_calibration_discharge import (  # noqa: E402
    freeze_calibration_discharge,
)


def test_valid_replacement_basin_has_complete_traceable_inputs_and_periods():
    audit = audit_basin_inputs(REPO_ROOT, "04015330", load_base_config(REPO_ROOT))

    assert audit["passed"] is True
    assert audit["periods"]["calibration_warmup_days"] == 365
    assert audit["periods"]["calibration_selection_days"] == 731
    assert audit["periods"]["evaluation_warmup_days"] == 365
    assert audit["periods"]["evaluation_days"] == 365
    assert audit["periods"]["common_forecast_origins"] == 358
    assert audit["temperature_quality"]["passed"] is True
    assert audit["area_relative_difference"] <= 0.05
    assert {row["variable_id"] for row in audit["variables"]} == {
        "precipitation",
        "mean_temperature",
        "potential_evapotranspiration",
        "streamflow",
    }
    assert all(len(row["source_sha256"]) == 64 for row in audit["variables"])
    assert audit["variables"][0]["future_availability"] == "historical_hindsight_only"
    assert audit["evaluation_discharge_values_parsed"] is False
    assert "complete_evaluation_discharge" not in audit["checks"]
    assert "evaluation_qc_flag_counts" not in audit
    streamflow = next(row for row in audit["variables"] if row["variable_id"] == "streamflow")
    assert streamflow["modeled_date_end"] == "2008-09-30"
    assert streamflow["source_sha256_scope"] == "entire frozen calibration-only twenty-two-basin table"
    assert len(audit["calibration_discharge_records"]) == 731


def test_contract_input_audit_never_opens_raw_streamflow(monkeypatch):
    def forbidden(*_args, **_kwargs):
        raise AssertionError("raw streamflow was opened before the contract was frozen")

    monkeypatch.setattr(input_audit_module, "load_discharge_period", forbidden)

    assert audit_basin_inputs(REPO_ROOT, "04015330", load_base_config(REPO_ROOT))["passed"] is True


def test_frozen_calibration_discharge_round_trips_every_binary_float_and_flag():
    config = load_base_config(REPO_ROOT)
    frozen, frozen_flags, _ = load_frozen_calibration_discharge(REPO_ROOT, "04015330", config)
    raw, raw_flags, _ = load_discharge_period(
        REPO_ROOT,
        "04015330",
        config,
        config["calibration_selection_start"],
        config["calibration_selection_end"],
    )

    assert np.array_equal(frozen.to_numpy(), raw.to_numpy())
    assert np.array_equal(frozen_flags.to_numpy(), raw_flags.to_numpy())


def test_model_forcing_exactly_matches_the_loader_used_to_train_center_parameters():
    config = load_base_config(REPO_ROOT)
    start = config["calibration_selection_start"]
    end = config["calibration_selection_end"]
    actual, _ = load_forcing_period(REPO_ROOT, "04015330", config, start, end)
    expected, _, _ = load_camels_basin(
        "04015330",
        data_root=REPO_ROOT / config["data_root"],
        start_date=start,
        end_date=end,
        forcing=config["parameter_source"]["forcing"],
        pet_method=config["parameter_source"]["pet_method"],
        keep_obs_nan_days=True,
    )

    assert actual.index.equals(expected.index)
    assert np.array_equal(
        actual[["prcp", "ep", "tmean"]].to_numpy(),
        expected[["prcp", "ep", "tmean"]].to_numpy(),
    )


def test_calibration_discharge_generator_reproduces_table_and_metadata_byte_for_byte(tmp_path):
    generated_table = tmp_path / "calibration_discharge_22_basins_v01.csv"
    generated_metadata = generated_table.with_suffix(".metadata.json")

    freeze_calibration_discharge(REPO_ROOT, generated_table, generated_metadata)

    frozen_root = REPO_ROOT / "src/hbv_multilead_joint_uncertainty/configs"
    assert generated_table.read_bytes() == (
        frozen_root / "calibration_discharge_22_basins_v01.csv"
    ).read_bytes()
    assert generated_metadata.read_bytes() == (
        frozen_root / "calibration_discharge_22_basins_v01.metadata.json"
    ).read_bytes()
    try:
        freeze_calibration_discharge(REPO_ROOT, generated_table, generated_metadata)
    except FileExistsError:
        pass
    else:
        raise AssertionError("calibration discharge generator overwrote frozen files")


def test_evaluation_discharge_audit_refuses_to_read_without_a_verified_contract(tmp_path):
    try:
        audit_evaluation_discharge(REPO_ROOT, "04015330", tmp_path / "missing_contract")
    except (FileNotFoundError, ValueError):
        pass
    else:
        raise AssertionError("evaluation discharge audit accepted a missing contract")


def test_confirmed_corrupt_maurer_basin_is_excluded_by_numeric_quality_evidence():
    config = load_base_config(REPO_ROOT)
    maurer, _ = load_forcing_period(
        REPO_ROOT,
        "04213075",
        config,
        config["evaluation_warmup_start"],
        config["calibration_selection_end"],
        forcing="maurer",
    )
    daymet, _ = load_forcing_period(
        REPO_ROOT,
        "04213075",
        config,
        config["evaluation_warmup_start"],
        config["calibration_selection_end"],
        forcing="daymet",
    )
    audit = audit_temperature_pair(maurer["tmean"], daymet["tmean"], config["input_quality"])

    assert audit["passed"] is False
    assert audit["minimum_maurer_temperature_c"] < -55.0
    assert abs(audit["mean_product_bias_c"]) > 50.0
    assert "minimum_maurer_temperature" in audit["failed_checks"]
