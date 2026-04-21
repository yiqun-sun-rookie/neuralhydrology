import pandas as pd

from src.xaj_global_pilot.selection import select_pilot_basins


def test_select_pilot_basins_returns_15_per_regime():
    rows = []
    for regime in ("snow-dominated", "humid", "semi-humid", "semi-arid/arid"):
        for idx in range(20):
            rows.append(
                {
                    "basin_id": f"{regime}-{idx}",
                    "regime": regime,
                    "region": f"region-{idx % 6}",
                    "continent": f"continent-{idx % 3}",
                    "area_km2": 100 + idx,
                    "seasonality_index": idx / 20,
                    "data_ok": True,
                    "selected_for_pilot": False,
                    "selection_note": "",
                }
            )
    registry = pd.DataFrame(rows)

    selected = select_pilot_basins(registry)

    assert len(selected) == 60
    assert selected.groupby("regime").size().to_dict() == {
        "snow-dominated": 15,
        "humid": 15,
        "semi-humid": 15,
        "semi-arid/arid": 15,
    }
