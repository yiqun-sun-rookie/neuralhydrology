"""Create the calibration-only discharge source used before evaluation is unlocked."""

from __future__ import annotations

import json
import io
import os
import sys
from pathlib import Path

import pandas as pd


REPO_ROOT = Path(__file__).resolve().parents[3]
if str(REPO_ROOT / "src") not in sys.path:
    sys.path.insert(0, str(REPO_ROOT / "src"))

from hbv_multilead_joint_uncertainty.contracts import load_base_config  # noqa: E402
from hbv_multilead_joint_uncertainty.input_audit import load_discharge_period  # noqa: E402


def freeze_calibration_discharge(
    repo_root: Path,
    output: Path,
    metadata_output: Path,
) -> tuple[Path, Path]:
    root = Path(repo_root).resolve()
    output = Path(output).resolve()
    metadata_output = Path(metadata_output).resolve()
    config = load_base_config(root)
    config_root = root / "src" / "hbv_multilead_joint_uncertainty" / "configs"
    pilot = pd.read_csv(config_root / "pilot_six_basins.csv", dtype={"basin_id": str})
    formal = pd.read_csv(config_root / "formal_sixteen_basins_v01.csv", dtype={"gauge_id": str})
    basin_ids = [
        *pilot["basin_id"].str.zfill(8).tolist(),
        *formal["gauge_id"].str.zfill(8).tolist(),
    ]
    if len(basin_ids) != 22 or len(set(basin_ids)) != 22:
        raise ValueError("calibration discharge freeze requires twenty-two unique development and formal basins")
    if output.exists() or metadata_output.exists():
        raise FileExistsError("refusing to overwrite the frozen calibration discharge source")
    rows = []
    sources = {}
    for basin_id in basin_ids:
        observations, flags, provenance = load_discharge_period(
            root,
            basin_id,
            config,
            config["calibration_selection_start"],
            config["calibration_selection_end"],
        )
        if observations.isna().any() or flags.isna().any():
            raise ValueError(f"basin {basin_id} calibration discharge is incomplete")
        sources[basin_id] = provenance
        rows.extend(
            {
                "basin_id": basin_id,
                "date": date.strftime("%Y-%m-%d"),
                "streamflow_mm_day": format(float(value), ".17g"),
                "quality_flag": str(flags.loc[date]),
            }
            for date, value in observations.items()
        )
    table = pd.DataFrame(rows)
    temporary = output.with_name(f".{output.name}.{os.getpid()}.tmp")
    metadata_temporary = metadata_output.with_name(f".{metadata_output.name}.{os.getpid()}.tmp")
    try:
        table_buffer = io.StringIO(newline="")
        table.to_csv(table_buffer, index=False, lineterminator="\n")
        temporary.write_bytes(table_buffer.getvalue().encode("utf-8"))
        metadata_text = (
            json.dumps(
            {
                "artifact_type": "calibration_only_discharge_source",
                "basin_count": 22,
                "basins": basin_ids,
                "date_start": config["calibration_selection_start"],
                "date_end": config["calibration_selection_end"],
                "days_per_basin": 731,
                "evaluation_discharge_values_parsed": False,
                "extraction_rule": (
                    "outside the calibration interval only year, month, and day tokens are inspected; "
                    "discharge and quality fields are parsed only inside the calibration interval"
                ),
                "sources": sources,
            },
            indent=2,
            sort_keys=True,
        )
            + "\n"
        )
        metadata_temporary.write_bytes(metadata_text.replace("\n", "\r\n").encode("utf-8"))
        os.replace(temporary, output)
        os.replace(metadata_temporary, metadata_output)
    except Exception:
        temporary.unlink(missing_ok=True)
        metadata_temporary.unlink(missing_ok=True)
        raise
    return output, metadata_output


def main() -> None:
    config_root = REPO_ROOT / "src" / "hbv_multilead_joint_uncertainty" / "configs"
    output = config_root / "calibration_discharge_22_basins_v01.csv"
    metadata_output = config_root / "calibration_discharge_22_basins_v01.metadata.json"
    freeze_calibration_discharge(REPO_ROOT, output, metadata_output)


if __name__ == "__main__":
    main()
