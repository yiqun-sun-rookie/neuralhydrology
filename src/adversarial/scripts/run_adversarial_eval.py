"""Main entry point for adversarial evaluation experiments."""
from __future__ import annotations

import argparse
import json
import logging
import sys
import time
from pathlib import Path

import torch
import yaml

# Ensure src/ is on path
_project_root = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(_project_root))

from src.adversarial.model_wrapper import CudaLSTMWrapper
from src.adversarial.attacks import ATTACK_REGISTRY
from src.adversarial.constraints import LpConstraint, PhysicalConstraint, StatisticalConstraint
from src.adversarial.evaluation.metrics import (
    compute_nse, compute_kge, delta_nse,
    detectability_ks, peak_error,
)
from src.adversarial.data_loader import load_basin_data

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
        sc = scaler.get("xarray_feature_center")
        ss = scaler.get("xarray_feature_scale")
        if sc is not None and feat in sc:
            center[i] = float(sc[feat].values)
        if ss is not None and feat in ss:
            scale[i] = float(ss[feat].values)

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
    """Run one attack on a single basin sample and return metrics dict."""
    x_d_adv = attack.attack(x_d, x_s, y_obs)
    with torch.no_grad():
        y_adv = wrapper.forward(x_d_adv, x_s)

    y_obs_flat = y_obs.squeeze(-1).flatten()
    y_clean_flat = y_clean.squeeze(-1).flatten()
    y_adv_flat = y_adv.squeeze(-1).flatten()

    # Filter NaN observations
    mask = ~y_obs_flat.isnan()
    y_o = y_obs_flat[mask]
    y_c = y_clean_flat[mask]
    y_a = y_adv_flat[mask]

    return {
        "nse_clean": compute_nse(y_o, y_c),
        "nse_adv": compute_nse(y_o, y_a),
        "delta_nse": delta_nse(y_o, y_c, y_a),
        "kge_clean": compute_kge(y_o, y_c),
        "kge_adv": compute_kge(y_o, y_a),
        "peak_error": peak_error(y_o, y_a, quantile=0.9),
        "detectability_ks": detectability_ks(x_d.flatten(), x_d_adv.flatten()),
        "l_inf": float((x_d_adv - x_d).abs().max()),
        "l2": float((x_d_adv - x_d).reshape(1, -1).norm(dim=1).mean()),
    }


def select_basin_samples(x_d, x_s, y_obs, n_samples: int = 5, seed: int = 42):
    """Select representative samples from a basin's test data.

    Picks samples with sufficient y_obs variance (non-degenerate).
    """
    torch.manual_seed(seed)
    N = x_d.shape[0]
    indices = torch.randperm(N)

    selected = []
    for idx in indices:
        y = y_obs[idx].squeeze(-1)
        mask = ~y.isnan()
        if mask.sum() > 100 and y[mask].std() > 0.1:
            selected.append(int(idx))
            if len(selected) >= n_samples:
                break

    if not selected:
        selected = [0]

    return selected


def _prepare_attack_sweep(cfg, attack_name):
    """Extract sweep parameters and base kwargs for an attack.

    Returns (base_kwargs, pre_windows, freq_bands_list, frac).
    """
    attack_cfg = dict(cfg["attacks"].get(attack_name, {}))

    # Handle special sweep parameters
    if attack_name == "causal_trigger":
        pre_windows = attack_cfg.pop("pre_windows", [7])
    else:
        pre_windows = [None]

    if attack_name == "spectral":
        freq_bands_list = attack_cfg.pop("freq_bands", ["all"])
    else:
        freq_bands_list = [None]

    if attack_name == "sparse_temporal":
        frac = attack_cfg.pop("max_steps_fraction", 0.05)
    else:
        frac = None

    # Remove non-constructor keys
    for key in ("pre_windows", "freq_bands", "max_steps_fraction"):
        attack_cfg.pop(key, None)

    return attack_cfg, pre_windows, freq_bands_list, frac


def _save_results(all_results, results_file):
    """Write results list to JSON file."""
    with open(results_file, "w") as f:
        json.dump(all_results, f, indent=2)
    logger.info(f"Saved {len(all_results)} results to {results_file}")


def main():
    parser = argparse.ArgumentParser(description="Adversarial evaluation of CudaLSTM")
    parser.add_argument("--config", default="src/adversarial/configs/adversarial_eval.yaml")
    parser.add_argument("--attack", default=None, help="Run specific attack only")
    parser.add_argument("--epsilon", type=float, default=None, help="Single epsilon")
    parser.add_argument("--constraint", default=None, help="Single constraint level")
    parser.add_argument("--target", default=None, help="Single attack target")
    parser.add_argument("--basin", default=None, help="Single basin ID")
    parser.add_argument("--basin-file", default=None, help="Text file with basin IDs (one per line)")
    parser.add_argument("--basin-range", default=None, help="START:END index range for chunked execution")
    parser.add_argument("--output-suffix", default=None, help="Custom suffix for output filename")
    parser.add_argument("--n-samples", type=int, default=1, help="Samples per basin")
    parser.add_argument("--dry-run", action="store_true", help="Print config and exit")
    args = parser.parse_args()

    cfg = load_config(args.config)
    output_dir = _project_root / cfg["output_dir"]
    output_dir.mkdir(parents=True, exist_ok=True)

    run_dir = _project_root / cfg["model"]["run_dir"]
    data_dir = _project_root / cfg["data"]["data_dir"] if cfg["data"].get("data_dir") else None
    device = cfg["model"]["device"]

    attacks_to_run = [args.attack] if args.attack else list(cfg["attacks"].keys())
    epsilons = [args.epsilon] if args.epsilon else cfg["epsilons"]
    constraints = [args.constraint] if args.constraint else cfg["constraint_levels"]
    targets = [args.target] if args.target else cfg["targets"]

    # Basin resolution: --basin > --basin-file > config YAML list
    if args.basin:
        basins = [args.basin]
    elif args.basin_file:
        with open(args.basin_file) as f:
            basins = [line.strip() for line in f if line.strip()]
    else:
        basins = cfg["data"]["basins"]

    # Apply range filter for chunked execution
    if args.basin_range:
        start, end = map(int, args.basin_range.split(":"))
        basins = basins[start:end]

    # Count experiments accounting for sweep parameters (pre_windows, freq_bands)
    n_experiments = 0
    for atk in attacks_to_run:
        _, pre_w, fb, _ = _prepare_attack_sweep(cfg, atk)
        n_experiments += len(pre_w) * len(fb) * len(epsilons) * len(constraints) * len(targets) * len(basins)
    logger.info(f"Experiment matrix: {len(attacks_to_run)} attacks x {len(epsilons)} eps x "
                f"{len(constraints)} constraints x {len(targets)} targets x {len(basins)} basins "
                f"= {n_experiments} experiments (incl. sweep params)")

    if args.dry_run:
        logger.info("Dry run — exiting.")
        return

    # Determine output file path
    if args.output_suffix:
        results_file = output_dir / f"results_{args.output_suffix}.json"
    else:
        results_file = output_dir / "results.json"

    logger.info("Loading CudaLSTM model...")
    wrapper = CudaLSTMWrapper(run_dir=run_dir, device=device)

    # Pre-compute attack sweep parameters (shared across basins)
    attack_sweeps = {}
    for attack_name in attacks_to_run:
        attack_sweeps[attack_name] = _prepare_attack_sweep(cfg, attack_name)

    all_results = []
    n_done = 0

    # Outer loop: iterate over basins (load one at a time to save memory)
    for basin_idx, basin_id in enumerate(basins):
        logger.info(f"Loading basin {basin_id} ({basin_idx + 1}/{len(basins)})...")
        x_d, x_s, y_obs = load_basin_data(
            run_dir=run_dir, basin_id=basin_id, period="test",
            device=device, data_dir=data_dir,
        )
        sample_indices = select_basin_samples(x_d, x_s, y_obs, n_samples=args.n_samples)

        # Pre-compute clean predictions for this basin
        with torch.no_grad():
            y_cleans = {i: wrapper.forward(x_d[i:i+1], x_s[i:i+1]) for i in sample_indices}
        logger.info(f"  {basin_id}: {len(sample_indices)} samples selected")

        # Inner loop: iterate over attacks x epsilons x constraints x targets
        for attack_name in attacks_to_run:
            attack_cfg, pre_windows, freq_bands_list, frac = attack_sweeps[attack_name]

            for epsilon in epsilons:
                for constraint_level in constraints:
                    constraint = build_constraint(constraint_level, epsilon, wrapper)

                    for target_name in targets:
                        for pre_w in pre_windows:
                            for freq_band in freq_bands_list:
                                # Build attack
                                kwargs = dict(attack_cfg)
                                kwargs.update(model=wrapper, constraint=constraint,
                                              target=target_name, epsilon=epsilon)
                                if attack_name == "causal_trigger" and pre_w is not None:
                                    kwargs["pre_window"] = pre_w
                                if attack_name == "spectral" and freq_band is not None:
                                    kwargs["freq_bands"] = freq_band
                                if attack_name == "sparse_temporal" and frac is not None:
                                    kwargs["max_steps"] = max(1, int(365 * frac))

                                attack = ATTACK_REGISTRY[attack_name](**kwargs)

                                for sample_idx in sample_indices:
                                    x_d1 = x_d[sample_idx:sample_idx+1]
                                    x_s1 = x_s[sample_idx:sample_idx+1]
                                    y_obs1 = y_obs[sample_idx:sample_idx+1]
                                    y_clean1 = y_cleans[sample_idx]

                                    t0 = time.time()
                                    result = run_single_experiment(
                                        attack, wrapper, x_d1, x_s1, y_obs1, y_clean1,
                                    )
                                    elapsed = time.time() - t0

                                    record = {
                                        "attack": attack_name,
                                        "epsilon": epsilon,
                                        "constraint": constraint_level,
                                        "target": target_name,
                                        "basin": basin_id,
                                        "sample_idx": sample_idx,
                                        "time_s": round(elapsed, 3),
                                    }
                                    if pre_w is not None:
                                        record["pre_window"] = pre_w
                                    if freq_band is not None:
                                        record["freq_band"] = freq_band
                                    record.update(result)
                                    all_results.append(record)

                                n_done += 1
                                if n_done % 10 == 0:
                                    logger.info(f"Progress: {n_done}/{n_experiments}")

        # Free basin data after processing
        del x_d, x_s, y_obs, sample_indices, y_cleans

        # Incremental checkpoint: save every 10 basins
        if (basin_idx + 1) % 10 == 0:
            _save_results(all_results, results_file)
            logger.info(f"Checkpoint saved after {basin_idx + 1} basins")

    # Final save
    _save_results(all_results, results_file)


if __name__ == "__main__":
    main()
