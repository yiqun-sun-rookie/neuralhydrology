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
from formal_action_resources_v09 import validate_formal_action_peak_estimate_v09
from memory_safety_v09 import (
    HostMemorySnapshot,
    MemorySafetyError,
    MemorySafetyGate,
    TaskMemoryLease,
    exclusive_high_load_lease_v09,
    sample_host_memory,
)
from stage_authorization_v09 import validate_stage_authorization_v09

_ACTION_AUTHORIZATION = {
    "synthetic_test": "synthetic_tests",
    "formal_target_bundle_generation": "formal_target_bundle_generation",
    "training": "training",
    "formal_prediction_generation": "formal_prediction_generation",
    "official_scoring": "official_scoring",
}
_ACTION_PEAK_METHODS = {
    "synthetic_test": {"synthetic_bound_v1"},
    "formal_target_bundle_generation": {"analytical_target_bundle_working_set_v1"},
    "training": {"analytical_training_working_set_v1"},
    "formal_prediction_generation": {"analytical_prediction_working_set_v1"},
    "official_scoring": {"analytical_file_working_set_v1"},
}


class LaunchAuthorizationError(RuntimeError):
    """Raised before an action that the frozen protocol has not authorized."""


def assert_launch_allowed_v09(
    config: dict,
    *,
    action: str,
    peak_estimate: Mapping,
    variant: str | None = None,
    snapshot: HostMemorySnapshot | None = None,
    lease: TaskMemoryLease | None = None,
    stage_authorization: Mapping | None = None,
    authorization_scope: str | None = None,
    stage_bindings: Mapping | None = None,
) -> dict:
    """Require exact authorization and a safe host-memory state."""
    validate_protocol_v09(config)
    if action not in _ACTION_AUTHORIZATION:
        raise ValueError(f"unknown version 09 action: {action}")
    authorization_key = _ACTION_AUTHORIZATION[action]
    if config["authorization"].get(authorization_key) is True:
        if any(value is not None for value in (stage_authorization, authorization_scope, stage_bindings)):
            raise LaunchAuthorizationError("protocol authorization cannot be mixed with a stage receipt")
        authorization_mode = "protocol_boolean"
    else:
        if action != "training" or any(
                value is None for value in (stage_authorization, authorization_scope, stage_bindings)):
            raise LaunchAuthorizationError(
                f"version 09 action {action} is not authorized by protocol {config['protocol_id']}")
        expected_binding_keys = {
            "protocol_sha256",
            "prerequisite_sha256",
            "executable_tree_sha256",
            "worktree_root",
            "output_root",
        }
        if not isinstance(stage_bindings, Mapping) or set(stage_bindings) != expected_binding_keys:
            raise LaunchAuthorizationError("formal training stage binding schema drift")
        validate_stage_authorization_v09(
            stage_authorization,
            action=action,
            scope=authorization_scope,
            protocol_sha256=stage_bindings["protocol_sha256"],
            prerequisite_sha256=stage_bindings["prerequisite_sha256"],
            executable_tree_sha256=stage_bindings["executable_tree_sha256"],
            worktree_root=stage_bindings["worktree_root"],
            output_root=stage_bindings["output_root"],
        )
        authorization_mode = "one_use_stage_receipt"
    allowed_peak_methods = _ACTION_PEAK_METHODS[action]
    if not allowed_peak_methods:
        raise MemorySafetyError(f"no trusted task-specific peak estimator is registered for action {action}")
    if peak_estimate.get("method") not in allowed_peak_methods:
        raise MemorySafetyError(f"peak estimate method is not registered for action {action}")
    if action in {
            "formal_target_bundle_generation",
            "training",
            "formal_prediction_generation",
    }:
        validate_formal_action_peak_estimate_v09(
            config,
            action,
            peak_estimate,
            variant=variant,
        )
    elif variant is not None:
        raise ValueError(f"model variant is not accepted for action {action}")
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
        "authorization_mode": authorization_mode,
        "authorization_scope": authorization_scope,
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
    parser.add_argument(
        "--variant",
        choices=(
            "strict_nesting_pair",
            "classic_lstm_256_clean",
            "classic_lstm_369_capacity",
            "continuous_multiscale_history",
        ),
    )
    parser.add_argument("--peak-estimate-evidence", type=Path, required=True)
    args = parser.parse_args()
    config = load_protocol_v09(args.config)
    peak_estimate = json.loads(args.peak_estimate_evidence.read_text(encoding="utf-8"))
    if args.action == "synthetic_test":
        report = assert_launch_allowed_v09(
            config,
            action=args.action,
            peak_estimate=peak_estimate,
            variant=args.variant,
        )
    else:
        with exclusive_high_load_lease_v09() as lease:
            report = assert_launch_allowed_v09(
                config,
                action=args.action,
                peak_estimate=peak_estimate,
                variant=args.variant,
                lease=lease,
            )
    print(json.dumps(report, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
