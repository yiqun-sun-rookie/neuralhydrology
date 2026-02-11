"""Run the full GloFAS processing pipeline via a single configuration."""

from __future__ import annotations

import argparse
import logging
from pathlib import Path
from typing import Any, Dict, Optional

import yaml

try:
    from . import (
        clip_glofas,
        download_glofas,
        plot_qc,
        prep_subbasins,
        qc_summary,
        select_subbasin_outlets,
    )
except ImportError:
    # Allow direct execution: `python run_pipeline.py --config ...`
    import clip_glofas
    import download_glofas
    import plot_qc
    import prep_subbasins
    import qc_summary
    import select_subbasin_outlets

LOG_FORMAT = "%(asctime)s | %(levelname)s | %(message)s"
PROJECT_ROOT = Path(__file__).resolve().parents[2]


def configure_logging(verbose: bool = False) -> None:
    level = logging.DEBUG if verbose else logging.INFO
    logging.basicConfig(level=level, format=LOG_FORMAT)


def resolve_path(path_str: Optional[str]) -> Optional[Path]:
    if not path_str:
        return None
    path = Path(path_str)
    if not path.is_absolute():
        path = PROJECT_ROOT / path
    return path.resolve()


def load_yaml_config(path: Path) -> Dict[str, Any]:
    with path.open("r", encoding="utf-8") as fp:
        data = yaml.safe_load(fp) or {}
    if not isinstance(data, dict):
        raise ValueError(f"Pipeline config must be a mapping, got {type(data)!r}")
    return data


def stage_enabled(section: Optional[Dict[str, Any]]) -> bool:
    if not section:
        return True
    return bool(section.get("enabled", True))


def require_path(section: Dict[str, Any], key: str, stage_name: str) -> Path:
    value = resolve_path(section.get(key))
    if value is None:
        raise ValueError(f"`{key}` is required for stage '{stage_name}'.")
    return value


def run_download_stage(section: Dict[str, Any]) -> None:
    config_path = require_path(section, "config", "download")
    if not config_path.exists():
        raise FileNotFoundError(f"Download config not found: {config_path}")
    cfg = download_glofas.load_config(config_path)
    download_glofas.run_download(cfg)


def run_clip_stage(section: Dict[str, Any]) -> None:
    config_path = require_path(section, "config", "clip")
    if not config_path.exists():
        raise FileNotFoundError(f"Clip config not found: {config_path}")
    cfg = clip_glofas.load_config(config_path)
    clip_glofas.run_clip(cfg)


def run_outlet_stage(section: Dict[str, Any]) -> None:
    config_path = require_path(section, "config", "outlets")
    if not config_path.exists():
        raise FileNotFoundError(f"Outlets config not found: {config_path}")
    cfg = select_subbasin_outlets.load_config(config_path)
    select_subbasin_outlets.run(cfg)


def run_qc_summary_stage(section: Dict[str, Any]) -> None:
    outputs_dir = require_path(section, "outputs_dir", "qc_summary")
    qc_summary.generate_qc(outputs_dir)


def run_qc_plots_stage(section: Dict[str, Any]) -> None:
    outputs_dir = require_path(section, "outputs_dir", "qc_plots")
    subbasin_path = require_path(section, "subbasin_file", "qc_plots")
    if not subbasin_path.exists():
        raise FileNotFoundError(f"Subbasin file not found: {subbasin_path}")
    plot_qc.generate_figures(outputs_dir, subbasin_path)


def run_subbasin_stage(section: Dict[str, Any]) -> None:
    config_path = require_path(section, "config", "subbasins")
    if not config_path.exists():
        raise FileNotFoundError(f"Subbasin config not found: {config_path}")
    cfg = prep_subbasins.load_config(config_path)
    prep_subbasins.run(cfg)


def run_pipeline(config: Dict[str, Any]) -> None:
    name = config.get("name", "glofas_pipeline")
    logging.info("Starting GloFAS pipeline: %s", name)

    subbasin_section = config.get("subbasins", {})
    if stage_enabled(subbasin_section):
        logging.info("Running stage: subbasins")
        run_subbasin_stage(subbasin_section)
    else:
        logging.info("Skipping stage: subbasins")

    download_section = config.get("download", {})
    if stage_enabled(download_section):
        logging.info("Running stage: download")
        run_download_stage(download_section)
    else:
        logging.info("Skipping stage: download")

    clip_section = config.get("clip", {})
    if stage_enabled(clip_section):
        logging.info("Running stage: clip")
        run_clip_stage(clip_section)
    else:
        logging.info("Skipping stage: clip")

    outlets_section = config.get("outlets", {})
    if stage_enabled(outlets_section):
        logging.info("Running stage: outlets")
        run_outlet_stage(outlets_section)
    else:
        logging.info("Skipping stage: outlets")

    qc_sum_section = config.get("qc_summary", {})
    if stage_enabled(qc_sum_section):
        logging.info("Running stage: qc_summary")
        run_qc_summary_stage(qc_sum_section)
    else:
        logging.info("Skipping stage: qc_summary")

    qc_plot_section = config.get("qc_plots", {})
    if stage_enabled(qc_plot_section):
        logging.info("Running stage: qc_plots")
        run_qc_plots_stage(qc_plot_section)
    else:
        logging.info("Skipping stage: qc_plots")

    logging.info("Pipeline %s completed.", name)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Run the multi-stage GloFAS processing pipeline."
    )
    parser.add_argument(
        "--config",
        type=Path,
        required=True,
        help="YAML file describing pipeline stages and per-stage configs.",
    )
    parser.add_argument(
        "--verbose",
        action="store_true",
        help="Enable DEBUG logging for troubleshooting.",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    configure_logging(args.verbose)
    config_path = args.config.resolve()
    if not config_path.exists():
        raise FileNotFoundError(f"Pipeline config not found: {config_path}")
    config = load_yaml_config(config_path)
    run_pipeline(config)


if __name__ == "__main__":
    main()

