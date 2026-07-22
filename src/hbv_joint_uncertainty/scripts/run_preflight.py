"""Run or independently verify the daily joint-uncertainty preflight."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[3]
SRC_ROOT = REPO_ROOT / "src"
if str(SRC_ROOT) not in sys.path:
    sys.path.insert(0, str(SRC_ROOT))

from hbv_joint_uncertainty.experiment import verify_experiment  # noqa: E402
from hbv_joint_uncertainty.orchestrator import run_preflight_experiment  # noqa: E402


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Run the bounded daily HBV-lite joint-uncertainty preflight.")
    parser.add_argument("--experiment-id", help="Unique non-overwriting experiment identifier.")
    parser.add_argument("--basin-id", action="append", help="Frozen basin identifier; repeat to select several.")
    parser.add_argument("--max-days", type=int, help="Limit evaluation days for a bounded smoke run.")
    parser.add_argument("--config", type=Path, help="Configuration path relative to the repository root.")
    parser.add_argument(
        "--dry-run", action="store_true", help="Verify sources and resources without loading basin data."
    )
    parser.add_argument("--verify-output", type=Path, help="Independently verify an existing output and exit.")
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    if args.verify_output is not None:
        result = verify_experiment(args.verify_output)
    else:
        if not args.experiment_id:
            parser.error("--experiment-id is required unless --verify-output is used")
        result = run_preflight_experiment(
            repo_root=REPO_ROOT,
            experiment_id=args.experiment_id,
            basin_ids=args.basin_id,
            max_days=args.max_days,
            config_path=args.config,
            dry_run=args.dry_run,
        )
    print(json.dumps(result, indent=2, sort_keys=True, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
