"""Atomic, permanent run-identifier registration."""

from __future__ import annotations

import json
import os
import re
from datetime import datetime
from pathlib import Path


def _timestamp() -> str:
    return datetime.now().astimezone().isoformat()


class RunRegistry:
    """Reserve an identifier once and retain its complete status history."""

    def __init__(self, results_root: Path, run_id: str):
        identifier = str(run_id)
        if re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.-]{0,127}", identifier) is None:
            raise ValueError("run identifier is invalid")
        self.identifier = identifier
        self.root = Path(results_root).resolve() / "registry"
        self.path = self.root / f"{identifier}.json"

    def reserve(self, run_type: str, **context) -> None:
        self.root.mkdir(parents=True, exist_ok=True)
        record = {
            "run_id": self.identifier,
            "run_type": str(run_type),
            "status": "running",
            "created_at": _timestamp(),
            "history": [{"status": "running", "timestamp": _timestamp(), **context}],
        }
        with self.path.open("x", encoding="utf-8") as handle:
            json.dump(record, handle, indent=2, sort_keys=True)
            handle.write("\n")

    def update(self, status: str, **context) -> None:
        if status not in {"running", "verified", "failed", "superseded"}:
            raise ValueError("registry status is invalid")
        if not self.path.is_file():
            raise FileNotFoundError(f"run identifier is not registered: {self.identifier}")
        record = json.loads(self.path.read_text(encoding="utf-8"))
        record["status"] = status
        record["updated_at"] = _timestamp()
        record.setdefault("history", []).append(
            {"status": status, "timestamp": record["updated_at"], **context}
        )
        temporary = self.path.with_name(f".{self.path.name}.{os.getpid()}.tmp")
        temporary.write_text(json.dumps(record, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        os.replace(temporary, self.path)

