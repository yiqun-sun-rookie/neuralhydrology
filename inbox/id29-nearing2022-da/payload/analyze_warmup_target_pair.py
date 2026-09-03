"""Independently score and decide the preregistered warmup-target retraining pair."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import pickle
from typing import Any, Iterable, Mapping

import numpy as np
import pandas as pd
from scipy import stats


TARGET = "QObs(mm/d)"


def _sha256_file(path: Path) -> str:
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def _load_json(path: Path) -> dict[str, Any]:
    payload = json.loads(Path(path).read_text(encoding="utf-8"))
    if not isinstance(payload, dict):
        raise TypeError(f"Expected a JSON object in {path}")
    return payload


def _load_pickle(path: Path) -> Mapping[str, object]:
    with Path(path).open("rb") as handle:
        payload = pickle.load(handle)
    if not isinstance(payload, Mapping):
        raise TypeError(f"Expected a trusted result mapping in {path}, got {type(payload).__name__}")
    return payload


def _dataset(payload: Mapping[str, object], basin: str):
    basin_payload = payload[basin]
    if not isinstance(basin_payload, Mapping) or "1D" not in basin_payload:
        raise KeyError(f"Basin {basin} lacks the required 1D result")
    frequency_payload = basin_payload["1D"]
    if not isinstance(frequency_payload, Mapping) or "xr" not in frequency_payload:
        raise KeyError(f"Basin {basin} lacks the required 1D/xr result")
    return frequency_payload["xr"]


def _series(dataset, variable: str) -> pd.Series:
    if variable not in dataset:
        raise KeyError(f"Missing result variable {variable}")
    values = np.asarray(dataset[variable].values)
    if values.ndim == 2 and values.shape[1] == 1:
        values = values[:, 0]
    elif values.ndim != 1:
        raise ValueError(f"Expected one value per date for {variable}, got shape {values.shape}")
    dates = pd.DatetimeIndex(np.asarray(dataset["date"].values))
    if len(dates) != len(values):
        raise ValueError(f"Date/value mismatch for {variable}: {len(dates)} versus {len(values)}")
    if dates.has_duplicates:
        raise ValueError(f"Duplicate dates are not allowed for {variable}")
    return pd.Series(values.astype(float), index=dates, name=variable)


def _candidate_on_finite_reference(reference_dataset, candidate_dataset) -> pd.DataFrame:
    obs = _series(reference_dataset, f"{TARGET}_obs")
    sim = _series(candidate_dataset, f"{TARGET}_sim")
    aligned = pd.concat([obs.rename("obs"), sim.rename("sim")], axis=1, join="inner")
    finite = np.isfinite(aligned["obs"].to_numpy()) & np.isfinite(aligned["sim"].to_numpy())
    return aligned.loc[finite]


def _nse(obs: np.ndarray, sim: np.ndarray) -> float:
    obs = np.asarray(obs, dtype=float)
    sim = np.asarray(sim, dtype=float)
    denominator = float(np.sum((obs - np.mean(obs))**2))
    if denominator == 0.0:
        raise ValueError("Nash-Sutcliffe efficiency is undefined for a constant observation series")
    return float(1.0 - np.sum((sim - obs)**2) / denominator)


def _bootstrap_median_effect(
    effects: np.ndarray,
    seed: int,
    replicates: int,
    quantiles: list[float],
    quantile_method: str,
) -> tuple[float, float]:
    if replicates <= 0:
        raise ValueError(f"bootstrap replicates must be positive, got {replicates}")
    rng = np.random.default_rng(seed)
    medians = np.empty(replicates, dtype=float)
    chunk_size = 1000
    for start in range(0, replicates, chunk_size):
        stop = min(replicates, start + chunk_size)
        indices = rng.integers(0, len(effects), size=(stop - start, len(effects)))
        medians[start:stop] = np.median(effects[indices], axis=1)
    lower, upper = np.quantile(medians, quantiles, method=quantile_method)
    return float(lower), float(upper)


def _wilcoxon(effects: np.ndarray, contract: dict[str, Any]) -> dict[str, float | str | bool]:
    if np.all(effects == 0.0):
        return {
            "statistic": 0.0,
            "pvalue": 1.0,
            **contract,
        }
    result = stats.wilcoxon(
        effects,
        alternative=contract["alternative"],
        zero_method=contract["zero_method"],
        method=contract["method"],
        correction=contract["correction"],
    )
    return {
        "statistic": float(result.statistic),
        "pvalue": float(result.pvalue),
        **contract,
    }


def analyze_pair(
    simulation_path: Path,
    registered_path: Path,
    control_path: Path,
    masked_path: Path,
    contract_path: Path,
) -> tuple[pd.DataFrame, dict[str, Any]]:
    """Return per-basin paired scores and the frozen decision without using the formal matrix gate."""
    paths = {
        "simulation": Path(simulation_path),
        "registered": Path(registered_path),
        "control": Path(control_path),
        "masked": Path(masked_path),
        "contract": Path(contract_path),
    }
    contract = _load_json(paths["contract"])
    if contract.get("schema") != "nearing2022-warmup-target-paired-analysis-contract-v1":
        raise ValueError("Unsupported warmup-pair analysis contract schema")
    if contract.get("common_index_rule") != "exact_registered_finite_dates_per_basin":
        raise ValueError("Analysis contract must require the exact registered finite date index")
    payloads = {name: _load_pickle(path) for name, path in paths.items() if name != "contract"}
    basin_sets = {name: set(payload) for name, payload in payloads.items()}
    expected = contract["basin_count"]
    if any(len(basins) != expected for basins in basin_sets.values()):
        raise ValueError(f"Every paired payload must contain exactly {expected} basins")
    if len({frozenset(basins) for basins in basin_sets.values()}) != 1:
        raise ValueError("Simulation, registered, control and masked basin sets differ")

    rows: list[dict[str, Any]] = []
    for basin in sorted(basin_sets["simulation"]):
        reference = _dataset(payloads["simulation"], basin)
        registered = _candidate_on_finite_reference(reference, _dataset(payloads["registered"], basin))
        control = _candidate_on_finite_reference(reference, _dataset(payloads["control"], basin))
        masked = _candidate_on_finite_reference(reference, _dataset(payloads["masked"], basin))
        for name, candidate in (("control", control), ("masked", masked)):
            if not candidate.index.equals(registered.index):
                raise ValueError(f"Basin {basin} {name} does not use the exact registered date index")
        if not np.array_equal(control["obs"].to_numpy(), registered["obs"].to_numpy(), equal_nan=True):
            raise ValueError(f"Basin {basin} control observations differ from the registered reference")
        if not np.array_equal(masked["obs"].to_numpy(), registered["obs"].to_numpy(), equal_nan=True):
            raise ValueError(f"Basin {basin} masked observations differ from the registered reference")
        obs = registered["obs"].to_numpy()
        registered_nse = _nse(obs, registered["sim"].to_numpy())
        control_nse = _nse(obs, control["sim"].to_numpy())
        masked_nse = _nse(obs, masked["sim"].to_numpy())
        rows.append({
            "basin": basin,
            "n_common": len(registered),
            "start_date": str(registered.index[0].date()),
            "end_date": str(registered.index[-1].date()),
            "registered_nse": registered_nse,
            "control_nse": control_nse,
            "masked_nse": masked_nse,
            "masked_minus_control_nse": masked_nse - control_nse,
        })
    per_basin = pd.DataFrame(rows).sort_values("basin").reset_index(drop=True)
    numeric = per_basin[["registered_nse", "control_nse", "masked_nse", "masked_minus_control_nse"]]
    if not np.all(np.isfinite(numeric.to_numpy())):
        raise ValueError("All 531 paired NSE values and effects must be finite")

    thresholds = contract["decision_thresholds"]
    registered_median = float(per_basin["registered_nse"].median())
    control_median = float(per_basin["control_nse"].median())
    masked_median = float(per_basin["masked_nse"].median())
    registered_difference = registered_median - thresholds["registered_current_median_nse"]
    if abs(registered_difference) > thresholds["registered_recompute_tolerance"]:
        raise ValueError(
            "Independently recomputed registered median NSE differs from the frozen contract: "
            f"difference={registered_difference}"
        )
    effects = per_basin["masked_minus_control_nse"].to_numpy(dtype=float)
    bootstrap = contract["bootstrap"]
    bootstrap_ci = _bootstrap_median_effect(
        effects,
        int(bootstrap["seed"]),
        int(bootstrap["replicates"]),
        [float(value) for value in bootstrap["quantiles"]],
        str(bootstrap["quantile_method"]),
    )
    author = float(thresholds["author_median_nse"])
    control_stability_difference = abs(control_median - thresholds["registered_current_median_nse"])
    control_stability_pass = control_stability_difference <= thresholds["control_stability_tolerance"]
    paper_gap_reduction = abs(control_median - author) - abs(masked_median - author)
    if author < control_median:
        paper_direction = "lower"
        interval_in_paper_direction = bootstrap_ci[1] < 0.0
    elif author > control_median:
        paper_direction = "higher"
        interval_in_paper_direction = bootstrap_ci[0] > 0.0
    else:
        paper_direction = "none"
        interval_in_paper_direction = False
    material = bool(
        control_stability_pass
        and paper_gap_reduction >= thresholds["minimum_material_gap_reduction"]
        and interval_in_paper_direction
    )
    paper_agreement = bool(material and abs(masked_median - author) <= thresholds["paper_agreement_tolerance"])
    if not control_stability_pass:
        status = "HOLD_RUNTIME_INSTABILITY"
    elif material:
        status = "MATERIAL_CONTRIBUTION"
    else:
        status = "NO_MATERIAL_CONTRIBUTION"

    decision = {
        "schema": "nearing2022-warmup-target-paired-analysis-v1",
        "status": status,
        "basins": len(per_basin),
        "date_indices_exact": True,
        "n_common_min": int(per_basin["n_common"].min()),
        "n_common_max": int(per_basin["n_common"].max()),
        "registered_median_nse": registered_median,
        "frozen_registered_median_nse": float(thresholds["registered_current_median_nse"]),
        "registered_recompute_difference": registered_difference,
        "control_median_nse": control_median,
        "masked_median_nse": masked_median,
        "author_median_nse": author,
        "primary_paired_effect": float(np.median(effects)),
        "bootstrap_ci": list(bootstrap_ci),
        "bootstrap": bootstrap,
        "wilcoxon": _wilcoxon(effects, contract["wilcoxon"]),
        "paper_direction": paper_direction,
        "bootstrap_interval_in_paper_direction": bool(interval_in_paper_direction),
        "control_stability_difference": control_stability_difference,
        "control_stability_tolerance": float(thresholds["control_stability_tolerance"]),
        "control_stability_pass": bool(control_stability_pass),
        "paper_gap_reduction": paper_gap_reduction,
        "minimum_material_gap_reduction": float(thresholds["minimum_material_gap_reduction"]),
        "material_warmup_contribution": material,
        "masked_absolute_paper_difference": abs(masked_median - author),
        "paper_agreement_tolerance": float(thresholds["paper_agreement_tolerance"]),
        "paper_agreement_pass": paper_agreement,
        "inputs": {
            name: {"path": str(path.resolve()), "sha256": _sha256_file(path)}
            for name, path in paths.items()
        },
        "registered_matrix_modified": False,
        "scientific_boundary": (
            "This pair quantifies the single warmup-target mask under the current runtime. It cannot establish "
            "unique historical causality or reproduce unavailable author-era dependencies and V100 execution."
        ),
    }
    return per_basin, decision


def _write_outputs(per_basin: pd.DataFrame, decision: dict[str, Any], csv_path: Path, json_path: Path) -> None:
    if csv_path.exists() or json_path.exists():
        raise FileExistsError(f"Refusing to overwrite paired analysis outputs: {csv_path}, {json_path}")
    csv_path.parent.mkdir(parents=True, exist_ok=True)
    json_path.parent.mkdir(parents=True, exist_ok=True)
    csv_temporary = csv_path.with_suffix(csv_path.suffix + ".tmp")
    json_temporary = json_path.with_suffix(json_path.suffix + ".tmp")
    if csv_temporary.exists() or json_temporary.exists():
        raise FileExistsError("Refusing stale paired-analysis temporary outputs")
    per_basin.to_csv(csv_temporary, index=False, lineterminator="\n", float_format="%.17g")
    json_temporary.write_text(
        json.dumps(decision, indent=2, sort_keys=True, allow_nan=False) + "\n",
        encoding="utf-8",
        newline="\n",
    )
    csv_temporary.replace(csv_path)
    json_temporary.replace(json_path)


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--simulation", type=Path, required=True)
    parser.add_argument("--registered", type=Path, required=True)
    parser.add_argument("--control", type=Path, required=True)
    parser.add_argument("--masked", type=Path, required=True)
    parser.add_argument("--contract", type=Path, required=True)
    parser.add_argument("--per-basin-out", type=Path, required=True)
    parser.add_argument("--decision-out", type=Path, required=True)
    return parser


def main(argv: Iterable[str] | None = None) -> int:
    args = _build_parser().parse_args(argv)
    per_basin, decision = analyze_pair(
        args.simulation,
        args.registered,
        args.control,
        args.masked,
        args.contract,
    )
    _write_outputs(per_basin, decision, args.per_basin_out, args.decision_out)
    print(json.dumps(decision, sort_keys=True, allow_nan=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
