"""Run the four reference candidates through both development protocols on real packages.

The resource snapshot is measured at start-up so the declared per-task peak and margin are
compared against real capacity, as required by the resource protocol.

Example
-------
python src/unified_autoresearch/scripts/run_real_development_loop.py \
    --package-root runs/unified_autoresearch/development_packages_real_v1 \
    --output-root runs/unified_autoresearch/development_loop_real_v1
"""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path

import psutil


MODULE_ROOT = Path(__file__).resolve().parents[1]
SRC_ROOT = MODULE_ROOT.parent
REPO_ROOT = SRC_ROOT.parent
if str(SRC_ROOT) not in sys.path:
    sys.path.insert(0, str(SRC_ROOT))

from unified_autoresearch.runtime.resources import ResourceSnapshot  # noqa: E402
from unified_autoresearch.workflow.development_loop import run_full_development_loop  # noqa: E402


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--repo-root", type=Path, default=REPO_ROOT)
    parser.add_argument("--package-root", type=Path, required=True)
    parser.add_argument("--output-root", type=Path, required=True)
    parser.add_argument(
        "--monitor-sample-interval-seconds",
        type=float,
        default=None,
        help="enable the independent resource supervisor on every run, sampled at this interval",
    )
    parser.add_argument(
        "--monitor-reason",
        type=str,
        default=None,
        help="required when the monitor is enabled; recorded as the per-task supervision reason",
    )
    arguments = parser.parse_args(argv)

    memory = psutil.virtual_memory()
    disk = psutil.disk_usage(str(arguments.repo_root))
    snapshot = ResourceSnapshot(
        available_cpu_cores=psutil.cpu_count(logical=True),
        available_gpu_count=0,
        available_memory_gb=memory.available / 2**30,
        free_disk_gb=disk.free / 2**30,
    )
    print(json.dumps(snapshot.__dict__, indent=2, sort_keys=True, default=float))

    result = run_full_development_loop(
        repo_root=arguments.repo_root,
        package_root=arguments.package_root,
        expected_package_manifest_sha256=_sha256(arguments.package_root / "PACKAGE_MANIFEST.json"),
        output_root=arguments.output_root,
        resource_snapshot=snapshot,
        monitor_sample_interval_seconds=arguments.monitor_sample_interval_seconds,
        monitor_reason=arguments.monitor_reason,
    )
    summary = {key: result[key] for key in result if key != "cells" and key != "candidates"}
    print(json.dumps(summary, indent=2, sort_keys=True))
    print(f"cells: {len(result['cells'])}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
