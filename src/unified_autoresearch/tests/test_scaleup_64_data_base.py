"""The source and package builders must accept the frozen sixty-four-basin selection.

The gate stays exact: only a record that is itself frozen is accepted. A record that merely
reproduces from approved inputs, but was never frozen, is still refused.
"""

import json
from pathlib import Path

import numpy as np
import pandas as pd
import pytest

from unified_autoresearch.data.packages import DEVELOPMENT_DATE_BOUNDS


MODULE_ROOT = Path(__file__).resolve().parents[1]
REPO_ROOT = MODULE_ROOT.parents[1]
FROZEN_STATIC_TABLE = MODULE_ROOT.parent / "fair_benchmark" / "frozen" / "bundle" / "track0_statics.csv"
ELIGIBLE_BASIN_LIST = REPO_ROOT / "examples" / "06-Finetuning" / "531_basin_list.txt"
PROTOCOL_PATH = MODULE_ROOT / "protocols" / "development_v1.json"
SELECTION_64_PATH = MODULE_ROOT / "selection" / "development_basins_64_v1.json"
SEALED_START, SEALED_END = pd.Timestamp("1989-10-01"), pd.Timestamp("1999-09-30")
RAW_START, RAW_END = pd.Timestamp("1989-10-01"), pd.Timestamp("2008-09-30")


def frozen_64_basins() -> list[str]:
    return list(json.loads(SELECTION_64_PATH.read_text(encoding="utf-8"))["basins"])


def synthetic_area(basin_index: int) -> int:
    """A distinct plausible catchment area per basin, so a swapped area changes the converted flow."""
    return 20_000_000 + basin_index * 37_000_000


def write_camels_tree(root: Path, basins: list[str], *, start: pd.Timestamp = RAW_START, end: pd.Timestamp = RAW_END) -> Path:
    """Write a CAMELS-US layout whose raw span deliberately covers the sealed final evaluation."""
    dates = pd.date_range(start, end, freq="D")
    offset = np.arange(len(dates), dtype=np.float64)
    for basin_index, basin in enumerate(basins):
        huc = basin[:2]
        forcing_dir = root / "basin_mean_forcing" / "maurer" / huc
        flow_dir = root / "usgs_streamflow" / huc
        forcing_dir.mkdir(parents=True, exist_ok=True)
        flow_dir.mkdir(parents=True, exist_ok=True)

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
        with (forcing_dir / f"{basin}_lump_maurer_forcing_leap.txt").open("w", encoding="utf-8", newline="\n") as stream:
            stream.write(f"{40.0 + basin_index:.4f}\n")
            stream.write(f"{100 + basin_index}\n")
            stream.write(f"{synthetic_area(basin_index)}\n")
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
        discharge.to_csv(flow_dir / f"{basin}_streamflow_qc.txt", sep=" ", index=False, header=False, lineterminator="\n")
    return root


def build_source(output_root: Path, camels_root: Path, selection_path: Path = SELECTION_64_PATH) -> dict:
    from unified_autoresearch.data.real_source import build_development_source_root

    return build_development_source_root(
        camels_root=camels_root,
        static_table_path=FROZEN_STATIC_TABLE,
        protocol_path=PROTOCOL_PATH,
        selection_path=selection_path,
        output_root=output_root,
    )


def build_packages(source_root: Path, output_root: Path, selection_path: Path = SELECTION_64_PATH) -> dict:
    from unified_autoresearch.data.packages import build_development_packages

    return build_development_packages(
        source_root=source_root,
        source_manifest_path=source_root / "SOURCE_MANIFEST.json",
        protocol_path=PROTOCOL_PATH,
        selection_path=selection_path,
        output_root=output_root,
    )


def test_source_builder_accepts_the_frozen_sixty_four_basin_selection(tmp_path):
    basins = frozen_64_basins()
    camels_root = write_camels_tree(tmp_path / "camels_us", basins)
    source_root = tmp_path / "development_source"

    manifest = build_source(source_root, camels_root)

    assert manifest["date_bounds"] == DEVELOPMENT_DATE_BOUNDS
    assert manifest["sealed_final_evaluation_present"] is False
    expected_days = (pd.Timestamp(DEVELOPMENT_DATE_BOUNDS[1]) - pd.Timestamp(DEVELOPMENT_DATE_BOUNDS[0])).days + 1
    for filename in ("features.parquet", "targets.parquet"):
        frame = pd.read_parquet(source_root / filename)
        dates = pd.to_datetime(frame["date"])
        assert set(frame["basin"]) == set(basins)
        assert len(frame) == expected_days * 64
        assert not dates.between(SEALED_START, SEALED_END).any()


def test_package_builder_accepts_the_frozen_sixty_four_basin_selection(tmp_path):
    basins = frozen_64_basins()
    camels_root = write_camels_tree(tmp_path / "camels_us", basins)
    source_root = tmp_path / "development_source"
    build_source(source_root, camels_root)

    manifest = build_packages(source_root, tmp_path / "packages")

    assert manifest["protocols"] == ["forward", "reverse"]
    assert manifest["basins"] == basins


def test_builders_still_reject_a_drifted_sixty_four_basin_record(tmp_path):
    basins = frozen_64_basins()
    camels_root = write_camels_tree(tmp_path / "camels_us", basins)
    drifted = tmp_path / "drifted.json"
    record = json.loads(SELECTION_64_PATH.read_text(encoding="utf-8"))
    record["basins"] = sorted(record["basins"])
    drifted.write_text(json.dumps(record), encoding="utf-8")

    with pytest.raises(ValueError, match="frozen development basin selection mismatch"):
        build_source(tmp_path / "development_source", camels_root, selection_path=drifted)
    assert not (tmp_path / "development_source").exists()


def test_builders_reject_a_reproducible_but_never_frozen_selection_size(tmp_path):
    """Sixteen basins recompute deterministically, yet were never frozen, so they stay refused."""
    from unified_autoresearch.selection.basins import freeze_selection

    unfrozen = tmp_path / "development_basins_16.json"
    freeze_selection(FROZEN_STATIC_TABLE, ELIGIBLE_BASIN_LIST, unfrozen, count=16)
    basins = json.loads(unfrozen.read_text(encoding="utf-8"))["basins"]
    camels_root = write_camels_tree(tmp_path / "camels_us", basins)

    with pytest.raises(ValueError, match="frozen development basin selection mismatch"):
        build_source(tmp_path / "development_source", camels_root, selection_path=unfrozen)
    assert not (tmp_path / "development_source").exists()


def test_source_builder_still_rejects_a_static_table_that_is_not_the_declared_one(tmp_path):
    from unified_autoresearch.data.real_source import build_development_source_root

    basins = frozen_64_basins()
    camels_root = write_camels_tree(tmp_path / "camels_us", basins)
    tampered = tmp_path / "statics_tampered.csv"
    frame = pd.read_csv(FROZEN_STATIC_TABLE, dtype={"gauge_id": str})
    frame.loc[0, "p_mean"] = float(frame.loc[0, "p_mean"]) + 1.0
    frame.to_csv(tampered, index=False)

    with pytest.raises(ValueError, match="static attribute table hash does not match the frozen selection input"):
        build_development_source_root(
            camels_root=camels_root,
            static_table_path=tampered,
            protocol_path=PROTOCOL_PATH,
            selection_path=SELECTION_64_PATH,
            output_root=tmp_path / "development_source",
        )
    assert not (tmp_path / "development_source").exists()
