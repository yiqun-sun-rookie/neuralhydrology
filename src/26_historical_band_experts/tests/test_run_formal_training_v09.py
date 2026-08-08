"""Resumable serial orchestrator (stage S4).

The behaviour that matters: stopping and restarting must be free. Progress is derived from
the sealed directories every time, so a restart neither re-runs finished work nor needs any
one-use token. Anything half-written stops the suite for a human instead of being cleaned up
automatically.
"""
from pathlib import Path
import json
import sys

import pytest

IDEA_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(IDEA_ROOT))

ORDER_PATH = IDEA_ROOT / "configs/formal_v09_run_order.json"


def _specs():
    from train_formal_v09 import load_run_order_v09

    return load_run_order_v09(ORDER_PATH)


def _seal_a_run(worktree, spec):
    """Write a directory that looks exactly like a finished run."""
    from artifact_v09 import canonical_sha256, exact_file_inventory, sha256_file, write_json_atomic
    from run_formal_training_v09 import run_paths_v09

    final, _, _ = run_paths_v09(worktree, spec)
    final.mkdir(parents=True, exist_ok=True)
    manifest = {
        "schema": "historical_multiscale_formal_v09_main_run_v1",
        "status": "formal_training_complete",
        "variant": spec.variant,
        "seed": spec.seed,
        "trainable_parameters": spec.trainable_parameters,
    }
    write_json_atomic(final / "manifest.json", manifest)
    sealed = exact_file_inventory(final, ("manifest.json",))
    write_json_atomic(
        final / "seal.json", {
            "schema": "historical_multiscale_formal_v09_main_run_seal_v1",
            "status": "sealed",
            "sealed_files": sealed,
            "sealed_files_sha256": canonical_sha256(sealed),
            "manifest_sha256": sha256_file(final / "manifest.json"),
        })
    return final


def _fake_launcher(recorder, *, fail_on=None, produce=True):
    def launcher(spec, *, worktree_root, output_dir, protocol_path, input_root, device, python=None):
        recorder.append(spec.run_id)
        if fail_on is not None and spec.run_id == fail_on:
            Path(output_dir).mkdir(parents=True, exist_ok=True)
            return 1
        if produce:
            _seal_into(Path(output_dir), spec)
        return 0

    return launcher


def _seal_into(directory, spec):
    from artifact_v09 import canonical_sha256, exact_file_inventory, sha256_file, write_json_atomic

    directory.mkdir(parents=True, exist_ok=True)
    write_json_atomic(
        directory / "manifest.json", {
            "schema": "historical_multiscale_formal_v09_main_run_v1",
            "status": "formal_training_complete",
            "variant": spec.variant,
            "seed": spec.seed,
            "trainable_parameters": spec.trainable_parameters,
        })
    sealed = exact_file_inventory(directory, ("manifest.json",))
    write_json_atomic(
        directory / "seal.json", {
            "schema": "historical_multiscale_formal_v09_main_run_seal_v1",
            "status": "sealed",
            "sealed_files": sealed,
            "sealed_files_sha256": canonical_sha256(sealed),
            "manifest_sha256": sha256_file(directory / "manifest.json"),
        })


def _suite(tmp_path, **kwargs):
    from run_formal_training_v09 import run_training_suite_v09

    return run_training_suite_v09(
        tmp_path,
        device="cpu",
        protocol_path=IDEA_ROOT / "configs/formal_v09_protocol.json",
        input_root=tmp_path / "inputs",
        run_order_path=ORDER_PATH,
        formal_root=tmp_path / "formal",
        **kwargs,
    )


# --------------------------------------------------------------------------------------


def test_each_family_gets_its_own_parent_directory(tmp_path):
    from run_formal_training_v09 import run_paths_v09

    roots = set()
    for spec in _specs():
        final, building, failed = run_paths_v09(tmp_path, spec)
        assert final.name == f"seed_{spec.seed}"
        assert building.name == f"seed_{spec.seed}.building"
        assert failed.name == f"seed_{spec.seed}.failed"
        roots.add(final.parent.name)
    assert roots == {"classic", "capacity", "continuous"}


def test_a_fresh_tree_has_everything_pending(tmp_path):
    from run_formal_training_v09 import scan_progress_v09

    progress = scan_progress_v09(tmp_path, _specs())
    assert progress["total"] == 24
    assert len(progress["pending"]) == 24
    assert progress["completed"] == [] and progress["dirty"] == []


def test_the_suite_runs_the_frozen_order_and_is_free_to_restart(tmp_path):
    specs = _specs()
    seen = []
    result = _suite(tmp_path, launcher=_fake_launcher(seen), max_runs=5)
    assert seen == [s.run_id for s in specs[:5]]
    assert result["status"] == "suite_incomplete"
    assert len(result["progress"]["completed"]) == 5

    # restarting must not repeat finished work and must need no token of any kind
    again = []
    result2 = _suite(tmp_path, launcher=_fake_launcher(again), max_runs=5)
    assert again == [s.run_id for s in specs[5:10]]
    assert len(result2["progress"]["completed"]) == 10

    rest = []
    result3 = _suite(tmp_path, launcher=_fake_launcher(rest))
    assert len(rest) == 14
    assert result3["status"] == "suite_complete"
    assert result3["progress"]["pending"] == []


def test_restarting_a_finished_suite_does_nothing(tmp_path):
    _suite(tmp_path, launcher=_fake_launcher([]))
    seen = []
    result = _suite(tmp_path, launcher=_fake_launcher(seen))
    assert seen == []
    assert result["status"] == "suite_complete"


def test_a_failed_run_stops_the_suite_and_keeps_finished_work(tmp_path):
    from run_formal_training_v09 import SuiteError, run_paths_v09

    specs = _specs()
    target = specs[3].run_id
    seen = []
    with pytest.raises(SuiteError, match="exited 1"):
        _suite(tmp_path, launcher=_fake_launcher(seen, fail_on=target))
    assert seen == [s.run_id for s in specs[:4]]
    for spec in specs[:3]:
        assert run_paths_v09(tmp_path, spec)[0].is_dir()
    failure = json.loads((tmp_path / "formal" / "training_attempt_01.failure.json").read_text(encoding="utf-8"))
    assert failure["run_id"] == target and failure["exit_code"] == 1
    assert failure["finished_this_call"] == [s.run_id for s in specs[:3]]


def test_a_half_written_directory_needs_a_human(tmp_path):
    from run_formal_training_v09 import SuiteError, run_paths_v09

    spec = _specs()[0]
    run_paths_v09(tmp_path, spec)[1].mkdir(parents=True)
    with pytest.raises(SuiteError, match="human decision"):
        _suite(tmp_path, launcher=_fake_launcher([]))


def test_a_failed_directory_also_needs_a_human(tmp_path):
    from run_formal_training_v09 import SuiteError, run_paths_v09

    spec = _specs()[0]
    run_paths_v09(tmp_path, spec)[2].mkdir(parents=True)
    with pytest.raises(SuiteError, match="human decision"):
        _suite(tmp_path, launcher=_fake_launcher([]))


def test_a_tampered_finished_run_is_not_accepted(tmp_path):
    from run_formal_training_v09 import SuiteError, scan_progress_v09

    spec = _specs()[0]
    final = _seal_a_run(tmp_path, spec)
    manifest = json.loads((final / "manifest.json").read_text(encoding="utf-8"))
    manifest["trainable_parameters"] = 1
    (final / "manifest.json").write_text(json.dumps(manifest), encoding="utf-8")
    with pytest.raises(SuiteError, match="hash drift"):
        scan_progress_v09(tmp_path, _specs())


def test_a_run_claiming_success_without_a_directory_is_rejected(tmp_path):
    from run_formal_training_v09 import SuiteError

    def launcher(spec, **kwargs):
        return 0

    with pytest.raises(SuiteError, match="no directory"):
        _suite(tmp_path, launcher=launcher)


def test_progress_ledger_tracks_the_directories(tmp_path):
    _suite(tmp_path, launcher=_fake_launcher([]), max_runs=3)
    ledger = json.loads((tmp_path / "formal" / "training_progress.json").read_text(encoding="utf-8"))
    assert len(ledger["progress"]["completed"]) == 3
    assert len(ledger["progress"]["pending"]) == 21


def test_the_orchestrator_uses_no_one_use_authorization():
    import inspect

    import run_formal_training_v09 as module

    source = inspect.getsource(module)
    for token in ("A09-TRAIN-01", "consume_stage_authorization_v09", "validate_stage_authorization_v09"):
        assert token not in source
