"""M2: Run random noise baselines 10 times with different seeds to assess stability.

Usage:
    python src/adversarial/scripts/run_random_repeats.py \
        --config src/adversarial/configs/eval_final_with_static.yaml \
        --n-repeats 10 \
        --output results/adversarial_eval/final_with_static/random_repeats.json
"""
from __future__ import annotations

import argparse
import json
import logging
import sys
import time
from pathlib import Path

import numpy as np
import torch
import yaml

_project_root = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(_project_root))

from src.adversarial.model_wrapper import CudaLSTMWrapper
from src.adversarial.attacks import ATTACK_REGISTRY
from src.adversarial.constraints import LpConstraint
from src.adversarial.evaluation.metrics import compute_nse, delta_nse
from src.adversarial.data_loader import load_basin_data

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
logger = logging.getLogger(__name__)

RANDOM_ATTACKS = ["gaussian_noise", "multiplicative_bias", "temporal_correlated_noise"]


def main():
    parser = argparse.ArgumentParser(description="Random noise stability assessment")
    parser.add_argument("--config", required=True)
    parser.add_argument("--n-repeats", type=int, default=10)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()

    with open(args.config) as f:
        cfg = yaml.safe_load(f)

    run_dir = _project_root / cfg["model"]["run_dir"]
    data_dir = _project_root / cfg["data"]["data_dir"] if cfg["data"].get("data_dir") else None
    device = "cpu"  # Force CPU for local runs
    epsilon = 0.1

    wrapper = CudaLSTMWrapper(run_dir=run_dir, device=device)
    constraint = LpConstraint(epsilon=epsilon, norm="linf")

    basin_file = _project_root / "src" / "adversarial" / "data" / "531_basins.txt"
    with open(basin_file) as f:
        basins = [line.strip() for line in f if line.strip()]
    logger.info("Loaded %d basins", len(basins))

    all_results = []
    t_start = time.time()

    for bi, basin_id in enumerate(basins):
        if (bi + 1) % 50 == 0:
            elapsed = time.time() - t_start
            rate = (bi + 1) / elapsed
            eta = (len(basins) - bi - 1) / rate
            logger.info("Basin %d/%d (%.1f basins/s, ETA %.0fs)", bi + 1, len(basins), rate, eta)

        try:
            x_d, x_s, y_obs = load_basin_data(
                run_dir=run_dir, basin_id=basin_id, period="test",
                device=device, data_dir=data_dir,
            )
        except Exception as e:
            logger.warning("Skipping basin %s: %s", basin_id, e)
            continue

        # Select a representative sample
        sample_idx = 0
        N = x_d.shape[0]
        for idx in range(N):
            y = y_obs[idx].squeeze(-1)
            mask = ~y.isnan()
            if mask.sum() > 100 and y[mask].std() > 0.1:
                sample_idx = idx
                break

        x_d1 = x_d[sample_idx:sample_idx + 1]
        x_s1 = x_s[sample_idx:sample_idx + 1]
        y_obs1 = y_obs[sample_idx:sample_idx + 1]

        with torch.no_grad():
            y_clean = wrapper.forward(x_d1, x_s1)

        # Replace NaN in y_obs with y_clean so the attack loss doesn't produce NaN
        y_obs_filled = y_obs1.clone()
        nan_mask = y_obs_filled.isnan()
        if nan_mask.any():
            y_obs_filled[nan_mask] = y_clean.detach()[nan_mask]

        for attack_name in RANDOM_ATTACKS:
            for seed_i in range(args.n_repeats):
                seed = seed_i + 1
                attack_cls = ATTACK_REGISTRY[attack_name]
                attack = attack_cls(
                    model=wrapper, constraint=constraint,
                    target="untargeted", epsilon=epsilon,
                    n_samples=1, seed=seed,
                )

                x_adv = attack.attack(x_d1, x_s1, y_obs_filled)
                with torch.no_grad():
                    y_adv = wrapper.forward(x_adv, x_s1)

                y_o = y_obs1.squeeze(-1).flatten()
                y_c = y_clean.squeeze(-1).flatten()
                y_a = y_adv.squeeze(-1).flatten()
                mask = ~y_o.isnan()

                nse_c = compute_nse(y_o[mask], y_c[mask])
                d_nse = delta_nse(y_o[mask], y_c[mask], y_a[mask])

                all_results.append({
                    "attack": attack_name,
                    "basin": basin_id,
                    "seed": seed,
                    "nse_clean": nse_c,
                    "delta_nse": d_nse,
                })

    elapsed_total = time.time() - t_start
    logger.info("Done: %d records in %.1fs", len(all_results), elapsed_total)

    # Save results
    output_path = Path(args.output)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    with open(output_path, "w") as f:
        json.dump(all_results, f, indent=2)

    # Print summary
    import pandas as pd
    df = pd.DataFrame(all_results)
    print("\n" + "=" * 70)
    print("Random Noise Stability Assessment (10 seeds, eps=0.1)")
    print("=" * 70)
    for atk in RANDOM_ATTACKS:
        sub = df[df["attack"] == atk]
        # Per-seed median
        seed_medians = sub.groupby("seed")["delta_nse"].median()
        overall_med = sub["delta_nse"].median()
        print(f"\n{atk}:")
        print(f"  Overall median dNSE: {overall_med:.4f}")
        print(f"  Per-seed medians: mean={seed_medians.mean():.4f}, std={seed_medians.std():.4f}")
        print(f"  Range: [{seed_medians.min():.4f}, {seed_medians.max():.4f}]")
        # Per-basin std
        basin_std = sub.groupby("basin")["delta_nse"].std()
        print(f"  Per-basin std: median={basin_std.median():.4f}, mean={basin_std.mean():.4f}")


if __name__ == "__main__":
    main()
