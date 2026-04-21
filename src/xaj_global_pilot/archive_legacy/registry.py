import pandas as pd

from src.xaj_global_pilot.classification import classify_regime, qc_record


def build_basin_registry(candidates: pd.DataFrame) -> pd.DataFrame:
    registry = candidates.copy()
    if "selection_note" not in registry.columns:
        registry["selection_note"] = ""

    records = registry.to_dict(orient="records")
    registry["regime"] = [classify_regime(record) for record in records]
    registry["data_ok"] = pd.Series([bool(qc_record(record)) for record in records], dtype=object)
    registry["selected_for_pilot"] = pd.Series([False] * len(registry), dtype=object)
    registry["selection_note"] = registry["selection_note"].fillna("")
    return registry

