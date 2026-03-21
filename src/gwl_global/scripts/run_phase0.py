"""Phase 0 orchestrator: discover -> download -> QC -> KNMI -> merge."""
import argparse
import logging
import sys
from pathlib import Path

# Ensure project root is on path (for `from src.gwl_global...` imports)
_project_root = str(Path(__file__).resolve().parent.parent.parent.parent)
if _project_root not in sys.path:
    sys.path.insert(0, _project_root)

import pandas as pd
from tqdm import tqdm

from src.gwl_global.config import data_dir, NL_BBOX
from src.gwl_global.fetch_wells import run_well_discovery
from src.gwl_global.fetch_gwl import run_gwl_download
from src.gwl_global.fetch_knmi import run_knmi_download
from src.gwl_global.quality import check_series_quality
from src.gwl_global.merge import run_merge

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
)
logger = logging.getLogger(__name__)


def run_quality_check(output_dir: Path) -> pd.DataFrame:
    """Run QC on all downloaded GWL time series."""
    ts_dir = output_dir / "timeseries"
    if not ts_dir.exists():
        logger.error("No timeseries directory found at %s", ts_dir)
        return pd.DataFrame()

    files = sorted(ts_dir.glob("*_gwl.csv"))
    logger.info("Running QC on %d time series ...", len(files))

    rows = []
    for f in tqdm(files, desc="QC"):
        bro_id = f.stem.replace("_gwl", "")
        try:
            df = pd.read_csv(f, parse_dates=["date"], index_col="date")
            result = check_series_quality(df)
            result["bro_id"] = bro_id
            rows.append(result)
        except Exception as exc:
            rows.append({
                "bro_id": bro_id,
                "passed": False,
                "fail_reasons": [f"read_error: {exc}"],
            })

    qc_df = pd.DataFrame(rows)
    qc_path = output_dir / "quality_check.csv"
    qc_df.to_csv(qc_path, index=False)
    logger.info("QC: %d passed / %d total.", qc_df["passed"].sum(), len(qc_df))
    return qc_df


def main():
    parser = argparse.ArgumentParser(description="GWL Global Phase 0: NL data acquisition")
    parser.add_argument("--output-dir", type=str, default=None, help="Output directory")
    parser.add_argument(
        "--bbox",
        type=float,
        nargs=4,
        default=list(NL_BBOX),
        metavar=("MIN_LON", "MIN_LAT", "MAX_LON", "MAX_LAT"),
        help="Bounding box (default: all Netherlands)",
    )
    parser.add_argument(
        "--max-pages",
        type=int,
        default=0,
        help="Max pages for well discovery (0=unlimited)",
    )
    parser.add_argument(
        "--step",
        type=str,
        default="all",
        choices=["discover", "download", "qc", "knmi", "merge", "all"],
        help="Run a specific step or all",
    )
    args = parser.parse_args()

    out = Path(args.output_dir) if args.output_dir else data_dir()
    bbox = tuple(args.bbox)

    steps = {
        "discover": lambda: run_well_discovery(out, bbox=bbox, max_pages=args.max_pages),
        "download": lambda: run_gwl_download(output_dir=out),
        "qc": lambda: run_quality_check(out),
        "knmi": lambda: run_knmi_download(output_dir=out),
        "merge": lambda: run_merge(output_dir=out),
    }

    if args.step == "all":
        for name, fn in steps.items():
            logger.info("=== Step: %s ===", name)
            fn()
    else:
        steps[args.step]()

    logger.info("Done.")


if __name__ == "__main__":
    main()
