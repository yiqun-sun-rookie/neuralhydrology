"""Paired analysis and frozen state-reset diagnostics for sequential history transfer."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
from typing import Mapping, Sequence

import numpy as np
import pandas as pd
import torch

from bands_v03 import forcing_prefix
from data import DataPack, load_basin_ids, load_data_pack, normalize_pack, split_target_indices
from metrics import per_basin_nse
from models_sequential_v07 import (
    RESET_MODES_SEQUENTIAL_V07,
    build_sequential_model_v07,
)
from train_sequential_v07 import (
    VARIANTS_SEQUENTIAL_V07,
    dynamic_batch_sequential_v07,
    validate_sequential_config_v07,
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


def evaluate_stage1_sequential_v07(paired: pd.DataFrame, gates: Mapping) -> dict:
    required = {
        "nse_classic",
        "nse_capacity",
        "nse_late_concat",
        "nse_candidate",
    }
    missing = required - set(paired.columns)
    if missing:
        raise ValueError(f"paired metrics are missing columns: {sorted(missing)}")
    delta_classic = paired["nse_candidate"] - paired["nse_classic"]
    delta_capacity = paired["nse_candidate"] - paired["nse_capacity"]
    delta_late = paired["nse_candidate"] - paired["nse_late_concat"]
    values = {
        "n_basins": int(len(paired)),
        "median_delta_classic": float(np.nanmedian(delta_classic)),
        "median_delta_capacity": float(np.nanmedian(delta_capacity)),
        "median_delta_late_concat": float(np.nanmedian(delta_late)),
        "win_fraction_classic": float(np.mean(delta_classic > 0)),
    }
    criteria = {
        "median_delta_classic_at_least": (
            values["median_delta_classic"] >= float(gates["median_delta_classic_at_least"])
        ),
        "median_delta_capacity_above": (
            values["median_delta_capacity"] > float(gates["median_delta_capacity_above"])
        ),
        "median_delta_late_concat_above": (
            values["median_delta_late_concat"] > float(gates["median_delta_late_concat_above"])
        ),
        "win_fraction_classic_at_least": (
            values["win_fraction_classic"] >= float(gates["win_fraction_classic_at_least"])
        ),
    }
    return {
        **values,
        "criteria": {key: bool(value) for key, value in criteria.items()},
        "passed": bool(all(criteria.values())),
    }


def assert_same_targets_v07(
    reference: pd.DataFrame,
    candidate: pd.DataFrame,
    label: str,
) -> None:
    if not candidate[["basin", "date"]].equals(reference[["basin", "date"]]):
        raise ValueError(f"{label} prediction keys differ")
    if not np.array_equal(candidate["qobs"].to_numpy(), reference["qobs"].to_numpy()):
        raise ValueError(f"{label} observations differ")


def _bootstrap_median_ci(
    values: np.ndarray,
    resamples: int,
    seed: int,
) -> list[float]:
    finite = np.asarray(values, dtype=float)
    finite = finite[np.isfinite(finite)]
    if len(finite) == 0:
        raise ValueError("bootstrap requires at least one finite paired difference")
    generator = np.random.default_rng(int(seed))
    medians = np.empty(int(resamples), dtype=np.float64)
    chunk_size = 10_000
    for start in range(0, int(resamples), chunk_size):
        stop = min(start + chunk_size, int(resamples))
        indices = generator.integers(0, len(finite), size=(stop - start, len(finite)))
        medians[start:stop] = np.median(finite[indices], axis=1)
    lower, upper = np.percentile(medians, [2.5, 97.5])
    return [float(lower), float(upper)]


def evaluate_multiseed_sequential_v07(
    seedwise: pd.DataFrame,
    ensemble: pd.DataFrame,
    bootstrap_resamples: int,
    bootstrap_seed: int,
) -> dict:
    seed_required = {"seed", "basin", "nse_classic", "nse_candidate"}
    ensemble_required = {
        "basin",
        "nse_classic",
        "nse_capacity",
        "nse_late_concat",
        "nse_candidate",
    }
    if seed_required - set(seedwise.columns):
        raise ValueError("seedwise metrics are missing required columns")
    if ensemble_required - set(ensemble.columns):
        raise ValueError("ensemble metrics are missing required columns")
    seed_medians = (
        seedwise.assign(delta=seedwise["nse_candidate"] - seedwise["nse_classic"])
        .groupby("seed", sort=True)["delta"]
        .median()
    )
    delta_classic = (ensemble["nse_candidate"] - ensemble["nse_classic"]).to_numpy(float)
    delta_capacity = (ensemble["nse_candidate"] - ensemble["nse_capacity"]).to_numpy(float)
    delta_late = (ensemble["nse_candidate"] - ensemble["nse_late_concat"]).to_numpy(float)
    ci = _bootstrap_median_ci(
        delta_classic,
        resamples=int(bootstrap_resamples),
        seed=int(bootstrap_seed),
    )
    values = {
        "n_basins": int(len(ensemble)),
        "positive_seed_count": int((seed_medians > 0).sum()),
        "seed_median_delta_classic": {
            str(int(seed)): float(value) for seed, value in seed_medians.items()
        },
        "median_delta_classic": float(np.nanmedian(delta_classic)),
        "median_delta_capacity": float(np.nanmedian(delta_capacity)),
        "median_delta_late_concat": float(np.nanmedian(delta_late)),
        "bootstrap_median_delta_ci95": ci,
    }
    criteria = {
        "at_least_two_positive_seeds": values["positive_seed_count"] >= 2,
        "bootstrap_lower_above_zero": ci[0] > 0,
        "median_delta_classic_at_least_0_01": values["median_delta_classic"] >= 0.01,
        "median_delta_capacity_above_zero": values["median_delta_capacity"] > 0,
        "median_delta_late_concat_above_zero": values["median_delta_late_concat"] > 0,
    }
    return {
        **values,
        "criteria": {key: bool(value) for key, value in criteria.items()},
        "passed": bool(all(criteria.values())),
    }


def _load_predictions(path: Path, expected_rows: int) -> pd.DataFrame:
    frame = pd.read_csv(path, dtype={"basin": str})
    if list(frame.columns) != ["basin", "date", "qobs", "qsim"]:
        raise ValueError(f"prediction columns are invalid in {path}")
    if len(frame) != int(expected_rows):
        raise ValueError(f"prediction row count must be {expected_rows} in {path}")
    return frame.sort_values(["basin", "date"]).reset_index(drop=True)


def _validated_run_predictions(
    run_dir: Path,
    variant: str,
    seed: int,
    expected_rows: int,
) -> pd.DataFrame:
    manifest_path = run_dir / "manifest.json"
    if not manifest_path.exists():
        raise FileNotFoundError(f"missing run manifest: {manifest_path}")
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    if manifest.get("status") != "complete":
        raise ValueError(f"run is not complete: {run_dir}")
    if manifest.get("variant") != variant or int(manifest.get("seed", -1)) != int(seed):
        raise ValueError(f"run identity mismatch: {run_dir}")
    if manifest.get("data_access") != {
        "raw_observed_discharge_reads": 0,
        "target_bundle_interface": True,
        "formal_evaluation_access": False,
    }:
        raise ValueError(f"run data-access boundary mismatch: {run_dir}")
    for name, expected in manifest.get("artifacts", {}).items():
        if _sha256(run_dir / name) != expected:
            raise ValueError(f"artifact hash mismatch: {run_dir / name}")
    predictions = _load_predictions(run_dir / "predictions.csv", expected_rows)
    saved_metrics = pd.read_csv(run_dir / "per_basin_metrics.csv", dtype={"basin": str})
    recomputed = per_basin_nse(predictions)
    pd.testing.assert_frame_equal(saved_metrics, recomputed, check_exact=True)
    return predictions


def _named_nse(predictions: pd.DataFrame, name: str) -> pd.DataFrame:
    return per_basin_nse(predictions)[["basin", "nse"]].rename(
        columns={"nse": f"nse_{name}"}
    )


def _paired_metrics(
    predictions: Mapping[str, pd.DataFrame],
    names: Sequence[str],
) -> pd.DataFrame:
    reference = predictions[names[0]]
    for name in names[1:]:
        assert_same_targets_v07(reference, predictions[name], name)
    paired = _named_nse(reference, names[0])
    for name in names[1:]:
        paired = paired.merge(
            _named_nse(predictions[name], name),
            on="basin",
            how="inner",
            validate="one_to_one",
        )
    return paired.sort_values("basin").reset_index(drop=True)


def _ensemble_predictions(
    frames: Sequence[pd.DataFrame],
    label: str,
) -> pd.DataFrame:
    if not frames:
        raise ValueError(f"{label} ensemble requires at least one frame")
    reference = frames[0]
    for index, frame in enumerate(frames[1:], start=1):
        assert_same_targets_v07(reference, frame, f"{label} member {index}")
    result = reference[["basin", "date", "qobs"]].copy()
    result["qsim"] = np.mean(
        np.stack([frame["qsim"].to_numpy(float) for frame in frames], axis=0),
        axis=0,
    )
    return result


def run_reset_diagnostics_v07(
    pack: DataPack,
    config: Mapping,
    seed: int,
    candidate_run_dir: str | Path,
    output_dir: str | Path,
    device: str,
) -> dict:
    validate_sequential_config_v07(config)
    candidate_run_dir = Path(candidate_run_dir)
    output_dir = Path(output_dir)
    if output_dir.exists() and any(output_dir.iterdir()):
        raise FileExistsError(f"output directory is not empty: {output_dir}")
    output_dir.mkdir(parents=True, exist_ok=True)
    manifest = json.loads((candidate_run_dir / "manifest.json").read_text(encoding="utf-8"))
    if manifest.get("variant") != "sequential_transfer" or int(manifest.get("seed", -1)) != int(seed):
        raise ValueError("candidate checkpoint identity mismatch")
    for name, expected in manifest.get("artifacts", {}).items():
        if _sha256(candidate_run_dir / name) != expected:
            raise ValueError(f"candidate artifact hash mismatch: {name}")
    torch_device = torch.device(device)
    checkpoint = torch.load(candidate_run_dir / "checkpoint.pt", map_location=torch_device)
    if checkpoint.get("variant") != "sequential_transfer":
        raise ValueError("checkpoint is not the sequential candidate")
    normalized = normalize_pack(pack, checkpoint["scaler"])
    forcing = torch.tensor(normalized.forcing, device=torch_device)
    statics = torch.tensor(normalized.statics, device=torch_device)
    prefix = forcing_prefix(forcing)
    model = build_sequential_model_v07("sequential_transfer", seed=int(seed)).to(torch_device)
    model.load_state_dict(checkpoint["model_state_dict"])
    model.eval()
    validation_basins, validation_times = split_target_indices(
        pack.dates,
        pack.discharge,
        split="validation",
    )
    validation_basins, validation_times = _limited_balanced_indices(
        validation_basins,
        validation_times,
        int(config.get("limit_validation_samples", 0)),
    )
    predictions_by_mode = {}
    metrics_by_mode = {}
    with torch.no_grad():
        for mode in config["reset_diagnostics"]:
            parts = []
            for start in range(0, len(validation_basins), int(config["validation_batch_size"])):
                basin_numpy = validation_basins[
                    start:start + int(config["validation_batch_size"])
                ]
                target_numpy = validation_times[
                    start:start + int(config["validation_batch_size"])
                ]
                basin_index = torch.tensor(basin_numpy, device=torch_device)
                target_index = torch.tensor(target_numpy, device=torch_device)
                dynamic = dynamic_batch_sequential_v07(
                    "sequential_transfer",
                    forcing,
                    prefix,
                    basin_index,
                    target_index,
                )
                prediction = model(
                    dynamic,
                    statics[basin_index],
                    dropout_context=None,
                    reset_mode=mode,
                ).prediction
                qsim = (
                    prediction.detach().cpu().numpy() * float(checkpoint["scaler"]["q_scale"])
                    + float(checkpoint["scaler"]["q_center"])
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
            predictions_path = output_dir / f"{mode}_predictions.csv"
            _atomic_frame(predictions_path, frame)
            predictions_by_mode[mode] = _load_predictions(predictions_path, len(frame))
            metrics_by_mode[mode] = per_basin_nse(predictions_by_mode[mode])
            _atomic_frame(output_dir / f"{mode}_per_basin_metrics.csv", metrics_by_mode[mode])

    reference = predictions_by_mode["none"]
    for mode in config["reset_diagnostics"][1:]:
        assert_same_targets_v07(reference, predictions_by_mode[mode], mode)
    normal_metrics = metrics_by_mode["none"][["basin", "nse"]].rename(
        columns={"nse": "nse_none"}
    )
    paired = normal_metrics
    for mode in config["reset_diagnostics"][1:]:
        paired = paired.merge(
            metrics_by_mode[mode][["basin", "nse"]].rename(
                columns={"nse": f"nse_{mode}"}
            ),
            on="basin",
            validate="one_to_one",
        )
    summary = {
        "status": "complete",
        "causal_attribution_allowed": False,
        "interpretation": "trained-checkpoint dependency diagnostic only",
        "median_nse": {
            mode: float(np.nanmedian(metrics_by_mode[mode]["nse"]))
            for mode in config["reset_diagnostics"]
        },
        "median_delta_vs_none": {
            mode: float(np.nanmedian(paired[f"nse_{mode}"] - paired["nse_none"]))
            for mode in config["reset_diagnostics"][1:]
        },
        "n_validation_predictions_per_mode": int(len(reference)),
    }
    _atomic_text(output_dir / "summary.json", json.dumps(summary, indent=2, sort_keys=True))
    artifact_names = [
        item
        for mode in config["reset_diagnostics"]
        for item in (f"{mode}_predictions.csv", f"{mode}_per_basin_metrics.csv")
    ] + ["summary.json"]
    output_manifest = {
        "status": "complete",
        "experiment_id": config["experiment_id"],
        "seed": int(seed),
        "reset_modes": list(config["reset_diagnostics"]),
        "causal_attribution_allowed": False,
        "n_validation_predictions_per_mode": int(len(reference)),
        "data_access": {
            "raw_observed_discharge_reads": 0,
            "target_bundle_interface": True,
            "formal_evaluation_access": False,
        },
        "artifacts": {name: _sha256(output_dir / name) for name in artifact_names},
    }
    _atomic_text(
        output_dir / "manifest.json",
        json.dumps(output_manifest, indent=2, sort_keys=True),
    )
    return output_manifest


def analyze_sequential_results_v07(config: Mapping) -> dict:
    validate_sequential_config_v07(config)
    if config["mode"] != "pilot":
        raise ValueError("scientific analysis requires pilot mode")
    results_root = _REPO / config["results_root"]
    stage1_seed = int(config["stage1_seed"])
    stage1_dirs = {
        variant: results_root / f"{variant}_s{stage1_seed}"
        for variant in VARIANTS_SEQUENTIAL_V07
    }
    missing = [
        str((path / "manifest.json").relative_to(_REPO))
        for path in stage1_dirs.values()
        if not (path / "manifest.json").exists()
    ]
    if missing:
        summary = {
            "status": "incomplete_stage1",
            "missing_runs": missing,
            "required_conditional_seeds": [],
        }
        results_root.mkdir(parents=True, exist_ok=True)
        _atomic_text(results_root / "summary.json", json.dumps(summary, indent=2, sort_keys=True))
        return summary
    predictions = {
        "classic": _validated_run_predictions(
            stage1_dirs["classic_lstm_256_keyed"],
            "classic_lstm_256_keyed",
            stage1_seed,
            43_860,
        ),
        "capacity": _validated_run_predictions(
            stage1_dirs["classic_lstm_455_keyed"],
            "classic_lstm_455_keyed",
            stage1_seed,
            43_860,
        ),
        "candidate": _validated_run_predictions(
            stage1_dirs["sequential_transfer"],
            "sequential_transfer",
            stage1_seed,
            43_860,
        ),
    }
    validate_frozen_file_hash(
        _REPO / config["legacy_late_concat_predictions"],
        config["legacy_late_concat_predictions_sha256"],
        "legacy late-concatenation predictions",
    )
    predictions["late_concat"] = _load_predictions(
        _REPO / config["legacy_late_concat_predictions"],
        43_860,
    )
    paired_stage1 = _paired_metrics(
        predictions,
        ("classic", "capacity", "late_concat", "candidate"),
    )
    if len(paired_stage1) != 60:
        raise ValueError(f"paired stage-one basin count must be 60, got {len(paired_stage1)}")
    stage1 = evaluate_stage1_sequential_v07(paired_stage1, config["stage1_gates"])
    _atomic_frame(results_root / "paired_per_basin_s100.csv", paired_stage1)
    reset_summary_path = results_root / f"reset_diagnostics_s{stage1_seed}" / "summary.json"
    reset_status = (
        json.loads(reset_summary_path.read_text(encoding="utf-8"))
        if reset_summary_path.exists()
        else {"status": "missing"}
    )
    if not stage1["passed"]:
        summary = {
            "status": "complete_stage1_no_go",
            "missing_runs": [],
            "required_conditional_seeds": [],
            "stage1": stage1,
            "reset_diagnostics": reset_status,
            "formal_evaluation_access": False,
        }
    else:
        conditional = [int(value) for value in config["conditional_seeds"]]
        conditional_dirs = {
            (variant, seed): results_root / f"{variant}_s{seed}"
            for seed in conditional
            for variant in VARIANTS_SEQUENTIAL_V07
        }
        missing_conditional = [
            str((path / "manifest.json").relative_to(_REPO))
            for path in conditional_dirs.values()
            if not (path / "manifest.json").exists()
        ]
        if missing_conditional:
            summary = {
                "status": "complete_stage1_go_pending_multiseed",
                "missing_runs": missing_conditional,
                "required_conditional_seeds": conditional,
                "stage1": stage1,
                "reset_diagnostics": reset_status,
                "formal_evaluation_access": False,
            }
        else:
            all_seeds = [stage1_seed] + conditional
            by_variant = {
                variant: [
                    _validated_run_predictions(
                        results_root / f"{variant}_s{seed}",
                        variant,
                        seed,
                        43_860,
                    )
                    for seed in all_seeds
                ]
                for variant in VARIANTS_SEQUENTIAL_V07
            }
            seedwise_parts = []
            for seed_index, seed in enumerate(all_seeds):
                seed_pair = _paired_metrics(
                    {
                        "classic": by_variant["classic_lstm_256_keyed"][seed_index],
                        "candidate": by_variant["sequential_transfer"][seed_index],
                    },
                    ("classic", "candidate"),
                )
                seed_pair.insert(0, "seed", seed)
                seedwise_parts.append(seed_pair)
            seedwise = pd.concat(seedwise_parts, ignore_index=True)
            ensemble_predictions = {
                "classic": _ensemble_predictions(
                    by_variant["classic_lstm_256_keyed"], "classic"
                ),
                "capacity": _ensemble_predictions(
                    by_variant["classic_lstm_455_keyed"], "capacity"
                ),
                "candidate": _ensemble_predictions(
                    by_variant["sequential_transfer"], "candidate"
                ),
            }
            validate_frozen_file_hash(
                _REPO / config["legacy_late_concat_multiseed_predictions"],
                config["legacy_late_concat_multiseed_predictions_sha256"],
                "legacy late-concatenation multiseed predictions",
            )
            ensemble_predictions["late_concat"] = _load_predictions(
                _REPO / config["legacy_late_concat_multiseed_predictions"],
                43_860,
            )
            ensemble_paired = _paired_metrics(
                ensemble_predictions,
                ("classic", "capacity", "late_concat", "candidate"),
            )
            multiseed = evaluate_multiseed_sequential_v07(
                seedwise,
                ensemble_paired,
                bootstrap_resamples=int(config["bootstrap_resamples"]),
                bootstrap_seed=int(config["bootstrap_seed"]),
            )
            _atomic_frame(results_root / "seedwise_paired_per_basin.csv", seedwise)
            _atomic_frame(results_root / "ensemble_paired_per_basin.csv", ensemble_paired)
            for name, frame in ensemble_predictions.items():
                _atomic_frame(results_root / f"{name}_ensemble_predictions.csv", frame)
            summary = {
                "status": (
                    "complete_multiseed_go_internal"
                    if multiseed["passed"]
                    else "complete_multiseed_no_go"
                ),
                "missing_runs": [],
                "required_conditional_seeds": [],
                "stage1": stage1,
                "multiseed": multiseed,
                "reset_diagnostics": reset_status,
                "formal_evaluation_access": False,
            }
    _atomic_text(results_root / "summary.json", json.dumps(summary, indent=2, sort_keys=True))
    analysis_artifacts = [
        "paired_per_basin_s100.csv",
        "summary.json",
    ]
    if "multiseed" in summary:
        analysis_artifacts.extend([
            "seedwise_paired_per_basin.csv",
            "ensemble_paired_per_basin.csv",
            "classic_ensemble_predictions.csv",
            "capacity_ensemble_predictions.csv",
            "late_concat_ensemble_predictions.csv",
            "candidate_ensemble_predictions.csv",
        ])
    analysis_manifest = {
        "status": "complete",
        "experiment_id": config["experiment_id"],
        "data_access": {
            "prediction_artifacts_only": True,
            "formal_evaluation_access": False,
            "raw_observed_discharge_reads": 0,
        },
        "artifacts": {
            name: _sha256(results_root / name)
            for name in analysis_artifacts
        },
    }
    _atomic_text(
        results_root / "analysis_manifest.json",
        json.dumps(analysis_manifest, indent=2, sort_keys=True),
    )
    return summary


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", type=Path, required=True)
    parser.add_argument("--reset-diagnostics", action="store_true")
    parser.add_argument("--data-dir", type=Path)
    parser.add_argument("--targets-file", type=Path)
    parser.add_argument("--targets-sha256")
    parser.add_argument("--device", default="cpu")
    args = parser.parse_args()
    config = json.loads(args.config.read_text(encoding="utf-8"))
    if not args.reset_diagnostics:
        print(json.dumps(analyze_sequential_results_v07(config), indent=2, sort_keys=True))
        return
    if args.data_dir is None or args.targets_file is None or args.targets_sha256 is None:
        raise ValueError("reset diagnostics require data-dir, targets-file, and targets-sha256")
    validate_sequential_config_v07(config)
    if args.targets_sha256.lower() != config["target_bundle_sha256"].lower():
        raise ValueError("command target SHA-256 does not match the frozen configuration")
    basin_file = _REPO / config["basin_file"]
    validate_frozen_file_hash(basin_file, config["basin_file_sha256"], "basin list")
    pack = load_data_pack(
        args.data_dir,
        load_basin_ids(basin_file),
        targets_file=args.targets_file,
        expected_targets_sha256=args.targets_sha256,
    )
    seed = int(config["stage1_seed"])
    result = run_reset_diagnostics_v07(
        pack=pack,
        config=config,
        seed=seed,
        candidate_run_dir=(
            _REPO / config["results_root"] / f"sequential_transfer_s{seed}"
        ),
        output_dir=(
            _REPO / config["results_root"] / f"reset_diagnostics_s{seed}"
        ),
        device=args.device,
    )
    print(json.dumps(result, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
