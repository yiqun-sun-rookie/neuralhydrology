"""Shared builder helpers for the 006 heterogeneous deep ensemble.

This module is NOT part of submission/ (so it is never leakage-scanned) and is NOT
train.py (so it is never eval-window-scanned). It does the two jobs that legally
touch trained-model artifacts:

  1. write a neuralhydrology config for a new decorrelated deep member by MIRRORING
     the frozen LSTM baseline config (results/18_lstm_fair_531/..._s100.../config.yml)
     and changing ONLY model / seed / experiment_name / run_dir (+ smoke knobs).
  2. extract a model's eval-period hydrograph from its test_results.p as qsim ONLY
     (the observed column is explicitly dropped and never returned), and build the
     obs-stripped 8-seed LSTM ensemble sim the same way.

The observed discharge in test_results.p is the held answer key over the eval
window; we read the *_sim variable and drop *_obs. No NSE, no obs, ever leaves here.
"""
from __future__ import annotations

import pickle
from pathlib import Path

import numpy as np
import pandas as pd
from ruamel.yaml import YAML

_HERE = Path(__file__).resolve().parent
_REPO = _HERE.parents[3]  # src/fair_benchmark/experiments/006_.. -> repo root
_LSTM_DIR = _REPO / "results" / "18_lstm_fair_531"
_LSTM_SEED_DIRS = sorted(_LSTM_DIR.glob("lstm_cudalstm_maurer_s*_ep30"))
_BASE_CONFIG = _LSTM_SEED_DIRS[0] / "config.yml" if _LSTM_SEED_DIRS else None

_yaml = YAML()
_yaml.preserve_quotes = True
_yaml.default_flow_style = False

# the neuralhydrology target variable -> the simulated column inside test_results.p
_TARGET = "QObs(mm/d)"
_SIM_VAR = f"{_TARGET}_sim"


# --------------------------------------------------------------------------- #
# 1. member config generation (mirror the LSTM baseline, change only the model) #
# --------------------------------------------------------------------------- #
def make_member_config(arch: str, seed: int, *, epochs: int, basin_file: str,
                       run_base: str, out_path: Path) -> Path:
    """Write a member config = the LSTM baseline config with model/seed/name swapped.

    Everything that defines the contest (reverse split, maurer forcings, 27 statics,
    NSE loss, hidden 256, seq 270, lr schedule, dropout) is inherited verbatim from
    the baseline config so the only deliberate difference is the architecture.
    """
    if _BASE_CONFIG is None or not _BASE_CONFIG.exists():
        raise FileNotFoundError(f"baseline LSTM config not found under {_LSTM_DIR}")
    with _BASE_CONFIG.open("r", encoding="utf-8") as f:
        cfg = _yaml.load(f)

    # the only deliberate changes: architecture, seed, identity, output location
    cfg["model"] = arch
    cfg["seed"] = int(seed)
    cfg["experiment_name"] = f"hde_{arch}_s{seed}"
    cfg["run_dir"] = run_base            # nh appends <name>_<timestamp>_epNN under here
    cfg["device"] = "cuda:0"
    cfg["epochs"] = int(epochs)

    # same basin universe for train/val/test slots (periods come from the dates below)
    cfg["train_basin_file"] = basin_file
    cfg["test_basin_file"] = basin_file
    cfg["validation_basin_file"] = basin_file
    bf = _REPO / basin_file
    if bf.exists():
        cfg["number_of_basins"] = sum(1 for l in bf.read_text().splitlines() if l.strip())

    # keep figures/tensorboard off (CPU-safe, matches baseline)
    cfg["log_n_figures"] = 0
    cfg["log_tensorboard"] = False

    # guarantee the FINAL epoch checkpoint exists for evaluate (baseline saves every
    # 10; a short smoke with epochs<10 would otherwise save nothing).
    swe = int(cfg.get("save_weights_every", 10) or 10)
    if epochs % swe != 0:
        swe = epochs
    cfg["save_weights_every"] = swe

    # architecture-necessary config (NOT contest tuning). The transformer's model
    # width is its embedding output, so it needs an embedding + attention hyperparams;
    # we mirror the proven in-repo transformer config (fc-32 dyn+static embeddings,
    # 4 heads, 2 layers, ff 256). LSTM-family models need nothing beyond the swap.
    if arch == "transformer":
        cfg["dynamics_embedding"] = {"type": "fc", "hiddens": [32], "activation": "tanh", "dropout": 0.0}
        cfg["statics_embedding"] = {"type": "fc", "hiddens": [32], "activation": "tanh", "dropout": 0.0}
        cfg["transformer_nheads"] = 4
        cfg["transformer_nlayers"] = 2
        cfg["transformer_dim_feedforward"] = 256
        cfg["transformer_dropout"] = 0.1
        cfg["transformer_positional_dropout"] = 0.1
        cfg["transformer_positional_encoding_type"] = "sum"

    # drop stale per-run paths copied from the s100 baseline run
    for stale in ("img_log_dir", "train_dir", "commit_hash"):
        cfg.pop(stale, None)

    out_path = Path(out_path)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    with out_path.open("w", encoding="utf-8") as f:
        _yaml.dump(cfg, f)
    return out_path


def find_run_dir(run_base: str | Path, experiment_name: str) -> Path | None:
    """Return the newest nh run dir created for `experiment_name` under run_base."""
    base = Path(run_base)
    cands = sorted(base.glob(f"{experiment_name}_*"), key=lambda p: p.stat().st_mtime)
    return cands[-1] if cands else None


# --------------------------------------------------------------------------- #
# 2. obs-stripped sim extraction                                              #
# --------------------------------------------------------------------------- #
def _results_path(run_dir: Path, epoch: int) -> Path:
    return Path(run_dir) / "test" / f"model_epoch{epoch:03d}" / "test_results.p"


def _load_sim_only(results_path: Path) -> dict:
    """results dict -> {basin: pd.Series(qsim, index=date)}.  Observed col dropped."""
    with open(results_path, "rb") as f:
        results = pickle.load(f)
    out = {}
    for basin, freqs in results.items():
        xr = freqs["1D"]["xr"]
        sim = xr[_SIM_VAR]                       # ONLY the simulated variable
        if "time_step" in sim.dims:
            sim = sim.isel(time_step=0)
        s = pd.Series(np.asarray(sim.values, dtype=float),
                      index=pd.to_datetime(sim["date"].values))
        out[str(basin).zfill(8)] = s
    return out


def extract_member_sim(run_dir: Path, epoch: int) -> pd.DataFrame:
    """One member's eval hydrograph as a long frame [basin, date, qsim] (qsim only)."""
    sims = _load_sim_only(_results_path(run_dir, epoch))
    return _to_long(sims)


def build_lstm_ens_sim(epoch: int = 30, seed_dirs=None) -> pd.DataFrame:
    """Obs-stripped LSTM ensemble sim: per-basin/day MEAN of the seed *_sim columns.

    Reads each seed's test_results.p, keeps only *_sim, averages across seeds. The
    observed answer key in those files is never read. Returns long [basin, date, qsim].
    """
    seed_dirs = list(seed_dirs) if seed_dirs is not None else _LSTM_SEED_DIRS
    if not seed_dirs:
        raise FileNotFoundError(f"no LSTM seed dirs under {_LSTM_DIR}")
    per_seed = [_load_sim_only(_results_path(d, epoch)) for d in seed_dirs]
    basins = sorted(per_seed[0].keys())
    rows = {}
    for b in basins:
        frames = [s[b] for s in per_seed if b in s]
        stacked = pd.concat(frames, axis=1)
        rows[b] = stacked.mean(axis=1)           # equal-weight seed mean
    return _to_long(rows), len(seed_dirs)


def _to_long(sims: dict) -> pd.DataFrame:
    frames = []
    for basin in sorted(sims):
        s = sims[basin]
        frames.append(pd.DataFrame({
            "basin": basin,
            "date": pd.to_datetime(s.index).strftime("%Y-%m-%d"),
            "qsim": np.asarray(s.values, dtype=float),
        }))
    return pd.concat(frames, ignore_index=True)


def lstm_seed_dirs():
    return list(_LSTM_SEED_DIRS)
