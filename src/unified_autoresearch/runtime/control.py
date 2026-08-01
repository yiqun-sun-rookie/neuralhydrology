"""Create one immutable stop request that a running candidate can poll."""

from __future__ import annotations

import json
import os
import re
from datetime import datetime, timezone
from pathlib import Path


REQUEST_ID_PATTERN = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$")


def request_controlled_stop(control_root: str | Path, *, request_id: str, reason: str) -> Path:
    """Exclusively create the fixed controlled-stop request file."""
    if REQUEST_ID_PATTERN.fullmatch(request_id) is None or not reason or len(reason) > 1024:
        raise ValueError("controlled stop request is invalid")
    root = Path(control_root).resolve()
    if not root.is_dir():
        raise ValueError(f"control root does not exist: {root}")
    path = root / "STOP_REQUEST.json"
    value = {
        "schema_version": "controlled_stop_request_v1",
        "request_id": request_id,
        "reason": reason,
        "created_at_utc": datetime.now(timezone.utc).isoformat(timespec="microseconds"),
    }
    descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o444)
    with os.fdopen(descriptor, "w", encoding="utf-8", newline="\n") as stream:
        json.dump(value, stream, indent=2, sort_keys=True)
        stream.write("\n")
        stream.flush()
        os.fsync(stream.fileno())
    return path

