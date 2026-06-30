"""Train the new DECORRELATED deep members for the 006 heterogeneous deep ensemble.

Train side — allowed to read TRAIN-period observed discharge (via the standard
neuralhydrology supervised setup; the config restricts training to the reverse
split 1999-10-01..2008-09-30). For each requested seed this:

  1. writes a member config that MIRRORS the frozen LSTM baseline config, changing
     only the architecture / seed / identity (see lib.make_member_config);
  2. trains it on the GPU via `nh_run train`;
  3. runs `nh_run evaluate --period test` to produce the member's hydrograph;
  4. extracts that hydrograph as qsim ONLY (lib.extract_member_sim drops observed).

It then averages the member sims into model/deep_ens_sim.parquet, builds the
obs-stripped 8-seed LSTM ensemble sim into model/lstm_ens_sim.parquet, and writes
model/manifest.json (the blend recipe predict.py consumes). Idempotent: a member
whose test_results.p already exists is reused, so the job is resumable.

Config via env (defaults = the full production run):
    HDE_ARCH        architecture for the new members (default below)
    HDE_SEEDS       comma seeds, e.g. "100,200,300,400"
    HDE_EPOCHS      training epochs (default 30, mirrors baseline)
    HDE_BASIN_FILE  repo-relative basin file (default = the frozen 531 set)
    HDE_GPU         gpu id (default 0)
    HDE_SKIP_LSTM   if "1", do not (re)build lstm_ens_sim (smoke convenience)
"""
from __future__ import annotations

import json
import os
import subprocess
import sys
import time
from pathlib import Path

import lib  # local (same dir); not scanned for leakage

_HERE = Path(__file__).resolve().parent
_REPO = _HERE.parents[3]
_MODEL = _HERE / "model"
_CONFIGS = _HERE / "configs"
_RUN_BASE = "results/19_hetero_deep_ensemble"

# default = the full production run. Architecture chosen after the smoke test:
# Mamba has only the slow sequential fallback here (no CUDA kernels), and nh's
# custom-cell EA-LSTM is ~12x slower than fused cudalstm; the Transformer is a
# genuinely distinct function class that trains fast natively -> our decorrelated member.
DEFAULT_ARCH = "transformer"
DEFAULT_SEEDS = "100,200,300,400"
DEFAULT_BASIN_FILE = "src/fair_benchmark/frozen/track0_forcing_only_basins.txt"

ARCH = os.environ.get("HDE_ARCH", DEFAULT_ARCH)
SEEDS = [int(s) for s in os.environ.get("HDE_SEEDS", DEFAULT_SEEDS).split(",") if s.strip()]
EPOCHS = int(os.environ.get("HDE_EPOCHS", "30"))
BASIN_FILE = os.environ.get("HDE_BASIN_FILE", DEFAULT_BASIN_FILE)
GPU = os.environ.get("HDE_GPU", "0")
SKIP_LSTM = os.environ.get("HDE_SKIP_LSTM", "0") == "1"


def _run(cmd, label):
    print(f"[train] {label}: {' '.join(str(c) for c in cmd)}", flush=True)
    r = subprocess.run([str(c) for c in cmd], cwd=str(_REPO))
    if r.returncode != 0:
        raise SystemExit(f"[train] {label} FAILED (exit {r.returncode})")


def _member_results_exists(run_dir: Path) -> bool:
    return run_dir is not None and (run_dir / "test" / f"model_epoch{EPOCHS:03d}" / "test_results.p").exists()


def train_member(seed: int) -> Path:
    name = f"hde_{ARCH}_s{seed}"
    cfg_path = lib.make_member_config(
        ARCH, seed, epochs=EPOCHS, basin_file=BASIN_FILE,
        run_base=_RUN_BASE, out_path=_CONFIGS / f"member_{ARCH}_s{seed}.yml")

    run_dir = lib.find_run_dir(_REPO / _RUN_BASE, name)
    if _member_results_exists(run_dir):
        print(f"[train] reuse existing member {name} -> {run_dir}", flush=True)
        return run_dir

    if run_dir is None or not (run_dir / f"model_epoch{EPOCHS:03d}.pt").exists():
        _run([sys.executable, "-m", "neuralhydrology.nh_run", "train",
              "--config-file", cfg_path, "--gpu", GPU], f"train {name}")
        run_dir = lib.find_run_dir(_REPO / _RUN_BASE, name)
        if run_dir is None:
            raise SystemExit(f"[train] could not locate run dir for {name} after training")

    _run([sys.executable, "-m", "neuralhydrology.nh_run", "evaluate",
          "--run-dir", run_dir, "--period", "test", "--epoch", str(EPOCHS), "--gpu", GPU],
         f"evaluate {name}")
    return run_dir


def _rebuild_artifacts(member_dirs: dict):
    """Build deep_ens_sim.parquet + lstm_ens_sim.parquet + manifest.json from the
    members completed so far. Called after EACH seed so a killed run stays scorable."""
    import pandas as pd
    done = {s: d for s, d in member_dirs.items()
            if _member_results_exists(Path(d))}
    if not done:
        return 0, 0
    per_member = [lib.extract_member_sim(Path(d), EPOCHS) for d in done.values()]
    deep = per_member[0].rename(columns={"qsim": "q0"})[["basin", "date", "q0"]]
    for i, df in enumerate(per_member[1:], 1):
        deep = deep.merge(df.rename(columns={"qsim": f"q{i}"}), on=["basin", "date"], how="outer")
    qcols = [c for c in deep.columns if c.startswith("q")]
    deep["qsim"] = deep[qcols].mean(axis=1)
    deep_out = deep[["basin", "date", "qsim"]].sort_values(["basin", "date"]).reset_index(drop=True)
    deep_out.to_parquet(_MODEL / "deep_ens_sim.parquet", index=False)

    n_lstm = 0
    if not SKIP_LSTM:
        if (_MODEL / "lstm_ens_sim.parquet").exists():
            n_lstm = 8  # the committed obs-stripped 8-seed LSTM ensemble sim
        else:
            lstm_long, n_lstm = lib.build_lstm_ens_sim(epoch=30)
            lstm_long.sort_values(["basin", "date"]).reset_index(drop=True).to_parquet(
                _MODEL / "lstm_ens_sim.parquet", index=False)

    manifest = {
        "arch": ARCH, "seeds": SEEDS, "epochs": EPOCHS,
        "n_deep": len(done), "n_lstm": n_lstm,
        "blend": "equal-weight mean over all members (n_lstm LSTM + n_deep deep)",
        "member_run_dirs": {str(s): d for s, d in done.items()},
        "basin_file": BASIN_FILE,
    }
    (_MODEL / "manifest.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    print(f"[train] artifacts: n_deep={len(done)} n_lstm={n_lstm} "
          f"deep_basins={deep_out['basin'].nunique()}", flush=True)
    return len(done), n_lstm


def main():
    t0 = time.time()
    _MODEL.mkdir(parents=True, exist_ok=True)
    print(f"[train] arch={ARCH} seeds={SEEDS} epochs={EPOCHS} basins={BASIN_FILE}", flush=True)

    member_dirs = {}
    for seed in SEEDS:
        member_dirs[seed] = str(train_member(seed))
        _rebuild_artifacts(member_dirs)   # refresh after each seed (partial-safe)

    print(f"[train] DONE ({time.time()-t0:.0f}s total)", flush=True)


if __name__ == "__main__":
    main()
