"""Run one declared candidate through both development protocols under supervision.

This is not a search: the candidate is named on the command line, it is the only one executed,
and nothing here proposes or ranks alternatives.

Example
-------
python src/unified_autoresearch/scripts/run_single_candidate.py \
    --candidate hbv_lite \
    --package-root runs/unified_autoresearch/development_packages_real_64_v1 \
    --output-root runs/unified_autoresearch/hbv_lite_64_v1 \
    --monitor-sample-interval-seconds 1.0 \
    --monitor-reason "first real candidate; per-basin calibration needs supervision"
"""

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
    REFERENCE_CATEGORIES,
    materialize_hbv_lite_candidate,
    materialize_reference_candidate,
)
from unified_autoresearch.runtime.resources import capture_resource_snapshot  # noqa: E402
from unified_autoresearch.workflow.candidate_development import run_single_candidate_development  # noqa: E402


DEPENDENCY_SETS = {"default": PINNED_DEPENDENCIES, "cluster": PINNED_DEPENDENCIES_CLUSTER}


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def _resolve(name: str, dependencies):
    if name == "hbv_lite":
        return lambda *, output_root: materialize_hbv_lite_candidate(
            output_root=output_root, dependencies=dependencies
        )
    if name in REFERENCE_CATEGORIES:
        return lambda *, output_root: materialize_reference_candidate(
            category=name, output_root=output_root, dependencies=dependencies
        )
    raise SystemExit(f"unknown candidate: {name!r}; choose from {['hbv_lite'] + list(REFERENCE_CATEGORIES)}")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--candidate", required=True)
    parser.add_argument("--repo-root", type=Path, default=REPO_ROOT)
    parser.add_argument("--package-root", type=Path, required=True)
    parser.add_argument("--output-root", type=Path, required=True)
    parser.add_argument("--monitor-sample-interval-seconds", type=float, default=None)
    parser.add_argument("--monitor-reason", type=str, default=None)
    parser.add_argument(
        "--dependencies",
        choices=sorted(DEPENDENCY_SETS),
        default="default",
        help="which frozen dependency declaration this run uses; 'cluster' is the HPC environment",
    )
    arguments = parser.parse_args(argv)

    manifest_path = arguments.package_root / "PACKAGE_MANIFEST.json"
    result = run_single_candidate_development(
        repo_root=arguments.repo_root,
        package_root=arguments.package_root,
        expected_package_manifest_sha256=_sha256(manifest_path),
        materialize=_resolve(arguments.candidate, DEPENDENCY_SETS[arguments.dependencies]),
        output_root=arguments.output_root,
        resource_snapshot=capture_resource_snapshot(arguments.repo_root),
        monitor_sample_interval_seconds=arguments.monitor_sample_interval_seconds,
        monitor_reason=arguments.monitor_reason,
    )
    print(
        json.dumps(
            {key: result[key] for key in ("candidate_id", "category", "basin_count", "cell_count", "registered_run_count")},
            indent=2,
            sort_keys=True,
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
