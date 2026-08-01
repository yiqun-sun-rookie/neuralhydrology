"""Validate candidate outputs against the frozen milestone-two contract."""

from __future__ import annotations

from dataclasses import asdict, dataclass

import pyarrow.parquet as parquet

from .descriptor import CandidateDescriptor
from .layout import RunLayout


PREDICTION_COLUMNS = frozenset({"basin", "date", "qsim"})


@dataclass(frozen=True)
class OutputContractAssessment:
    valid: bool
    expected_top_level: tuple[str, ...]
    actual_top_level: tuple[str, ...]
    failures: tuple[str, ...]

    def as_dict(self) -> dict:
        return asdict(self)


def assess_output_contract(
    descriptor: CandidateDescriptor,
    layout: RunLayout,
    mode: str,
) -> OutputContractAssessment:
    """Check output names, object types, and the prediction Parquet schema."""
    expected = tuple(sorted(descriptor.outputs[mode]))
    actual = tuple(sorted(path.name for path in layout.output_root.iterdir()))
    failures: list[str] = []
    missing = sorted(set(expected) - set(actual))
    extra = sorted(set(actual) - set(expected))
    if missing:
        failures.append(f"required top-level outputs are missing: {missing}")
    if extra:
        failures.append(f"undeclared top-level outputs are present: {extra}")

    if mode == "train":
        model_artifacts = layout.output_root / "model_artifacts"
        if model_artifacts.exists() and not model_artifacts.is_dir():
            failures.append("model_artifacts must be a directory")
    elif mode == "predict":
        predictions = layout.output_root / "predictions.parquet"
        if predictions.exists() and not predictions.is_file():
            failures.append("predictions.parquet must be a regular file")
        elif predictions.is_file():
            try:
                columns = frozenset(parquet.read_schema(predictions).names)
            except (OSError, TypeError, ValueError) as error:
                failures.append(f"predictions.parquet is not a readable Parquet file: {type(error).__name__}")
            else:
                missing_columns = sorted(PREDICTION_COLUMNS - columns)
                if missing_columns:
                    failures.append(f"predictions.parquet is missing required columns: {missing_columns}")
    else:
        raise ValueError(f"unsupported candidate mode: {mode!r}")

    return OutputContractAssessment(
        valid=not failures,
        expected_top_level=expected,
        actual_top_level=actual,
        failures=tuple(failures),
    )
