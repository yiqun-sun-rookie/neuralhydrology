import pandas as pd

from src.xaj_global_pilot.config import MAX_BASINS_PER_REGION, REGIME_NAMES, REGIME_SAMPLE_SIZE


def select_pilot_basins(registry: pd.DataFrame) -> pd.DataFrame:
    selected_frames = []
    for regime in REGIME_NAMES:
        regime_df = registry[(registry["regime"] == regime) & (registry["data_ok"] == True)].copy()  # noqa: E712
        if len(regime_df) < REGIME_SAMPLE_SIZE:
            raise ValueError(f"Not enough eligible basins for regime '{regime}'")

        if "area_km2" not in regime_df.columns:
            regime_df["area_km2"] = 0.0
        if "seasonality_index" not in regime_df.columns:
            regime_df["seasonality_index"] = 0.0

        regime_df = regime_df.sort_values(
            by=["region", "continent", "area_km2", "seasonality_index", "basin_id"],
            kind="mergesort",
        )

        picks = []
        region_counts = {}
        for _, row in regime_df.iterrows():
            region = row.get("region", "unknown")
            if region_counts.get(region, 0) >= MAX_BASINS_PER_REGION:
                continue
            picks.append(row.to_dict())
            region_counts[region] = region_counts.get(region, 0) + 1
            if len(picks) == REGIME_SAMPLE_SIZE:
                break

        if len(picks) < REGIME_SAMPLE_SIZE:
            already_selected = {row["basin_id"] for row in picks}
            for _, row in regime_df.iterrows():
                if row["basin_id"] in already_selected:
                    continue
                picks.append(row.to_dict())
                if len(picks) == REGIME_SAMPLE_SIZE:
                    break

        selected_frames.append(pd.DataFrame(picks))

    selected = pd.concat(selected_frames, ignore_index=True)
    selected["selected_for_pilot"] = pd.Series([True] * len(selected), dtype=object)
    selected["selection_note"] = selected["selection_note"].replace("", "pilot selection")
    return selected
