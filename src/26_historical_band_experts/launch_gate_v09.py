"""Authorization and physical-memory gate shared by every version 09 entry point."""
from __future__ import annotations

import argparse
from collections.abc import Mapping
import json
from pathlib import Path
import sys


IDEA_ROOT = Path(__file__).resolve().parent
WORKTREE_SRC = IDEA_ROOT.parent
if str(WORKTREE_SRC) not in sys.path:
    sys.path.insert(0, str(WORKTREE_SRC))

from formal_v09_protocol import load_protocol_v09, validate_protocol_v09
from memory_safety_v09 import (
    HostMemorySnapshot,
    MemorySafetyError,
    MemorySafetyGate,
    TaskMemoryLease,
    exclusive_high_load_lease_v09,
    sample_host_memory,
)


_ACTION_AUTHORIZATION = {
    "synthetic_test": "synthetic_tests",
    "formal_target_bundle_generation": "formal_target_bundle_generation",
    "training": "training",
    "formal_prediction_generation": "formal_prediction_generation",
    "official_scoring": "official_scoring",
}
_ACTION_PEAK_METHODS = {
    "synthetic_test": {"synthetic_bound_v1"},
    "formal_target_bundle_generation": set(),
    "training": set(),
    "formal_prediction_generation": set(),
    "official_scoring": {"analytical_file_working_set_v1"},
}


class LaunchAuthorizationError(RuntimeError):
    """Raised before an action that the frozen protocol has not authorized."""


def assert_launch_allowed_v09(
    config: dict,
    *,
    action: str,
    peak_estimate: Mapping,
    snapshot: HostMemorySnapshot | None = None,
    lease: TaskMemoryLease | None = None,
) -> dict:
    """Require both explicit protocol authorization and a safe host-memory state."""
    validate_protocol_v09(config)
    if action not in _ACTION_AUTHORIZATION:
        raise ValueError(f"unknown version 09 action: {action}")
    authorization_key = _ACTION_AUTHORIZATION[action]
    if config["authorization"].get(authorization_key) is not True:
        raise LaunchAuthorizationError(
            f"version 09 action {action} is not authorized by protocol {config['protocol_id']}"
        )
    allowed_peak_methods = _ACTION_PEAK_METHODS[action]
    if not allowed_peak_methods:
        raise MemorySafetyError(
            f"no trusted task-specific peak estimator is registered for action {action}"
        )
    if peak_estimate.get("method") not in allowed_peak_methods:
        raise MemorySafetyError(
            f"peak estimate method is not registered for action {action}"
        )
    if snapshot is None:
        snapshot = sample_host_memory()
    gate = MemorySafetyGate.from_snapshot(snapshot, config["memory_safety"])
    memory_report = gate.assert_start_safe(
        snapshot,
        peak_estimate,
        long_running=action != "synthetic_test",
        lease=lease,
    )
    return {
        "status": "launch_allowed",
        "protocol_id": config["protocol_id"],
        "action": action,
        "authorization_key": authorization_key,
        "memory": memory_report,
        "host": {
            "total_bytes": snapshot.total_bytes,
            "available_bytes": snapshot.available_bytes,
            "commit_headroom_bytes": snapshot.commit_headroom_bytes,
            "process_rss_bytes": snapshot.process_rss_bytes,
        },
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", type=Path, required=True)
    parser.add_argument("--action", choices=tuple(_ACTION_AUTHORIZATION), required=True)
    parser.add_argument("--peak-estimate-evidence", type=Path, required=True)
    args = parser.parse_args()
    config = load_protocol_v09(args.config)
    peak_estimate = json.loads(args.peak_estimate_evidence.read_text(encoding="utf-8"))
    if args.action == "synthetic_test":
        report = assert_launch_allowed_v09(
            config,
            action=args.action,
            peak_estimate=peak_estimate,
        )
    else:
        with exclusive_high_load_lease_v09() as lease:
            report = assert_launch_allowed_v09(
                config,
                action=args.action,
                peak_estimate=peak_estimate,
                lease=lease,
            )
    print(json.dumps(report, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
