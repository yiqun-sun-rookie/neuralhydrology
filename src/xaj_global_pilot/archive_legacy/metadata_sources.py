from pathlib import Path

import pandas as pd

from neuralhydrology.datasetzoo.caravan import load_caravan_attributes, load_caravan_timeseries
from src.xaj_global_pilot.config import split_periods


def load_caravan_candidate_metadata(caravan_root: Path | str) -> pd.DataFrame:
    caravan_root = Path(caravan_root)
    attributes = load_caravan_attributes(caravan_root).reset_index()
    if "gauge_id" not in attributes.columns:
        raise ValueError("Caravan attributes must include a gauge_id index/column.")

    candidates = pd.DataFrame(
        {
            "basin_id": attributes["gauge_id"].astype(str),
            "dataset": "caravan",
            "region": attributes["gauge_id"].astype(str).str.split("_").str[0],
            "continent": "unknown",
            "area_km2": _pick_first(attributes, ["area", "area_gages2"], default=pd.NA),
            "forest_frac": _pick_first(attributes, ["for_pc_sse", "frac_forest"], default=pd.NA),
            "precip_mean": _pick_first(attributes, ["p_mean"], default=pd.NA),
            "pet_mean": _pick_first(attributes, ["pet_mean", "pet_mean_ERA5_LAND", "pet_mean_FAO_PM"], default=pd.NA),
            "aridity_index": _pick_first(attributes, ["aridity_ERA5_LAND", "aridity"], default=pd.NA),
            "snow_fraction": _pick_first(attributes, ["frac_snow"], default=0.0),
            "temp_coldest_quarter": _pick_first(attributes, ["temp_coldest_quarter"], default=pd.NA),
            "cold_season_precip_fraction": _pick_first(
                attributes,
                ["cold_season_precip_fraction"],
                default=0.0,
            ),
            "seasonality_index": _pick_first(
                attributes,
                ["p_seasonality", "seasonality_index", "seasonality_ERA5_LAND", "seasonality_FAO_PM"],
                default=pd.NA,
            ),
            "human_impact_flag": False,
            "missing_rate": 0.0,
            "split_coverage_ok": attributes["gauge_id"].astype(str).map(
                lambda basin_id: _has_required_split_coverage(caravan_root, basin_id)
            ),
            "selection_note": "",
        }
    )
    return candidates.sort_values("basin_id").reset_index(drop=True)


def _pick_first(df: pd.DataFrame, column_names: list[str], default):
    for column_name in column_names:
        if column_name in df.columns:
            return df[column_name]
    return default


def _has_required_split_coverage(caravan_root: Path, basin_id: str) -> bool:
    try:
        timeseries = load_caravan_timeseries(data_dir=caravan_root, basin=basin_id)
    except Exception:
        return False

    if "streamflow" not in timeseries.columns:
        return False

    aligned = timeseries.dropna(subset=["streamflow"])
    if aligned.empty:
        return False

    for start_date, end_date in split_periods().values():
        if aligned.loc[start_date:end_date].empty:
            return False
    return True
