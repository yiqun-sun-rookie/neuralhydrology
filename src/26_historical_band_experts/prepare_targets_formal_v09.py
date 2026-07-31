"""Authorized, streaming target preparation for formal version 09."""
from __future__ import annotations

import argparse
import csv
import hashlib
import json
import os
from pathlib import Path
import stat
import subprocess
from typing import Callable, Mapping, Sequence

import numpy as np
import pandas as pd

from formal_action_runtime_v09 import FormalActionRuntimeV09, run_authorized_formal_action_v09
from formal_v09_protocol import load_protocol_v09, validate_protocol_v09


IDEA_ROOT = Path(__file__).resolve().parent
WORKTREE_ROOT = IDEA_ROOT.parents[1]
DEFAULT_CONFIG = IDEA_ROOT / "configs/formal_v09_protocol.json"
FORMAL_RELATIVE_OUTPUT = Path(
    "results/26_historical_band_experts/formal_v09/inputs/training_targets.csv"
)
FORMAL_DATA_RELATIVE_ROOT = Path("data/camels_us")
TRAIN_START = pd.Timestamp("1999-10-01")
VALIDATION_END = pd.Timestamp("2008-09-30")
FORMAL_START = pd.Timestamp("1989-10-01")
FORMAL_END = pd.Timestamp("1999-09-30")
_DISCHARGE_TO_MM_PER_DAY = 28_316_846.592 * 86_400
_BUILD_SOURCE_FILES = (
    "src/26_historical_band_experts/configs/formal_v09_protocol.json",
    "src/26_historical_band_experts/formal_action_resources_v09.py",
    "src/26_historical_band_experts/formal_action_runtime_v09.py",
    "src/26_historical_band_experts/formal_v09_protocol.py",
    "src/26_historical_band_experts/launch_gate_v09.py",
    "src/26_historical_band_experts/memory_safety_v09.py",
    "src/26_historical_band_experts/prepare_targets_formal_v09.py",
    "src/fair_benchmark/task_memory_v09.py",
)


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _canonical_sha256(value: object) -> str:
    payload = json.dumps(
        value,
        sort_keys=True,
        separators=(",", ":"),
        ensure_ascii=False,
        allow_nan=False,
    ).encode("utf-8")
    return hashlib.sha256(payload).hexdigest()


def _normalize_basins(values: Sequence[str]) -> tuple[str, ...]:
    basin_ids = tuple(str(value).strip().zfill(8) for value in values)
    if not basin_ids or any(not value.isdigit() or len(value) != 8 for value in basin_ids):
        raise ValueError("basin identifiers must be nonempty eight-digit values")
    if len(set(basin_ids)) != len(basin_ids):
        raise ValueError("basin identifiers must be unique")
    return basin_ids


def _basins_from_file(path: Path) -> tuple[str, ...]:
    return _normalize_basins(
        tuple(line.strip() for line in path.read_text(encoding="utf-8").splitlines() if line.strip())
    )


def _validate_formal_basin_file_v09(config: Mapping, path: str | Path) -> tuple[str, ...]:
    path = Path(path)
    basin_ids = _basins_from_file(path)
    if len(basin_ids) != int(config["basin_count"]):
        raise ValueError("formal basin file count differs from the frozen protocol")
    if _sha256(path) != config["basin_file_sha256"]:
        raise ValueError("formal basin file SHA-256 differs from the frozen protocol")
    return basin_ids


def _primary_repository_root_v09() -> Path:
    if WORKTREE_ROOT.parent.name == ".worktrees":
        return WORKTREE_ROOT.parents[1]
    return WORKTREE_ROOT


def _formal_data_root_v09(config: Mapping) -> Path:
    configured = Path(config["formal_action_resources"]["target_bundle"]["data_root"])
    if configured != FORMAL_DATA_RELATIVE_ROOT or configured.is_absolute():
        raise ValueError("formal data root differs from the frozen repository-relative root")
    return _primary_repository_root_v09() / configured


def _is_reparse_point_v09(path: str | Path) -> bool:
    path = Path(path)
    if not path.exists() and not path.is_symlink():
        return False
    status = os.lstat(path)
    attributes = int(getattr(status, "st_file_attributes", 0))
    reparse_flag = int(getattr(stat, "FILE_ATTRIBUTE_REPARSE_POINT", 0))
    return path.is_symlink() or bool(reparse_flag and attributes & reparse_flag)


def _assert_no_reparse_components_v09(root: str | Path, target: str | Path) -> None:
    root = Path(os.path.abspath(root))
    target = Path(os.path.abspath(target))
    if target != root and root not in target.parents:
        raise ValueError("target path escapes its trusted root")
    relative_parts = target.relative_to(root).parts
    current = root
    for part in (None, *relative_parts):
        if part is not None:
            current = current / part
        if _is_reparse_point_v09(current):
            raise ValueError(f"reparse point is forbidden in trusted path: {current}")
    resolved_root = root.resolve(strict=False)
    resolved_target = target.resolve(strict=False)
    if resolved_target != resolved_root and resolved_root not in resolved_target.parents:
        raise ValueError("resolved target path escapes its trusted root")


def _cleanup_partial(paths: Sequence[Path]) -> None:
    for path in paths:
        try:
            path.unlink()
        except FileNotFoundError:
            pass


def _formal_output_context_v09(
    output_path: Path,
    runtime: FormalActionRuntimeV09 | None,
) -> tuple[bool, Callable[[], object] | None]:
    formal_root = Path(
        os.path.abspath(WORKTREE_ROOT / "results/26_historical_band_experts/formal_v09")
    )
    absolute_output = Path(os.path.abspath(output_path))
    inside_formal_tree = absolute_output == formal_root or formal_root in absolute_output.parents
    if not inside_formal_tree:
        if runtime is not None:
            raise ValueError("formal runtime cannot publish outside the fixed formal result tree")
        return False, None
    if runtime is None or not runtime.is_valid_for("formal_target_bundle_generation"):
        raise ValueError("formal target path requires an authorized runtime capability")
    expected = Path(
        os.path.abspath(
            WORKTREE_ROOT
            / runtime.config["formal_action_resources"]["target_bundle"]["output_path"]
        )
    )
    if absolute_output != expected:
        raise ValueError("formal runtime can publish only the frozen target path")
    _assert_no_reparse_components_v09(WORKTREE_ROOT, absolute_output.parent)
    return True, runtime.checkpoint


def _write_streaming_target_bundle_v09(
    *,
    basins: Sequence[str],
    basin_file: str | Path,
    output_path: str | Path,
    load_one: Callable[[str], pd.Series],
    checkpoint: Callable[[], object] | None = None,
    protocol_canonical_sha256: str | None = None,
    runtime: FormalActionRuntimeV09 | None = None,
    manifest_metadata: Callable[[], Mapping] | None = None,
) -> dict:
    basin_file = Path(basin_file)
    output_path = Path(output_path)
    formal_output, formal_checkpoint = _formal_output_context_v09(output_path, runtime)
    if formal_output:
        checkpoint = formal_checkpoint
    manifest_path = output_path.with_suffix(".manifest.json")
    output_temporary = output_path.with_suffix(output_path.suffix + ".tmp")
    manifest_temporary = manifest_path.with_suffix(manifest_path.suffix + ".tmp")
    for path in (output_path, manifest_path, output_temporary, manifest_temporary):
        if path.exists():
            raise FileExistsError(f"target artifact already exists: {path}")

    basin_ids = _normalize_basins(basins)
    initial_basin_file_sha256 = _sha256(basin_file)
    if basin_ids != _basins_from_file(basin_file):
        raise ValueError("basin sequence differs from the trusted basin file")
    allowed_dates = pd.date_range(TRAIN_START, VALIDATION_END, freq="D")
    output_path.parent.mkdir(parents=True, exist_ok=True)
    if formal_output:
        _assert_no_reparse_components_v09(WORKTREE_ROOT, output_path.parent)
    output_moved = False
    try:
        if checkpoint is not None:
            checkpoint()
        with output_temporary.open("x", encoding="utf-8", newline="") as handle:
            writer = csv.writer(handle, lineterminator="\n")
            writer.writerow(("basin", "date", "qobs"))
            for basin in basin_ids:
                series = load_one(basin)
                if not isinstance(series, pd.Series):
                    raise TypeError("load_one must return a pandas Series")
                indexed = series.copy()
                indexed.index = pd.to_datetime(indexed.index)
                selected = pd.to_numeric(indexed.reindex(allowed_dates), errors="coerce")
                values = selected.to_numpy(dtype=np.float64)
                if not np.isfinite(values).all() or np.any(values < 0):
                    raise ValueError(f"allowed target window is incomplete for basin {basin}")
                writer.writerows(
                    (basin, date.strftime("%Y-%m-%d"), format(float(value), ".17g"))
                    for date, value in zip(allowed_dates, values, strict=True)
                )
                del series, indexed, selected, values
                if checkpoint is not None:
                    checkpoint()
        os.replace(output_temporary, output_path)
        output_moved = True
        manifest = {
            "status": "complete",
            "writer": "stream_one_basin_v1",
            "basin_count": len(basin_ids),
            "row_count": len(basin_ids) * len(allowed_dates),
            "minimum_date": str(TRAIN_START.date()),
            "maximum_date": str(VALIDATION_END.date()),
            "basin_file_sha256": initial_basin_file_sha256,
            "target_bundle_sha256": _sha256(output_path),
            "formal_evaluation_rows_emitted": 0,
            "formal_evaluation_qobs_parsed": 0,
            "trusted_raw_streamflow_files_read": len(basin_ids),
            "candidate_raw_streamflow_files_read": 0,
        }
        if protocol_canonical_sha256 is not None:
            manifest["protocol_canonical_sha256"] = protocol_canonical_sha256
        if manifest_metadata is not None:
            extra = dict(manifest_metadata())
            overlap = set(manifest) & set(extra)
            if overlap:
                raise ValueError(f"manifest metadata overwrites protected fields: {sorted(overlap)}")
            manifest.update(extra)
        if _sha256(basin_file) != initial_basin_file_sha256:
            raise ValueError("trusted basin file changed during target construction")
        with manifest_temporary.open("x", encoding="utf-8", newline="\n") as handle:
            json.dump(manifest, handle, indent=2, sort_keys=True)
            handle.write("\n")
        os.replace(manifest_temporary, manifest_path)
        return manifest
    except BaseException:
        _cleanup_partial((output_temporary, manifest_temporary))
        if output_moved:
            _cleanup_partial((output_path,))
        raise


def write_synthetic_target_bundle_v09(
    *,
    basins: Sequence[str],
    basin_file: str | Path,
    output_path: str | Path,
    load_one: Callable[[str], pd.Series],
    checkpoint: Callable[[], object] | None = None,
) -> dict:
    """Exercise the streaming writer outside the complete formal result tree."""
    output_path = Path(output_path).resolve()
    formal_root = (
        WORKTREE_ROOT / "results/26_historical_band_experts/formal_v09"
    ).resolve()
    if output_path == formal_root or formal_root in output_path.parents:
        raise ValueError("synthetic writer cannot write inside the formal result tree")
    return _write_streaming_target_bundle_v09(
        basins=basins,
        basin_file=basin_file,
        output_path=output_path,
        load_one=load_one,
        checkpoint=checkpoint,
    )


def _find_unique_source_v09(root: Path, pattern: str) -> Path:
    matches = sorted(root.glob(pattern))
    if len(matches) != 1:
        raise FileNotFoundError(f"expected one trusted source for {pattern}, found {len(matches)}")
    source = matches[0]
    _assert_no_reparse_components_v09(root, source)
    if not source.is_file():
        raise FileNotFoundError(f"trusted source is not a regular file: {source}")
    return source


def _read_maurer_area_v09(path: Path) -> int:
    with path.open("r", encoding="utf-8") as handle:
        handle.readline()
        handle.readline()
        area = int(handle.readline().strip())
    if area <= 0:
        raise ValueError("Maurer source area must be positive")
    return area


def _scan_date_prefix_v09(line: str, *, line_number: int) -> tuple[tuple[str, str, str, str], int]:
    """Return only basin/year/month/day tokens and the untouched remainder offset."""
    fields = []
    cursor = 0
    length = len(line)
    while len(fields) < 4:
        while cursor < length and line[cursor].isspace():
            cursor += 1
        start = cursor
        while cursor < length and not line[cursor].isspace():
            cursor += 1
        if start == cursor:
            raise ValueError(f"invalid streamflow date prefix at line {line_number}")
        fields.append(line[start:cursor])
    return (fields[0], fields[1], fields[2], fields[3]), cursor


def _load_training_discharge_window_v09(path: str | Path, *, area: int) -> pd.Series:
    """Parse discharge values only inside 1999-10-01 through 2008-09-30."""
    dates = []
    values = []
    with Path(path).open("r", encoding="utf-8") as handle:
        for line_number, line in enumerate(handle, 1):
            (_basin, year_text, month_text, day_text), remainder_offset = (
                _scan_date_prefix_v09(line, line_number=line_number)
            )
            year, month, day = (int(value) for value in (year_text, month_text, day_text))
            date = pd.Timestamp(year=year, month=month, day=day)
            if date < TRAIN_START or date > VALIDATION_END:
                continue
            target_fields = line[remainder_offset:].split()
            if len(target_fields) < 2:
                raise ValueError(f"invalid training streamflow row at line {line_number}")
            qobs_cfs = float(target_fields[0])
            dates.append(date)
            values.append(_DISCHARGE_TO_MM_PER_DAY * qobs_cfs / (area * 10**6))
    if len(dates) != len(set(dates)):
        raise ValueError("training discharge source contains duplicate dates")
    return pd.Series(values, index=pd.DatetimeIndex(dates), dtype=np.float64)


def _source_tree_provenance_v09() -> dict:
    completed = subprocess.run(
        ["git", "status", "--porcelain", "--untracked-files=all"],
        cwd=WORKTREE_ROOT,
        capture_output=True,
        text=True,
        check=True,
    )
    if completed.stdout:
        raise ValueError("formal target construction requires a clean Git worktree")
    commit = subprocess.run(
        ["git", "rev-parse", "HEAD"],
        cwd=WORKTREE_ROOT,
        capture_output=True,
        text=True,
        check=True,
    ).stdout.strip()
    files = [
        {"relative_path": relative, "sha256": _sha256(WORKTREE_ROOT / relative)}
        for relative in _BUILD_SOURCE_FILES
    ]
    return {
        "schema": "git_clean_exact_files_v1",
        "git_commit": commit,
        "git_worktree_clean": True,
        "files": files,
        "tree_sha256": _canonical_sha256(files),
    }


def prepare_formal_target_bundle_v09(config: Mapping) -> dict:
    """Use only frozen roots and the fixed destination after formal authorization."""
    validate_protocol_v09(config)
    target_spec = config["formal_action_resources"]["target_bundle"]
    relative_output = Path(target_spec["output_path"])
    if relative_output != FORMAL_RELATIVE_OUTPUT or relative_output.is_absolute():
        raise ValueError("formal target output path differs from the frozen destination")
    relative_manifest = Path(target_spec["manifest_path"])
    if relative_manifest != relative_output.with_suffix(".manifest.json"):
        raise ValueError("formal target manifest path differs from the frozen destination")
    data_root = _formal_data_root_v09(config)
    basin_file = WORKTREE_ROOT / config["basin_file"]
    output_path = WORKTREE_ROOT / relative_output

    def build(runtime: FormalActionRuntimeV09) -> dict:
        _assert_no_reparse_components_v09(_primary_repository_root_v09(), data_root)
        _assert_no_reparse_components_v09(WORKTREE_ROOT, basin_file)
        if not data_root.is_dir():
            raise FileNotFoundError(f"frozen formal data root does not exist: {data_root}")
        basin_ids = _validate_formal_basin_file_v09(config, basin_file)
        source_tree = _source_tree_provenance_v09()
        source_records = []

        def load_one(basin: str) -> pd.Series:
            forcing = _find_unique_source_v09(
                data_root / "basin_mean_forcing" / "maurer",
                f"**/{basin}_*_forcing_leap.txt",
            )
            discharge = _find_unique_source_v09(
                data_root / "usgs_streamflow",
                f"**/{basin}_streamflow_qc.txt",
            )
            before = {"maurer": _sha256(forcing), "streamflow": _sha256(discharge)}
            area = _read_maurer_area_v09(forcing)
            series = _load_training_discharge_window_v09(discharge, area=area)
            after = {"maurer": _sha256(forcing), "streamflow": _sha256(discharge)}
            if after != before:
                raise ValueError(f"trusted source changed while reading basin {basin}")
            for kind, path in (("maurer", forcing), ("streamflow", discharge)):
                source_records.append({
                    "basin": basin,
                    "kind": kind,
                    "relative_path": path.relative_to(data_root).as_posix(),
                    "sha256": before[kind],
                })
            return series

        def manifest_metadata() -> Mapping:
            if len(source_records) != 2 * len(basin_ids):
                raise ValueError("formal source manifest coverage is incomplete")
            return {
                "canonical_data_root": str(data_root.resolve(strict=True)),
                "canonical_data_root_relative": FORMAL_DATA_RELATIVE_ROOT.as_posix(),
                "source_hash_policy": target_spec["source_hashes"],
                "evaluation_observation_handling": target_spec[
                    "evaluation_observation_handling"
                ],
                "source_files": source_records,
                "source_files_sha256": _canonical_sha256(source_records),
                "build_source_tree": source_tree,
            }

        return _write_streaming_target_bundle_v09(
            basins=basin_ids,
            basin_file=basin_file,
            output_path=output_path,
            load_one=load_one,
            runtime=runtime,
            protocol_canonical_sha256=runtime.estimate["evidence"][
                "protocol_canonical_sha256"
            ],
            manifest_metadata=manifest_metadata,
        )

    return run_authorized_formal_action_v09(
        config,
        action="formal_target_bundle_generation",
        callback=build,
    )


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", type=Path, default=DEFAULT_CONFIG)
    args = parser.parse_args()
    config = load_protocol_v09(args.config)
    report = prepare_formal_target_bundle_v09(config)
    print(json.dumps(report, indent=2, sort_keys=True, default=str))


if __name__ == "__main__":
    main()
