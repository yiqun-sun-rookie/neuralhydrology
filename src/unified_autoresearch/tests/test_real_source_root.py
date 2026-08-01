import json
from pathlib import Path

import numpy as np
import pandas as pd
import pytest

from unified_autoresearch.data.packages import DEVELOPMENT_DATE_BOUNDS, FROZEN_DEVELOPMENT_SELECTION


MODULE_ROOT = Path(__file__).resolve().parents[1]
FROZEN_STATIC_TABLE = MODULE_ROOT.parent / "fair_benchmark" / "frozen" / "bundle" / "track0_statics.csv"
PROTOCOL_PATH = MODULE_ROOT / "protocols" / "development_v1.json"
SELECTION_PATH = MODULE_ROOT / "selection" / "development_basins_v1.json"
SEALED_START, SEALED_END = pd.Timestamp("1989-10-01"), pd.Timestamp("1999-09-30")
RAW_START, RAW_END = pd.Timestamp("1989-10-01"), pd.Timestamp("2008-09-30")
CUBIC_FEET_PER_SECOND_TO_MILLIMETRES = 28316846.592 * 86400 / 10**6

FIXTURE_AREAS = {
    "10259000": 22393821,
    "04045500": 1471570000,
    "12175500": 3576400000,
    "02300700": 118366000,
    "08190500": 3373520000,
    "02038850": 342650000,
    "11230500": 227150000,
    "06847900": 1442740000,
}


def _frozen_basins() -> list[str]:
    return list(FROZEN_DEVELOPMENT_SELECTION["basins"])


def _write_camels_tree(root: Path, *, start: pd.Timestamp = RAW_START, end: pd.Timestamp = RAW_END) -> Path:
    """Write a CAMELS-US layout whose raw span deliberately covers the sealed final evaluation."""
    dates = pd.date_range(start, end, freq="D")
    for basin_index, basin in enumerate(_frozen_basins()):
        huc = basin[:2]
        forcing_dir = root / "basin_mean_forcing" / "maurer" / huc
        flow_dir = root / "usgs_streamflow" / huc
        forcing_dir.mkdir(parents=True, exist_ok=True)
        flow_dir.mkdir(parents=True, exist_ok=True)

        offset = np.arange(len(dates), dtype=np.float64)
        forcing = pd.DataFrame(
            {
                "Year": dates.year,
                "Mnth": dates.month,
                "Day": dates.day,
                "Hr": 12,
                "Dayl(s)": 43200.0,
                "PRCP(mm/day)": offset % 17 + basin_index,
                "SRAD(W/m2)": offset % 23 + 100.0 + basin_index,
                "SWE(mm)": offset % 5,
                "Tmax(C)": offset % 29 + 10.0 + basin_index,
                "Tmin(C)": offset % 19 - 5.0 + basin_index,
                "Vp(Pa)": offset % 31 + 1000.0 + basin_index,
            }
        )
        forcing_path = forcing_dir / f"{basin}_lump_maurer_forcing_leap.txt"
        with forcing_path.open("w", encoding="utf-8", newline="\n") as stream:
            stream.write(f"{40.0 + basin_index:.4f}\n")
            stream.write(f"{100 + basin_index}\n")
            stream.write(f"{FIXTURE_AREAS[basin]}\n")
            forcing.to_csv(stream, sep=" ", index=False, lineterminator="\n")

        discharge = pd.DataFrame(
            {
                "basin": basin,
                "Year": dates.year,
                "Mnth": dates.month,
                "Day": dates.day,
                "QObs": offset % 41 + 1.0 + basin_index,
                "flag": "A",
            }
        )
        flow_path = flow_dir / f"{basin}_streamflow_qc.txt"
        discharge.to_csv(flow_path, sep=" ", index=False, header=False, lineterminator="\n")
    return root


def _build(tmp_path, camels_root, **overrides):
    from unified_autoresearch.data.real_source import build_development_source_root

    parameters = {
        "camels_root": camels_root,
        "static_table_path": FROZEN_STATIC_TABLE,
        "protocol_path": PROTOCOL_PATH,
        "selection_path": SELECTION_PATH,
        "output_root": tmp_path / "development_source",
    }
    parameters.update(overrides)
    return build_development_source_root(**parameters)


def test_real_source_builder_emits_only_the_development_window_and_drops_sealed_dates(tmp_path):
    camels_root = _write_camels_tree(tmp_path / "camels_us")
    output_root = tmp_path / "development_source"

    manifest = _build(tmp_path, camels_root)

    assert manifest["date_bounds"] == DEVELOPMENT_DATE_BOUNDS
    assert manifest["sealed_final_evaluation_present"] is False
    assert {path.name for path in output_root.iterdir()} == {
        "features.parquet",
        "targets.parquet",
        "static_attributes.json",
        "SOURCE_MANIFEST.json",
    }

    expected_days = (pd.Timestamp(DEVELOPMENT_DATE_BOUNDS[1]) - pd.Timestamp(DEVELOPMENT_DATE_BOUNDS[0])).days + 1
    for filename in ("features.parquet", "targets.parquet"):
        frame = pd.read_parquet(output_root / filename)
        dates = pd.to_datetime(frame["date"])
        assert len(frame) == expected_days * len(_frozen_basins())
        assert set(frame["basin"]) == set(_frozen_basins())
        assert dates.min() == pd.Timestamp(DEVELOPMENT_DATE_BOUNDS[0])
        assert dates.max() == pd.Timestamp(DEVELOPMENT_DATE_BOUNDS[1])
        assert not dates.between(SEALED_START, SEALED_END).any()


def test_real_source_root_is_accepted_by_the_development_package_builder(tmp_path):
    from unified_autoresearch.data.packages import build_development_packages

    camels_root = _write_camels_tree(tmp_path / "camels_us")
    output_root = tmp_path / "development_source"
    _build(tmp_path, camels_root)

    package_manifest = build_development_packages(
        source_root=output_root,
        source_manifest_path=output_root / "SOURCE_MANIFEST.json",
        protocol_path=PROTOCOL_PATH,
        selection_path=SELECTION_PATH,
        output_root=tmp_path / "packages",
    )

    assert package_manifest["protocols"] == ["forward", "reverse"]
    assert package_manifest["basins"] == _frozen_basins()


def test_real_source_builder_refuses_to_overwrite_an_existing_root(tmp_path):
    camels_root = _write_camels_tree(tmp_path / "camels_us")
    (tmp_path / "development_source").mkdir()

    with pytest.raises(FileExistsError):
        _build(tmp_path, camels_root)


def test_real_source_builder_rejects_drifted_basin_selection(tmp_path):
    camels_root = _write_camels_tree(tmp_path / "camels_us")
    drifted = tmp_path / "development_basins_drifted.json"
    selection = json.loads(SELECTION_PATH.read_text(encoding="utf-8"))
    selection["basins"] = sorted(selection["basins"])
    drifted.write_text(json.dumps(selection), encoding="utf-8")

    with pytest.raises(ValueError, match="frozen development basin selection mismatch"):
        _build(tmp_path, camels_root, selection_path=drifted)
    assert not (tmp_path / "development_source").exists()


def test_real_source_builder_rejects_a_static_table_that_is_not_the_frozen_table(tmp_path):
    camels_root = _write_camels_tree(tmp_path / "camels_us")
    tampered = tmp_path / "statics_tampered.csv"
    frame = pd.read_csv(FROZEN_STATIC_TABLE, dtype={"gauge_id": str})
    frame.loc[0, "p_mean"] = float(frame.loc[0, "p_mean"]) + 1.0
    frame.to_csv(tampered, index=False)

    with pytest.raises(ValueError, match="static attribute table hash does not match the frozen selection input"):
        _build(tmp_path, camels_root, static_table_path=tampered)
    assert not (tmp_path / "development_source").exists()


def test_real_source_builder_rejects_a_missing_day_inside_the_development_window(tmp_path):
    camels_root = _write_camels_tree(tmp_path / "camels_us")
    basin = _frozen_basins()[0]
    path = next(camels_root.rglob(f"{basin}_lump_maurer_forcing_leap.txt"))
    lines = path.read_text(encoding="utf-8").splitlines()
    header, body = lines[:4], lines[4:]
    kept = [line for line in body if line.split()[:3] != ["2003", "5", "4"]]
    assert len(kept) == len(body) - 1
    path.write_text("\n".join(header + kept) + "\n", encoding="utf-8")

    with pytest.raises(ValueError, match="development window requires a complete daily record"):
        _build(tmp_path, camels_root)
    assert not (tmp_path / "development_source").exists()


def test_real_source_builder_rejects_missing_discharge_inside_the_development_window(tmp_path):
    camels_root = _write_camels_tree(tmp_path / "camels_us")
    basin = _frozen_basins()[0]
    path = next(camels_root.rglob(f"{basin}_streamflow_qc.txt"))
    frame = pd.read_csv(path, sep=r"\s+", header=None, names=["basin", "Year", "Mnth", "Day", "QObs", "flag"])
    mask = (frame["Year"] == 2003) & (frame["Mnth"] == 5) & (frame["Day"] == 4)
    frame.loc[mask, "QObs"] = -999.0
    frame.to_csv(path, sep=" ", index=False, header=False, lineterminator="\n")

    with pytest.raises(ValueError, match="development window requires finite observed discharge"):
        _build(tmp_path, camels_root)
    assert not (tmp_path / "development_source").exists()


def test_real_source_builder_converts_discharge_to_millimetres_per_day_with_header_area(tmp_path):
    camels_root = _write_camels_tree(tmp_path / "camels_us")
    output_root = tmp_path / "development_source"
    _build(tmp_path, camels_root)

    basin = _frozen_basins()[0]
    targets = pd.read_parquet(output_root / "targets.parquet")
    targets = targets.loc[targets["basin"] == basin].copy()
    targets["date"] = pd.to_datetime(targets["date"])
    targets = targets.sort_values("date").reset_index(drop=True)

    raw = pd.read_csv(
        next(camels_root.rglob(f"{basin}_streamflow_qc.txt")),
        sep=r"\s+",
        header=None,
        names=["basin", "Year", "Mnth", "Day", "QObs", "flag"],
    )
    raw["date"] = pd.to_datetime(raw[["Year", "Mnth", "Day"]].rename(columns={"Year": "year", "Mnth": "month", "Day": "day"}))
    raw = raw.loc[raw["date"].between(*pd.to_datetime(DEVELOPMENT_DATE_BOUNDS))].sort_values("date").reset_index(drop=True)

    expected = raw["QObs"].to_numpy() * CUBIC_FEET_PER_SECOND_TO_MILLIMETRES / FIXTURE_AREAS[basin]
    np.testing.assert_allclose(targets["qobs"].to_numpy(), expected, rtol=0.0, atol=0.0)


def test_real_source_builder_writes_the_twenty_seven_frozen_static_attributes(tmp_path):
    from unified_autoresearch.selection.basins import APPROVED_STATIC_ATTRIBUTES

    camels_root = _write_camels_tree(tmp_path / "camels_us")
    output_root = tmp_path / "development_source"
    _build(tmp_path, camels_root)

    statics = json.loads((output_root / "static_attributes.json").read_text(encoding="utf-8"))
    assert statics["schema_version"] == "development_static_attributes_v1"
    assert set(statics["basins"]) == set(_frozen_basins())
    reference = pd.read_csv(FROZEN_STATIC_TABLE, dtype={"gauge_id": str}).set_index("gauge_id")
    for basin, values in statics["basins"].items():
        assert set(values) == set(APPROVED_STATIC_ATTRIBUTES)
        for name in APPROVED_STATIC_ATTRIBUTES:
            assert values[name] == pytest.approx(float(reference.loc[basin, name]), rel=0.0, abs=0.0)
