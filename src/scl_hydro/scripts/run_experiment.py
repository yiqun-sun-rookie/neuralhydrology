"""SCL-LSTM training entry point.

Usage:
    cd src && python -m scl_hydro.scripts.run_experiment --config <path_to_yml>
"""
import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent.parent))

from scl_hydro.config import SCLConfig


def main():
    parser = argparse.ArgumentParser(description="Train SCL-LSTM model")
    parser.add_argument("--config", type=str, required=True, help="Path to YAML config file")
    parser.add_argument("--gpu", type=int, default=-1, help="GPU id (-1 for CPU)")
    args = parser.parse_args()

    cfg = SCLConfig(args.config)
    device = f"cuda:{args.gpu}" if args.gpu >= 0 else "cpu"

    print(f"SCL-LSTM Training")
    print(f"  seg_length={cfg.seg_length}, context_length={cfg.context_length}")
    print(f"  overlap_length={cfg.overlap_length}, scl_weight={cfg.scl_weight}")
    print(f"  device={device}")

    # TODO: Full training loop integration with CAMELS data loading
    # This will be implemented when connecting to the actual CAMELS dataset
    print("Config loaded successfully. Full training loop TBD.")


if __name__ == "__main__":
    main()
