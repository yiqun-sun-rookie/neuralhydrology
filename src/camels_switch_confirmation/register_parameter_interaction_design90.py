"""Build the deterministic input tables for the parFC Design90 scale-up.

This module does not create the registered configuration and never starts an
experiment. It selects basins without reading parameter-switch outcomes and
writes only new, exclusive registration tables.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

import numpy as np
import pandas as pd


CELL_ORDER = (
    (1, False),
    (1, True),
    (2, False),
    (2, True),
    (3, False),
    (3, True),
)
EXPECTED_CELL_SIZES = (77, 100, 31, 146, 9, 168)
CELL_ALLOCATIONS = (16, 16, 16, 16, 9, 17)
WINDOW_START = "1989-10-01"
WINDOW_END = "1993-03-13"
WINDOW_DAYS = 1260
PARAMETER_TABLE = Path(
    "results/10_global_conceptual_model_benchmark/camels_us_531_repro_v01/"
    "summary/hbv_lite_cma_rising_local_full.csv"
)
PRECHECK_TABLE = Path(
    "results/23_camels_switch_confirmation/g1_precheck_v01/g1_precheck.csv"
)
LEGACY_PROBABILITY_ROOT = Path(
    "results/23_camels_switch_confirmation/"
    "g2_switch_confirmation_v01_noise_nd01_design531_q3e8_r1_s01_20260809_local/"
    "probs"
)
BASIN_TABLE = Path(
    "docs/plans/2026-08-10-camels-parfc-state-interaction-design90-basins-v01.csv"
)
COVERAGE_TABLE = Path(
    "docs/plans/2026-08-10-camels-parfc-state-interaction-design90-coverage-v01.csv"
)
RAW_INPUT_MANIFEST = Path(
    "docs/plans/2026-08-10-camels-parfc-state-interaction-design90-input-manifest-v01.csv"
)
LEGACY_REFERENCE_MANIFEST = Path(
    "docs/plans/2026-08-10-camels-parfc-state-interaction-design90-legacy-reference-v01.csv"
)


def sha256_file(path: str | Path) -> str:
    digest = hashlib.sha256()
    with Path(path).open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def _normalize_basin_ids(values: pd.Series, label: str) -> pd.Series:
    normalized = values.astype(str).str.strip().str.zfill(8)
    if not normalized.str.fullmatch(r"\d{8}").all():
        raise ValueError(f"{label} contains an invalid basin identifier")
    return normalized


def _required_columns(frame: pd.DataFrame, required: set[str], label: str) -> None:
    missing = sorted(required.difference(frame.columns))
    if missing:
        raise ValueError(f"{label} missing columns: {', '.join(missing)}")


def _interior_indices(cell_size: int, allocation: int) -> list[int]:
    if allocation == cell_size:
        return list(range(cell_size))
    indices = [
        int(round(k * (cell_size - 1) / (allocation + 1)))
        for k in range(1, allocation + 1)
    ]
    if (
        len(indices) != allocation
        or len(set(indices)) != allocation
        or min(indices) < 0
        or max(indices) >= cell_size
    ):
        raise ValueError("mechanical within-cell ranks are not unique and valid")
    return indices


def select_design90_basins(
    precheck_frame: pd.DataFrame,
    parameter_frame: pd.DataFrame,
) -> pd.DataFrame:
    """Select the registered 90 unique basins without outcome information."""
    precheck_required = {
        "basin_id",
        "run_status",
        "r_min",
        "fc_member2",
        "fc_clipped_any",
        "predicted_identifiable",
        "feasible_zero_clipping",
        "n_forcing_days",
    }
    parameter_required = {"basin_id", "state_SM"}
    _required_columns(precheck_frame, precheck_required, "precheck table")
    _required_columns(parameter_frame, parameter_required, "parameter table")

    precheck = precheck_frame.loc[:, sorted(precheck_required)].copy()
    parameters = parameter_frame.loc[:, sorted(parameter_required)].copy()
    precheck["basin_id"] = _normalize_basin_ids(
        precheck["basin_id"], "precheck table"
    )
    parameters["basin_id"] = _normalize_basin_ids(
        parameters["basin_id"], "parameter table"
    )
    if precheck["basin_id"].duplicated().any():
        raise ValueError("precheck table contains duplicate basins")
    if parameters["basin_id"].duplicated().any():
        raise ValueError("parameter table contains duplicate basins")
    if len(precheck) != 531 or not (precheck["run_status"] == "success").all():
        raise ValueError("selection requires exactly 531 successful precheck rows")

    merged = precheck.merge(
        parameters,
        on="basin_id",
        how="left",
        validate="one_to_one",
    )
    numeric_columns = ["r_min", "fc_member2", "state_SM", "n_forcing_days"]
    for column in numeric_columns:
        merged[column] = pd.to_numeric(merged[column], errors="coerce")
    if not np.isfinite(merged[numeric_columns].to_numpy(dtype=np.float64)).all():
        raise ValueError("selection inputs contain non-finite numeric values")
    if not (merged["n_forcing_days"].astype(int) == WINDOW_DAYS).all():
        raise ValueError("selection requires 1260 forcing days for every basin")
    if not merged["feasible_zero_clipping"].map(
        lambda value: value is True or str(value).lower() == "true"
    ).all():
        raise ValueError("selection requires zero-clipping-feasible precheck rows")

    merged = merged.sort_values(
        ["r_min", "basin_id"], kind="mergesort"
    ).reset_index(drop=True)
    merged["rmin_tertile"] = np.repeat([1, 2, 3], 177)
    merged["initial_half_capacity_overflow"] = (
        merged["state_SM"] > merged["fc_member2"]
    )

    selected_parts = []
    observed_cell_sizes = []
    for (tertile, overflow), expected_size, allocation in zip(
        CELL_ORDER,
        EXPECTED_CELL_SIZES,
        CELL_ALLOCATIONS,
    ):
        cell = merged[
            (merged["rmin_tertile"] == tertile)
            & (merged["initial_half_capacity_overflow"] == overflow)
        ].copy()
        cell = cell.sort_values(["r_min", "basin_id"], kind="mergesort")
        observed_cell_sizes.append(len(cell))
        if len(cell) != expected_size:
            raise ValueError(
                "registered selection cell sizes changed: "
                f"expected {EXPECTED_CELL_SIZES}, observed {tuple(observed_cell_sizes)}"
            )
        indices = _interior_indices(len(cell), allocation)
        chosen = cell.iloc[indices].copy()
        chosen["cell_size"] = len(cell)
        chosen["cell_allocation"] = allocation
        chosen["within_cell_index_zero_based"] = indices
        denominator = max(len(cell) - 1, 1)
        chosen["within_cell_rank_fraction"] = [
            index / denominator for index in indices
        ]
        selected_parts.append(chosen)

    selected = pd.concat(selected_parts, ignore_index=True)
    if len(selected) != 90 or selected["basin_id"].nunique() != 90:
        raise ValueError("registered selection did not produce 90 unique basins")
    columns = [
        "basin_id",
        "rmin_tertile",
        "initial_half_capacity_overflow",
        "cell_size",
        "cell_allocation",
        "within_cell_index_zero_based",
        "within_cell_rank_fraction",
        "r_min",
        "state_SM",
        "fc_member2",
        "fc_clipped_any",
        "predicted_identifiable",
        "feasible_zero_clipping",
        "n_forcing_days",
    ]
    return selected.loc[:, columns]


def write_csv_exclusive(frame: pd.DataFrame, target: str | Path) -> None:
    path = Path(target)
    if path.exists():
        raise FileExistsError(f"registered artifact already exists: {path}")
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("x", encoding="utf-8", newline="") as handle:
        frame.to_csv(handle, index=False, lineterminator="\n")


def _relative(repo_root: Path, path: Path) -> str:
    return path.relative_to(repo_root).as_posix()


def _exact_glob(root: Path, pattern: str, label: str) -> Path:
    matches = sorted(root.glob(pattern))
    if len(matches) != 1 or not matches[0].is_file():
        raise FileNotFoundError(
            f"expected exactly one {label} file for pattern {pattern}, got {len(matches)}"
        )
    return matches[0]


def _manifest_row(
    repo_root: Path,
    category: str,
    basin_id: str,
    path: Path,
) -> dict:
    return {
        "category": category,
        "basin_id": basin_id,
        "relative_path": _relative(repo_root, path),
        "bytes": path.stat().st_size,
        "sha256": sha256_file(path),
    }


def build_raw_input_manifest(repo_root: Path, basin_ids: list[str]) -> pd.DataFrame:
    rows = []
    for basin_id in basin_ids:
        forcing = _exact_glob(
            repo_root,
            f"data/camels_us/basin_mean_forcing/maurer/*/"
            f"{basin_id}_lump_maurer_forcing_leap.txt",
            "Maurer forcing",
        )
        streamflow = _exact_glob(
            repo_root,
            f"data/camels_us/usgs_streamflow/*/{basin_id}_streamflow_qc.txt",
            "United States Geological Survey streamflow",
        )
        rows.append(_manifest_row(repo_root, "maurer_forcing", basin_id, forcing))
        rows.append(_manifest_row(repo_root, "usgs_streamflow", basin_id, streamflow))
    shared = (
        (
            "camels_topography",
            repo_root / "data/camels_us/camels_attributes_v2.0/camels_topo.txt",
        ),
        ("forcing_loader_source", repo_root / "src/hydroagent/data_loading.py"),
        ("parameter_table", repo_root / PARAMETER_TABLE),
        ("g1_precheck_table", repo_root / PRECHECK_TABLE),
    )
    for category, path in shared:
        if not path.is_file():
            raise FileNotFoundError(f"registered shared input is missing: {path}")
        rows.append(_manifest_row(repo_root, category, "", path))
    frame = pd.DataFrame(rows)
    if len(frame) != 184 or frame["relative_path"].duplicated().any():
        raise ValueError("raw-input manifest must contain 184 unique paths")
    return frame


def build_legacy_reference_manifest(
    repo_root: Path,
    basin_ids: list[str],
) -> pd.DataFrame:
    rows = []
    for basin_id in basin_ids:
        for seed in (0, 1):
            path = repo_root / LEGACY_PROBABILITY_ROOT / f"{basin_id}_s{seed}.npz"
            if not path.is_file():
                raise FileNotFoundError(f"legacy Arm-A probability file is missing: {path}")
            rows.append(
                {
                    "basin_id": basin_id,
                    "seed": seed,
                    "relative_path": _relative(repo_root, path),
                    "bytes": path.stat().st_size,
                    "sha256": sha256_file(path),
                }
            )
    frame = pd.DataFrame(rows)
    if len(frame) != 180:
        raise ValueError("legacy reference manifest must contain 180 tasks")
    return frame


def build_coverage_table(repo_root: Path, basin_ids: list[str]) -> pd.DataFrame:
    from hydroagent.data_loading import load_camels_basin

    rows = []
    data_root = repo_root / "data/camels_us"
    for basin_id in basin_ids:
        forcing, _observations, _attributes = load_camels_basin(
            basin_id,
            data_root=data_root,
            start_date=WINDOW_START,
            end_date=WINDOW_END,
            forcing="maurer",
            pet_method="oudin",
            keep_obs_nan_days=True,
        )
        pet_column = "ep" if "ep" in forcing.columns else "pet"
        finite_prcp = bool(np.isfinite(forcing["prcp"].to_numpy()).all())
        finite_ep = bool(np.isfinite(forcing[pet_column].to_numpy()).all())
        finite_tmean = bool(
            "tmean" in forcing.columns
            and np.isfinite(forcing["tmean"].to_numpy()).all()
        )
        rows.append(
            {
                "basin_id": basin_id,
                "n_days": len(forcing),
                "first_date": str(pd.Timestamp(forcing.index[0]).date()),
                "last_date": str(pd.Timestamp(forcing.index[-1]).date()),
                "finite_prcp": finite_prcp,
                "finite_ep": finite_ep,
                "finite_tmean": finite_tmean,
                "all_required_forcing_finite": bool(
                    finite_prcp and finite_ep and finite_tmean
                ),
            }
        )
    frame = pd.DataFrame(rows)
    valid = (
        len(frame) == 90
        and (frame["n_days"] == WINDOW_DAYS).all()
        and (frame["first_date"] == WINDOW_START).all()
        and (frame["last_date"] == WINDOW_END).all()
        and frame["all_required_forcing_finite"].all()
    )
    if not valid:
        raise ValueError("forcing coverage failed the registered 1260-day contract")
    return frame


def generate_registration_tables(repo_root: str | Path) -> dict:
    root = Path(repo_root).resolve()
    targets = [
        root / BASIN_TABLE,
        root / COVERAGE_TABLE,
        root / RAW_INPUT_MANIFEST,
        root / LEGACY_REFERENCE_MANIFEST,
    ]
    existing = [str(path) for path in targets if path.exists()]
    if existing:
        raise FileExistsError(
            "registered artifact already exists: " + ", ".join(existing)
        )
    precheck = pd.read_csv(root / PRECHECK_TABLE, dtype={"basin_id": str})
    parameters = pd.read_csv(root / PARAMETER_TABLE, dtype={"basin_id": str})
    selected = select_design90_basins(precheck, parameters)
    basin_ids = selected["basin_id"].tolist()
    coverage = build_coverage_table(root, basin_ids)
    raw_manifest = build_raw_input_manifest(root, basin_ids)
    legacy_manifest = build_legacy_reference_manifest(root, basin_ids)
    frames = [selected, coverage, raw_manifest, legacy_manifest]
    for frame, target in zip(frames, targets):
        write_csv_exclusive(frame, target)
    return {
        "basin_count": len(selected),
        "cell_allocations": selected.groupby(
            ["rmin_tertile", "initial_half_capacity_overflow"], sort=True
        ).size().tolist(),
        "raw_input_manifest_rows": len(raw_manifest),
        "legacy_reference_rows": len(legacy_manifest),
        "artifacts": {
            _relative(root, path): sha256_file(path) for path in targets
        },
    }


def _parse_args(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo-root", default=str(Path(__file__).resolve().parents[2]))
    return parser.parse_args(argv)


def main(argv=None) -> int:
    arguments = _parse_args(argv)
    result = generate_registration_tables(arguments.repo_root)
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
