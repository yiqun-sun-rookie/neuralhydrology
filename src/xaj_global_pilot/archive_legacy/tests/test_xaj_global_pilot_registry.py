import pandas as pd

from src.xaj_global_pilot.registry import build_basin_registry


def test_build_basin_registry_adds_required_columns():
    candidates = pd.DataFrame(
        [
            {
                "basin_id": "0001",
                "region": "A",
                "snow_fraction": 0.0,
                "temp_coldest_quarter": 5.0,
                "cold_season_precip_fraction": 0.1,
                "aridity_index": 0.8,
                "missing_rate": 0.0,
                "human_impact_flag": False,
                "split_coverage_ok": True,
            }
        ]
    )

    registry = build_basin_registry(candidates)

    assert "regime" in registry.columns
    assert "data_ok" in registry.columns
    assert "selected_for_pilot" in registry.columns
    assert registry.loc[0, "regime"] == "humid"
    assert registry.loc[0, "data_ok"] is True


def test_build_basin_registry_marks_split_coverage_failures_as_data_not_ok():
    candidates = pd.DataFrame(
        [
            {
                "basin_id": "0001",
                "region": "A",
                "snow_fraction": 0.0,
                "temp_coldest_quarter": 5.0,
                "cold_season_precip_fraction": 0.1,
                "aridity_index": 0.8,
                "missing_rate": 0.0,
                "human_impact_flag": False,
                "split_coverage_ok": False,
            }
        ]
    )

    registry = build_basin_registry(candidates)

    assert registry.loc[0, "data_ok"] is False
