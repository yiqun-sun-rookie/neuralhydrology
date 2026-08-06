"""Independently verify a built development source root and its two protocol packages.

Writes the per-basin verification report so the result can be re-read byte for byte.

Example
-------
python src/unified_autoresearch/scripts/verify_development_artifacts.py \
    --source-root runs/unified_autoresearch/development_source_real_64_v1 \
    --package-root runs/unified_autoresearch/development_packages_real_64_v1 \
    --selection src/unified_autoresearch/selection/development_basins_64_v1.json \
    --report runs/unified_autoresearch/VERIFICATION_DEVELOPMENT_ARTIFACTS_64.json
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path


MODULE_ROOT = Path(__file__).resolve().parents[1]
SRC_ROOT = MODULE_ROOT.parent
REPO_ROOT = SRC_ROOT.parent
if str(SRC_ROOT) not in sys.path:
    sys.path.insert(0, str(SRC_ROOT))

from unified_autoresearch.data.verification import verify_development_artifacts  # noqa: E402


DEFAULT_CAMELS_ROOT = REPO_ROOT / "data" / "camels_us"
DEFAULT_STATIC_TABLE = SRC_ROOT / "fair_benchmark" / "frozen" / "bundle" / "track0_statics.csv"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--source-root", type=Path, required=True)
    parser.add_argument("--package-root", type=Path, required=True)
    parser.add_argument("--camels-root", type=Path, default=DEFAULT_CAMELS_ROOT)
    parser.add_argument("--static-table", type=Path, default=DEFAULT_STATIC_TABLE)
    parser.add_argument("--protocol", type=Path, default=MODULE_ROOT / "protocols" / "development_v1.json")
    parser.add_argument("--selection", type=Path, required=True)
    parser.add_argument("--report", type=Path, required=True)
    arguments = parser.parse_args(argv)

    report = verify_development_artifacts(
        source_root=arguments.source_root,
        package_root=arguments.package_root,
        camels_root=arguments.camels_root,
        static_table_path=arguments.static_table,
        protocol_path=arguments.protocol,
        selection_path=arguments.selection,
    )
    if arguments.report.exists():
        raise FileExistsError(arguments.report)
    arguments.report.parent.mkdir(parents=True, exist_ok=True)
    arguments.report.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")

    print(f"basins verified: {report['basin_count']}")
    print(f"sealed interval rows: {report['sealed_interval_rows_total']}")
    print(f"artifact files pinned: {report['artifact_files_scanned']}")
    print(f"all passed: {report['all_passed']}")
    for failure in report["failures"][:20]:
        print(f"  FAIL {failure}")
    return 0 if report["all_passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
