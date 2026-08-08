"""Write the pre-search basin eligibility record for a frozen development package.

Run this BEFORE any candidate, so the unstable set is derived from validation truth rather than
chosen after seeing scores. The record refuses to overwrite an existing file.

Example
-------
python src/unified_autoresearch/scripts/classify_development_basins.py \
    --package-root runs/unified_autoresearch/development_packages_real_64_v1 \
    --output runs/unified_autoresearch/BASIN_ELIGIBILITY_64_v1.json
"""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path


MODULE_ROOT = Path(__file__).resolve().parents[1]
SRC_ROOT = MODULE_ROOT.parent
if str(SRC_ROOT) not in sys.path:
    sys.path.insert(0, str(SRC_ROOT))

from unified_autoresearch.evaluation.basin_eligibility import classify_development_basins  # noqa: E402


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--package-root", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    arguments = parser.parse_args(argv)

    manifest_path = arguments.package_root / "PACKAGE_MANIFEST.json"
    record = classify_development_basins(
        package_root=arguments.package_root,
        expected_package_manifest_sha256=_sha256(manifest_path),
        output_path=arguments.output,
    )
    print(
        json.dumps(
            {
                "standard_basin_count": len(record["standard_basins"]),
                "unstable_basin_count": len(record["unstable_basins"]),
                "unstable_basins": record["unstable_basins"],
                "thresholds": record["thresholds"],
                "record_sha256": _sha256(Path(arguments.output).resolve()),
            },
            indent=2,
            sort_keys=True,
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
