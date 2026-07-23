"""Generate and seal the G3 ideal-experiment low observation-noise input.

The ideal-condition observation noise is anchored to the MATLAB favorable
regime (2.6% of the trained-center mean discharge for basin 12143600), a
principled level at which the reference WALRUS IMM demonstrably identifies.
Sealed as g3_ideal_inputs_v01 before any run.
"""

from __future__ import annotations

import datetime as dt
import sys
from pathlib import Path

import pandas as pd

REPO_ROOT = Path(__file__).resolve().parents[3]
if str(REPO_ROOT / "src") not in sys.path:
    sys.path.insert(0, str(REPO_ROOT / "src"))

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

PARAM_CSV = (
    "results/23_hbv_multilead_joint_uncertainty/formal_contract_sixteen_v05/"
    "parameter_vectors.csv"
)
PARAM_SHA256 = "f75d746e32f233f658676f8e15894cd7c3d5d415595f0839335d92caeb8ce46f"
BASIN_ID = "12143600"
MATLAB_FAVORABLE_RELATIVE_NOISE = 0.026
OUTPUT_DIR = "results/23_hbv_multilead_joint_uncertainty/g3_ideal_inputs_v01"


def main() -> None:
    started_at = dt.datetime.now(dt.timezone.utc).isoformat()
    param_path = REPO_ROOT / PARAM_CSV
    if _sha256(param_path) != PARAM_SHA256:
        raise RuntimeError("frozen parameter table checksum mismatch")
    table = pd.read_csv(param_path, dtype={"basin_id": str, "parameter_id": str})
    center = table[
        (table["basin_id"].astype(str).str.zfill(8) == BASIN_ID.zfill(8))
        & (table["parameter_id"] == "trained_center")
    ]
    if len(center) != 1:
        raise RuntimeError("expected exactly one trained_center row")
    mean_discharge = float(center.iloc[0]["development_mean_discharge_mm_day"])
    std = MATLAB_FAVORABLE_RELATIVE_NOISE * mean_discharge

    output = REPO_ROOT / OUTPUT_DIR
    staging = output.with_name(output.name + ".incomplete")
    if output.exists() or staging.exists():
        raise FileExistsError("refusing to overwrite existing evidence")
    staging.mkdir(parents=True, exist_ok=False)

    frame = pd.DataFrame(
        [
            {
                "basin_id": BASIN_ID,
                "standard_deviation_mm_day": std,
                "variance_mm2_day2": std * std,
                "meaning": (
                    "ideal-experiment low observation error anchored to the MATLAB "
                    "favorable regime (2.6% of trained-center mean discharge)"
                ),
            }
        ]
    )
    noise_csv = staging / "observation_noise_low.csv"
    frame.to_csv(noise_csv, index=False, lineterminator="\n")

    manifest = {
        "artifact": "g3_ideal_inputs_v01",
        "design_doc": "docs/plans/2026-07-23-g3-ideal-experiment-gate-design.md",
        "source_parameter_csv": PARAM_CSV,
        "source_parameter_sha256": PARAM_SHA256,
        "source_basin_id": BASIN_ID,
        "trained_center_mean_discharge_mm_day": mean_discharge,
        "matlab_favorable_relative_noise": MATLAB_FAVORABLE_RELATIVE_NOISE,
        "standard_deviation_mm_day": std,
        "rule": "std = 0.026 * trained_center_mean_discharge_mm_day (bitwise recomputable)",
        "files": {"observation_noise_low.csv": _sha256(noise_csv)},
        "generated_at_utc": started_at,
    }
    _json_write(staging / "manifest.json", manifest)
    _json_write(staging / "environment.json", _environment(REPO_ROOT, started_at))
    _json_write(staging / "checksums.json", _checksums_for_directory(staging))
    _replace_directory_with_retries(staging, output)
    print(f"sealed {output}: std={std:.10f} mm/day (2.6% of {mean_discharge:.6f})")


if __name__ == "__main__":
    main()
