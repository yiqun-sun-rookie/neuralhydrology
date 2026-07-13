"""Replay saved GR4J/XAJ/HBV parameters against the current forward code.

This is a fairness/reproducibility audit, not a recalibration. It reads the
final per-basin summary CSVs, re-simulates the evaluation period with the saved
parameters, and compares recomputed NSE against the stored headline artifacts.

Two replay modes are supported:

* ``saved_state`` uses the eval-init ``state_*`` columns saved in the CSV.
* ``warmup_recomputed`` recomputes the eval-init state from the one-year warmup
  forcing used by the original runners.

The audit is intended to answer whether code changes to the snow front end or
forward models invalidate the already calibrated parameter artifacts.
"""
from __future__ import annotations

import argparse
import json
import os
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Callable, Iterable

import numpy as np
import pandas as pd

_HERE = Path(__file__).resolve()
_REPO_ROOT = _HERE.parents[3]
if str(_REPO_ROOT / "src") not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT / "src"))
if str(_REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT))

from xaj_global_pilot.config import REPRO_FORCING, REPRO_VERSION, benchmark_results_dir, repro_split_periods  # noqa: E402
from xaj_global_pilot.metrics import compute_metrics  # noqa: E402

ReplayFn = Callable[[np.ndarray, np.ndarray, np.ndarray, dict, object], tuple[np.ndarray, object]]

SUMMARY_DIR = benchmark_results_dir(REPRO_VERSION) / "summary"
DEFAULT_SUMMARIES = {
    "GR4J": SUMMARY_DIR / "gr4j_pdd_cma_FINAL_pt_v1_local_full.csv",
    "XAJ": SUMMARY_DIR / "xaj_pdd_cma_FINAL_pt_v1_5k3_local_full.csv",
    "HBV": SUMMARY_DIR / "hbv_lite_cma_FINAL_pt_v1_warmup_local_full.csv",
}
DEFAULT_OUT_DIR = (
    Path("draft") / "papers" / "10_18_conceptual_lstm_package" / "audit" /
    "R01_saved_parameter_replay_current_code"
)
REPLAY_MODES = ("saved_state", "warmup_recomputed")


@dataclass(frozen=True)
class ModelSpec:
    label: str
    summary_path: Path
    param_names: tuple[str, ...]
    state_names: tuple[str, ...]
    state_kind: str
    simulate: ReplayFn
    fill_nan_forcing: bool


def _extract_params(row: pd.Series, param_names: Iterable[str]) -> dict[str, float]:
    params = {}
    for name in param_names:
        col = f"p_{name}"
        if col not in row:
            raise KeyError(f"Missing parameter column {col!r}")
        value = row[col]
        if pd.isna(value):
            raise ValueError(f"Parameter column {col!r} is NaN")
        params[name] = float(value)
    return params


def _extract_state_vector(row: pd.Series, state_names: Iterable[str]) -> np.ndarray:
    values = []
    for name in state_names:
        col = f"state_{name}"
        if col not in row:
            raise KeyError(f"Missing state column {col!r}")
        value = row[col]
        if pd.isna(value):
            raise ValueError(f"State column {col!r} is NaN")
        values.append(float(value))
    return np.asarray(values, dtype=np.float64)


def _extract_state_dict(row: pd.Series, state_names: Iterable[str]) -> dict[str, float]:
    values = _extract_state_vector(row, state_names)
    return dict(zip(state_names, values.tolist()))


def _classify_replay_status(abs_nse_diff: float, tolerance: float) -> str:
    return "pass" if np.isfinite(abs_nse_diff) and abs_nse_diff <= tolerance else "fail"


def summarize_replay_rows(rows: pd.DataFrame) -> pd.DataFrame:
    """Return one audit summary row per model and replay mode."""
    if rows.empty:
        return pd.DataFrame(columns=[
            "model", "replay_mode", "n", "n_pass", "n_fail", "n_error",
            "max_abs_nse_diff", "median_abs_nse_diff", "saved_median_nse",
            "replay_median_nse", "overall_status",
        ])

    out = []
    for (model, mode), group in rows.groupby(["model", "replay_mode"], sort=True):
        diffs = pd.to_numeric(group["abs_nse_diff"], errors="coerce")
        saved = (pd.to_numeric(group["nse_saved"], errors="coerce")
                 if "nse_saved" in group else pd.Series(dtype=float))
        replay = (pd.to_numeric(group["nse_replay"], errors="coerce")
                  if "nse_replay" in group else pd.Series(dtype=float))
        n_pass = int((group["status"] == "pass").sum())
        n_fail = int((group["status"] == "fail").sum())
        n_error = int((group["status"] == "error").sum())
        out.append({
            "model": model,
            "replay_mode": mode,
            "n": int(len(group)),
            "n_pass": n_pass,
            "n_fail": n_fail,
            "n_error": n_error,
            "max_abs_nse_diff": float(diffs.max()) if diffs.notna().any() else np.nan,
            "median_abs_nse_diff": float(diffs.median()) if diffs.notna().any() else np.nan,
            "saved_median_nse": float(saved.median()) if saved.notna().any() else np.nan,
            "replay_median_nse": float(replay.median()) if replay.notna().any() else np.nan,
            "overall_status": "pass" if n_fail == 0 and n_error == 0 else "fail",
        })
    return pd.DataFrame(out).sort_values(["model", "replay_mode"]).reset_index(drop=True)


def _build_model_specs(summary_paths: dict[str, Path] | None = None) -> dict[str, ModelSpec]:
    from scl_hydro.hbv_lite_numpy import PARAM_NAMES as HBV_PARAM_NAMES
    from scl_hydro.hbv_lite_numpy import STATE_NAMES as HBV_STATE_NAMES
    from scl_hydro.hbv_lite_numpy import simulate_hbv_lite
    from xaj_global_pilot.gr4j_core import PDD_GR4J_PARAM_NAMES, STATE_NAMES as GR4J_STATE_NAMES
    from xaj_global_pilot.gr4j_model import simulate_pdd_gr4j
    from xaj_global_pilot.xaj_model import PDD_XAJ_PARAM_NAMES, simulate_pdd_xaj
    from xaj_global_pilot.scripts.run_xaj_pdd_cma_repro_v01 import STATE_NAMES as XAJ_STATE_NAMES

    paths = {label: Path(path) for label, path in (summary_paths or DEFAULT_SUMMARIES).items()}
    return {
        "GR4J": ModelSpec(
            label="GR4J",
            summary_path=paths["GR4J"],
            param_names=tuple(PDD_GR4J_PARAM_NAMES),
            state_names=tuple(GR4J_STATE_NAMES),
            state_kind="vector",
            simulate=simulate_pdd_gr4j,
            fill_nan_forcing=True,
        ),
        "XAJ": ModelSpec(
            label="XAJ",
            summary_path=paths["XAJ"],
            param_names=tuple(PDD_XAJ_PARAM_NAMES),
            state_names=tuple(XAJ_STATE_NAMES),
            state_kind="matrix1",
            simulate=simulate_pdd_xaj,
            fill_nan_forcing=True,
        ),
        "HBV": ModelSpec(
            label="HBV",
            summary_path=paths["HBV"],
            param_names=tuple(HBV_PARAM_NAMES),
            state_names=tuple(HBV_STATE_NAMES),
            state_kind="dict",
            simulate=simulate_hbv_lite,
            fill_nan_forcing=False,
        ),
    }


def _read_summary(path: Path) -> pd.DataFrame:
    if not path.exists():
        raise FileNotFoundError(f"Summary CSV not found: {path}")
    df = pd.read_csv(path, dtype={"basin_id": str}, keep_default_na=False)
    df["basin_id"] = df["basin_id"].astype(str).str.zfill(8)
    return df


def _select_common_basins(frames: dict[str, pd.DataFrame], basins: list[str] | None, limit: int | None) -> list[str]:
    sets = []
    for df in frames.values():
        ok = df[(df["period"].astype(str) == "evaluation") & (df["run_status"].astype(str) == "success")]
        sets.append(set(ok["basin_id"]))
    common = sorted(set.intersection(*sets)) if sets else []
    if basins:
        requested = {str(b).zfill(8) for b in basins}
        common = [b for b in common if b in requested]
    if limit is not None:
        common = common[:limit]
    return common


def _forcing_arrays(forcing_df: pd.DataFrame, fill_nan: bool) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    pet_col = "ep" if "ep" in forcing_df.columns else "pet" if "pet" in forcing_df.columns else None
    if pet_col is None:
        raise RuntimeError("No PET column in forcing dataframe")
    rain = forcing_df["prcp"].to_numpy(dtype=np.float64)
    pet = forcing_df[pet_col].to_numpy(dtype=np.float64)
    temp = (forcing_df["tmean"].to_numpy(dtype=np.float64)
            if "tmean" in forcing_df.columns else np.zeros_like(rain))
    if fill_nan:
        rain = np.nan_to_num(rain, nan=0.0)
        pet = np.nan_to_num(pet, nan=0.0)
        temp = np.nan_to_num(temp, nan=0.0)
    return rain, pet, temp


def _state_from_saved_row(spec: ModelSpec, row: pd.Series):
    if spec.state_kind == "dict":
        return _extract_state_dict(row, spec.state_names)
    state = _extract_state_vector(row, spec.state_names)
    if spec.state_kind == "matrix1":
        return state.reshape(1, -1)
    return state


def _recompute_warmup_state(
    spec: ModelSpec,
    basin_id: str,
    params: dict[str, float],
    data_root: str,
    forcing: str,
    pet_method: str,
    eval_start: str,
):
    from hydroagent.data_loading import load_camels_basin

    warmup_start = (pd.Timestamp(eval_start) - pd.DateOffset(years=1)).strftime("%Y-%m-%d")
    warmup_end = (pd.Timestamp(eval_start) - pd.DateOffset(days=1)).strftime("%Y-%m-%d")
    forcing_w, _, _ = load_camels_basin(
        basin_id,
        data_root=data_root,
        start_date=warmup_start,
        end_date=warmup_end,
        forcing=forcing,
        pet_method=pet_method,
        keep_obs_nan_days=True,
    )
    rain_w, pet_w, temp_w = _forcing_arrays(forcing_w, spec.fill_nan_forcing)
    _, state = spec.simulate(rain_w, pet_w, temp_w, params, None)
    return state


def _replay_one(
    spec: ModelSpec,
    row: pd.Series,
    replay_mode: str,
    data_root: str,
    forcing: str,
    pet_method: str,
    eval_period: tuple[str, str],
    tolerance: float,
) -> dict:
    from hydroagent.data_loading import load_camels_basin

    basin_id = str(row["basin_id"]).zfill(8)
    out = {
        "model": spec.label,
        "replay_mode": replay_mode,
        "basin_id": basin_id,
        "nse_saved": np.nan,
        "nse_replay": np.nan,
        "nse_diff": np.nan,
        "abs_nse_diff": np.nan,
        "status": "error",
        "error_message": "",
        "state_init_mode_saved": row.get("state_init_mode", ""),
    }

    try:
        if str(row.get("run_status", "")) != "success":
            raise RuntimeError(f"Cannot replay non-success row: run_status={row.get('run_status')!r}")
        params = _extract_params(row, spec.param_names)
        if replay_mode == "saved_state":
            initial_state = _state_from_saved_row(spec, row)
        elif replay_mode == "warmup_recomputed":
            initial_state = _recompute_warmup_state(
                spec, basin_id, params, data_root, forcing, pet_method, eval_period[0])
        else:
            raise ValueError(f"Unknown replay mode: {replay_mode}")

        forcing_eval, obs_eval, _ = load_camels_basin(
            basin_id,
            data_root=data_root,
            start_date=eval_period[0],
            end_date=eval_period[1],
            forcing=forcing,
            pet_method=pet_method,
            keep_obs_nan_days=True,
        )
        rain_eval, pet_eval, temp_eval = _forcing_arrays(forcing_eval, spec.fill_nan_forcing)
        q_eval, _ = spec.simulate(rain_eval, pet_eval, temp_eval, params, initial_state)
        metrics = compute_metrics(obs_eval, pd.Series(q_eval, index=obs_eval.index, name="qsim"))

        saved_nse = float(row["nse"])
        replay_nse = float(metrics["nse"])
        diff = replay_nse - saved_nse
        abs_diff = abs(diff)
        out.update({
            "nse_saved": saved_nse,
            "nse_replay": replay_nse,
            "nse_diff": diff,
            "abs_nse_diff": abs_diff,
            "kge_replay": float(metrics["kge"]),
            "bias_replay": float(metrics["bias"]),
            "peak_bias_replay": float(metrics["peak_bias"]),
            "lowflow_bias_replay": float(metrics["lowflow_bias"]),
            "status": _classify_replay_status(abs_diff, tolerance),
        })
    except Exception as exc:  # noqa: BLE001
        out["error_message"] = f"{type(exc).__name__}: {exc}"
    return out


def run_replay_audit(
    models: list[str],
    replay_modes: list[str],
    data_root: str,
    forcing: str,
    pet_method: str,
    tolerance: float,
    limit: int | None = None,
    basins: list[str] | None = None,
    summary_paths: dict[str, Path] | None = None,
) -> tuple[pd.DataFrame, pd.DataFrame, dict]:
    specs = _build_model_specs(summary_paths)
    selected_specs = {label: specs[label] for label in models}
    frames = {label: _read_summary(spec.summary_path) for label, spec in selected_specs.items()}
    common_basins = _select_common_basins(frames, basins, limit)
    periods = repro_split_periods()
    eval_period = periods["evaluation"]

    rows = []
    total = len(selected_specs) * len(replay_modes) * len(common_basins)
    done = 0
    for label, spec in selected_specs.items():
        df = frames[label].set_index("basin_id", drop=False)
        for basin_id in common_basins:
            row = df.loc[basin_id]
            if isinstance(row, pd.DataFrame):
                row = row.iloc[0]
            for mode in replay_modes:
                done += 1
                result = _replay_one(spec, row, mode, data_root, forcing, pet_method, eval_period, tolerance)
                rows.append(result)
                print(
                    f"[{done:4d}/{total}] {label:<4} {mode:<17} {basin_id} "
                    f"{result['status']:<5} diff={result['abs_nse_diff']}",
                    flush=True,
                )

    rows_df = pd.DataFrame(rows)
    summary_df = summarize_replay_rows(rows_df)
    manifest = {
        "audit_id": "R01_saved_parameter_replay_current_code",
        "protocol": "repro_v01",
        "purpose": "Replay saved calibrated parameters under the current code to audit result validity after fairness fixes.",
        "models": models,
        "replay_modes": replay_modes,
        "n_common_basins": len(common_basins),
        "basins": common_basins,
        "data_root": data_root,
        "forcing": forcing,
        "pet_method": pet_method,
        "evaluation_start": eval_period[0],
        "evaluation_end": eval_period[1],
        "tolerance_abs_nse": tolerance,
        "summary_paths": {label: str(spec.summary_path) for label, spec in selected_specs.items()},
        "overall_status": "pass" if not summary_df.empty and (summary_df["overall_status"] == "pass").all() else "fail",
    }
    return rows_df, summary_df, manifest


def _write_markdown(summary_df: pd.DataFrame, manifest: dict, out_path: Path) -> None:
    lines = [
        "# Saved-Parameter Replay Audit",
        "",
        f"Audit ID: `{manifest['audit_id']}`",
        "",
        "Purpose: verify whether the final conceptual benchmark artifacts remain valid under the current forward-model code.",
        "",
        f"Overall status: `{manifest['overall_status']}`",
        "",
        "| model | replay mode | n | n fail | n error | max abs NSE diff | saved median NSE | replay median NSE | status |",
        "|---|---|---:|---:|---:|---:|---:|---:|---|",
    ]
    for _, row in summary_df.iterrows():
        lines.append(
            f"| {row['model']} | {row['replay_mode']} | {int(row['n'])} | "
            f"{int(row['n_fail'])} | {int(row['n_error'])} | "
            f"{float(row['max_abs_nse_diff']):.9g} | {float(row['saved_median_nse']):.6f} | "
            f"{float(row['replay_median_nse']):.6f} | {row['overall_status']} |"
        )
    lines.extend([
        "",
        "Interpretation:",
        "- `saved_state` checks saved parameters plus saved eval-init state against the current simulation code.",
        "- `warmup_recomputed` checks saved parameters plus current warmup/data-loading logic against the current simulation code.",
        "- Passing replay supports artifact validity; it does not prove that model structures are fully equivalent.",
        "",
    ])
    out_path.write_text("\n".join(lines), encoding="utf-8")


def _build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--model", action="append", choices=["GR4J", "XAJ", "HBV"],
                   help="Model label to replay. Repeatable. Defaults to all three.")
    p.add_argument("--replay-mode", action="append", choices=list(REPLAY_MODES),
                   help="Replay mode. Repeatable. Defaults to both modes.")
    p.add_argument("--basin", action="append", default=None,
                   help="Restrict to an 8-digit basin id. Repeatable.")
    p.add_argument("--limit", type=int, default=None,
                   help="Restrict to the first N common successful basins after sorting.")
    p.add_argument("--data-root", default="data/camels_us")
    p.add_argument("--forcing", default=REPRO_FORCING)
    p.add_argument("--pet-method", choices=["oudin", "priestley_taylor"], default="priestley_taylor")
    p.add_argument("--tolerance", type=float, default=1e-6)
    p.add_argument("--out-dir", default=str(DEFAULT_OUT_DIR))
    p.add_argument("--allow-mismatch", action="store_true",
                   help="Return exit code 0 even if replay mismatches are found.")
    return p


def main(argv=None) -> int:
    args = _build_parser().parse_args(argv)
    models = args.model or ["GR4J", "XAJ", "HBV"]
    replay_modes = args.replay_mode or list(REPLAY_MODES)
    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    for var in ("OMP_NUM_THREADS", "MKL_NUM_THREADS", "OPENBLAS_NUM_THREADS", "NUMEXPR_NUM_THREADS"):
        os.environ.setdefault(var, "1")

    rows_df, summary_df, manifest = run_replay_audit(
        models=models,
        replay_modes=replay_modes,
        data_root=args.data_root,
        forcing=args.forcing,
        pet_method=args.pet_method,
        tolerance=args.tolerance,
        limit=args.limit,
        basins=args.basin,
    )
    rows_path = out_dir / "saved_parameter_replay_rows.csv"
    summary_path = out_dir / "saved_parameter_replay_summary.csv"
    manifest_path = out_dir / "MANIFEST.json"
    md_path = out_dir / "saved_parameter_replay_audit.md"
    rows_df.to_csv(rows_path, index=False)
    summary_df.to_csv(summary_path, index=False)
    manifest_path.write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    _write_markdown(summary_df, manifest, md_path)

    print()
    print(summary_df.to_string(index=False))
    print()
    print(f"Rows: {rows_path}")
    print(f"Summary: {summary_path}")
    print(f"Manifest: {manifest_path}")
    print(f"Memo: {md_path}")

    if manifest["overall_status"] != "pass" and not args.allow_mismatch:
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
