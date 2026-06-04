"""Backfill the ``state_init_mode`` column on every per-basin and summary CSV
under ``results/10_global_conceptual_model_benchmark/camels_us_531_repro_v01*/``.

The column was added by the patched runner after the original lockdown and
warmup ensembles had been written, so existing CSVs lack it. The semantic
mode can be unambiguously inferred from the parent directory name:

- Directory ends with ``_warmup`` (e.g. ``camels_us_531_repro_v01_warmup``,
  ``..._v7_PT_tight_warmup``) → ``warmup_year_end_1989-09-30``
- Any other repro_v01 variant directory → ``cal_final_2008-09-30``

This script is idempotent: CSVs that already have the column are skipped.

Usage::

    python -X utf8 -m src.scl_hydro.scripts.backfill_state_init_mode

Or with a dry run::

    python -X utf8 -m src.scl_hydro.scripts.backfill_state_init_mode --dry-run
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

import pandas as pd

_HERE = Path(__file__).resolve()
_REPO_ROOT = _HERE.parents[3]


def _mode_for_dir(d: Path) -> str:
    return ("warmup_year_end_1989-09-30"
            if d.name.endswith("_warmup")
            else "cal_final_2008-09-30")


def _backfill_csv(p: Path, mode: str, dry_run: bool) -> tuple[bool, str]:
    """Return (was_modified, reason)."""
    df = pd.read_csv(p, dtype={"basin_id": str}, keep_default_na=False)
    if "state_init_mode" in df.columns:
        return False, "already_has_column"
    df["state_init_mode"] = mode
    if not dry_run:
        df.to_csv(p, index=False)
    return True, "added"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dry-run", action="store_true",
                        help="Report what would be modified without writing.")
    args = parser.parse_args(argv)

    base = _REPO_ROOT / "results" / "10_global_conceptual_model_benchmark"
    if not base.exists():
        print(f"Base path not found: {base}")
        return 1

    variant_dirs = sorted(
        d for d in base.iterdir()
        if d.is_dir() and d.name.startswith("camels_us_531_repro_v01")
        and (d / "hbv_lite_cma").is_dir()
    )

    total_per_basin = total_summary = 0
    modified_per_basin = modified_summary = 0
    skipped_per_basin = skipped_summary = 0
    by_mode: dict[str, int] = {}

    for vdir in variant_dirs:
        mode = _mode_for_dir(vdir)
        by_mode[mode] = by_mode.get(mode, 0) + 1

        # Per-basin CSVs
        per_basin_dir = vdir / "hbv_lite_cma"
        per_basin_files = sorted(per_basin_dir.glob("*.csv"))
        for f in per_basin_files:
            total_per_basin += 1
            mod, _ = _backfill_csv(f, mode, args.dry_run)
            if mod:
                modified_per_basin += 1
            else:
                skipped_per_basin += 1

        # Summary CSV
        summary_dir = vdir / "summary"
        if summary_dir.is_dir():
            for f in summary_dir.glob("*.csv"):
                total_summary += 1
                mod, _ = _backfill_csv(f, mode, args.dry_run)
                if mod:
                    modified_summary += 1
                else:
                    skipped_summary += 1

        print(f"  {vdir.name:<55} mode={mode:<32} "
              f"per_basin={len(per_basin_files)}")

    print()
    print(f"{'='*72}")
    print(f"BACKFILL state_init_mode {'(DRY-RUN)' if args.dry_run else ''}")
    print(f"{'='*72}")
    print(f"  Variant dirs:        {len(variant_dirs)}")
    print(f"  Variants by mode:    {by_mode}")
    print(f"  Per-basin CSVs:      total={total_per_basin}  "
          f"modified={modified_per_basin}  skipped={skipped_per_basin}")
    print(f"  Summary CSVs:        total={total_summary}  "
          f"modified={modified_summary}  skipped={skipped_summary}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
