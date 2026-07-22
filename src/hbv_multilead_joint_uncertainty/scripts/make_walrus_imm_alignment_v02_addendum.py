"""Addendum evidence for walrus_imm_alignment_v02 (review remediation items 2-3).

Regenerates the deterministic G2 single-filter trajectories with the same
tested functions the sealed run used, and captures the promised step-level
diagnostic (prior, sigma points, derived gain) at the first divergence step
of filter 1. Writes a sealed sibling directory; the already-sealed v02
directory is not touched.
"""

from __future__ import annotations

import datetime as dt
import json
import sys
from pathlib import Path

import numpy as np

REPO_ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(REPO_ROOT / "src"))

from hbv_multilead_joint_uncertainty.scripts.run_candidate_likelihood_identifiability import (  # noqa: E402
    _checksums_for_directory,
    _environment,
    _json_write,
)
from hbv_multilead_joint_uncertainty.scripts.run_three_stage_switching_validation import (  # noqa: E402
    _replace_directory_with_retries,
)
from hbv_multilead_joint_uncertainty.scripts.run_walrus_imm_alignment import (  # noqa: E402
    _build_filter,
    _gate2_single_filters,
    _load_workspace,
    _make_transition,
    _sha256,
)

DIAGNOSTIC_FILTER = 0
DIAGNOSTIC_STEP_ONE_BASED = 20


def _step20_diagnostic(data: dict, expected_posterior: np.ndarray) -> dict:
    sub_filter = _build_filter(data, DIAGNOSTIC_FILTER)
    diagnostic = {}
    for index in range(1, DIAGNOSTIC_STEP_ONE_BASED - 1):
        sub_filter.transition = _make_transition(data, DIAGNOSTIC_FILTER, index - 1)
        sub_filter.predict()
        sub_filter.update(np.array([data["qobs"][index]]))
    index = DIAGNOSTIC_STEP_ONE_BASED - 1
    sub_filter.transition = _make_transition(data, DIAGNOSTIC_FILTER, index - 1)
    prior_state, prior_covariance = sub_filter.predict()
    sigmas = sub_filter.sigma_generator.sigma_points(prior_state, prior_covariance)
    result = sub_filter.update(np.array([data["qobs"][index]]))
    innovation = float(result.innovation[0])
    derived_gain = (result.posterior_state - result.prior_state) / innovation
    if not np.array_equal(result.posterior_state, expected_posterior):
        raise RuntimeError(
            "diagnostic posterior does not bitwise match the G2 trajectory row; "
            "warm-up window is misaligned"
        )
    reference_row = data["states_upd_filters"][DIAGNOSTIC_FILTER][index]
    diagnostic["filter_one_based"] = DIAGNOSTIC_FILTER + 1
    diagnostic["step_one_based"] = DIAGNOSTIC_STEP_ONE_BASED
    diagnostic["prior_state"] = prior_state.tolist()
    diagnostic["prior_covariance_diagonal"] = np.diag(prior_covariance).tolist()
    diagnostic["sigma_points_hq_column"] = sigmas[:, 2].tolist()
    diagnostic["sigma_points_hq_min"] = float(sigmas[:, 2].min())
    diagnostic["sigma_points_hq_crosses_zero"] = bool(sigmas[:, 2].min() < 0.0 < sigmas[:, 2].max())
    diagnostic["innovation"] = innovation
    diagnostic["innovation_variance"] = float(result.innovation_covariance[0, 0])
    diagnostic["derived_gain"] = derived_gain.tolist()
    diagnostic["posterior_state_python"] = result.posterior_state.tolist()
    diagnostic["posterior_state_matlab_reference"] = reference_row.tolist()
    diagnostic["posterior_abs_diff"] = np.abs(result.posterior_state - reference_row).tolist()
    return diagnostic


def main() -> None:
    started_at = dt.datetime.now(dt.timezone.utc).isoformat()
    config_path = REPO_ROOT / "src/hbv_multilead_joint_uncertainty/configs/walrus_imm_alignment_v02.json"
    config = json.loads(config_path.read_text(encoding="utf-8"))
    mat_path = Path(config["inputs"]["reference_mat"]["path"])
    actual_hash = _sha256(mat_path)
    if actual_hash != config["inputs"]["reference_mat"]["sha256"]:
        raise RuntimeError("reference mat hash mismatch")
    sealed_dir = REPO_ROOT / "results/23_hbv_multilead_joint_uncertainty/walrus_imm_alignment_v02"
    sealed_gate_results = json.loads((sealed_dir / "gate_results.json").read_text(encoding="utf-8"))

    output = REPO_ROOT / "results/23_hbv_multilead_joint_uncertainty/walrus_imm_alignment_v02_addendum_r1"
    incomplete = output.with_name(output.name + ".incomplete")
    if output.exists() or incomplete.exists():
        raise RuntimeError(f"output already exists: {output} or {incomplete}")

    data = _load_workspace(mat_path)
    gate2, trajectories = _gate2_single_filters(data, 1e-6)
    for regenerated, sealed in zip(gate2["per_filter"], sealed_gate_results["gate2"]["per_filter"]):
        if regenerated["first_exceed_step_one_based"] != sealed["first_exceed_step_one_based"]:
            raise RuntimeError(f"regenerated G2 disagrees with sealed run: {regenerated} vs {sealed}")
    diagnostic = _step20_diagnostic(
        data,
        expected_posterior=trajectories[DIAGNOSTIC_FILTER][DIAGNOSTIC_STEP_ONE_BASED - 1],
    )

    incomplete.mkdir(parents=True, exist_ok=False)
    np.savez_compressed(
        incomplete / "g2_python_trajectories.npz",
        python_updated_states=np.asarray(trajectories),
    )
    _json_write(incomplete / "g2_step20_filter1_diagnostic.json", diagnostic)
    _json_write(
        incomplete / "provenance.json",
        {
            "purpose": "review remediation items 2-3 for walrus_imm_alignment_v02",
            "supersedes": (
                "walrus_imm_alignment_v02_addendum: its g2_step20_filter1_diagnostic.json "
                "double-assimilated the diagnostic step (warm-up loop off-by-one) and its "
                "posterior comparison is misaligned; its g2_python_trajectories.npz is unaffected. "
                "r1 adds a bitwise invariant tying the diagnostic posterior to the G2 trajectory row."
            ),
            "regenerated_with": "same tested functions as the sealed run (deterministic)",
            "regeneration_consistency": "per-filter first_exceed identical to sealed gate_results.json",
            "reference_mat_sha256": actual_hash,
            "config_sha256": _sha256(config_path),
            "started_at": started_at,
            "ended_at": dt.datetime.now(dt.timezone.utc).isoformat(),
        },
    )
    _json_write(incomplete / "environment.json", _environment(REPO_ROOT, started_at))
    _json_write(incomplete / "checksums.json", _checksums_for_directory(incomplete))
    _replace_directory_with_retries(incomplete, output)
    print(json.dumps({"addendum": str(output), "g2_consistent_with_sealed": True}))


if __name__ == "__main__":
    main()
