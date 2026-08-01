"""Build one isolated, non-reusable candidate run directory."""

from __future__ import annotations

import json
import shutil
import stat
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Mapping

from .descriptor import CandidateDescriptor


@dataclass(frozen=True)
class RunLayout:
    root: Path
    descriptor_path: Path
    candidate_root: Path
    input_root: Path
    output_root: Path
    checkpoint_staging_root: Path
    checkpoints_root: Path
    control_root: Path
    log_root: Path


def _make_tree_read_only(root: Path) -> None:
    for path in sorted(root.rglob("*"), reverse=True):
        if path.is_file():
            path.chmod(stat.S_IREAD)


def _copy_input(source: Path, target: Path) -> None:
    if source.is_dir():
        shutil.copytree(source, target)
    elif source.is_file():
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, target)
    else:
        raise ValueError(f"declared input does not exist: {source}")


def _unlinked_path(path: str | Path) -> Path:
    """Resolve a declared path only after proving the path itself is not a symbolic link."""
    given = Path(path).absolute()
    if given.is_symlink():
        raise ValueError(f"linked input or candidate file is forbidden: {given}")
    return given.resolve()


def _reject_linked_files(root: Path) -> None:
    paths = [root, *root.rglob("*")] if root.is_dir() else [root]
    for path in paths:
        if path.is_symlink() or (path.is_file() and path.stat().st_nlink != 1):
            raise ValueError(f"linked input or candidate file is forbidden: {path}")


def create_run_layout(
    root: str | Path,
    *,
    descriptor: CandidateDescriptor,
    candidate_source_root: str | Path,
    mode: str,
    input_sources: Mapping[str, str | Path],
) -> RunLayout:
    """Copy exactly one mode's declared inputs into a newly created run root."""
    final_root = Path(root).resolve()
    if final_root.exists():
        raise FileExistsError(f"run root already exists: {final_root}")
    if mode not in {"train", "predict"}:
        raise ValueError(f"unsupported candidate mode: {mode!r}")
    expected_inputs = set(descriptor.allowed_reads[mode])
    if set(input_sources) != expected_inputs:
        raise ValueError("input sources must exactly match declared reads")

    candidate_source = _unlinked_path(candidate_source_root)
    if not candidate_source.is_dir():
        raise ValueError(f"candidate source root does not exist: {candidate_source}")
    sources = {name: _unlinked_path(path) for name, path in input_sources.items()}
    for source in sources.values():
        if not source.exists():
            raise ValueError(f"declared input does not exist: {source}")
    _reject_linked_files(candidate_source)
    for source in sources.values():
        _reject_linked_files(source)

    final_root.parent.mkdir(parents=True, exist_ok=True)
    final_root.mkdir()
    descriptor_path = final_root / "candidate-descriptor.json"
    candidate_root = final_root / "candidate"
    input_root = final_root / "inputs"
    output_root = final_root / "outputs"
    checkpoint_staging_root = final_root / "checkpoint_staging"
    checkpoints_root = final_root / "checkpoints"
    control_root = final_root / "control"
    log_root = final_root / "logs"

    shutil.copytree(candidate_source, candidate_root)
    input_root.mkdir()
    for name, source in sources.items():
        _copy_input(source, input_root / name)
    output_root.mkdir()
    checkpoint_staging_root.mkdir()
    checkpoints_root.mkdir()
    control_root.mkdir()
    log_root.mkdir()
    with descriptor_path.open("x", encoding="utf-8", newline="\n") as stream:
        json.dump(asdict(descriptor), stream, indent=2, sort_keys=True)
        stream.write("\n")
        stream.flush()
    _make_tree_read_only(candidate_root)
    _make_tree_read_only(input_root)

    return RunLayout(
        root=final_root,
        descriptor_path=descriptor_path,
        candidate_root=candidate_root,
        input_root=input_root,
        output_root=output_root,
        checkpoint_staging_root=checkpoint_staging_root,
        checkpoints_root=checkpoints_root,
        control_root=control_root,
        log_root=log_root,
    )
