"""Seal the candidate forecast paths behind the G3 forecast-weight-drift round.

The sealed drift evidence stores the combined forecasts but not the per-candidate
forecast paths, so the round's DEFINING operation

    frozen_forecast[lead] = final_assimilation_posterior . candidate_paths[lead, :]

could not be checked from the sealed arrays alone (independent-review finding).
This addendum reproduces the same truths deterministically, seals the
no-interaction candidate paths, and records three bit-for-bit identity checks:

  1. frozen combination identity   -- frozen forecast equals the frozen-weight
     combination of the stored candidate paths;
  2. drifting combination identity -- the drifting forecast equals the
     drifting-weight combination of the SAME paths, i.e. the two variants differ
     only in the weights;
  3. weight independence at production scale -- each candidate path equals an
     independent single-candidate run, which is what makes the no-interaction
     comparison an exact ablation of the drift.

It also re-checks the drift round's no-interaction and oracle forecasts against
the sealed phase-2 evidence. Nothing outside its own output directory is written.
"""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import sys
from pathlib import Path

import numpy as np

REPO_ROOT = Path(__file__).resolve().parents[3]
if str(REPO_ROOT / "src") not in sys.path:
    sys.path.insert(0, str(REPO_ROOT / "src"))

from hbv_multilead_joint_uncertainty.forecast_weight_drift import (  # noqa: E402
    assimilate_family_forecast_paths,
    frozen_weight_forecast,
)
from hbv_multilead_joint_uncertainty.methods import build_method_definitions  # noqa: E402
from hbv_multilead_joint_uncertainty.scripts.run_three_stage_switching_validation import (  # noqa: E402
    _environment,
    _forcing_blocks,
    _json_write,
    _load_observation_noise,
    _load_parameter_vectors,
    _load_process_covariances,
    _protected_hashes,
    _replace_directory_with_retries,
    _sha256,
    _validated_blocks,
)
from hbv_multilead_joint_uncertainty.three_stage_switching_validation import (  # noqa: E402
    _assimilate_record_then_forecast,
    run_three_stage_switching_validation,
)


def _max_absolute_difference(left, right) -> float:
    return float(np.max(np.abs(np.asarray(left) - np.asarray(right)), initial=0.0))


def run(repo_root: Path, config_path: Path, sealed_dir: Path, output_dir: Path) -> dict:
    root = repo_root.resolve()
    sealed = sealed_dir.resolve()
    output = output_dir.resolve()
    incomplete = output.with_name(output.name + ".incomplete")
    if output.exists() or incomplete.exists():
        raise FileExistsError("refusing to overwrite existing evidence")
    config_bytes = config_path.resolve().read_bytes()
    config_hash = hashlib.sha256(config_bytes).hexdigest()
    config = json.loads(config_bytes.decode("utf-8"))
    blocks = _validated_blocks(config)
    started_at = dt.datetime.now(dt.timezone.utc).isoformat()

    sealed_evidence_path = sealed / "evidence.npz"
    sealed_hash = _sha256(sealed_evidence_path)
    sealed_evidence = np.load(sealed_evidence_path, allow_pickle=False)
    protected_before = _protected_hashes(root, config.get("protected_paths", ()))

    parameter_vectors, _, parameter_hash = _load_parameter_vectors(root, config)
    process_covariances, process_scales, _, process_hash = _load_process_covariances(root, config)
    observation_std, _, observation_hash = _load_observation_noise(root, config)
    forcing = _forcing_blocks(config, blocks)
    stay = float(config["factor_transition_stay_probability"])
    selected_process = str(config["process_noise_source"]["selected_process_id"])
    definitions = build_method_definitions(
        parameter_vectors, process_scales, process_covariances, selected_process
    )
    result = run_three_stage_switching_validation(
        forcing_blocks=forcing,
        block_ids=tuple(str(value["block_id"]) for value in blocks),
        parameter_vectors=parameter_vectors,
        process_scales=process_scales,
        process_covariances=process_covariances,
        selected_process_id=selected_process,
        scenario=str(config["scenario"]),
        process_noise_seeds=tuple(int(value["process_noise_seed"]) for value in blocks),
        observation_noise_seeds=tuple(int(value["observation_noise_seed"]) for value in blocks),
        warmup_days=int(config["forcing"]["warmup_days"]),
        stage_lengths=tuple(int(value) for value in config["stage_lengths"]),
        lead_days=tuple(int(value) for value in config["lead_days"]),
        initial_covariance_fraction=float(config["initial_covariance_fraction"]),
        observation_standard_deviation=observation_std,
        factor_transition_stay_probability=stay,
    )

    primary = result.schedule.primary_method_name
    candidates = tuple(definitions[primary])
    candidate_count = len(candidates)
    block_count = len(result.block_ids)
    truth_count = int(result.method_assimilation_probabilities.shape[1])
    assimilation_days = int(result.assimilation_days)
    leads = np.asarray(result.forecast_lead_days, dtype=np.int64)
    lead_count = len(leads)

    candidate_paths = np.empty(
        (block_count, truth_count, lead_count, candidate_count), dtype=np.float64
    )
    independent_paths = np.empty_like(candidate_paths)
    frozen_rebuilt = np.empty((block_count, truth_count, lead_count), dtype=np.float64)
    drifting_rebuilt = np.empty_like(frozen_rebuilt)

    for block in range(block_count):
        initial_states = {
            pid: result.initial_parameter_states[block, index]
            for index, pid in enumerate(result.parameter_ids)
        }
        active_forcing = result.forcing_blocks[block][int(result.warmup_days) :]
        covariance = result.initial_covariances[block]
        for truth in range(truth_count):
            observations = result.observed_discharge[block, truth]
            paths = assimilate_family_forecast_paths(
                candidates, initial_states, covariance, active_forcing, observations,
                assimilation_days, leads, observation_std, stay, "none",
            )
            candidate_paths[block, truth] = paths["candidate_predictions"]
            frozen_rebuilt[block, truth] = frozen_weight_forecast(
                paths["candidate_predictions"], paths["final_posterior_weights"]
            )
            for lead in range(lead_count):
                drifting_rebuilt[block, truth, lead] = float(
                    paths["forecast_weights"][lead] @ paths["candidate_predictions"][lead]
                )
            for index, candidate in enumerate(candidates):
                _, _, _, single = _assimilate_record_then_forecast(
                    candidates=(candidate,),
                    initial_states=initial_states,
                    covariance=covariance,
                    active_forcing=active_forcing,
                    observations=observations,
                    assimilation_days=assimilation_days,
                    leads=leads,
                    observation_standard_deviation=observation_std,
                    factor_transition_stay_probability=stay,
                )
                independent_paths[block, truth, :, index] = single.combined_predictions

    sealed_frozen = sealed_evidence["forecast_none_frozen"]
    sealed_drifting = sealed_evidence["forecast_none_drifting"]
    checks = {
        "frozen_combination_identity_bit_exact": bool(
            np.array_equal(frozen_rebuilt, sealed_frozen)
        ),
        "frozen_combination_identity_max_absolute_difference": _max_absolute_difference(
            frozen_rebuilt, sealed_frozen
        ),
        "drifting_combination_identity_bit_exact": bool(
            np.array_equal(drifting_rebuilt, sealed_drifting)
        ),
        "drifting_combination_identity_max_absolute_difference": _max_absolute_difference(
            drifting_rebuilt, sealed_drifting
        ),
        "candidate_paths_equal_independent_single_candidate_runs_bit_exact": bool(
            np.array_equal(candidate_paths, independent_paths)
        ),
        "candidate_paths_versus_independent_max_absolute_difference": _max_absolute_difference(
            candidate_paths, independent_paths
        ),
    }
    phase_two = config.get("phase_two_evidence_for_cross_check")
    if phase_two:
        phase_two_path = (root / str(phase_two["path"])).resolve()
        if _sha256(phase_two_path) != str(phase_two["sha256"]):
            raise ValueError("phase-2 evidence checksum mismatch")
        earlier = np.load(phase_two_path, allow_pickle=False)
        checks["drift_round_none_equals_phase_two_none_bit_exact"] = bool(
            np.array_equal(sealed_drifting, earlier["forecast_none"])
        )
        checks["drift_round_oracle_equals_phase_two_oracle_bit_exact"] = bool(
            np.array_equal(sealed_evidence["oracle_forecast"], earlier["forecast_oracle"])
        )

    all_bit_exact = all(value for key, value in checks.items() if key.endswith("bit_exact"))

    incomplete.mkdir(parents=True, exist_ok=False)
    (incomplete / "config_snapshot.json").write_bytes(config_bytes)
    _json_write(incomplete / "environment.json", _environment(root, started_at))
    np.savez_compressed(
        incomplete / "evidence.npz",
        leads=leads,
        block_ids=np.asarray(result.block_ids),
        candidate_paths_none=candidate_paths,
        independent_single_candidate_paths=independent_paths,
        frozen_rebuilt=frozen_rebuilt,
        drifting_rebuilt=drifting_rebuilt,
    )
    protected_after = _protected_hashes(root, config.get("protected_paths", ()))
    summary = {
        "purpose": "seal the no-interaction candidate forecast paths behind the drift round and verify the round's defining combination identities bit-for-bit",
        "sealed_drift_evidence_path": str(sealed_evidence_path.relative_to(root).as_posix()),
        "sealed_drift_evidence_sha256": sealed_hash,
        "config_sha256": config_hash,
        "parameter_snapshot_sha256": parameter_hash,
        "process_snapshot_sha256": process_hash,
        "observation_snapshot_sha256": observation_hash,
        "protected_artifacts_unchanged": protected_before == protected_after,
        "checks": checks,
        "all_bit_exact": bool(all_bit_exact),
    }
    _json_write(incomplete / "summary.json", summary)
    checksums = {
        path.relative_to(incomplete).as_posix(): _sha256(path)
        for path in sorted(incomplete.rglob("*"))
        if path.is_file() and path.name != "checksums.json"
    }
    _json_write(incomplete / "checksums.json", checksums)
    if not summary["protected_artifacts_unchanged"]:
        raise RuntimeError("protected artifacts changed during verification")
    _replace_directory_with_retries(incomplete, output)
    return summary


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo-root", type=Path, required=True)
    parser.add_argument("--config", type=Path, required=True)
    parser.add_argument("--sealed-dir", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    arguments = parser.parse_args()
    summary = run(arguments.repo_root, arguments.config, arguments.sealed_dir, arguments.output_dir)
    print(json.dumps(summary, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
