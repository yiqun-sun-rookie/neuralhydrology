#!/usr/bin/env python
"""
Config Validator - Check for Data Leakage

Validates NeuralHydrology config files for:
1. Train/Val/Test period overlap
2. AR input lag vs lead time
3. Improper qobs usage

Usage:
    python tools/validate_config.py path/to/config.yml
    python tools/validate_config.py --dir src/namou_kuwei/configs/
    python tools/validate_config.py --dir src/ --verbose
"""
import argparse
import yaml
from pathlib import Path
from datetime import datetime
import sys


def parse_date(date_str: str) -> datetime:
    """Parse date string in various formats."""
    formats = ["%d/%m/%Y", "%Y-%m-%d", "%Y-%m-%d %H:%M:%S"]
    for fmt in formats:
        try:
            return datetime.strptime(date_str, fmt)
        except ValueError:
            continue
    raise ValueError(f"Cannot parse date: {date_str}")


def validate_config(cfg_path: Path) -> tuple[bool, list[str]]:
    """
    Validate a configuration file for data leakage.
    
    Returns:
        (is_valid, list of error messages)
    """
    errors = []
    warnings = []
    
    with open(cfg_path, "r", encoding="utf-8") as f:
        cfg = yaml.safe_load(f)
    
    # 1. Check time split
    try:
        train_start = parse_date(cfg["train_start_date"])
        train_end = parse_date(cfg["train_end_date"])
        val_start = parse_date(cfg["validation_start_date"])
        val_end = parse_date(cfg["validation_end_date"])
        test_start = parse_date(cfg["test_start_date"])
        test_end = parse_date(cfg["test_end_date"])
        
        if train_end >= val_start:
            errors.append(f"Train/Val overlap: train_end ({cfg['train_end_date']}) >= val_start ({cfg['validation_start_date']})")
        if val_end >= test_start:
            errors.append(f"Val/Test overlap: val_end ({cfg['validation_end_date']}) >= test_start ({cfg['test_start_date']})")
        if train_end >= test_start:
            errors.append(f"Train/Test overlap: train_end ({cfg['train_end_date']}) >= test_start ({cfg['test_start_date']})")
            
    except KeyError as e:
        errors.append(f"Missing date field: {e}")
    except ValueError as e:
        errors.append(f"Invalid date format: {e}")
    
    # 2. Check AR input configuration
    ar_inputs = cfg.get("autoregressive_inputs", [])
    lagged = cfg.get("lagged_features", {})
    predict_n = cfg.get("predict_last_n", 1)
    
    if ar_inputs:
        model = cfg.get("model", "").lower()
        if model not in ("arlstm", "earlstm"):
            errors.append(f"Model '{model}' does not support autoregressive_inputs. Use 'arlstm' or 'earlstm'.")
        
        # Check that AR inputs are properly lagged
        for ar_input in ar_inputs:
            # Parse the shift value from name like "qobs_shift24"
            if "_shift" in ar_input:
                parts = ar_input.rsplit("_shift", 1)
                if len(parts) == 2 and parts[1].isdigit():
                    shift = int(parts[1])
                    var_name = parts[0]
                    
                    # Check if this shift is defined in lagged_features
                    if var_name not in lagged:
                        errors.append(f"AR input '{ar_input}' requires lagged_features.{var_name} to be defined")
                    else:
                        shifts = lagged[var_name]
                        if isinstance(shifts, int):
                            shifts = [shifts]
                        if shift not in shifts:
                            errors.append(f"AR input '{ar_input}' requires shift={shift} in lagged_features.{var_name}")
                    
                    # Check for seq2seq leakage
                    if predict_n > 1 and shift < predict_n:
                        warnings.append(f"Seq2Seq: AR lag ({shift}) < predict_last_n ({predict_n}) may cause leakage at later steps")
            else:
                errors.append(f"AR input '{ar_input}' must be a shifted variable (e.g., 'qobs_shift1')")
    
    # 3. Check qobs is not in dynamic_inputs (would cause leakage)
    dynamic_inputs = cfg.get("dynamic_inputs", [])
    if "qobs" in dynamic_inputs:
        errors.append("'qobs' in dynamic_inputs causes data leakage! Use lagged_features instead.")
    
    return len(errors) == 0, errors, warnings


def print_detailed_report(cfg_path: Path, cfg: dict, errors: list, warnings: list):
    """Print detailed validation report."""
    print(f"\n{'='*60}")
    print(f"Config: {cfg_path}")
    print(f"{'='*60}")
    
    # Time periods
    print("\nTime Periods:")
    for period in ["train", "validation", "test"]:
        start = cfg.get(f"{period}_start_date", "N/A")
        end = cfg.get(f"{period}_end_date", "N/A")
        print(f"  {period.capitalize():12}: {start} ~ {end}")
    
    # AR configuration
    ar_inputs = cfg.get("autoregressive_inputs", [])
    lagged = cfg.get("lagged_features", {})
    predict_n = cfg.get("predict_last_n", 1)
    
    if ar_inputs or lagged:
        print("\nAR Configuration:")
        print(f"  lagged_features: {lagged}")
        print(f"  autoregressive_inputs: {ar_inputs}")
        print(f"  predict_last_n: {predict_n}")
    
    # Errors and warnings
    if errors:
        print(f"\n{'!'*60}")
        print("ERRORS (must fix):")
        for e in errors:
            print(f"  [ERROR] {e}")
        print(f"{'!'*60}")
    
    if warnings:
        print("\nWarnings:")
        for w in warnings:
            print(f"  [WARN] {w}")
    
    if not errors:
        print("\n[OK] No data leakage detected")


def main():
    parser = argparse.ArgumentParser(description="Validate NeuralHydrology config for data leakage")
    parser.add_argument("path", nargs="?", help="Config file or directory")
    parser.add_argument("--dir", type=str, help="Directory to scan for YAML files")
    parser.add_argument("--verbose", "-v", action="store_true", help="Print detailed report")
    args = parser.parse_args()
    
    paths = []
    if args.dir:
        paths = list(Path(args.dir).rglob("*.yml"))
    elif args.path:
        p = Path(args.path)
        if p.is_dir():
            paths = list(p.rglob("*.yml"))
        else:
            paths = [p]
    else:
        parser.print_help()
        return
    
    total = 0
    passed = 0
    
    for cfg_path in sorted(paths):
        total += 1
        is_valid, errors, warnings = validate_config(cfg_path)
        
        if args.verbose or (not is_valid):
            with open(cfg_path, "r", encoding="utf-8") as f:
                cfg = yaml.safe_load(f)
            print_detailed_report(cfg_path, cfg, errors, warnings)
        elif is_valid and not warnings:
            print(f"[OK] {cfg_path.name}")
        elif is_valid:
            print(f"[WARN] {cfg_path.name}")
            for w in warnings:
                print(f"       {w}")
        else:
            print(f"[FAIL] {cfg_path.name}")
            for e in errors:
                print(f"       {e}")
        
        if is_valid:
            passed += 1
    
    print(f"\nSummary: {passed}/{total} passed")
    sys.exit(0 if passed == total else 1)


if __name__ == "__main__":
    main()
