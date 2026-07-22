"""Generate and seal the G2 spacing-multiplier candidate tables.

Reads the frozen three-candidate parameter table (basin 12143600), scales the
two equifinal candidates around the fixed trained center for every frozen
multiplier, hard-validates parameter bounds (rejecting, never truncating), and
seals one CSV per multiplier into g2_spacing_inputs_v01.
"""

from __future__ import annotations

import datetime as dt
import sys
from pathlib import Path

import pandas as pd

REPO_ROOT = Path(__file__).resolve().parents[3]
if str(REPO_ROOT / "src") not in sys.path:
    sys.path.insert(0, str(REPO_ROOT / "src"))

from hbv_multilead_joint_uncertainty.g2_curve_design import SPACING_MULTIPLIERS  # noqa: E402
from hbv_multilead_joint_uncertainty.g2_spacing_inputs import (  # noqa: E402
    CENTER_PARAMETER_ID,
    SCALED_PARAMETER_IDS,
    build_scaled_parameter_table,
)
from hbv_multilead_joint_uncertainty.scripts.run_candidate_likelihood_identifiability import (  # noqa: E402
    _checksums_for_directory,
    _environment,
    _json_write,
)
from hbv_multilead_joint_uncertainty.scripts.run_synthetic_truth_validation import (  # noqa: E402
    _sha256,
)
from hbv_multilead_joint_uncertainty.scripts.run_three_stage_switching_validation import (  # noqa: E402
    _replace_directory_with_retries,
)

SOURCE_CSV = (
    "results/23_hbv_multilead_joint_uncertainty/formal_contract_sixteen_v05/"
    "parameter_vectors.csv"
)
SOURCE_SHA256 = "f75d746e32f233f658676f8e15894cd7c3d5d415595f0839335d92caeb8ce46f"
SOURCE_BASIN_ID = "12143600"
OUTPUT_DIR = "results/23_hbv_multilead_joint_uncertainty/g2_spacing_inputs_v01"


def _multiplier_file_name(multiplier: float) -> str:
    return f"parameter_vectors_m{int(round(multiplier * 10.0)):02d}.csv"


def main() -> None:
    started_at = dt.datetime.now(dt.timezone.utc).isoformat()
    source_path = REPO_ROOT / SOURCE_CSV
    if _sha256(source_path) != SOURCE_SHA256:
        raise RuntimeError("frozen parameter table checksum mismatch")
    table = pd.read_csv(source_path, dtype={"basin_id": str, "parameter_id": str})
    expected_ids = (SCALED_PARAMETER_IDS[0], CENTER_PARAMETER_ID, SCALED_PARAMETER_IDS[1])
    base_rows = table.loc[
        (table["basin_id"].astype(str).str.zfill(8) == SOURCE_BASIN_ID.zfill(8))
        & (table["parameter_id"].isin(expected_ids))
    ]
    if len(base_rows) != 3:
        raise RuntimeError("expected exactly three frozen candidate rows")

    output = REPO_ROOT / OUTPUT_DIR
    staging = output.with_name(output.name + ".incomplete")
    if output.exists() or staging.exists():
        raise FileExistsError("refusing to overwrite existing evidence")
    staging.mkdir(parents=True, exist_ok=False)

    files = {}
    for multiplier in SPACING_MULTIPLIERS:
        scaled = build_scaled_parameter_table(base_rows, multiplier)
        name = _multiplier_file_name(multiplier)
        target = staging / name
        scaled.to_csv(target, index=False, lineterminator="\n")
        files[name] = {"multiplier": multiplier, "sha256": _sha256(target)}

    manifest = {
        "artifact": "g2_spacing_inputs_v01",
        "design_doc": "docs/plans/2026-07-22-g2-identification-time-curve-design.md",
        "source_csv": SOURCE_CSV,
        "source_sha256": SOURCE_SHA256,
        "source_basin_id": SOURCE_BASIN_ID,
        "rule": (
            "trained_center unchanged; equifinal candidates scaled as "
            "center + multiplier * (vector - center); any explicit v1 bound "
            "violation rejects the whole multiplier (no truncation)"
        ),
        "multipliers": list(SPACING_MULTIPLIERS),
        "files": files,
        "generated_at_utc": started_at,
    }
    _json_write(staging / "manifest.json", manifest)
    _json_write(staging / "environment.json", _environment(REPO_ROOT, started_at))
    _json_write(staging / "checksums.json", _checksums_for_directory(staging))
    _replace_directory_with_retries(staging, output)
    print(f"sealed {output} with {len(files)} multiplier tables")


if __name__ == "__main__":
    main()
