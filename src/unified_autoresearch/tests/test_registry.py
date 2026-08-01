import json
import hashlib
import os
import sqlite3
from datetime import datetime, timezone
from concurrent.futures import ThreadPoolExecutor

import pytest


def _registry(tmp_path):
    from unified_autoresearch.registry.store import Registry

    return Registry(tmp_path / "registry.sqlite")


def test_candidate_records_are_immutable_and_corrections_reference_latest_record(tmp_path):
    registry = _registry(tmp_path)
    original = registry.append_candidate("candidate-a", {"category": "deep_learning", "entrypoint": "a.py"})

    with sqlite3.connect(registry.path) as connection:
        with pytest.raises(sqlite3.IntegrityError, match="records are immutable"):
            connection.execute("UPDATE records SET subject_id = 'changed' WHERE record_id = ?", (original, ))
        with pytest.raises(sqlite3.IntegrityError, match="records are immutable"):
            connection.execute("DELETE FROM records WHERE record_id = ?", (original, ))

    with pytest.raises(ValueError, match="correction must reference the latest record"):
        registry.append_candidate("candidate-a", {"category": "deep_learning", "entrypoint": "b.py"})

    corrected = registry.append_candidate(
        "candidate-a", {"category": "deep_learning", "entrypoint": "b.py"}, corrects_record_id=original
    )
    records = registry.records(record_type="candidate", subject_id="candidate-a")
    assert [record["record_id"] for record in records] == [original, corrected]
    assert records[1]["corrects_record_id"] == original

    with pytest.raises(ValueError, match="correction must reference the latest record"):
        registry.append_candidate(
            "candidate-a", {"category": "deep_learning", "entrypoint": "c.py"}, corrects_record_id=original
        )


def test_experiment_correction_cannot_reference_another_subject(tmp_path):
    registry = _registry(tmp_path)
    candidate = registry.append_candidate("candidate-a", {"category": "custom_python"})
    experiment_a = registry.append_experiment("experiment-a", {"candidate_record_id": candidate, "seed": 1})
    experiment_b = registry.append_experiment("experiment-b", {"candidate_record_id": candidate, "seed": 2})

    with pytest.raises(ValueError, match="correction must reference the latest record"):
        registry.append_experiment(
            "experiment-a", {"candidate_record_id": candidate, "seed": 3}, corrects_record_id=experiment_b
        )
    corrected = registry.append_experiment(
        "experiment-a", {"candidate_record_id": candidate, "seed": 3}, corrects_record_id=experiment_a
    )
    assert corrected != experiment_a


def test_state_transitions_are_atomic_and_illegal_transition_is_rejected(tmp_path):
    from unified_autoresearch.registry.scheduler_lock import SchedulerLock

    registry = _registry(tmp_path)
    registry.transition("experiment-a", expected_from=None, to_state="registered", reason="definition appended")
    registry.transition("experiment-a", expected_from="registered", to_state="validated", reason="contract valid")
    registry.transition("experiment-a", expected_from="validated", to_state="queued", reason="ready")

    def start():
        try:
            registry.transition(
                "experiment-a",
                expected_from="queued",
                to_state="running",
                reason="scheduler",
                scheduler_lock=lock,
            )
            return "success"
        except ValueError as error:
            return str(error)

    lock = SchedulerLock(registry.scheduler_lock_path, run_id="scheduler-run")
    lock.acquire()
    try:
        with ThreadPoolExecutor(max_workers=2) as executor:
            outcomes = list(executor.map(lambda _: start(), range(2)))
    finally:
        lock.release()
    assert outcomes.count("success") == 1
    assert sum("state changed concurrently" in outcome for outcome in outcomes) == 1
    assert registry.current_state("experiment-a") == "running"

    with pytest.raises(ValueError, match="illegal state transition"):
        registry.transition("experiment-a", expected_from="running", to_state="validated", reason="go backwards")


def test_transition_to_running_requires_the_configured_scheduler_lock(tmp_path):
    from unified_autoresearch.registry.scheduler_lock import SchedulerLock

    registry = _registry(tmp_path)
    registry.transition("experiment-a", expected_from=None, to_state="registered", reason="definition appended")
    registry.transition("experiment-a", expected_from="registered", to_state="validated", reason="contract valid")
    registry.transition("experiment-a", expected_from="validated", to_state="queued", reason="ready")

    with pytest.raises(PermissionError, match="scheduler lock"):
        registry.transition("experiment-a", expected_from="queued", to_state="running", reason="unlocked caller")

    wrong_lock = SchedulerLock(tmp_path / "other-scheduler.lock", run_id="wrong-scheduler")
    wrong_lock.acquire()
    try:
        with pytest.raises(PermissionError, match="path does not match"):
            registry.transition(
                "experiment-a",
                expected_from="queued",
                to_state="running",
                reason="wrong lock",
                scheduler_lock=wrong_lock,
            )
    finally:
        wrong_lock.release()

    owner = SchedulerLock(registry.scheduler_lock_path, run_id="scheduler-run")
    owner.acquire()
    try:
        registry.transition(
            "experiment-a",
            expected_from="queued",
            to_state="running",
            reason="owned lock",
            scheduler_lock=owner,
        )
    finally:
        owner.release()

    payload = json.loads(registry.records(record_type="state", subject_id="experiment-a")[-1]["payload_json"])
    assert payload["scheduler_lock"]["lock_path"] == str(registry.scheduler_lock_path)
    assert payload["scheduler_lock"]["run_id"] == "scheduler-run"
    assert len(payload["scheduler_lock"]["token_sha256"]) == 64


def test_registry_verifier_detects_chain_tampering(tmp_path):
    registry = _registry(tmp_path)
    registry.append_candidate("candidate-a", {"category": "fusion"})
    registry.append_candidate("candidate-b", {"category": "conceptual_rainfall_runoff"})
    assert registry.verify()["failure_count"] == 0

    with sqlite3.connect(registry.path) as connection:
        connection.execute("DROP TRIGGER records_no_update")
        connection.execute(
            "UPDATE records SET payload_json = ? WHERE subject_id = ?",
            (json.dumps({"category": "tampered"}), "candidate-a"),
        )

    verification = registry.verify()
    assert verification["failure_count"] >= 1
    assert any("record hash mismatch" in failure for failure in verification["failures"])


def test_registry_verifier_detects_deleted_chain_tail_with_external_receipt(tmp_path):
    registry = _registry(tmp_path)
    registry.append_candidate("candidate-a", {"category": "fusion"})
    registry.append_candidate("candidate-b", {"category": "conceptual_rainfall_runoff"})

    with sqlite3.connect(registry.path) as connection:
        connection.execute("DROP TRIGGER records_no_delete")
        connection.execute("DELETE FROM records WHERE sequence = (SELECT MAX(sequence) FROM records)")

    verification = registry.verify()
    assert verification["failure_count"] >= 1
    assert any("receipt" in failure for failure in verification["failures"])


def test_registry_creates_and_verifies_receipt_beyond_windows_max_path(tmp_path):
    if os.name != "nt":
        pytest.skip("Windows extended-length path behavior")

    from unified_autoresearch.registry.store import Registry

    deep_root = tmp_path
    sample_receipt_name = f"{'0' * 20}.{'a' * 32}.json"
    index = 0
    while len(str(deep_root / "registry.sqlite.receipts" / sample_receipt_name)) <= 270:
        deep_root /= f"segment-{index:02d}-{'x' * 20}"
        index += 1
    deep_root.mkdir(parents=True)
    registry = Registry(deep_root / "registry.sqlite")

    assert len(str(registry.path)) < 260
    assert len(str(registry.receipt_dir / sample_receipt_name)) > 260

    record_id = registry.append_candidate("candidate-deep", {"category": "custom_python"})

    receipt_name = registry._receipt_name(1, record_id)
    receipt_path = registry.receipt_dir / receipt_name
    assert os.path.isfile(f"\\\\?\\{receipt_path}")
    assert registry.records() == registry.records(record_type="candidate", subject_id="candidate-deep")
    assert registry.verify() == {"record_count": 1, "failure_count": 0, "failures": []}


def _fingerprint(component_value="a"):
    names = [
        "git_commit", "code", "uncommitted_diff", "configuration", "dependencies", "data_manifest",
        "random_seeds", "artifacts"
    ]
    details = {name: {"value": component_value} for name in names}
    components = {
        name: hashlib.sha256(
            json.dumps(details[name], sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
        ).hexdigest()
        for name in names
    }
    body = json.dumps(
        {"schema_version": "experiment_fingerprint_v1", "components": components},
        sort_keys=True,
        separators=(",", ":"),
        ensure_ascii=False,
    ).encode("utf-8")
    return {
        "schema_version": "experiment_fingerprint_v1",
        "components": components,
        "root_sha256": hashlib.sha256(body).hexdigest(),
        "details": details,
    }


def test_fingerprint_records_are_validated_and_corrected_by_append_only_reference(tmp_path):
    registry = _registry(tmp_path)
    original = registry.append_fingerprint("experiment-a/run-1", _fingerprint("a"))

    invalid = _fingerprint("b")
    invalid["root_sha256"] = "0" * 64
    with pytest.raises(ValueError, match="fingerprint root mismatch"):
        registry.append_fingerprint("experiment-b/run-1", invalid)

    with pytest.raises(ValueError, match="correction must reference the latest record"):
        registry.append_fingerprint("experiment-a/run-1", _fingerprint("b"))
    corrected = registry.append_fingerprint(
        "experiment-a/run-1", _fingerprint("b"), corrects_record_id=original
    )
    assert corrected != original
    assert registry.verify()["failure_count"] == 0


def test_registry_verifier_revalidates_fingerprint_payload_semantics(tmp_path):
    from unified_autoresearch.registry.store import _canonical_json, _hash_record

    registry = _registry(tmp_path)
    original = registry.append_fingerprint("experiment-a/run-1", _fingerprint("a"))
    invalid = _fingerprint("b")
    invalid["details"]["code"] = {"value": "changed-without-updating-component"}

    previous = registry.records()[-1]
    body = {
        "sequence": int(previous["sequence"]) + 1,
        "record_id": "forged-fingerprint-record",
        "record_type": "fingerprint",
        "subject_id": "experiment-a/run-1",
        "payload_json": _canonical_json(invalid),
        "corrects_record_id": original,
        "created_at_utc": datetime.now(timezone.utc).isoformat(timespec="microseconds"),
        "previous_record_hash": previous["record_hash"],
    }
    record_hash = _hash_record(body)
    with sqlite3.connect(registry.path) as connection:
        connection.execute(
            """INSERT INTO records
               (sequence, record_id, record_type, subject_id, payload_json, corrects_record_id,
                created_at_utc, previous_record_hash, record_hash)
               VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)""",
            (*body.values(), record_hash),
        )
    registry._write_receipt({**body, "record_hash": record_hash})

    verification = registry.verify()
    assert verification["failure_count"] >= 1
    assert any("fingerprint payload" in failure for failure in verification["failures"])
