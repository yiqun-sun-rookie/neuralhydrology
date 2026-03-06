"""Main entry point for adversarial evaluation experiments."""
from __future__ import annotations

import argparse
import json
import logging
import sys
from pathlib import Path

import torch
import yaml

# Ensure src/ is on path
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from src.adversarial.model_wrapper import CudaLSTMWrapper
from src.adversarial.attacks import ATTACK_REGISTRY
from src.adversarial.constraints import LpConstraint, PhysicalConstraint, StatisticalConstraint
from src.adversarial.evaluation.metrics import (
    compute_nse, compute_kge, delta_nse, attack_success_rate,
    detectability_ks, peak_error,
)

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
logger = logging.getLogger(__name__)


def load_config(path: str) -> dict:
    with open(path) as f:
        return yaml.safe_load(f)


def build_constraint(level: str, epsilon: float, wrapper: CudaLSTMWrapper):
    """Build constraint object for given level."""
    if level == "lp":
        return LpConstraint(epsilon=epsilon, norm="linf")

    scaler = wrapper.get_scaler()
    center = torch.zeros(wrapper.n_dynamic)
    scale = torch.ones(wrapper.n_dynamic)
    for i, feat in enumerate(wrapper.dynamic_features):
        if hasattr(scaler, 'get'):
            center[i] = float(scaler.get("xarray_feature_center", {}).get(feat, 0.0))
            scale[i] = float(scaler.get("xarray_feature_scale", {}).get(feat, 1.0))

    if level == "physical":
        return PhysicalConstraint(epsilon=epsilon,
                                   feature_names=wrapper.dynamic_features,
                                   scaler_center=center, scaler_scale=scale)
    elif level == "statistical":
        return StatisticalConstraint(epsilon=epsilon,
                                      feature_names=wrapper.dynamic_features,
                                      scaler_center=center, scaler_scale=scale)
    raise ValueError(f"Unknown constraint level: {level}")


def run_single_experiment(attack, wrapper, x_d, x_s, y_obs, y_clean):
    """Run one attack and return metrics dict."""
    x_d_adv = attack.attack(x_d, x_s, y_obs)
    with torch.no_grad():
        y_adv = wrapper.forward(x_d_adv, x_s)

    y_obs_flat = y_obs.squeeze(-1).flatten()
    y_clean_flat = y_clean.squeeze(-1).flatten()
    y_adv_flat = y_adv.squeeze(-1).flatten()

    return {
        "nse_clean": compute_nse(y_obs_flat, y_clean_flat),
        "nse_adv": compute_nse(y_obs_flat, y_adv_flat),
        "delta_nse": delta_nse(y_obs_flat, y_clean_flat, y_adv_flat),
        "kge_clean": compute_kge(y_obs_flat, y_clean_flat),
        "kge_adv": compute_kge(y_obs_flat, y_adv_flat),
        "peak_error": peak_error(y_obs_flat, y_adv_flat, quantile=0.9),
        "detectability_ks": detectability_ks(x_d.flatten(), x_d_adv.flatten()),
        "l_inf": float((x_d_adv - x_d).abs().max()),
        "l2": float((x_d_adv - x_d).reshape(1, -1).norm(dim=1).mean()),
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", default="src/adversarial/configs/adversarial_eval.yaml")
    parser.add_argument("--attack", default=None, help="Run specific attack only")
    parser.add_argument("--epsilon", type=float, default=None, help="Single epsilon")
    args = parser.parse_args()

    cfg = load_config(args.config)
    output_dir = Path(cfg["output_dir"])
    output_dir.mkdir(parents=True, exist_ok=True)

    logger.info("Loading CudaLSTM model...")
    wrapper = CudaLSTMWrapper(
        run_dir=Path(cfg["model"]["run_dir"]),
        device=cfg["model"]["device"],
    )

    attacks_to_run = [args.attack] if args.attack else list(cfg["attacks"].keys())
    epsilons = [args.epsilon] if args.epsilon else cfg["epsilons"]

    all_results = []

    for attack_name in attacks_to_run:
        for epsilon in epsilons:
            for constraint_level in cfg["constraint_levels"]:
                for target in cfg["targets"]:
                    logger.info(f"Running {attack_name} | eps={epsilon} | "
                                f"{constraint_level} | {target}")

                    constraint = build_constraint(constraint_level, epsilon, wrapper)
                    attack_cls = ATTACK_REGISTRY[attack_name]
                    attack_kwargs = dict(cfg["attacks"].get(attack_name, {}))
                    # Remove keys that need special handling
                    for key in ("pre_windows", "freq_bands", "max_steps_fraction"):
                        attack_kwargs.pop(key, None)
                    attack = attack_cls(
                        model=wrapper, constraint=constraint,
                        target=target, epsilon=epsilon,
                        **attack_kwargs,
                    )

                    # TODO: iterate over basins + data batches
                    # For each basin:
                    #   x_d, x_s, y_obs = load_basin_data(...)
                    #   y_clean = wrapper.forward(x_d, x_s)
                    #   result = run_single_experiment(attack, wrapper, x_d, x_s, y_obs, y_clean)
                    #   all_results.append({...})

    results_file = output_dir / "results.json"
    with open(results_file, "w") as f:
        json.dump(all_results, f, indent=2)
    logger.info(f"Results saved to {results_file}")


if __name__ == "__main__":
    main()
