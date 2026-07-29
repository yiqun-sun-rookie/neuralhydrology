"""Authorization and physical-memory gate shared by every version 09 entry point."""
from __future__ import annotations

import argparse
import json
from pathlib import Path

from formal_v09_protocol import load_protocol_v09, validate_protocol_v09
from memory_safety_v09 import HostMemorySnapshot, MemorySafetyGate, sample_host_memory


_ACTION_AUTHORIZATION = {
    "synthetic_test": "synthetic_tests",
    "formal_target_bundle_generation": "formal_target_bundle_generation",
    "training": "training",
    "formal_prediction_generation": "formal_prediction_generation",
    "official_scoring": "official_scoring",
}


class LaunchAuthorizationError(RuntimeError):
    """Raised before an action that the frozen protocol has not authorized."""


def assert_launch_allowed_v09(
    config: dict,
    *,
    action: str,
    estimated_peak_bytes: int,
    snapshot: HostMemorySnapshot | None = None,
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
    if snapshot is None:
        snapshot = sample_host_memory()
    gate = MemorySafetyGate.from_snapshot(snapshot)
    memory_report = gate.assert_start_safe(
        snapshot,
        estimated_peak_bytes=int(estimated_peak_bytes),
        long_running=action != "synthetic_test",
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
            "process_rss_bytes": snapshot.process_rss_bytes,
        },
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", type=Path, required=True)
    parser.add_argument("--action", choices=tuple(_ACTION_AUTHORIZATION), required=True)
    parser.add_argument("--estimated-peak-gib", type=float, required=True)
    args = parser.parse_args()
    if args.estimated_peak_gib < 0:
        raise ValueError("--estimated-peak-gib must be nonnegative")
    config = load_protocol_v09(args.config)
    report = assert_launch_allowed_v09(
        config,
        action=args.action,
        estimated_peak_bytes=int(args.estimated_peak_gib * 2**30),
    )
    print(json.dumps(report, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
