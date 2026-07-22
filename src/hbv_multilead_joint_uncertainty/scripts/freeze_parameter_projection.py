"""Freeze the twenty non-performance fields required by this study."""

from __future__ import annotations

import csv
import hashlib
import json
import os
import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[3]
if str(REPO_ROOT / "src") not in sys.path:
    sys.path.insert(0, str(REPO_ROOT / "src"))

from hbv_multilead_joint_uncertainty.contracts import (  # noqa: E402
    TRAINING_PROJECTION_COLUMNS,
    csv_projection_sha256,
)


def _sha256(path: Path) -> str:
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def _metadata_payload(
    source: Path,
    source_metadata_path: Path,
    source_metadata: dict,
    projection_table_sha256: str,
    projection_content_sha256: str,
) -> dict:
    return {
        "artifact_type": "frozen_trained_parameter_projection",
        "artifact_version": "trained_parameter_projection_531_v01",
        "row_count": 531,
        "column_count": len(TRAINING_PROJECTION_COLUMNS),
        "columns": list(TRAINING_PROJECTION_COLUMNS),
        "performance_columns_included": False,
        "projection_table_sha256": projection_table_sha256,
        "projection_content_sha256": projection_content_sha256,
        "source": {
            "table_path": source.relative_to(REPO_ROOT).as_posix(),
            "table_sha256": _sha256(source),
            "metadata_path": source_metadata_path.relative_to(REPO_ROOT).as_posix(),
            "metadata_sha256": _sha256(source_metadata_path),
        },
        "training_protocol": {
            "protocol": source_metadata["protocol"],
            "protocol_version": source_metadata["protocol_version"],
            "model": "HBV-lite conceptual rainfall-runoff model",
            "forcing": "Maurer daily basin forcing",
            "potential_evapotranspiration_method": "Priestley-Taylor",
            "parameter_bounds": "version 1",
            "calibration_start": source_metadata["calibration_start"],
            "calibration_end": source_metadata["calibration_end"],
            "objective": "Nash-Sutcliffe efficiency",
            "optimizer": "Covariance Matrix Adaptation Evolution Strategy with three restarts",
            "trials_per_restart": source_metadata["trials"],
            "warmup_year_used": source_metadata["warmup_year"],
        },
        "creation_rule": (
            "Copy the twenty named non-performance fields as text from each of the 531 source rows; "
            "preserve source row order; reject missing, duplicate, or extra selected fields."
        ),
        "evaluation_metrics_used_for_projection": False,
    }


def freeze_parameter_projection(
    source: Path,
    source_metadata_path: Path,
    output: Path,
) -> tuple[Path, Path]:
    source = Path(source).resolve()
    source_metadata_path = Path(source_metadata_path).resolve()
    output = Path(output).resolve()
    metadata_output = output.with_suffix(".metadata.json")
    if output.exists() or metadata_output.exists():
        raise FileExistsError("refusing to overwrite the frozen parameter projection or metadata")
    temporary = output.with_name(f".{output.name}.{os.getpid()}.tmp")
    metadata_temporary = metadata_output.with_name(f".{metadata_output.name}.{os.getpid()}.tmp")
    try:
        with source.open("r", encoding="utf-8", newline="") as input_handle, temporary.open(
            "x", encoding="utf-8", newline=""
        ) as output_handle:
            reader = csv.reader(input_handle)
            writer = csv.writer(output_handle, lineterminator="\n")
            header = next(reader)
            if len(header) != len(set(header)):
                raise ValueError("source parameter table has duplicate columns")
            indices = [header.index(column) for column in TRAINING_PROJECTION_COLUMNS]
            writer.writerow(TRAINING_PROJECTION_COLUMNS)
            row_count = 0
            for row in reader:
                if len(row) != len(header):
                    raise ValueError("source parameter row length does not match its header")
                writer.writerow([row[index] for index in indices])
                row_count += 1
        if row_count != 531:
            raise ValueError(f"parameter projection contains {row_count} rows; expected 531")
        source_metadata = json.loads(source_metadata_path.read_text(encoding="utf-8"))
        payload = _metadata_payload(
            source,
            source_metadata_path,
            source_metadata,
            _sha256(temporary),
            csv_projection_sha256(temporary),
        )
        metadata_temporary.write_bytes(
            (json.dumps(payload, indent=2, ensure_ascii=False) + "\n").encode("utf-8")
        )
        os.replace(temporary, output)
        os.replace(metadata_temporary, metadata_output)
    except Exception:
        temporary.unlink(missing_ok=True)
        metadata_temporary.unlink(missing_ok=True)
        raise
    return output, metadata_output


def main() -> None:
    source = (
        REPO_ROOT
        / "results"
        / "10_global_conceptual_model_benchmark"
        / "camels_us_531_repro_v01"
        / "summary"
        / "hbv_lite_cma_FINAL_pt_v1_warmup_local_full.csv"
    )
    output = (
        REPO_ROOT
        / "src"
        / "hbv_multilead_joint_uncertainty"
        / "configs"
        / "trained_parameter_projection_531_v01.csv"
    )
    freeze_parameter_projection(source, source.with_suffix(".metadata.json"), output)


if __name__ == "__main__":
    main()
