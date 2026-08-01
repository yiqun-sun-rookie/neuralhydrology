"""Immutable, hash-chained candidate, experiment, and state records."""

from __future__ import annotations

import hashlib
import json
import os
import sqlite3
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


ZERO_HASH = "0" * 64
CORRECTABLE_TYPES = {"candidate", "experiment", "fingerprint"}
ALLOWED_TRANSITIONS = {
    (None, "registered"),
    ("registered", "validated"),
    ("registered", "rejected"),
    ("validated", "queued"),
    ("queued", "running"),
    ("running", "checkpointed"),
    ("running", "succeeded"),
    ("running", "failed"),
    ("checkpointed", "running"),
    ("failed", "queued"),
}
LOCK_REQUIRED_TRANSITIONS = {
    ("queued", "running"),
    ("checkpointed", "running"),
    ("running", "checkpointed"),
    ("running", "succeeded"),
    ("running", "failed"),
}


def _io_path(path: str | Path) -> str:
    absolute = str(Path(path).resolve())
    if os.name != "nt" or absolute.startswith("\\\\?\\"):
        return absolute
    if absolute.startswith("\\\\"):
        return "\\\\?\\UNC\\" + absolute[2:]
    return "\\\\?\\" + absolute


def _canonical_json(value: Any) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False, allow_nan=False)


def _hash_record(record: dict[str, Any]) -> str:
    return hashlib.sha256(_canonical_json(record).encode("utf-8")).hexdigest()


class Registry:
    """Append records atomically; derive current state instead of updating rows."""

    def __init__(
        self,
        path: str | Path,
        *,
        scheduler_lock_path: str | Path | None = None,
        receipt_dir: str | Path | None = None,
    ):
        self.path = Path(path).resolve()
        self.scheduler_lock_path = (
            Path(scheduler_lock_path).resolve()
            if scheduler_lock_path is not None
            else self.path.with_name("scheduler.lock")
        )
        self.receipt_dir = (
            Path(receipt_dir).resolve()
            if receipt_dir is not None
            else self.path.with_name(f"{self.path.name}.receipts")
        )
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self.receipt_dir.mkdir(parents=True, exist_ok=True)
        self._initialize()

    def _connect(self) -> sqlite3.Connection:
        connection = sqlite3.connect(self.path, timeout=10.0, isolation_level=None)
        connection.row_factory = sqlite3.Row
        connection.execute("PRAGMA foreign_keys = ON")
        connection.execute("PRAGMA busy_timeout = 10000")
        return connection

    def _initialize(self) -> None:
        with self._connect() as connection:
            connection.executescript(
                """
                PRAGMA journal_mode = DELETE;
                PRAGMA synchronous = FULL;
                CREATE TABLE IF NOT EXISTS records (
                    sequence INTEGER PRIMARY KEY,
                    record_id TEXT NOT NULL UNIQUE,
                    record_type TEXT NOT NULL CHECK(record_type IN ('candidate', 'experiment', 'state', 'fingerprint')),
                    subject_id TEXT NOT NULL,
                    payload_json TEXT NOT NULL,
                    corrects_record_id TEXT,
                    created_at_utc TEXT NOT NULL,
                    previous_record_hash TEXT NOT NULL,
                    record_hash TEXT NOT NULL UNIQUE,
                    FOREIGN KEY(corrects_record_id) REFERENCES records(record_id)
                );
                CREATE INDEX IF NOT EXISTS records_subject ON records(record_type, subject_id, sequence);
                CREATE TRIGGER IF NOT EXISTS records_no_update
                BEFORE UPDATE ON records
                BEGIN
                    SELECT RAISE(ABORT, 'records are immutable');
                END;
                CREATE TRIGGER IF NOT EXISTS records_no_delete
                BEFORE DELETE ON records
                BEGIN
                    SELECT RAISE(ABORT, 'records are immutable');
                END;
                """
            )

    def _latest(self, connection: sqlite3.Connection, record_type: str, subject_id: str) -> sqlite3.Row | None:
        return connection.execute(
            "SELECT * FROM records WHERE record_type = ? AND subject_id = ? ORDER BY sequence DESC LIMIT 1",
            (record_type, subject_id),
        ).fetchone()

    @staticmethod
    def _receipt_name(sequence: int, record_id: str) -> str:
        return f"{sequence:020d}.{record_id}.json"

    @staticmethod
    def _receipt_payload(row: dict[str, Any]) -> dict[str, Any]:
        return {
            "schema_version": "registry_receipt_v1",
            "sequence": int(row["sequence"]),
            "record_id": str(row["record_id"]),
            "record_type": str(row["record_type"]),
            "subject_id": str(row["subject_id"]),
            "previous_record_hash": str(row["previous_record_hash"]),
            "record_hash": str(row["record_hash"]),
        }

    def _write_receipt(self, row: dict[str, Any]) -> None:
        receipt = self._receipt_payload(row)
        path = self.receipt_dir / self._receipt_name(receipt["sequence"], receipt["record_id"])
        descriptor = os.open(_io_path(path), os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o444)
        try:
            with os.fdopen(descriptor, "w", encoding="utf-8", newline="\n") as stream:
                stream.write(_canonical_json(receipt))
                stream.write("\n")
                stream.flush()
                os.fsync(stream.fileno())
        except Exception:
            try:
                os.unlink(_io_path(path))
            except FileNotFoundError:
                pass
            raise

    def _append_locked(
        self,
        connection: sqlite3.Connection,
        record_type: str,
        subject_id: str,
        payload: dict[str, Any],
        corrects_record_id: str | None,
    ) -> str:
        latest = self._latest(connection, record_type, subject_id)
        if record_type in CORRECTABLE_TYPES:
            expected_correction = None if latest is None else str(latest["record_id"])
            if corrects_record_id != expected_correction:
                raise ValueError("correction must reference the latest record for the same type and subject")
        elif corrects_record_id is not None:
            raise ValueError(f"{record_type} records do not accept correction references")

        sequence = int(connection.execute("SELECT COALESCE(MAX(sequence), 0) + 1 FROM records").fetchone()[0])
        previous_row = connection.execute("SELECT record_hash FROM records ORDER BY sequence DESC LIMIT 1").fetchone()
        previous_hash = ZERO_HASH if previous_row is None else str(previous_row["record_hash"])
        record_id = uuid.uuid4().hex
        payload_json = _canonical_json(payload)
        created_at = datetime.now(timezone.utc).isoformat(timespec="microseconds")
        body = {
            "sequence": sequence,
            "record_id": record_id,
            "record_type": record_type,
            "subject_id": subject_id,
            "payload_json": payload_json,
            "corrects_record_id": corrects_record_id,
            "created_at_utc": created_at,
            "previous_record_hash": previous_hash,
        }
        record_hash = _hash_record(body)
        connection.execute(
            """INSERT INTO records
               (sequence, record_id, record_type, subject_id, payload_json, corrects_record_id,
                created_at_utc, previous_record_hash, record_hash)
               VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)""",
            (
                sequence,
                record_id,
                record_type,
                subject_id,
                payload_json,
                corrects_record_id,
                created_at,
                previous_hash,
                record_hash,
            ),
        )
        self._write_receipt({**body, "record_hash": record_hash})
        return record_id

    def _append_definition(
        self,
        record_type: str,
        subject_id: str,
        payload: dict[str, Any],
        corrects_record_id: str | None,
    ) -> str:
        with self._connect() as connection:
            connection.execute("BEGIN IMMEDIATE")
            try:
                record_id = self._append_locked(connection, record_type, subject_id, payload, corrects_record_id)
                connection.commit()
                return record_id
            except Exception:
                connection.rollback()
                raise

    def append_candidate(
        self, candidate_id: str, description: dict[str, Any], *, corrects_record_id: str | None = None
    ) -> str:
        return self._append_definition("candidate", candidate_id, description, corrects_record_id)

    def append_experiment(
        self, experiment_id: str, definition: dict[str, Any], *, corrects_record_id: str | None = None
    ) -> str:
        return self._append_definition("experiment", experiment_id, definition, corrects_record_id)

    def append_fingerprint(
        self, run_id: str, fingerprint: dict[str, Any], *, corrects_record_id: str | None = None
    ) -> str:
        from .fingerprint import validate_fingerprint

        validate_fingerprint(fingerprint)
        return self._append_definition("fingerprint", run_id, fingerprint, corrects_record_id)

    def current_state(self, experiment_id: str) -> str | None:
        with self._connect() as connection:
            latest = self._latest(connection, "state", experiment_id)
        if latest is None:
            return None
        return str(json.loads(latest["payload_json"])["to_state"])

    def transition(
        self,
        experiment_id: str,
        *,
        expected_from: str | None,
        to_state: str,
        reason: str,
        scheduler_lock: Any | None = None,
    ) -> str:
        with self._connect() as connection:
            connection.execute("BEGIN IMMEDIATE")
            try:
                latest = self._latest(connection, "state", experiment_id)
                current = None if latest is None else str(json.loads(latest["payload_json"])["to_state"])
                if current != expected_from:
                    raise ValueError(f"state changed concurrently: expected {expected_from!r}, found {current!r}")
                if (current, to_state) not in ALLOWED_TRANSITIONS:
                    raise ValueError(f"illegal state transition: {current!r} -> {to_state!r}")
                payload: dict[str, Any] = {"from_state": current, "to_state": to_state, "reason": reason}
                if (current, to_state) in LOCK_REQUIRED_TRANSITIONS:
                    if scheduler_lock is None:
                        raise PermissionError("configured scheduler lock ownership is required for this transition")
                    if Path(scheduler_lock.path).resolve() != self.scheduler_lock_path:
                        raise PermissionError("scheduler lock path does not match the registry configuration")
                    payload["scheduler_lock"] = scheduler_lock.ownership_proof()
                record_id = self._append_locked(
                    connection,
                    "state",
                    experiment_id,
                    payload,
                    None,
                )
                if scheduler_lock is not None and (current, to_state) in LOCK_REQUIRED_TRANSITIONS:
                    scheduler_lock.ownership_proof()
                connection.commit()
                return record_id
            except Exception:
                connection.rollback()
                raise

    def records(self, *, record_type: str | None = None, subject_id: str | None = None) -> list[dict[str, Any]]:
        clauses: list[str] = []
        parameters: list[str] = []
        if record_type is not None:
            clauses.append("record_type = ?")
            parameters.append(record_type)
        if subject_id is not None:
            clauses.append("subject_id = ?")
            parameters.append(subject_id)
        where = "" if not clauses else " WHERE " + " AND ".join(clauses)
        with self._connect() as connection:
            rows = connection.execute(f"SELECT * FROM records{where} ORDER BY sequence", parameters).fetchall()
        return [dict(row) for row in rows]

    def verify(self) -> dict[str, Any]:
        failures: list[str] = []
        rows = self.records()
        previous_hash = ZERO_HASH
        latest_by_subject: dict[tuple[str, str], str] = {}
        state_by_experiment: dict[str, str | None] = {}
        for row in rows:
            body = {
                key: row[key]
                for key in (
                    "sequence",
                    "record_id",
                    "record_type",
                    "subject_id",
                    "payload_json",
                    "corrects_record_id",
                    "created_at_utc",
                    "previous_record_hash",
                )
            }
            if row["previous_record_hash"] != previous_hash:
                failures.append(f"record {row['record_id']} previous hash mismatch")
            if _hash_record(body) != row["record_hash"]:
                failures.append(f"record {row['record_id']} record hash mismatch")
            previous_hash = str(row["record_hash"])

            key = (str(row["record_type"]), str(row["subject_id"]))
            if row["record_type"] in CORRECTABLE_TYPES:
                expected = latest_by_subject.get(key)
                if row["corrects_record_id"] != expected:
                    failures.append(f"record {row['record_id']} correction chain mismatch")
                latest_by_subject[key] = str(row["record_id"])
                if row["record_type"] == "fingerprint":
                    from .fingerprint import validate_fingerprint

                    try:
                        fingerprint = json.loads(row["payload_json"])
                        if not isinstance(fingerprint, dict):
                            raise ValueError("fingerprint payload is not an object")
                        validate_fingerprint(fingerprint)
                    except (json.JSONDecodeError, TypeError, ValueError) as error:
                        failures.append(f"record {row['record_id']} fingerprint payload invalid: {error}")
            elif row["record_type"] == "state":
                try:
                    payload = json.loads(row["payload_json"])
                except json.JSONDecodeError as error:
                    failures.append(f"record {row['record_id']} state payload invalid: {error}")
                    continue
                current = state_by_experiment.get(str(row["subject_id"]))
                if payload.get("from_state") != current or (current, payload.get("to_state")) not in ALLOWED_TRANSITIONS:
                    failures.append(f"record {row['record_id']} state transition mismatch")
                if (current, payload.get("to_state")) in LOCK_REQUIRED_TRANSITIONS:
                    proof = payload.get("scheduler_lock")
                    if not isinstance(proof, dict) or proof.get("lock_path") != str(self.scheduler_lock_path):
                        failures.append(f"record {row['record_id']} scheduler lock proof mismatch")
                state_by_experiment[str(row["subject_id"])] = payload.get("to_state")

        expected_receipts = {
            self._receipt_name(int(row["sequence"]), str(row["record_id"])): self._receipt_payload(row) for row in rows
        }
        with os.scandir(_io_path(self.receipt_dir)) as entries:
            actual_paths = {
                entry.name: entry.path
                for entry in entries
                if entry.name.endswith(".json") and entry.is_file()
            }
        for name in sorted(set(expected_receipts) - set(actual_paths)):
            failures.append(f"registry receipt missing: {name}")
        for name in sorted(set(actual_paths) - set(expected_receipts)):
            failures.append(f"registry receipt has no database record: {name}")
        for name in sorted(set(expected_receipts) & set(actual_paths)):
            try:
                with open(actual_paths[name], "r", encoding="utf-8") as stream:
                    actual = json.load(stream)
            except (OSError, json.JSONDecodeError):
                failures.append(f"registry receipt is unreadable: {name}")
                continue
            if actual != expected_receipts[name]:
                failures.append(f"registry receipt mismatch: {name}")
        return {"record_count": len(rows), "failure_count": len(failures), "failures": failures}
