"""Build the real, development-only source root from the CAMELS-US archive.

This is the one authorised entry point for opening the raw archive. It writes the
attested source root that :mod:`unified_autoresearch.data.packages` will accept, and
never emits a value from the sealed final evaluation interval.

Example
-------
python src/unified_autoresearch/scripts/build_real_development_source.py \
    --output-root runs/unified_autoresearch/development_source_real_v1
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

from unified_autoresearch.data.real_source import build_development_source_root  # noqa: E402


DEFAULT_CAMELS_ROOT = REPO_ROOT / "data" / "camels_us"
DEFAULT_STATIC_TABLE = SRC_ROOT / "fair_benchmark" / "frozen" / "bundle" / "track0_statics.csv"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--camels-root", type=Path, default=DEFAULT_CAMELS_ROOT)
    parser.add_argument("--static-table", type=Path, default=DEFAULT_STATIC_TABLE)
    parser.add_argument("--protocol", type=Path, default=MODULE_ROOT / "protocols" / "development_v1.json")
    parser.add_argument("--selection", type=Path, default=MODULE_ROOT / "selection" / "development_basins_v1.json")
    parser.add_argument("--output-root", type=Path, required=True)
    arguments = parser.parse_args(argv)

    manifest = build_development_source_root(
        camels_root=arguments.camels_root,
        static_table_path=arguments.static_table,
        protocol_path=arguments.protocol,
        selection_path=arguments.selection,
        output_root=arguments.output_root,
    )
    print(json.dumps(manifest, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
