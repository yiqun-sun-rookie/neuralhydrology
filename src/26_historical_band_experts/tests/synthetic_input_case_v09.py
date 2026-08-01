import csv
import hashlib
from pathlib import Path

import numpy as np
import pandas as pd


def _sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _write_maurer(path: Path, offset: float) -> None:
    rows = [
        " 44.0\n",
        " 133.0\n",
        " 1000000\n",
        "Year Mnth Day Hr Dayl(s) PRCP(mm/day) SRAD(W/m2) SWE(mm) Tmax(C) Tmin(C) Vp(Pa)\n",
    ]
    for index, date in enumerate(pd.date_range("2000-01-01", "2000-01-05", freq="D")):
        temperature = offset + index + 1.0
        rows.append(
            f"{date.year} {date.month:02d} {date.day:02d} 12 100.0 "
            f"{offset + index + 0.5} {20 + offset + index} 0.0 "
            f"{temperature} {temperature} {300 + offset + index}\n"
        )
    path.write_text("".join(rows), encoding="utf-8")


def make_synthetic_input_case(tmp_path: Path) -> dict:
    from artifact_v09 import array_payload_sha256, canonical_sha256
    from data import STATIC_COLUMNS
    from formal_input_contract_v09 import DYNAMIC_COLUMNS_V09, FORMAL_V09_STATIC_COLUMNS
    from formal_input_sources_v09 import load_static_arrays_v09

    basins = ("00000001", "00000002", "00000003")
    data_root = tmp_path / "maurer"
    data_root.mkdir()
    sources = []
    for basin_index, basin in enumerate(basins):
        path = data_root / f"{basin}.txt"
        _write_maurer(path, float(basin_index))
        sources.append({"basin": basin, "relative_path": path.name, "sha256": _sha(path)})

    static_frame = pd.DataFrame({"gauge_id": basins})
    for column_index, column in enumerate(STATIC_COLUMNS):
        static_frame[column] = np.asarray([1.0, 3.0, 7.0]) + column_index
    static_path = tmp_path / "statics.csv"
    static_frame.to_csv(static_path, index=False)
    raw, normalized, _ = load_static_arrays_v09(
        static_path,
        expected_sha256=_sha(static_path),
        basins=basins,
    )

    target_dates = pd.date_range("2000-01-03", "2000-01-05", freq="D")
    target_path = tmp_path / "targets.csv"
    with target_path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.writer(handle, lineterminator="\n")
        writer.writerow(("basin", "date", "qobs"))
        for basin_index, basin in enumerate(basins):
            for date_index, date in enumerate(target_dates):
                writer.writerow((basin, date.strftime("%Y-%m-%d"), 1.0 + basin_index + date_index / 10))

    contract = {
        "schema": "synthetic_complete_input_contract_v1",
        "protocol_raw_sha256": "1" * 64,
        "protocol_canonical_sha256": "2" * 64,
        "basin_count": len(basins),
        "basins": list(basins),
        "forcing_period": ["2000-01-01", "2000-01-05"],
        "training_period": ["2000-01-03", "2000-01-05"],
        "evaluation_period": ["1999-01-01", "1999-12-31"],
        "forcing_shape": [len(basins), 5, 5],
        "target_shape": [len(basins), 3],
        "dynamic_columns": list(DYNAMIC_COLUMNS_V09),
        "static_columns": list(FORMAL_V09_STATIC_COLUMNS),
        "static_file_sha256": _sha(static_path),
        "static_raw_float64_sha256": array_payload_sha256(raw),
        "static_normalized_float32_sha256": array_payload_sha256(normalized),
        "target_bundle_sha256": _sha(target_path),
        "target_manifest_sha256": "3" * 64,
        "maurer_sources": sources,
    }
    contract["contract_sha256"] = canonical_sha256(contract)
    return {
        "contract": contract,
        "data_root": data_root,
        "static_path": static_path,
        "target_path": target_path,
        "source_tree": {
            "schema": "exact_source_tree_v1",
            "files": [],
            "tree_sha256": "4" * 64,
            "environment": {"mode": "synthetic_only"},
        },
        "resource_evidence": {"method": "synthetic_bound_v1", "evidence_sha256": "5" * 64},
        "authorization_consumption": {"status": "synthetic_only", "sha256": "6" * 64},
    }


def build_synthetic_case(tmp_path: Path) -> tuple[dict, Path]:
    from formal_input_v09 import build_synthetic_input_seal_v09

    case = make_synthetic_input_case(tmp_path)
    root = tmp_path / "input_seal"
    report = build_synthetic_input_seal_v09(
        **case,
        building_root=root,
        checkpoint=lambda: None,
    )
    assert report["status"] == "complete_input_audit_passed"
    return case, root
