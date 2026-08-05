from __future__ import annotations

import argparse
import csv
import hashlib
import json
from pathlib import Path

import numpy as np
from PIL import Image


EXPECTED_STATE_HASH = "22f1b99ee0cf537e1aa7c9b414662c0b390510f2dc0d6b07bf538dd6dda33a04"
EXPECTED_TRUTH_HASH = "77f84d793f18a72972e5af5f2ac4ed767645471e37da31c612ab995ecf4bbf67"
IMAGE_NAMES = [
    "five_hydrologic_states_with_true_parameter_stages.png",
    "all_15_states_with_true_parameter_stages_trial_1.png",
    "all_15_states_with_true_parameter_stages_trial_2.png",
    "all_15_states_with_true_parameter_stages_trial_3.png",
]


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def maximum_absolute_difference(left: np.ndarray, right: np.ndarray) -> float:
    return float(np.max(np.abs(left.astype(np.float64) - right.astype(np.float64))))


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--state-evidence", type=Path, required=True)
    parser.add_argument("--truth-evidence", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    args = parser.parse_args()
    state_evidence = args.state_evidence.resolve()
    truth_evidence = args.truth_evidence.resolve()
    output_dir = args.output_dir.resolve()
    report_path = output_dir / "verification.json"
    if report_path.exists():
        raise FileExistsError(f"Refusing to overwrite {report_path}")

    checks: dict[str, object] = {}
    state_hash = sha256_file(state_evidence)
    truth_hash = sha256_file(truth_evidence)
    checks["state_evidence_hash_matches"] = state_hash == EXPECTED_STATE_HASH
    checks["truth_evidence_hash_matches"] = truth_hash == EXPECTED_TRUTH_HASH

    with np.load(state_evidence, allow_pickle=False) as state_source, np.load(truth_evidence, allow_pickle=False) as truth_source, np.load(output_dir / "plotted_data.npz", allow_pickle=False) as plotted:
        days = int(truth_source["assimilation_days"])
        open_loop_index = truth_source["method_names"].astype(str).tolist().index("open_loop")
        references = {
            "parameter_indices": truth_source["truth_parameter_indices"][:, :days],
            "truth_states": state_source["truth_states"][0],
            "full_interaction_states": state_source["global_posterior_states"][0, :, 0],
            "no_interaction_states": state_source["global_posterior_states"][0, :, 1],
            "open_loop_states": truth_source["method_assimilation_states"][0, :, open_loop_index, :days, :],
        }
        differences = {name: maximum_absolute_difference(plotted[name], reference) for name, reference in references.items()}
        checks["plotted_arrays_maximum_absolute_differences"] = differences
        checks["all_plotted_arrays_exactly_match_sources"] = all(value == 0.0 for value in differences.values())
        truth_alignment = maximum_absolute_difference(
            state_source["truth_states"], truth_source["truth_states"][:, :, :days, :]
        )
        checks["truth_files_alignment_maximum_absolute_difference"] = truth_alignment
        checks["truth_files_align_exactly"] = truth_alignment == 0.0
        switches = [
            (np.flatnonzero(row[1:] != row[:-1]) + 1).tolist()
            for row in plotted["parameter_indices"]
        ]
        checks["switch_indices_zero_based"] = switches
        checks["all_trials_switch_only_at_180_and_360"] = all(row == [180, 360] for row in switches)
        checks["state_count_is_15"] = plotted["truth_states"].shape[-1] == 15
        checks["assimilation_day_count_is_540"] = plotted["truth_states"].shape[-2] == 540
        checks["all_plotted_arrays_finite"] = all(np.all(np.isfinite(plotted[name])) for name in references)

    with (output_dir / "stage_schedule.csv").open("r", newline="", encoding="utf-8-sig") as handle:
        schedule_rows = list(csv.DictReader(handle))
    checks["stage_schedule_has_nine_rows"] = len(schedule_rows) == 9
    checks["every_stage_has_180_days"] = all(
        int(row["end_day"]) - int(row["start_day"]) + 1 == 180 for row in schedule_rows
    )

    image_details: dict[str, object] = {}
    for name in IMAGE_NAMES:
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
    checks["image_details"] = image_details
    checks["all_images_decode"] = len(image_details) == len(IMAGE_NAMES)

    boolean_checks = [value for value in checks.values() if isinstance(value, bool)]
    status = "pass" if boolean_checks and all(boolean_checks) else "fail"
    report = {
        "audit_id": "state_parameter_stage_overlay_20260801_v01",
        "status": status,
        "state_evidence": str(state_evidence),
        "state_evidence_sha256": state_hash,
        "truth_evidence": str(truth_evidence),
        "truth_evidence_sha256": truth_hash,
        "checks": checks,
    }
    with report_path.open("x", encoding="utf-8") as handle:
        json.dump(report, handle, ensure_ascii=False, indent=2)
        handle.write("\n")
    if status != "pass":
        raise SystemExit("Independent verification failed")


if __name__ == "__main__":
    main()
