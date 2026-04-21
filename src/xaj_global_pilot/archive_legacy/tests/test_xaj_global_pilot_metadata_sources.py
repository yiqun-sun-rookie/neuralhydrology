from pathlib import Path

import pandas as pd

from src.xaj_global_pilot.metadata_sources import load_caravan_candidate_metadata


def test_load_caravan_candidate_metadata_reads_attributes_tree(tmp_path: Path):
    subdataset_dir = tmp_path / "attributes" / "camels"
    subdataset_dir.mkdir(parents=True)
    (subdataset_dir / "climate.csv").write_text(
        "\n".join(
            [
                "gauge_id,p_mean,pet_mean_ERA5_LAND,aridity_ERA5_LAND,frac_snow,seasonality_ERA5_LAND",
                "camels_01022500,3.0,2.0,0.7,0.1,0.2",
                "camels_02064000,4.0,3.0,1.2,0.3,0.4",
            ]
        ),
        encoding="utf-8",
    )
    (subdataset_dir / "physio.csv").write_text(
        "\n".join(
            [
                "gauge_id,area,for_pc_sse",
                "camels_01022500,100.0,0.5",
                "camels_02064000,200.0,0.7",
            ]
        ),
        encoding="utf-8",
    )

    candidates = load_caravan_candidate_metadata(tmp_path)

    assert list(candidates["basin_id"]) == ["camels_01022500", "camels_02064000"]
    assert "snow_fraction" in candidates.columns
    assert "aridity_index" in candidates.columns
    assert "dataset" in candidates.columns
    assert candidates.loc[0, "dataset"] == "caravan"
    assert candidates.loc[1, "region"] == "camels"
    assert candidates.loc[0, "pet_mean"] == 2.0
    assert candidates.loc[1, "seasonality_index"] == 0.4


def test_load_caravan_candidate_metadata_marks_missing_or_empty_timeseries_as_split_coverage_failure(tmp_path: Path,
                                                                                                   monkeypatch):
    subdataset_dir = tmp_path / "attributes" / "camels"
    subdataset_dir.mkdir(parents=True)
    (subdataset_dir / "climate.csv").write_text(
        "\n".join(
            [
                "gauge_id,p_mean,pet_mean_ERA5_LAND,aridity_ERA5_LAND,frac_snow,seasonality_ERA5_LAND",
                "camels_good,3.0,2.0,0.7,0.1,0.2",
                "camels_empty,4.0,3.0,1.2,0.3,0.4",
                "camels_missing,4.0,3.0,1.2,0.3,0.4",
            ]
        ),
        encoding="utf-8",
    )
    (subdataset_dir / "physio.csv").write_text(
        "\n".join(
            [
                "gauge_id,area,for_pc_sse",
                "camels_good,100.0,0.5",
                "camels_empty,200.0,0.7",
                "camels_missing,300.0,0.2",
            ]
        ),
        encoding="utf-8",
    )

    def fake_load_caravan_timeseries(*, data_dir, basin):
        if basin == "camels_good":
            idx = pd.date_range("1981-01-01", "2020-12-31", freq="D")
            return pd.DataFrame(
                {
                    "total_precipitation_sum": 1.0,
                    "potential_evaporation_sum_ERA5_LAND": 0.2,
                    "temperature_2m_mean": 3.0,
                    "streamflow": 0.5,
                },
                index=idx,
            )
        if basin == "camels_empty":
            idx = pd.date_range("1970-01-01", "1970-01-10", freq="D")
            return pd.DataFrame(
                {
                    "total_precipitation_sum": 1.0,
                    "potential_evaporation_sum_ERA5_LAND": 0.2,
                    "temperature_2m_mean": 3.0,
                    "streamflow": 0.5,
                },
                index=idx,
            )
        raise FileNotFoundError("missing timeseries")

    monkeypatch.setattr("src.xaj_global_pilot.metadata_sources.load_caravan_timeseries", fake_load_caravan_timeseries)

    candidates = load_caravan_candidate_metadata(tmp_path)

    assert list(candidates["split_coverage_ok"]) == [False, True, False]
