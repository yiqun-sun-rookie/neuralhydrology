#!/usr/bin/env python
"""
Configuration Generator for Streamflow Forecasting

Generate NeuralHydrology configs from site templates with proper AR lag handling.

Usage Examples:
    # Pure rainfall baseline (1h forecast)
    python src/namou_kuwei/scripts/gen_config.py --site namou_kuwei --type rain --lead 1
    
    # Rain + AR with 6h lead time
    python src/namou_kuwei/scripts/gen_config.py --site namou_kuwei --type ar --lead 6
    
    # Rain + AR + Static with 24h lead time
    python src/namou_kuwei/scripts/gen_config.py --site namou_kuwei --type ar_static --lead 24
    
    # Seq-to-Seq 24h prediction with AR
    python src/namou_kuwei/scripts/gen_config.py --site namou_kuwei --type seq2seq_ar --lead 24 --predict-steps 24
"""
import argparse
import yaml
from pathlib import Path
from datetime import datetime


def load_site_config(site_name: str) -> dict:
    """Load site configuration from templates folder."""
    idea_root = Path(__file__).resolve().parents[1]  # .../src/namou_kuwei
    repo_root = Path(__file__).resolve().parents[3]  # repository root
    candidates = [
        # Current idea-local layout
        idea_root / "configs" / f"site_{site_name}.yml",
        idea_root / "configs" / "templates" / f"site_{site_name}.yml",
        # Repo-level explicit path (same target, safer for manual runs)
        repo_root / "src" / "namou_kuwei" / "configs" / f"site_{site_name}.yml",
        repo_root / "src" / "namou_kuwei" / "configs" / "templates" / f"site_{site_name}.yml",
        # Backward compatibility with legacy layout
        repo_root / "experiments" / "templates" / f"site_{site_name}.yml",
    ]
    for template_path in candidates:
        if template_path.exists():
            with open(template_path, "r", encoding="utf-8") as f:
                return yaml.safe_load(f)
    raise FileNotFoundError(
        "Site config not found. Checked:\n- " + "\n- ".join(str(p) for p in candidates)
    )


def validate_no_leakage(cfg: dict) -> list:
    """Check for potential data leakage issues."""
    errors = []
    
    # 1. Check time split overlap
    from datetime import datetime
    def parse_date(s):
        return datetime.strptime(s, "%d/%m/%Y")
    
    train_end = parse_date(cfg["train_end_date"])
    val_start = parse_date(cfg["validation_start_date"])
    val_end = parse_date(cfg["validation_end_date"])
    test_start = parse_date(cfg["test_start_date"])
    
    if train_end >= val_start:
        errors.append(f"Train period overlaps with validation: {cfg['train_end_date']} >= {cfg['validation_start_date']}")
    if val_end >= test_start:
        errors.append(f"Validation period overlaps with test: {cfg['validation_end_date']} >= {cfg['test_start_date']}")
    
    # 2. Check AR input lag matches lead time
    if cfg.get("autoregressive_inputs"):
        for ar_input in cfg["autoregressive_inputs"]:
            if not ar_input.endswith(f"_shift{cfg.get('_lead_time', 1)}"):
                errors.append(f"AR input '{ar_input}' lag doesn't match lead time {cfg.get('_lead_time', 1)}")
    
    return errors


def generate_config(
    site_name: str,
    config_type: str,  # rain, ar, ar_static, seq2seq_rain, seq2seq_ar
    lead_time: int = 1,
    predict_steps: int = 1,
    hidden_size: int = 64,
    seq_length: int = 168,
    epochs: int = 60,
    output_dir: str = None,
) -> dict:
    """Generate a complete training configuration."""
    
    site = load_site_config(site_name)
    
    # Determine experiment name
    type_abbrev = {
        "rain": "Rain",
        "ar": "Rain_AR", 
        "ar_static": "Rain_AR_Static",
        "seq2seq_rain": "Seq2Seq_Rain",
        "seq2seq_ar": "Seq2Seq_AR",
    }
    is_seq2seq = config_type.startswith("seq2seq")
    exp_suffix = f"_{predict_steps}h" if is_seq2seq else f"_LT{lead_time}h"
    experiment_name = f"{type_abbrev[config_type]}{exp_suffix}"
    
    # Build config
    cfg = {
        "experiment_name": experiment_name,
        "run_dir": site["run_dir"],
        "data_dir": site["data_dir"],
        "dataset": "generic",
        "train_basin_file": site["train_basin_file"],
        "validation_basin_file": site["validation_basin_file"],
        "test_basin_file": site["test_basin_file"],
        "train_start_date": site["train_start_date"],
        "train_end_date": site["train_end_date"],
        "validation_start_date": site["validation_start_date"],
        "validation_end_date": site["validation_end_date"],
        "test_start_date": site["test_start_date"],
        "test_end_date": site["test_end_date"],
        "dynamic_inputs": site["dynamic_inputs"].copy(),
        "target_variables": site["target_variables"].copy(),
    }
    
    # Add static attributes if requested
    if config_type in ("ar_static",):
        cfg["static_attributes"] = site.get("static_attributes", [])
    
    # Configure AR inputs
    use_ar = config_type in ("ar", "ar_static", "seq2seq_ar")
    if use_ar:
        cfg["model"] = "arlstm"
        cfg["lagged_features"] = {"qobs": [lead_time]}
        cfg["autoregressive_inputs"] = [f"qobs_shift{lead_time}"]
        cfg["_lead_time"] = lead_time  # For validation
    else:
        cfg["model"] = "cudalstm"
    
    # Model architecture
    cfg["head"] = "regression"
    cfg["hidden_size"] = hidden_size if not is_seq2seq else 128
    cfg["initial_forget_bias"] = 3
    cfg["seq_length"] = seq_length if not is_seq2seq else max(seq_length, predict_steps + 24)
    cfg["predict_last_n"] = predict_steps if is_seq2seq else 1
    
    # Training settings
    cfg["optimizer"] = "Adam"
    cfg["loss"] = "NSE"
    cfg["learning_rate"] = {0: 0.001, 30: 0.0005, 60: 0.0001}
    cfg["batch_size"] = 256
    cfg["epochs"] = epochs
    cfg["clip_gradient_norm"] = 1.0
    cfg["validate_every"] = 5
    cfg["save_weights_every"] = 5
    cfg["seed"] = 2025
    cfg["device"] = "cpu"
    
    # Custom normalization
    cfg["custom_normalization"] = site.get("custom_normalization", {})
    
    # Metrics
    cfg["metrics"] = ["NSE", "KGE", "RMSE", "Peak-MAPE"]
    
    # Validate before returning
    errors = validate_no_leakage(cfg)
    if errors:
        print("WARNING: Potential data leakage detected:")
        for e in errors:
            print(f"  - {e}")
    
    # Remove internal fields
    cfg.pop("_lead_time", None)
    
    return cfg


def save_config(cfg: dict, output_path: Path):
    """Save configuration to YAML file."""
    # Add header comment
    header = f"""# Auto-generated config
# Generated: {datetime.now().strftime('%Y-%m-%d %H:%M')}
# Experiment: {cfg['experiment_name']}
#
# AR Input Lag: {cfg.get('lagged_features', {}).get('qobs', ['N/A'])}
# Predict Steps: {cfg.get('predict_last_n', 1)}
"""
    
    output_path.parent.mkdir(parents=True, exist_ok=True)
    with open(output_path, "w", encoding="utf-8") as f:
        f.write(header + "\n")
        yaml.dump(cfg, f, default_flow_style=False, allow_unicode=True, sort_keys=False)
    print(f"Saved: {output_path}")


def main():
    parser = argparse.ArgumentParser(description="Generate NeuralHydrology config")
    parser.add_argument("--site", required=True, help="Site name (e.g., namou_kuwei)")
    parser.add_argument("--type", required=True, choices=["rain", "ar", "ar_static", "seq2seq_rain", "seq2seq_ar"],
                        help="Config type")
    parser.add_argument("--lead", type=int, default=1, help="Lead time in hours (AR lag)")
    parser.add_argument("--predict-steps", type=int, default=1, help="Number of steps to predict (seq2seq)")
    parser.add_argument("--hidden", type=int, default=64, help="Hidden size")
    parser.add_argument("--seq-len", type=int, default=168, help="Sequence length")
    parser.add_argument("--epochs", type=int, default=60, help="Training epochs")
    parser.add_argument("--output", type=str, default=None, help="Output path (auto-generated if not specified)")
    parser.add_argument("--dry-run", action="store_true", help="Print config without saving")
    
    args = parser.parse_args()
    
    cfg = generate_config(
        site_name=args.site,
        config_type=args.type,
        lead_time=args.lead,
        predict_steps=args.predict_steps,
        hidden_size=args.hidden,
        seq_length=args.seq_len,
        epochs=args.epochs,
    )
    
    if args.dry_run:
        print(yaml.dump(cfg, default_flow_style=False, allow_unicode=True, sort_keys=False))
        return
    
    # Auto-generate output path
    if args.output:
        output_path = Path(args.output)
    else:
        output_dir = Path(__file__).resolve().parents[1] / "configs" / "generated"
        output_path = output_dir / f"{cfg['experiment_name']}.yml"
    
    save_config(cfg, output_path)


if __name__ == "__main__":
    main()








