"""Render a non-destructive visual readout from the independently verified evidence."""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
from datetime import datetime, timezone
from pathlib import Path
from uuid import uuid4

import matplotlib.image as matplotlib_image
import numpy as np


PROJECT_ROOT = Path(__file__).resolve().parents[3]
SRC_ROOT = PROJECT_ROOT / "src"
if str(SRC_ROOT) not in sys.path:
    sys.path.insert(0, str(SRC_ROOT))

from hbv_multilead_joint_uncertainty.truth_parameter_switch_state_response_plotting import (  # noqa: E402
    plot_initial_new_parameter_domain_projection,
    plot_per_state_standardized_response,
    plot_state_group_standardized_response,
)


EXPERIMENT_ID = "g3_truth_parameter_switch_state_response_causal_control_v01"
DEFAULT_RESULT = PROJECT_ROOT / "results/23_hbv_multilead_joint_uncertainty" / EXPERIMENT_ID
DEFAULT_OUTPUT = DEFAULT_RESULT.with_name(f"{EXPERIMENT_ID}_visual_readout_v01")
PLOTTING_SOURCE = PROJECT_ROOT / (
    "src/hbv_multilead_joint_uncertainty/truth_parameter_switch_state_response_plotting.py"
)


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def render(result_dir: Path, output_dir: Path) -> dict:
    result_dir = result_dir.resolve()
    output_dir = output_dir.resolve()
    if output_dir.exists():
        raise FileExistsError(f"visual readout directory already exists: {output_dir}")
    verification_path = result_dir / "independent_verification.json"
    verification = json.loads(verification_path.read_text(encoding="utf-8"))
    if verification.get("status") != "passed":
        raise ValueError("visual readout requires passed independent verification")
    evidence_path = result_dir / "evidence.npz"
    evidence_sha256 = _sha256(evidence_path)
    if evidence_sha256 != verification.get("evidence_sha256"):
        raise ValueError("verified evidence SHA-256 changed before visual rendering")
    required = (
        "lead_days",
        "state_names",
        "unique_transition_labels",
        "transition_state_root_mean_square_standardized_response",
        "state_group_names",
        "group_root_mean_square_standardized_response",
        "transition_group_root_mean_square_standardized_response",
        "initial_new_parameter_domain_projection_standardized_adjustments",
        "event_transition_labels",
    )
    with np.load(evidence_path, allow_pickle=False) as archive:
        values = {name: np.asarray(archive[name]).copy() for name in required}

    staging = output_dir.with_name(f"{output_dir.name}.incomplete.{uuid4().hex}")
    staging.mkdir(parents=True, exist_ok=False)
    plot_per_state_standardized_response(
        staging / "per_state_standardized_response.png",
        leads=values["lead_days"],
        state_names=values["state_names"],
        transition_labels=values["unique_transition_labels"],
        transition_state_response=values["transition_state_root_mean_square_standardized_response"],
    )
    plot_state_group_standardized_response(
        staging / "state_group_standardized_response.png",
        leads=values["lead_days"],
        group_names=values["state_group_names"],
        pooled_group_response=values["group_root_mean_square_standardized_response"],
        transition_labels=values["unique_transition_labels"],
        transition_group_response=values["transition_group_root_mean_square_standardized_response"],
    )
    plot_initial_new_parameter_domain_projection(
        staging / "initial_new_parameter_domain_projection.png",
        standardized_projection_adjustments=values[
            "initial_new_parameter_domain_projection_standardized_adjustments"
        ],
        state_names=values["state_names"],
        event_transition_labels=values["event_transition_labels"],
    )
    figure_names = (
        "per_state_standardized_response.png",
        "state_group_standardized_response.png",
        "initial_new_parameter_domain_projection.png",
    )
    for name in figure_names:
        image = matplotlib_image.imread(staging / name)
        if image.size == 0 or image.ndim not in (2, 3) or not np.all(np.isfinite(image)):
            raise ValueError(f"visual readout figure failed decoding: {name}")
    manifest = {
        "classification": "visual_readout_only",
        "created_utc": datetime.now(timezone.utc).isoformat(),
        "scientific_evidence_modified": False,
        "source_evidence": str(evidence_path),
        "source_evidence_sha256": evidence_sha256,
        "source_independent_verification": str(verification_path),
        "source_independent_verification_sha256": _sha256(verification_path),
        "plotting_source": str(PLOTTING_SOURCE),
        "plotting_source_sha256": _sha256(PLOTTING_SOURCE),
        "figure_sha256": {name: _sha256(staging / name) for name in figure_names},
    }
    (staging / "readout_manifest.json").write_text(
        json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    if output_dir.exists():
        raise FileExistsError(f"visual readout directory appeared during rendering: {output_dir}")
    staging.rename(output_dir)
    return {**manifest, "output_directory": str(output_dir)}


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--result-dir", type=Path, default=DEFAULT_RESULT)
    parser.add_argument("--output-dir", type=Path, default=DEFAULT_OUTPUT)
    args = parser.parse_args()
    print(json.dumps(render(args.result_dir, args.output_dir), indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
