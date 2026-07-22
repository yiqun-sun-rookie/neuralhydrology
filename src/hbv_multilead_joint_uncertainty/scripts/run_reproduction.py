"""Prepare, run, aggregate, or verify resilient formal-result reproduction shards."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[3]
if str(REPO_ROOT / "src") not in sys.path:
    sys.path.insert(0, str(REPO_ROOT / "src"))

from hbv_multilead_joint_uncertainty.reproduction import (  # noqa: E402
    aggregate_reproduction_shards,
    prepare_reproduction_session,
    run_reproduction_shard,
    verify_reproduction_aggregation,
    verify_reproduction_session,
    verify_reproduction_shard,
)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo-root", type=Path, default=REPO_ROOT)
    subparsers = parser.add_subparsers(dest="command", required=True)

    session = subparsers.add_parser("prepare-reproduction-session")
    session.add_argument("--contract", type=Path, required=True)
    session.add_argument("--reference", type=Path, required=True)
    session.add_argument("--session-id", required=True)

    shard = subparsers.add_parser("run-reproduction-shard")
    shard.add_argument("--session", type=Path, required=True)
    shard.add_argument("--shard-root", type=Path, required=True)
    shard.add_argument("--log-root", type=Path)
    shard.add_argument("--shard-id", required=True)
    shard.add_argument("--basin-id", required=True)

    aggregation = subparsers.add_parser("aggregate-reproduction-shards")
    aggregation.add_argument("--session", type=Path, required=True)
    aggregation.add_argument("--shard-root", type=Path, required=True)
    aggregation.add_argument("--aggregation-id", required=True)

    verify_session = subparsers.add_parser("verify-reproduction-session")
    verify_session.add_argument("--session", type=Path, required=True)

    verify_shard = subparsers.add_parser("verify-reproduction-shard")
    verify_shard.add_argument("--session", type=Path, required=True)
    verify_shard.add_argument("--shard", type=Path, required=True)

    verify_aggregation = subparsers.add_parser("verify-reproduction-aggregation")
    verify_aggregation.add_argument("--aggregation", type=Path, required=True)
    return parser


def main(argv=None) -> int:
    arguments = build_parser().parse_args(argv)
    root = arguments.repo_root.resolve()
    if arguments.command == "prepare-reproduction-session":
        result = prepare_reproduction_session(
            root,
            arguments.contract,
            arguments.reference,
            arguments.session_id,
        )
    elif arguments.command == "run-reproduction-shard":
        result = run_reproduction_shard(
            root,
            arguments.session,
            arguments.shard_root,
            arguments.shard_id,
            arguments.basin_id,
            log_root=arguments.log_root,
        )
    elif arguments.command == "aggregate-reproduction-shards":
        result = aggregate_reproduction_shards(
            root,
            arguments.session,
            arguments.shard_root,
            arguments.aggregation_id,
        )
    elif arguments.command == "verify-reproduction-session":
        result = verify_reproduction_session(arguments.session, root)
    elif arguments.command == "verify-reproduction-shard":
        result = verify_reproduction_shard(arguments.shard, arguments.session, root)
    else:
        result = verify_reproduction_aggregation(arguments.aggregation, root)
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
