#!/usr/bin/env python
"""
Experiment Runner - Train, Evaluate, and Record Results

Usage:
    # Quick run: generate config + validate + train + evaluate
    python src/namou_kuwei/scripts/run_experiment.py quick --site namou_kuwei --type ar --lead 1
    
    # Run a single experiment
    python src/namou_kuwei/scripts/run_experiment.py train --config src/namou_kuwei/configs/no_leak/03_with_ar/rain_ar_LT1h.yml
    
    # Evaluate existing run
    python src/namou_kuwei/scripts/run_experiment.py evaluate --run-dir results/04_namou_kuwei/L3_Rain_AR_LT1h_2025_1204_...
    
    # Compare all runs
    python src/namou_kuwei/scripts/run_experiment.py compare --results-dir results/04_namou_kuwei
"""
import argparse
import subprocess
import sys
from pathlib import Path
import pandas as pd
import yaml
from datetime import datetime


def run_train(config_path: str, device: str = None):
    """Run training with validation."""
    # First validate config
    result = subprocess.run(
        [sys.executable, "src/namou_kuwei/scripts/validate_config.py", config_path],
        capture_output=True, text=True
    )
    if result.returncode != 0:
        print("Config validation failed:")
        print(result.stdout)
        print(result.stderr)
        return None
    
    # Run training
    cmd = [sys.executable, "-m", "neuralhydrology.nh_run", "train", "--config-file", config_path]
    if device:
        cmd.extend(["--device", device])
    
    print(f"Starting training: {config_path}")
    result = subprocess.run(cmd)
    return result.returncode == 0


def run_evaluate(run_dir: str, period: str = "test"):
    """Run evaluation on a trained model."""
    cmd = [sys.executable, "-m", "neuralhydrology.nh_run", "evaluate", "--run-dir", run_dir]
    if period:
        cmd.extend(["--period", period])
    
    print(f"Evaluating: {run_dir}")
    result = subprocess.run(cmd)
    return result.returncode == 0


def run_quick(site: str, config_type: str, lead: int, predict_steps: int = 1, device: str = None):
    """Generate config + validate + train + evaluate in one go."""
    from gen_config import generate_config, save_config
    from pathlib import Path
    
    # 1. Generate config
    print(f"\n[1/4] Generating config: site={site}, type={config_type}, lead={lead}h")
    cfg = generate_config(
        site_name=site,
        config_type=config_type,
        lead_time=lead,
        predict_steps=predict_steps,
    )
    
    output_dir = Path(__file__).resolve().parents[1] / "configs" / "generated"
    output_path = output_dir / f"{cfg['experiment_name']}.yml"
    save_config(cfg, output_path)
    
    # 2. Validate
    print(f"\n[2/4] Validating config...")
    result = subprocess.run(
        [sys.executable, "src/namou_kuwei/scripts/validate_config.py", str(output_path)],
        capture_output=True, text=True
    )
    print(result.stdout)
    if result.returncode != 0:
        print("Validation failed. Aborting.")
        return False
    
    # 3. Train
    print(f"\n[3/4] Training...")
    cmd = [sys.executable, "-m", "neuralhydrology.nh_run", "train", "--config-file", str(output_path)]
    result = subprocess.run(cmd)
    if result.returncode != 0:
        print("Training failed.")
        return False
    
    # 4. Find latest run and evaluate
    print(f"\n[4/4] Evaluating...")
    results_dir = Path(cfg["run_dir"])
    runs = sorted([d for d in results_dir.iterdir() if d.is_dir() and cfg["experiment_name"] in d.name], 
                  key=lambda x: x.stat().st_mtime, reverse=True)
    if runs:
        run_dir = runs[0]
        cmd = [sys.executable, "-m", "neuralhydrology.nh_run", "evaluate", "--run-dir", str(run_dir)]
        subprocess.run(cmd)
        
        # Print results
        metrics = extract_metrics(run_dir)
        if metrics:
            print(f"\n{'='*40}")
            print(f"Results: {run_dir.name}")
            for k, v in metrics.items():
                print(f"  {k}: {v:.4f}")
            print(f"{'='*40}")
    
    return True


def compare_results(results_dir: str, metric: str = "NSE"):
    """Compare results across all runs in a directory."""
    results_path = Path(results_dir)
    runs = []
    
    for run_dir in sorted(results_path.iterdir()):
        if not run_dir.is_dir():
            continue
        
        # Look for test metrics
        metrics_file = run_dir / "test" / "model_epoch060" / "test_metrics.csv"
        if not metrics_file.exists():
            metrics_file = run_dir / "test_metrics.csv"
        if not metrics_file.exists():
            continue
        
        try:
            df = pd.read_csv(metrics_file)
            if metric in df.columns:
                runs.append({
                    "Experiment": run_dir.name.split("_2025")[0],
                    "Run Dir": run_dir.name,
                    metric: df[metric].mean() if len(df) > 1 else df[metric].iloc[0]
                })
        except Exception as e:
            print(f"Warning: Could not read {metrics_file}: {e}")
    
    if runs:
        comparison = pd.DataFrame(runs)
        comparison = comparison.sort_values(metric, ascending=False)
        print(f"\n{'='*60}")
        print(f"Results Comparison ({metric})")
        print(f"{'='*60}")
        print(comparison.to_string(index=False))
        return comparison
    else:
        print("No results found")
        return None


def extract_metrics(run_dir: Path) -> dict:
    """Extract metrics from a run directory."""
    metrics = {}
    
    # Check various possible locations
    possible_paths = [
        run_dir / "test" / "model_epoch060" / "test_metrics.csv",
        run_dir / "test_metrics.csv",
    ]
    
    for p in possible_paths:
        if p.exists():
            df = pd.read_csv(p)
            for col in ["NSE", "KGE", "RMSE", "Peak-MAPE"]:
                if col in df.columns:
                    metrics[col] = df[col].iloc[0] if len(df) == 1 else df[col].mean()
            break
    
    return metrics


def main():
    parser = argparse.ArgumentParser(description="Experiment Runner")
    subparsers = parser.add_subparsers(dest="command", help="Commands")
    
    # Quick command (all-in-one)
    quick_parser = subparsers.add_parser("quick", help="Generate + validate + train + evaluate")
    quick_parser.add_argument("--site", required=True, help="Site name (e.g., namou_kuwei)")
    quick_parser.add_argument("--type", required=True, choices=["rain", "ar", "ar_static", "seq2seq_rain", "seq2seq_ar"],
                              help="Config type")
    quick_parser.add_argument("--lead", type=int, default=1, help="Lead time in hours")
    quick_parser.add_argument("--predict-steps", type=int, default=1, help="Prediction steps (seq2seq)")
    quick_parser.add_argument("--device", default=None, help="Device (cpu/cuda)")
    
    # Train command
    train_parser = subparsers.add_parser("train", help="Train a model")
    train_parser.add_argument("--config", required=True, help="Config file path")
    train_parser.add_argument("--device", default=None, help="Device (cpu/cuda)")
    
    # Evaluate command
    eval_parser = subparsers.add_parser("evaluate", help="Evaluate a model")
    eval_parser.add_argument("--run-dir", required=True, help="Run directory")
    eval_parser.add_argument("--period", default="test", help="Period (test/validation)")
    
    # Compare command
    compare_parser = subparsers.add_parser("compare", help="Compare results")
    compare_parser.add_argument("--results-dir", required=True, help="Results directory")
    compare_parser.add_argument("--metric", default="NSE", help="Metric to sort by")
    
    args = parser.parse_args()
    
    if args.command == "quick":
        success = run_quick(args.site, args.type, args.lead, args.predict_steps, args.device)
        sys.exit(0 if success else 1)
    elif args.command == "train":
        success = run_train(args.config, args.device)
        sys.exit(0 if success else 1)
    elif args.command == "evaluate":
        success = run_evaluate(args.run_dir, args.period)
        sys.exit(0 if success else 1)
    elif args.command == "compare":
        compare_results(args.results_dir, args.metric)
    else:
        parser.print_help()


if __name__ == "__main__":
    main()


