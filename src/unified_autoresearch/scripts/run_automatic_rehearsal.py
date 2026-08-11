"""Run the frozen three-candidate automatic-research rehearsal on eight development basins."""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path


MODULE_ROOT = Path(__file__).resolve().parents[1]
SRC_ROOT = MODULE_ROOT.parent
REPO_ROOT = SRC_ROOT.parent
if str(SRC_ROOT) not in sys.path:
    sys.path.insert(0, str(SRC_ROOT))

from unified_autoresearch.candidates.catalog import (  # noqa: E402
    PINNED_DEPENDENCIES,
    PINNED_DEPENDENCIES_CLUSTER,
)
from unified_autoresearch.runtime.resources import capture_resource_snapshot  # noqa: E402
from unified_autoresearch.workflow.automatic_rehearsal import run_automatic_rehearsal  # noqa: E402


POLICY_PATH = MODULE_ROOT / "protocols" / "automatic_rehearsal_v1.json"
DEPENDENCY_SETS = {"default": PINNED_DEPENDENCIES, "cluster": PINNED_DEPENDENCIES_CLUSTER}


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo-root", type=Path, default=REPO_ROOT)
    parser.add_argument("--package-root", type=Path, required=True)
    parser.add_argument("--output-root", type=Path, required=True)
    parser.add_argument("--policy-path", type=Path, default=POLICY_PATH)
    parser.add_argument("--dependencies", choices=sorted(DEPENDENCY_SETS), default="default")
    parser.add_argument("--monitor-sample-interval-seconds", type=float, default=None)
    parser.add_argument("--monitor-reason", type=str, default=None)
    arguments = parser.parse_args(argv)

    result = run_automatic_rehearsal(
        repo_root=arguments.repo_root,
        package_root=arguments.package_root,
        expected_package_manifest_sha256=_sha256(arguments.package_root / "PACKAGE_MANIFEST.json"),
        policy_path=arguments.policy_path,
        output_root=arguments.output_root,
        resource_snapshot=capture_resource_snapshot(arguments.repo_root),
        candidate_dependencies=DEPENDENCY_SETS[arguments.dependencies],
        monitor_sample_interval_seconds=arguments.monitor_sample_interval_seconds,
        monitor_reason=arguments.monitor_reason,
    )
    print(
        json.dumps(
            {
                key: result[key]
                for key in (
                    "candidate_count",
                    "registered_run_count",
                    "score_report_count",
                    "total_denied_event_count",
                    "recommended_candidate_id",
                )
            },
            indent=2,
            sort_keys=True,
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
