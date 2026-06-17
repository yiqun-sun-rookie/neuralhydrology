"""Train N seeds of a given base config (resumable: skips seeds already trained),
evaluate each on test, then build the seed-ensemble and report its NSE.

Faithful to Kratzert 2019: 8-seed mean ensemble. Single-seed already reproduces
Kratzert single (~0.731); the ensemble approaches the headline (~0.758 cudalstm+static).

Usage:
  python -X utf8 -m src.lstm_fair_531.scripts.run_seed_ensemble \
    --base-config src/lstm_fair_531/configs/lstm_cudalstm_maurer_531_s100.yml \
    --seeds 100 200 300 400 500 600 700 800 \
    --tag cudalstm_maurer

Notes: seed 100 run already exists; this skips it. Runs sequentially (safe on one GPU).
"""
import argparse
import subprocess
import sys
from pathlib import Path

import yaml


def find_run_dir(run_root: Path, exp_name: str):
    cands = sorted(run_root.glob(f"{exp_name}_*"), key=lambda p: p.stat().st_mtime)
    return cands[-1] if cands else None


def has_test_metrics(run_dir: Path):
    return run_dir is not None and any(run_dir.glob("test/model_epoch*/test_metrics.csv"))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--base-config", required=True)
    ap.add_argument("--seeds", nargs="+", type=int, required=True)
    ap.add_argument("--tag", default="ens")
    ap.add_argument("--epochs", type=int, default=None, help="override epochs (default: keep config)")
    ap.add_argument("--no-ensemble", action="store_true", help="train+eval only, skip ensemble step")
    ap.add_argument("--num-workers", type=int, default=None, help="override num_workers in generated configs")
    args = ap.parse_args()

    base = yaml.safe_load(Path(args.base_config).read_text())
    run_root = Path(base["run_dir"])
    base_exp = base["experiment_name"].rsplit("_s", 1)[0]  # strip _s100 -> base
    epochs = args.epochs or base["epochs"]

    run_dirs = []
    for seed in args.seeds:
        exp = f"{base_exp}_s{seed}"
        existing = find_run_dir(run_root, exp)
        if has_test_metrics(existing):
            print(f"[skip] seed {seed}: already trained+evaluated -> {existing}")
            run_dirs.append(existing)
            continue
        # write a per-seed config
        cfg = dict(base)
        cfg["seed"] = seed
        cfg["experiment_name"] = exp
        cfg["epochs"] = epochs
        if args.num_workers is not None:
            cfg["num_workers"] = args.num_workers
        cfg_path = Path(args.base_config).parent / f"_gen_{exp}.yml"
        cfg_path.write_text(yaml.safe_dump(cfg, sort_keys=False, allow_unicode=True))
        print(f"\n[train] seed {seed} -> {cfg_path}")
        r = subprocess.run([sys.executable, "-X", "utf8", "-m", "neuralhydrology.nh_run",
                            "train", "--config-file", str(cfg_path)])
        if r.returncode != 0:
            print(f"[ERROR] training seed {seed} failed (exit {r.returncode}); stopping.")
            sys.exit(1)
        rd = find_run_dir(run_root, exp)
        print(f"[eval] seed {seed} -> {rd}")
        r = subprocess.run([sys.executable, "-X", "utf8", "-m", "neuralhydrology.nh_run",
                            "evaluate", "--run-dir", str(rd), "--period", "test", "--epoch", str(epochs)])
        if r.returncode != 0:
            print(f"[ERROR] eval seed {seed} failed; stopping.")
            sys.exit(1)
        run_dirs.append(rd)

    if args.no_ensemble:
        print(f"\n[train-only] done; {len(run_dirs)} seed run dirs ready (ensemble skipped).")
        return

    # ---- build ensemble ----
    print(f"\n[ensemble] {len(run_dirs)} seeds")
    from neuralhydrology.utils.nh_results_ensemble import create_results_ensemble
    # NOTE: must pass Path objects (not str) — create_results_ensemble does run_dirs[0] / 'config.yml'
    ens = create_results_ensemble([Path(d) for d in run_dirs], metrics=["NSE"], period="test")
    import numpy as np
    nses = []
    for basin, freqs in ens.items():
        for freq, xr in freqs.items():
            v = xr["NSE"] if "NSE" in xr else None
            try:
                nses.append(float(v))
            except Exception:
                pass
    nses = np.array([x for x in nses if np.isfinite(x)])
    out = run_root / "_reports" / f"ensemble_{args.tag}_{len(run_dirs)}seed.txt"
    out.parent.mkdir(parents=True, exist_ok=True)
    msg = (f"ensemble {args.tag} ({len(run_dirs)} seeds) test NSE: "
           f"median={np.median(nses):.4f} mean={np.mean(nses):.4f} n={len(nses)}\n"
           f"run_dirs:\n" + "\n".join(str(d) for d in run_dirs) + "\n")
    out.write_text(msg)
    print(msg)
    print(f"wrote {out}")
    # also dump per-basin ensemble NSE for the comparison script
    import pandas as pd
    rows = []
    for basin, freqs in ens.items():
        for freq, xr in freqs.items():
            try:
                rows.append((basin, float(xr["NSE"])))
            except Exception:
                rows.append((basin, np.nan))
    pd.DataFrame(rows, columns=["basin", "NSE"]).to_csv(
        run_root / "_reports" / f"ensemble_{args.tag}_{len(run_dirs)}seed_per_basin.csv", index=False)


if __name__ == "__main__":
    main()
