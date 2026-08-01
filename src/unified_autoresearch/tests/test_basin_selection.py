from pathlib import Path

import pandas as pd
import pytest


STATIC_COLUMNS = [
    "p_mean",
    "pet_mean",
    "aridity",
    "p_seasonality",
    "frac_snow",
    "high_prec_freq",
    "high_prec_dur",
    "low_prec_freq",
    "low_prec_dur",
    "elev_mean",
    "slope_mean",
    "area_gages2",
    "frac_forest",
    "lai_max",
    "lai_diff",
    "gvf_max",
    "gvf_diff",
    "soil_depth_pelletier",
    "soil_depth_statsgo",
    "soil_porosity",
    "soil_conductivity",
    "max_water_content",
    "sand_frac",
    "silt_frac",
    "clay_frac",
    "carbonate_rocks_frac",
    "geol_permeability",
]


def _write_inputs(tmp_path: Path, *, rows: int = 12) -> tuple[Path, Path]:
    table = []
    for row in range(rows):
        values = {name: float((row + 1) * (column + 2) % 17) for column, name in enumerate(STATIC_COLUMNS)}
        values["gauge_id"] = f"{1000000 + row:08d}"
        table.append(values)
    static_path = tmp_path / "statics.csv"
    pd.DataFrame(table).to_csv(static_path, index=False)
    basin_path = tmp_path / "basins.txt"
    basin_path.write_text("\n".join(row["gauge_id"] for row in table) + "\n", encoding="utf-8")
    return static_path, basin_path


def test_static_only_selection_is_deterministic_and_row_order_independent(tmp_path):
    from unified_autoresearch.selection.basins import select_development_basins

    static_path, basin_path = _write_inputs(tmp_path)
    first = select_development_basins(static_path, basin_path, count=8)

    shuffled = pd.read_csv(static_path, dtype={"gauge_id": str}).sample(frac=1.0, random_state=99)
    shuffled_path = tmp_path / "statics_shuffled.csv"
    shuffled.to_csv(shuffled_path, index=False)
    second = select_development_basins(shuffled_path, basin_path, count=8)

    assert first == second
    assert len(first) == 8
    assert len(set(first)) == 8
    assert all(len(basin) == 8 and basin.isdigit() for basin in first)


@pytest.mark.parametrize("forbidden", ["q_mean", "runoff_ratio", "baseflow_index", "model_nse"])
def test_selection_rejects_flow_or_model_result_columns(tmp_path, forbidden):
    from unified_autoresearch.selection.basins import select_development_basins

    static_path, basin_path = _write_inputs(tmp_path)
    frame = pd.read_csv(static_path, dtype={"gauge_id": str})
    frame[forbidden] = 1.0
    frame.to_csv(static_path, index=False)

    with pytest.raises(ValueError, match="exactly 27 approved static attributes"):
        select_development_basins(static_path, basin_path, count=8)


@pytest.mark.parametrize("replacement", ["q_mean", "model_nse"])
def test_selection_rejects_replacing_an_approved_attribute_with_forbidden_data(tmp_path, replacement):
    from unified_autoresearch.selection.basins import select_development_basins

    static_path, basin_path = _write_inputs(tmp_path)
    frame = pd.read_csv(static_path, dtype={"gauge_id": str})
    frame = frame.rename(columns={"p_mean": replacement})
    frame.to_csv(static_path, index=False)

    with pytest.raises(ValueError, match="exactly 27 approved static attributes"):
        select_development_basins(static_path, basin_path, count=8)


def test_freeze_selection_refuses_overwrite_and_records_input_hashes(tmp_path):
    from unified_autoresearch.selection.basins import freeze_selection

    static_path, basin_path = _write_inputs(tmp_path)
    output = tmp_path / "development_basins_v1.json"
    frozen = freeze_selection(static_path, basin_path, output, count=8)

    assert output.exists()
    assert frozen["selection_method"] == "deterministic_standardized_farthest_point_v1"
    assert len(frozen["basins"]) == 8
    assert len(frozen["static_sha256"]) == 64
    assert len(frozen["eligible_basins_sha256"]) == 64

    with pytest.raises(FileExistsError):
        freeze_selection(static_path, basin_path, output, count=8)
