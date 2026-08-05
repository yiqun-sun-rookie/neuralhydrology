from __future__ import annotations

import argparse
import csv
import hashlib
import json
from pathlib import Path

import numpy as np
from PIL import Image


EXPECTED_EVIDENCE_SHA256 = (
    "77f84d793f18a72972e5af5f2ac4ed767645471e37da31c612ab995ecf4bbf67"
)
EXPECTED_SWITCHES = [180, 360]
EXPECTED_IMAGE_NAMES = [
    "truth_parameter_switch_audit_all_trials.png",
    "truth_parameter_switch_audit_trial_1.png",
    "truth_parameter_switch_audit_trial_2.png",
    "truth_parameter_switch_audit_trial_3.png",
]


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--evidence", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    args = parser.parse_args()
    evidence = args.evidence.resolve()
    output_dir = args.output_dir.resolve()
    verification_path = output_dir / "verification.json"
    if verification_path.exists():
        raise FileExistsError(f"Refusing to overwrite {verification_path}")

    checks: dict[str, object] = {}
    evidence_hash = sha256_file(evidence)
    checks["source_evidence_sha256_matches"] = evidence_hash == EXPECTED_EVIDENCE_SHA256

    with np.load(evidence, allow_pickle=False) as source, np.load(output_dir / "plotted_data.npz", allow_pickle=False) as plotted:
        days = int(source["assimilation_days"])
        checks["assimilation_days_equal_540"] = days == 540
        checks["registered_block_matches"] = str(plotted["registered_block_id"]) == str(source["block_ids"][0])
        comparisons = {
            "parameter_indices": source["truth_parameter_indices"][:, :days],
            "process_indices": source["truth_process_indices"][:, :days],
            "truth_states": source["truth_states"][0, :, :days, :],
            "truth_discharge": source["truth_discharge"][0, :, :days],
            "observed_discharge": source["observed_discharge"][0, :, :days],
            "observation_standard_normals": source["observation_standard_normals"][0, :days],
        }
        max_differences: dict[str, float] = {}
        for name, reference in comparisons.items():
            candidate = plotted[name]
            max_difference = float(np.max(np.abs(candidate.astype(np.float64) - reference.astype(np.float64))))
            max_differences[name] = max_difference
        checks["plotted_arrays_exactly_match_source"] = all(value == 0.0 for value in max_differences.values())
        checks["plotted_array_max_absolute_differences"] = max_differences

        parameter_indices = plotted["parameter_indices"]
        switches = [
            (np.flatnonzero(row[1:] != row[:-1]) + 1).tolist()
            for row in parameter_indices
        ]
        checks["switches_exactly_180_and_360"] = all(row == EXPECTED_SWITCHES for row in switches)
        checks["switch_indices_zero_based"] = switches
        process_unique = [np.unique(row).tolist() for row in plotted["process_indices"]]
        checks["process_candidate_fixed"] = all(row == [2] for row in process_unique)
        checks["process_indices_by_trial"] = process_unique

        observation_std = float(source["observation_standard_deviation"])
        observation_residual = (
            source["observed_discharge"][:, :, :days]
            - source["truth_discharge"][:, :, :days]
            - observation_std * source["observation_standard_normals"][:, np.newaxis, :days]
        )
        maximum_observation_residual = float(np.max(np.abs(observation_residual)))
        checks["observation_equation_maximum_absolute_residual"] = maximum_observation_residual
        checks["observation_equation_passes_1e_minus_12"] = maximum_observation_residual <= 1.0e-12
        checks["all_truth_arrays_finite"] = bool(
            np.all(np.isfinite(source["truth_states"]))
            and np.all(np.isfinite(source["truth_discharge"]))
            and np.all(np.isfinite(source["observed_discharge"]))
        )

    with (output_dir / "stage_schedule.csv").open("r", newline="", encoding="utf-8") as handle:
        schedule_rows = list(csv.DictReader(handle))
    checks["stage_schedule_has_nine_rows"] = len(schedule_rows) == 9
    checks["all_stages_have_180_days"] = all(
        int(row["end_day"]) - int(row["start_day"]) + 1 == 180 for row in schedule_rows
    )
    checks["all_schedule_process_indices_equal_2"] = all(int(row["process_index"]) == 2 for row in schedule_rows)

    with (output_dir / "boundary_state_change_audit.csv").open("r", newline="", encoding="utf-8") as handle:
        boundary_rows = list(csv.DictReader(handle))
    checks["boundary_audit_has_90_rows"] = len(boundary_rows) == 3 * 2 * 15
    checks["boundary_audit_values_are_finite"] = all(
        np.isfinite(float(row["absolute_boundary_change"]))
        and np.isfinite(float(row["non_boundary_95th_percentile_absolute_change"]))
        for row in boundary_rows
    )

    image_details: dict[str, object] = {}
    for name in EXPECTED_IMAGE_NAMES:
        path = output_dir / name
        with Image.open(path) as image:
            image.verify()
        with Image.open(path) as image:
            image_details[name] = {
                "width": image.width,
                "height": image.height,
                "mode": image.mode,
                "sha256": sha256_file(path),
            }
    checks["all_images_decode_and_have_positive_dimensions"] = all(
        row["width"] > 0 and row["height"] > 0 for row in image_details.values()
    )
    checks["image_details"] = image_details

    boolean_checks = [value for value in checks.values() if isinstance(value, bool)]
    status = "pass" if boolean_checks and all(boolean_checks) else "fail"
    report = {
        "audit_id": "truth_parameter_switch_audit_20260801_v01",
        "status": status,
        "independent_verifier": str(Path(__file__).resolve()),
        "source_evidence": str(evidence),
        "source_evidence_sha256": evidence_hash,
        "checks": checks,
    }
    with verification_path.open("x", encoding="utf-8") as handle:
        json.dump(report, handle, indent=2, ensure_ascii=False)
        handle.write("\n")
    if status != "pass":
        raise SystemExit("Independent verification failed")


if __name__ == "__main__":
    main()
