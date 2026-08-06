"""Per-basin verification of a built development source root and its two protocol packages.

The verifier re-derives every claim from the raw archive and the frozen tables. It never
re-runs the builder, so a builder bug cannot hide behind itself.
"""

import json
import shutil
from pathlib import Path

import pandas as pd
import pytest

from unified_autoresearch.tests.test_scaleup_64_data_base import (
    FROZEN_STATIC_TABLE,
    PROTOCOL_PATH,
    SELECTION_64_PATH,
    build_packages,
    build_source,
    frozen_64_basins,
    synthetic_area,
    write_camels_tree,
)


SENSITIVE_BASINS = ("06847900", "08190500")


@pytest.fixture(scope="module")
def built(tmp_path_factory) -> dict:
    root = tmp_path_factory.mktemp("artifacts")
    camels_root = write_camels_tree(root / "camels_us", frozen_64_basins())
    source_root = root / "development_source"
    package_root = root / "packages"
    build_source(source_root, camels_root)
    build_packages(source_root, package_root)
    return {"root": root, "camels_root": camels_root, "source_root": source_root, "package_root": package_root}


def _verify(built: dict, **overrides) -> dict:
    from unified_autoresearch.data.verification import verify_development_artifacts

    parameters = {
        "source_root": built["source_root"],
        "package_root": built["package_root"],
        "camels_root": built["camels_root"],
        "static_table_path": FROZEN_STATIC_TABLE,
        "protocol_path": PROTOCOL_PATH,
        "selection_path": SELECTION_64_PATH,
    }
    parameters.update(overrides)
    return verify_development_artifacts(**parameters)


def _tampered_copy(built: dict, tmp_path: Path) -> dict:
    copy = {key: value for key, value in built.items()}
    for key in ("source_root", "package_root"):
        destination = tmp_path / Path(built[key]).name
        shutil.copytree(built[key], destination)
        copy[key] = destination
    return copy


def test_verification_of_a_clean_build_passes_every_basin(built):
    report = _verify(built)

    assert report["schema_version"] == "development_artifact_verification_v1"
    assert report["all_passed"] is True
    assert report["basin_count"] == 64
    assert set(report["basins"]) == set(frozen_64_basins())
    assert all(entry["passed"] for entry in report["basins"].values())
    assert report["failures"] == []


def test_verification_reports_zero_sealed_interval_rows_in_every_artifact(built):
    report = _verify(built)

    assert report["sealed_final_evaluation"] == ["1989-10-01", "1999-09-30"]
    assert report["sealed_interval_rows_total"] == 0
    for entry in report["basins"].values():
        assert entry["sealed_interval_rows"] == 0
    assert report["artifact_files_scanned"] >= 1 + 2 * (4 + 2)


def test_verification_confirms_the_unit_conversion_against_the_raw_archive_exactly(built):
    report = _verify(built)

    assert report["discharge_conversion"] == "28316846.592 * cfs * 86400 / (area_m2 * 10**6)"
    for basin_index, basin in enumerate(frozen_64_basins()):
        entry = report["basins"][basin]
        assert entry["header_area_m2"] == synthetic_area(basin_index)
        assert entry["discharge_max_absolute_error"] == 0.0


def test_verification_confirms_the_date_boundaries_and_complete_daily_record(built):
    report = _verify(built)

    expected_days = (pd.Timestamp("2008-09-30") - pd.Timestamp("1999-10-01")).days + 1
    for entry in report["basins"].values():
        assert entry["development_days"] == expected_days
        assert entry["date_bounds"] == ["1999-10-01", "2008-09-30"]
        assert entry["missing_days"] == 0
    assert report["protocol_windows"] == {
        "forward": {"train": ["1999-10-01", "2005-09-30"], "validation": ["2005-10-01", "2008-09-30"]},
        "reverse": {"train": ["2002-10-01", "2008-09-30"], "validation": ["1999-10-01", "2002-09-30"]},
    }
    for entry in report["basins"].values():
        for protocol_name in ("forward", "reverse"):
            windows = entry["protocol_days"][protocol_name]
            assert windows["train"] + windows["validation"] == expected_days


def test_verification_confirms_no_observed_discharge_reaches_any_prediction_package(built):
    report = _verify(built)

    assert report["prediction_packages_free_of_observed_discharge"] is True
    for entry in report["basins"].values():
        assert entry["prediction_rows_with_discharge"] == 0


def test_verification_confirms_twenty_seven_static_attributes_per_basin(built):
    report = _verify(built)

    for entry in report["basins"].values():
        assert entry["static_attribute_count"] == 27
        assert entry["static_attributes_missing"] == []
        assert entry["static_attributes_match_frozen_table"] is True


def test_verification_records_diagnostics_for_the_two_sensitive_basins(built):
    report = _verify(built)

    assert set(report["sensitive_basins"]) == set(SENSITIVE_BASINS)
    for basin in SENSITIVE_BASINS:
        diagnostics = report["basins"][basin]["diagnostics"]
        assert diagnostics["zero_flow_days"] >= 0
        assert diagnostics["validation_discharge_standard_deviation"]["forward"] >= 0.0
        assert diagnostics["validation_discharge_standard_deviation"]["reverse"] >= 0.0


def test_verification_ranks_the_diagnostic_extremes_instead_of_trusting_a_fixed_watchlist(built):
    """At sixty-four basins the two historically named basins are no longer the extremes."""
    report = _verify(built)
    extremes = report["diagnostic_extremes"]

    zero_flow = extremes["most_zero_flow_days"]
    lowest_spread = extremes["lowest_validation_discharge_standard_deviation"]
    assert len(zero_flow) == 5 and len(lowest_spread) == 5
    assert [entry["basin"] for entry in zero_flow] == sorted(
        (entry["basin"] for entry in zero_flow),
        key=lambda basin: (-report["basins"][basin]["diagnostics"]["zero_flow_days"], basin),
    )
    assert zero_flow[0]["zero_flow_days"] >= zero_flow[-1]["zero_flow_days"]
    assert lowest_spread[0]["standard_deviation"] <= lowest_spread[-1]["standard_deviation"]
    for entry in lowest_spread:
        diagnostics = report["basins"][entry["basin"]]["diagnostics"]["validation_discharge_standard_deviation"]
        assert entry["standard_deviation"] == pytest.approx(min(diagnostics.values()), rel=0.0, abs=0.0)


def test_verification_pins_every_artifact_file_by_hash(built):
    report = _verify(built)

    assert len(report["artifact_sha256"]) == report["artifact_files_scanned"]
    assert all(len(digest) == 64 for digest in report["artifact_sha256"].values())
    assert report["source_manifest_hashes_match"] is True
    assert report["package_manifest_hashes_match"] is True


def test_verification_fails_when_a_sealed_interval_row_is_injected(built, tmp_path):
    copy = _tampered_copy(built, tmp_path)
    path = copy["source_root"] / "features.parquet"
    frame = pd.read_parquet(path)
    frame.loc[0, "date"] = pd.Timestamp("1995-01-01")
    frame.to_parquet(path, index=False)

    report = _verify(copy)

    assert report["all_passed"] is False
    assert report["sealed_interval_rows_total"] == 1
    assert any("sealed" in failure for failure in report["failures"])


def test_verification_fails_when_the_discharge_unit_conversion_is_wrong(built, tmp_path):
    copy = _tampered_copy(built, tmp_path)
    path = copy["source_root"] / "targets.parquet"
    frame = pd.read_parquet(path)
    frame.loc[0, "qobs"] = float(frame.loc[0, "qobs"]) * 2.0
    frame.to_parquet(path, index=False)

    report = _verify(copy)

    assert report["all_passed"] is False
    tampered_basin = frame.loc[0, "basin"]
    assert report["basins"][tampered_basin]["discharge_max_absolute_error"] > 0.0
    assert report["basins"][tampered_basin]["passed"] is False


def test_verification_fails_when_observed_discharge_leaks_into_a_prediction_package(built, tmp_path):
    copy = _tampered_copy(built, tmp_path)
    path = copy["package_root"] / "forward" / "predict" / "predict_features.parquet"
    frame = pd.read_parquet(path)
    frame["qobs"] = 1.0
    frame.to_parquet(path, index=False)

    report = _verify(copy)

    assert report["all_passed"] is False
    assert report["prediction_packages_free_of_observed_discharge"] is False
    assert any("discharge" in failure for failure in report["failures"])


def test_verification_fails_when_a_static_attribute_is_dropped(built, tmp_path):
    copy = _tampered_copy(built, tmp_path)
    path = copy["source_root"] / "static_attributes.json"
    statics = json.loads(path.read_text(encoding="utf-8"))
    basin = frozen_64_basins()[0]
    dropped = sorted(statics["basins"][basin])[0]
    del statics["basins"][basin][dropped]
    path.write_text(json.dumps(statics, indent=2, sort_keys=True) + "\n", encoding="utf-8")

    report = _verify(copy)

    assert report["all_passed"] is False
    assert report["basins"][basin]["static_attribute_count"] == 26
    assert report["basins"][basin]["static_attributes_missing"] == [dropped]


def test_verification_fails_when_a_development_day_is_removed(built, tmp_path):
    copy = _tampered_copy(built, tmp_path)
    basin = frozen_64_basins()[0]
    for filename in ("features.parquet", "targets.parquet"):
        path = copy["source_root"] / filename
        frame = pd.read_parquet(path)
        drop = frame.index[(frame["basin"] == basin) & (pd.to_datetime(frame["date"]) == pd.Timestamp("2003-05-04"))]
        frame.drop(index=drop).to_parquet(path, index=False)

    report = _verify(copy)

    assert report["all_passed"] is False
    assert report["basins"][basin]["missing_days"] == 1
    assert report["basins"][basin]["passed"] is False


def test_verification_fails_when_an_artifact_no_longer_matches_its_manifest_hash(built, tmp_path):
    copy = _tampered_copy(built, tmp_path)
    path = copy["source_root"] / "targets.parquet"
    frame = pd.read_parquet(path)
    frame.to_parquet(path, index=False, compression="gzip")

    report = _verify(copy)

    assert report["all_passed"] is False
    assert report["source_manifest_hashes_match"] is False
