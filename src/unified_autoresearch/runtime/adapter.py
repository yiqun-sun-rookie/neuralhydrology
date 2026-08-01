"""Construct the fixed command used for every Python candidate."""

from __future__ import annotations

import sys
from pathlib import Path


def build_candidate_command(*, policy_path: Path, access_log_path: Path, entrypoint: Path, mode: str) -> list[str]:
    bootstrap = Path(__file__).with_name("bootstrap.py").resolve()
    return [
        sys.executable,
        "-B",
        str(bootstrap),
        "--policy",
        str(policy_path),
        "--access-log",
        str(access_log_path),
        "--entrypoint",
        str(entrypoint),
        "--mode",
        mode,
    ]

