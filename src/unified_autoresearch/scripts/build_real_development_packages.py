"""Build the two isolated development packages from an attested source root.

Example
-------
python src/unified_autoresearch/scripts/build_real_development_packages.py \
    --source-root runs/unified_autoresearch/development_source_real_v1 \
    --output-root runs/unified_autoresearch/development_packages_real_v1
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path


MODULE_ROOT = Path(__file__).resolve().parents[1]
SRC_ROOT = MODULE_ROOT.parent
if str(SRC_ROOT) not in sys.path:
    sys.path.insert(0, str(SRC_ROOT))

from unified_autoresearch.data.packages import build_development_packages  # noqa: E402


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--source-root", type=Path, required=True)
    parser.add_argument("--protocol", type=Path, default=MODULE_ROOT / "protocols" / "development_v1.json")
    parser.add_argument("--selection", type=Path, default=MODULE_ROOT / "selection" / "development_basins_v1.json")
    parser.add_argument("--output-root", type=Path, required=True)
    arguments = parser.parse_args(argv)

    manifest = build_development_packages(
        source_root=arguments.source_root,
        source_manifest_path=arguments.source_root / "SOURCE_MANIFEST.json",
        protocol_path=arguments.protocol,
        selection_path=arguments.selection,
        output_root=arguments.output_root,
    )
    print(json.dumps({key: manifest[key] for key in ("schema_version", "protocols", "basins")}, indent=2))
    print(f"files: {len(manifest['files'])}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
