"""Frozen paired analysis and gate-zero diagnostics for continuous history version 08."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
from typing import Mapping

import numpy as np
import pandas as pd
import torch

from bands_continuous_v08 import forcing_prefix
from data import DataPack, load_basin_ids, load_data_pack, normalize_pack
from metrics import per_basin_nse
from models_continuous_v08 import build_model_v08
from models_v03 import _append_statics
from train_continuous_v08 import (
    dynamic_batch_v08,
    split_target_indices_v08,
    validate_config_v08,
)
from train_v05 import _limited_balanced_indices, validate_frozen_file_hash


_REPO = Path(__file__).resolve().parents[2]


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _atomic_text(path: Path, content: str) -> None:
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(content, encoding="utf-8")
    os.replace(temporary, path)


def _atomic_frame(path: Path, frame: pd.DataFrame) -> None:
    temporary = path.with_suffix(path.suffix + ".tmp")
    frame.to_csv(temporary, index=False)
    os.replace(temporary, path)


def _bootstrap_median_ci(
    values: np.ndarray,
    resamples: int,
    seed: int,
) -> list[float]:
    values = np.asarray(values, dtype=np.float64)
    if values.ndim != 1 or values.size == 0 or not np.isfinite(values).all():
        raise ValueError("bootstrap values must be a finite nonempty vector")
    generator = np.random.default_rng(int(seed))
    medians = np.empty(int(resamples), dtype=np.float64)
    block = 10_000
    for start in range(0, int(resamples), block):
        count = min(block, int(resamples) - start)
        indices = generator.integers(0, len(values), size=(count, len(values)))
        medians[start:start + count] = np.median(values[indices], axis=1)
    lower, upper = np.quantile(medians, [0.025, 0.975])
    return [float(lower), float(upper)]


def evaluate_stage1_v08(
    paired: pd.DataFrame,
    gates: Mapping,
    bootstrap_resamples: int,
    bootstrap_seed: int,
) -> dict:
    """Apply all four preregistered seed-100 gates."""
    required = {"basin", "nse_classic", "nse_capacity", "nse_candidate"}
    if not required.issubset(paired.columns):
        raise ValueError(f"paired metrics must contain {sorted(required)}")
    numeric = paired[["nse_classic", "nse_capacity", "nse_candidate"]].to_numpy(
        dtype=np.float64
    )
    if not np.isfinite(numeric).all():
        raise ValueError("paired metrics must be finite")
    delta_classic = paired["nse_candidate"].to_numpy() - paired["nse_classic"].to_numpy()
    delta_capacity = (
        paired["nse_candidate"].to_numpy() - paired["nse_capacity"].to_numpy()
    )
    median_delta_classic = float(np.median(delta_classic))
    median_delta_capacity = float(np.median(delta_capacity))
    win_fraction = float(np.mean(delta_classic > 0))
    interval = _bootstrap_median_ci(
        delta_classic,
        int(bootstrap_resamples),
        int(bootstrap_seed),
    )
    criteria = {
        "median_delta_classic_at_least": median_delta_classic
        >= float(gates["median_delta_classic_at_least"]),
        "median_delta_capacity_above": median_delta_capacity
        > float(gates["median_delta_capacity_above"]),
        "win_fraction_classic_at_least": win_fraction
        >= float(gates["win_fraction_classic_at_least"]),
        "bootstrap_ci_lower_above": interval[0]
        > float(gates["bootstrap_ci_lower_above"]),
    }
    return {
        "passed": bool(all(criteria.values())),
        "criteria": criteria,
        "n_basins": int(len(paired)),
        "median_nse_classic": float(np.median(paired["nse_classic"])),
        "median_nse_capacity": float(np.median(paired["nse_capacity"])),
        "median_nse_candidate": float(np.median(paired["nse_candidate"])),
        "median_delta_classic": median_delta_classic,
        "median_delta_capacity": median_delta_capacity,
        "win_fraction_classic": win_fraction,
        "bootstrap_median_delta_ci95": interval,
        "bootstrap_resamples": int(bootstrap_resamples),
        "bootstrap_seed": int(bootstrap_seed),
    }


def assert_same_targets_v08(
    reference: pd.DataFrame,
    candidate: pd.DataFrame,
    label: str,
) -> None:
    keys = ["basin", "date"]
    if not reference[keys].reset_index(drop=True).equals(
        candidate[keys].reset_index(drop=True)
    ):
        raise ValueError(f"{label} prediction keys do not match")
    if not np.array_equal(
        reference["qobs"].to_numpy(),
        candidate["qobs"].to_numpy(),
    ):
        raise ValueError(f"{label} observations do not match")


def _load_predictions(path: Path, expected_rows: int) -> pd.DataFrame:
    frame = pd.read_csv(path, dtype={"basin": str})
    if list(frame.columns) != ["basin", "date", "qobs", "qsim"]:
        raise ValueError(f"unexpected prediction columns in {path}")
    if len(frame) != int(expected_rows):
        raise ValueError(f"prediction row count mismatch in {path}")
    if not np.isfinite(frame[["qobs", "qsim"]].to_numpy()).all():
        raise ValueError(f"non-finite prediction values in {path}")
    return frame.sort_values(["basin", "date"]).reset_index(drop=True)


def _validated_run_predictions(
    run_dir: Path,
    variant: str,
    seed: int,
    expected_rows: int,
) -> pd.DataFrame:
    manifest_path = run_dir / "manifest.json"
    if not manifest_path.exists():
        raise FileNotFoundError(manifest_path)
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    if manifest.get("status") != "complete":
        raise ValueError(f"run is not complete: {run_dir}")
    if manifest.get("variant") != variant or int(manifest.get("seed", -1)) != int(seed):
        raise ValueError(f"run identity mismatch: {run_dir}")
    access = manifest.get("data_access", {})
    if (
        access.get("raw_observed_discharge_reads") != 0
        or access.get("formal_evaluation_target_access") is not False
        or access.get("unused_previous_validation_target_uses") != 0
    ):
        raise ValueError(f"run data-access boundary mismatch: {run_dir}")
    for name, expected in manifest.get("artifacts", {}).items():
        if _sha256(run_dir / name) != expected:
            raise ValueError(f"artifact hash mismatch: {run_dir / name}")
    predictions = _load_predictions(run_dir / "predictions.csv", expected_rows)
    saved_metrics = pd.read_csv(
        run_dir / "per_basin_metrics.csv",
        dtype={"basin": str},
    )
    recomputed = per_basin_nse(predictions)
    pd.testing.assert_frame_equal(saved_metrics, recomputed, check_exact=True)
    return predictions


def _named_nse(predictions: pd.DataFrame, name: str) -> pd.DataFrame:
    return per_basin_nse(predictions).rename(columns={"nse": name})


def _paired_metrics(
    classic: pd.DataFrame,
    capacity: pd.DataFrame,
    candidate: pd.DataFrame,
) -> pd.DataFrame:
    assert_same_targets_v08(classic, capacity, "capacity")
    assert_same_targets_v08(classic, candidate, "candidate")
    paired = _named_nse(classic, "nse_classic")
    paired = paired.merge(
        _named_nse(capacity, "nse_capacity"),
        on="basin",
        validate="one_to_one",
    )
    paired = paired.merge(
        _named_nse(candidate, "nse_candidate"),
        on="basin",
        validate="one_to_one",
    )
    return paired.sort_values("basin").reset_index(drop=True)


def run_history_gate_diagnostic_v08(
    pack: DataPack,
    config: Mapping,
    seed: int,
    candidate_run_dir: str | Path,
    output_dir: str | Path,
    device: str,
) -> dict:
    """Evaluate normal and zero-gate predictions from one frozen candidate checkpoint."""
    validate_config_v08(config)
    if int(seed) != int(config["stage1_seed"]):
        raise ValueError("gate diagnostic uses the frozen stage-one seed")
    candidate_run_dir = Path(candidate_run_dir)
    output_dir = Path(output_dir)
    if output_dir.exists() and any(output_dir.iterdir()):
        raise FileExistsError(f"output directory is not empty: {output_dir}")
    output_dir.mkdir(parents=True, exist_ok=True)
    expected_rows = (
        int(config["expected_confirmation_predictions"])
        if config["mode"] == "pilot"
        else int(config["limit_confirmation_samples"])
    )
    saved_candidate = _validated_run_predictions(
        candidate_run_dir,
        "continuous_multiscale_history",
        seed,
        expected_rows,
    )
    checkpoint = torch.load(candidate_run_dir / "checkpoint.pt", map_location=device)
    if checkpoint.get("variant") != "continuous_multiscale_history":
        raise ValueError("candidate checkpoint identity mismatch")
    torch_device = torch.device(device)
    model = build_model_v08("continuous_multiscale_history", int(seed)).to(torch_device)
    model.load_state_dict(checkpoint["model_state_dict"])
    scaler = checkpoint["scaler"]
    normalized = normalize_pack(pack, scaler)
    forcing = torch.tensor(normalized.forcing, device=torch_device)
    prefix = forcing_prefix(forcing)
    statics = torch.tensor(normalized.statics, device=torch_device)
    confirmation_basins, confirmation_times = split_target_indices_v08(
        pack.dates,
        pack.discharge,
        "confirmation",
        config,
    )
    confirmation_basins, confirmation_times = _limited_balanced_indices(
        confirmation_basins,
        confirmation_times,
        int(config.get("limit_confirmation_samples", 0)),
    )
    model.eval()
    state_norms = None
    mode_frames = {}
    with torch.no_grad():
        for mode in config["diagnostic_modes"]:
            parts = []
            for start in range(
                0,
                len(confirmation_basins),
                int(config["confirmation_batch_size"]),
            ):
                basin_numpy = confirmation_basins[
                    start:start + int(config["confirmation_batch_size"])
                ]
                target_numpy = confirmation_times[
                    start:start + int(config["confirmation_batch_size"])
                ]
                basin_index = torch.tensor(basin_numpy, device=torch_device)
                target_index = torch.tensor(target_numpy, device=torch_device)
                dynamic = dynamic_batch_v08(
                    "continuous_multiscale_history",
                    forcing,
                    prefix,
                    basin_index,
                    target_index,
                )
                if state_norms is None:
                    _, (hidden, cell) = model.history_encoder(
                        _append_statics(dynamic["history"], statics[basin_index])
                    )
                    state_norms = {
                        "history_hidden_mean_l2": float(
                            hidden[-1].norm(dim=-1).mean().cpu()
                        ),
                        "history_cell_mean_l2": float(
                            cell[-1].norm(dim=-1).mean().cpu()
                        ),
                    }
                prediction = model(
                    dynamic,
                    statics[basin_index],
                    dropout_context=None,
                    history_mode=mode,
                ).prediction
                qsim = (
                    prediction.detach().cpu().numpy() * float(scaler["q_scale"])
                    + float(scaler["q_center"])
                )
                parts.append(pd.DataFrame({
                    "basin": [pack.basins[index] for index in basin_numpy],
                    "date": pack.dates[target_numpy].strftime("%Y-%m-%d"),
                    "qobs": pack.discharge[basin_numpy, target_numpy],
                    "qsim": qsim,
                }))
            frame = pd.concat(parts, ignore_index=True).sort_values(
                ["basin", "date"]
            ).reset_index(drop=True)
            _atomic_frame(output_dir / f"{mode}_predictions.csv", frame)
            reloaded = pd.read_csv(
                output_dir / f"{mode}_predictions.csv",
                dtype={"basin": str},
            )
            _atomic_frame(
                output_dir / f"{mode}_per_basin_metrics.csv",
                per_basin_nse(reloaded),
            )
            mode_frames[mode] = reloaded

    assert_same_targets_v08(saved_candidate, mode_frames["normal"], "normal diagnostic")
    if not np.array_equal(
        saved_candidate["qsim"].to_numpy(),
        mode_frames["normal"]["qsim"].to_numpy(),
    ):
        maximum = float(
            np.max(
                np.abs(
                    saved_candidate["qsim"].to_numpy()
                    - mode_frames["normal"]["qsim"].to_numpy()
                )
            )
        )
        raise ValueError(f"normal diagnostic does not reproduce candidate; max abs {maximum}")
    normal_metrics = per_basin_nse(mode_frames["normal"])
    zero_metrics = per_basin_nse(mode_frames["history_gates_zero"])
    paired = normal_metrics.merge(
        zero_metrics,
        on="basin",
        suffixes=("_normal", "_gates_zero"),
        validate="one_to_one",
    )
    training_diagnostics = json.loads(
        (candidate_run_dir / "training_diagnostics.json").read_text(encoding="utf-8")
    )
    summary = {
        "status": "complete",
        "seed": int(seed),
        "causal_attribution_allowed": False,
        "modes": list(config["diagnostic_modes"]),
        "n_confirmation_predictions_per_mode": int(expected_rows),
        "median_nse": {
            "normal": float(np.nanmedian(paired["nse_normal"])),
            "history_gates_zero": float(np.nanmedian(paired["nse_gates_zero"])),
        },
        "median_delta_gates_zero_minus_normal": float(
            np.nanmedian(paired["nse_gates_zero"] - paired["nse_normal"])
        ),
        "hidden_gate_norm": float(model.hidden_gate.detach().norm().cpu()),
        "cell_gate_norm": float(model.cell_gate.detach().norm().cpu()),
        "state_norms_first_batch": state_norms,
        "recent_parameter_l2_drift": training_diagnostics["recent_parameter_l2_drift"],
    }
    _atomic_text(output_dir / "summary.json", json.dumps(summary, indent=2, sort_keys=True))
    artifact_names = [
        f"{mode}_{suffix}"
        for mode in config["diagnostic_modes"]
        for suffix in ("predictions.csv", "per_basin_metrics.csv")
    ] + ["summary.json"]
    manifest = {
        "status": "complete",
        "experiment_id": config["experiment_id"],
        "experiment_family": config["experiment_family"],
        "seed": int(seed),
        "causal_attribution_allowed": False,
        "n_confirmation_predictions_per_mode": int(expected_rows),
        "data_access": {
            "raw_observed_discharge_reads": 0,
            "target_bundle_interface": True,
            "formal_evaluation_target_access": False,
            "unused_previous_validation_target_uses": 0,
            "earliest_forcing_date": str(pack.dates.min().date()),
        },
        "artifacts": {name: _sha256(output_dir / name) for name in artifact_names},
    }
    _atomic_text(output_dir / "manifest.json", json.dumps(manifest, indent=2, sort_keys=True))
    return manifest


def _ensemble_predictions(frames: list[pd.DataFrame]) -> pd.DataFrame:
    reference = frames[0]
    for index, frame in enumerate(frames[1:], start=1):
        assert_same_targets_v08(reference, frame, f"ensemble member {index}")
    values = np.mean(
        np.stack([frame["qsim"].to_numpy() for frame in frames], axis=0),
        axis=0,
    )
    result = reference[["basin", "date", "qobs"]].copy()
    result["qsim"] = values
    return result


def evaluate_multiseed_v08(
    seedwise: pd.DataFrame,
    ensemble: pd.DataFrame,
    gates: Mapping,
    bootstrap_resamples: int,
    bootstrap_seed: int,
) -> dict:
    seed_deltas = seedwise.assign(
        delta=seedwise["nse_candidate"] - seedwise["nse_classic"]
    ).groupby("seed")["delta"].median()
    stage = evaluate_stage1_v08(
        ensemble,
        gates,
        bootstrap_resamples,
        bootstrap_seed,
    )
    criteria = dict(stage["criteria"])
    criteria["positive_seed_count_at_least_two"] = int((seed_deltas > 0).sum()) >= 2
    return {
        **stage,
        "passed": bool(all(criteria.values())),
        "criteria": criteria,
        "positive_seed_count": int((seed_deltas > 0).sum()),
        "seed_median_deltas": {
            str(int(seed)): float(value) for seed, value in seed_deltas.items()
        },
    }


def _results_root(config: Mapping) -> Path:
    root = Path(str(config["results_root"]))
    return root if root.is_absolute() else _REPO / root


def analyze_results_v08(config: Mapping) -> dict:
    """Validate frozen runs, apply gates, and persist the staged decision."""
    validate_config_v08(config)
    root = _results_root(config)
    root.mkdir(parents=True, exist_ok=True)
    seed = int(config["stage1_seed"])
    expected_rows = (
        int(config["expected_confirmation_predictions"])
        if config["mode"] == "pilot"
        else int(config["limit_confirmation_samples"])
    )
    stage1 = {
        variant: root / f"{variant}_s{seed}"
        for variant in config["variants"]
    }
    missing = [str(path) for path in stage1.values() if not (path / "manifest.json").exists()]
    if missing:
        summary = {"status": "incomplete_stage1", "missing": missing}
        _atomic_text(root / "summary.json", json.dumps(summary, indent=2, sort_keys=True))
        return summary
    predictions = {
        variant: _validated_run_predictions(path, variant, seed, expected_rows)
        for variant, path in stage1.items()
    }
    paired = _paired_metrics(
        predictions["classic_lstm_256_keyed"],
        predictions["classic_lstm_369_keyed"],
        predictions["continuous_multiscale_history"],
    )
    if config["mode"] == "pilot" and len(paired) != 60:
        raise ValueError(f"pilot paired basin count must be 60, got {len(paired)}")
    _atomic_frame(root / f"paired_per_basin_s{seed}.csv", paired)
    stage_result = evaluate_stage1_v08(
        paired,
        config["stage1_gates"],
        int(config["bootstrap_resamples"]),
        int(config["bootstrap_seed"]),
    )
    diagnostic_path = root / f"history_gate_diagnostic_s{seed}" / "summary.json"
    diagnostic = (
        json.loads(diagnostic_path.read_text(encoding="utf-8"))
        if diagnostic_path.exists()
        else None
    )
    if not stage_result["passed"]:
        summary = {
            "status": "complete_stage1_no_go",
            "experiment_id": config["experiment_id"],
            "stage1": stage_result,
            "history_gate_diagnostic": diagnostic,
            "conditional_seeds_authorized": False,
            "formal_evaluation_target_access": False,
        }
    else:
        conditional = [int(value) for value in config["conditional_seeds"]]
        conditional_dirs = [
            root / f"{variant}_s{conditional_seed}"
            for conditional_seed in conditional
            for variant in config["variants"]
        ]
        if not all((path / "manifest.json").exists() for path in conditional_dirs):
            summary = {
                "status": "complete_stage1_go_pending_multiseed",
                "experiment_id": config["experiment_id"],
                "stage1": stage_result,
                "history_gate_diagnostic": diagnostic,
                "conditional_seeds_authorized": True,
                "formal_evaluation_target_access": False,
            }
        else:
            all_seeds = [seed] + conditional
            by_seed: dict[int, dict[str, pd.DataFrame]] = {}
            seedwise_parts = []
            for current_seed in all_seeds:
                by_seed[current_seed] = {
                    variant: _validated_run_predictions(
                        root / f"{variant}_s{current_seed}",
                        variant,
                        current_seed,
                        expected_rows,
                    )
                    for variant in config["variants"]
                }
                current = _paired_metrics(
                    by_seed[current_seed]["classic_lstm_256_keyed"],
                    by_seed[current_seed]["classic_lstm_369_keyed"],
                    by_seed[current_seed]["continuous_multiscale_history"],
                )
                current.insert(0, "seed", current_seed)
                seedwise_parts.append(current)
            seedwise = pd.concat(seedwise_parts, ignore_index=True)
            ensemble_predictions = {
                variant: _ensemble_predictions(
                    [by_seed[current_seed][variant] for current_seed in all_seeds]
                )
                for variant in config["variants"]
            }
            ensemble = _paired_metrics(
                ensemble_predictions["classic_lstm_256_keyed"],
                ensemble_predictions["classic_lstm_369_keyed"],
                ensemble_predictions["continuous_multiscale_history"],
            )
            multiseed = evaluate_multiseed_v08(
                seedwise,
                ensemble,
                config["stage1_gates"],
                int(config["bootstrap_resamples"]),
                int(config["bootstrap_seed"]),
            )
            _atomic_frame(root / "seedwise_per_basin.csv", seedwise)
            _atomic_frame(root / "ensemble_per_basin.csv", ensemble)
            for variant, frame in ensemble_predictions.items():
                _atomic_frame(root / f"{variant}_ensemble_predictions.csv", frame)
            summary = {
                "status": (
                    "complete_multiseed_go"
                    if multiseed["passed"]
                    else "complete_multiseed_no_go"
                ),
                "experiment_id": config["experiment_id"],
                "stage1": stage_result,
                "multiseed": multiseed,
                "history_gate_diagnostic": diagnostic,
                "conditional_seeds_authorized": True,
                "formal_evaluation_target_access": False,
            }
    _atomic_text(root / "summary.json", json.dumps(summary, indent=2, sort_keys=True))
    artifact_names = ["summary.json", f"paired_per_basin_s{seed}.csv"]
    if "multiseed" in summary:
        artifact_names += [
            "seedwise_per_basin.csv",
            "ensemble_per_basin.csv",
            *[
                f"{variant}_ensemble_predictions.csv"
                for variant in config["variants"]
            ],
        ]
    manifest = {
        "status": "complete",
        "experiment_id": config["experiment_id"],
        "experiment_family": config["experiment_family"],
        "analysis_status": summary["status"],
        "artifacts": {name: _sha256(root / name) for name in artifact_names},
    }
    _atomic_text(root / "analysis_manifest.json", json.dumps(manifest, indent=2, sort_keys=True))
    return summary


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", type=Path, required=True)
    parser.add_argument("--gate-diagnostic", action="store_true")
    parser.add_argument("--data-dir", type=Path)
    parser.add_argument("--targets-file", type=Path)
    parser.add_argument("--targets-sha256")
    parser.add_argument("--device", default="cpu")
    args = parser.parse_args()
    config = json.loads(args.config.read_text(encoding="utf-8"))
    validate_config_v08(config)
    if not args.gate_diagnostic:
        result = analyze_results_v08(config)
        print(json.dumps(result, indent=2, sort_keys=True))
        return
    if args.data_dir is None or args.targets_file is None or args.targets_sha256 is None:
        raise ValueError("gate diagnostic requires data-dir, targets-file, and targets-sha256")
    if args.targets_sha256.lower() != config["target_bundle_sha256"].lower():
        raise ValueError("command target SHA-256 does not match the frozen configuration")
    basin_file = _REPO / config["basin_file"]
    validate_frozen_file_hash(basin_file, config["basin_file_sha256"], "basin list")
    basins = load_basin_ids(basin_file)
    pack = load_data_pack(
        args.data_dir,
        basins,
        targets_file=args.targets_file,
        expected_targets_sha256=args.targets_sha256,
    )
    root = _results_root(config)
    seed = int(config["stage1_seed"])
    result = run_history_gate_diagnostic_v08(
        pack,
        config,
        seed,
        root / f"continuous_multiscale_history_s{seed}",
        root / f"history_gate_diagnostic_s{seed}",
        args.device,
    )
    print(json.dumps(result, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
