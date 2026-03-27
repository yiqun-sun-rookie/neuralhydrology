"""Experiment launcher: enumerate adaptation configs and materialize a job manifest."""
import argparse
import json
import re
import shutil
from dataclasses import dataclass
from pathlib import Path
from typing import List

CONFIGS_DIR = Path(__file__).resolve().parents[1] / "configs"

_ADAPT_PATTERN = re.compile(r"adapt_(low_shift|high_shift)_(head|embedding|lstm|full)\.yml")


@dataclass
class MatrixEntry:
    config_name: str
    split_label: str
    adaptation_group: str


@dataclass
class MaterializeResult:
    manifest_path: Path


def build_run_matrix() -> List[MatrixEntry]:
    """Enumerate adaptation configs from the configs directory.

    Returns entries sorted by (shift: low before high, then group alphabetically).
    """
    _shift_order = {"low_shift": 0, "high_shift": 1}
    entries = []
    for path in CONFIGS_DIR.glob("adapt_*.yml"):
        m = _ADAPT_PATTERN.match(path.name)
        if m:
            entries.append(MatrixEntry(
                config_name=path.name,
                split_label=m.group(1),
                adaptation_group=m.group(2),
            ))
    entries.sort(key=lambda e: (_shift_order.get(e.split_label, 99), e.adaptation_group))
    return entries


def materialize_run_matrix(
    source_run_dir: Path,
    output_dir: Path,
) -> MaterializeResult:
    """Copy adaptation configs into output_dir and write a manifest with commands.

    Parameters
    ----------
    source_run_dir : Path
        Directory of the pretrained source model (must contain config.yml and a checkpoint).
    output_dir : Path
        Where to write materialized configs and manifest.json.

    Returns
    -------
    MaterializeResult
    """
    output_dir.mkdir(parents=True, exist_ok=True)
    matrix = build_run_matrix()
    manifest = []

    for entry in matrix:
        src_config = CONFIGS_DIR / entry.config_name
        dst_config = output_dir / entry.config_name
        shutil.copy2(src_config, dst_config)

        command = (
            f"python -m neuralhydrology.nh_run finetune "
            f"--config-file {dst_config} "
            f"--gpu 0"
        )

        manifest.append({
            "config_name": entry.config_name,
            "split_label": entry.split_label,
            "adaptation_group": entry.adaptation_group,
            "base_run_dir": str(source_run_dir),
            "materialized_config_path": str(dst_config),
            "command": command,
        })

    manifest_path = output_dir / "manifest.json"
    manifest_path.write_text(json.dumps(manifest, indent=2, ensure_ascii=False), encoding="utf-8")
    return MaterializeResult(manifest_path=manifest_path)


def main():
    parser = argparse.ArgumentParser(description="Materialize adaptation experiment matrix.")
    parser.add_argument("--source-run-dir", type=Path, required=True, help="Pretrained source model run directory")
    parser.add_argument("--output-dir", type=Path, default=Path("results/pretrained_lstm_knowledge_separation"))
    args = parser.parse_args()

    result = materialize_run_matrix(source_run_dir=args.source_run_dir, output_dir=args.output_dir)
    manifest = json.loads(result.manifest_path.read_text(encoding="utf-8"))

    print(f"Materialized {len(manifest)} runs to {args.output_dir}")
    print()
    for row in manifest:
        print(f"  [{row['split_label']}] {row['adaptation_group']:10s} → {row['command']}")


if __name__ == "__main__":
    main()
