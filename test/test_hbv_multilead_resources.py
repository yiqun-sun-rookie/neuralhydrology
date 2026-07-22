import sys
import threading
import hashlib
import json
from datetime import datetime, timedelta, timezone
from pathlib import Path

import pytest
import pandas as pd


REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT / "src"))

from hbv_joint_uncertainty.resource_monitor import ResourceSnapshot  # noqa: E402
from hbv_multilead_joint_uncertainty.resource_monitor import (  # noqa: E402
    ResourceRecorder,
    ResourceGateError,
    enforce_running_gate,
    enforce_start_gate,
    verify_resource_history_rows,
)
import hbv_multilead_joint_uncertainty.resource_monitor as monitor_module  # noqa: E402
import hbv_multilead_joint_uncertainty.orchestrator as orchestrator_module  # noqa: E402
import hbv_multilead_joint_uncertainty.scripts.run_multilead as run_multilead_module  # noqa: E402
from hbv_multilead_joint_uncertainty.orchestrator import (  # noqa: E402
    _quarantine_published_artifact,
    prepare_contract_package,
    verify_run_log,
)
from hbv_multilead_joint_uncertainty.scripts.run_multilead import (  # noqa: E402
    _load_smoke_table,
    build_parser,
)


RESOURCE_CONFIG = {
    "minimum_start_available_fraction": 0.25,
    "minimum_running_available_fraction": 0.20,
    "maximum_estimated_peak_fraction_of_available": 0.60,
    "minimum_free_disk_gib": 50.0,
    "minimum_output_space_multiplier": 3.0,
    "monitor_interval_seconds": 15.0,
    "maximum_resource_probe_seconds": 5.0,
    "reserved_logical_processors": 2,
}


def _snapshot(available_fraction=0.30, available_gib=10.0, disk_gib=100.0, processors=8):
    return ResourceSnapshot(
        timestamp="2026-07-14T00:00:00+08:00",
        total_memory_gib=32.0,
        available_memory_gib=available_gib,
        available_memory_fraction=available_fraction,
        cpu_load_percent=0.0,
        logical_processors=processors,
        disk_free_gib=disk_gib,
        gpu_name=None,
        gpu_memory_total_mib=None,
        gpu_memory_free_mib=None,
        gpu_utilization_percent=None,
        process_rss_gib=0.1,
        process_peak_working_set_gib=0.2,
    )


def test_start_gate_uses_exact_memory_peak_disk_and_processor_thresholds():
    enforce_start_gate(_snapshot(), RESOURCE_CONFIG, estimated_peak_gib=5.9, estimated_output_gib=10.0)

    with pytest.raises(ResourceGateError, match="25"):
        enforce_start_gate(_snapshot(available_fraction=0.249), RESOURCE_CONFIG, 1.0, 1.0)
    with pytest.raises(ResourceGateError, match="60"):
        enforce_start_gate(_snapshot(), RESOURCE_CONFIG, 6.01, 1.0)
    with pytest.raises(ResourceGateError, match="disk"):
        enforce_start_gate(_snapshot(disk_gib=49.9), RESOURCE_CONFIG, 1.0, 1.0)
    with pytest.raises(ResourceGateError, match="two logical"):
        enforce_start_gate(_snapshot(processors=2), RESOURCE_CONFIG, 1.0, 1.0)
    with pytest.raises(ResourceGateError, match="positive"):
        enforce_start_gate(_snapshot(), RESOURCE_CONFIG, 0.0, 1.0)
    with pytest.raises(ResourceGateError, match="positive"):
        enforce_start_gate(_snapshot(), RESOURCE_CONFIG, 1.0, 0.0)


def test_running_gate_stops_below_twenty_percent_available_memory():
    enforce_running_gate(
        _snapshot(available_fraction=0.20),
        RESOURCE_CONFIG,
        estimated_output_gib=1.0,
    )

    with pytest.raises(ResourceGateError, match="20"):
        enforce_running_gate(
            _snapshot(available_fraction=0.199),
            RESOURCE_CONFIG,
            estimated_output_gib=1.0,
        )
    with pytest.raises(ResourceGateError, match="disk"):
        enforce_running_gate(
            _snapshot(disk_gib=59.9),
            RESOURCE_CONFIG,
            estimated_output_gib=20.0,
        )


def test_resource_gate_messages_report_the_configured_memory_thresholds():
    lowered = {
        **RESOURCE_CONFIG,
        "minimum_start_available_fraction": 0.16,
        "minimum_running_available_fraction": 0.125,
    }

    with pytest.raises(ResourceGateError, match=r"16% start threshold"):
        enforce_start_gate(
            _snapshot(available_fraction=0.159),
            lowered,
            estimated_peak_gib=1.0,
            estimated_output_gib=1.0,
        )
    with pytest.raises(ResourceGateError, match=r"12\.5% running threshold"):
        enforce_running_gate(
            _snapshot(available_fraction=0.124),
            lowered,
            estimated_output_gib=1.0,
        )


def test_background_monitor_records_without_business_checkpoints_and_propagates_gate_failure(
    tmp_path, monkeypatch
):
    calls = 0
    sampled = threading.Event()

    def capture(_path):
        nonlocal calls
        calls += 1
        if calls >= 2:
            sampled.set()
            return _snapshot(available_fraction=0.19)
        return _snapshot()

    config = {**RESOURCE_CONFIG, "monitor_interval_seconds": 0.01}
    monkeypatch.setattr(monitor_module, "capture_resource_snapshot", capture)
    recorder = ResourceRecorder(tmp_path, config, tmp_path / "resources.json")
    recorder.start(estimated_peak_gib=1.0, estimated_output_gib=1.0)
    assert sampled.wait(timeout=1.0)
    assert recorder._monitor_stop.wait(timeout=1.0)

    with pytest.raises(ResourceGateError, match="20"):
        recorder.checkpoint("business_checkpoint")
    recorder.abort()
    assert any(row["event"] == "background_monitor" for row in recorder.history)


def test_abort_keeps_a_live_thread_reference_and_stopped_monitor_never_writes_after_capture(
    tmp_path, monkeypatch
):
    capture_started = threading.Event()
    release_capture = threading.Event()
    calls = 0

    def capture(_path):
        nonlocal calls
        calls += 1
        if calls > 1:
            capture_started.set()
            release_capture.wait(timeout=5.0)
        return _snapshot()

    config = {
        **RESOURCE_CONFIG,
        "monitor_interval_seconds": 0.01,
        "maximum_resource_probe_seconds": 0.0,
    }
    monkeypatch.setattr(monitor_module, "capture_resource_snapshot", capture)
    recorder = ResourceRecorder(tmp_path, config, tmp_path / "resources.json")
    recorder.start(estimated_peak_gib=1.0, estimated_output_gib=1.0)
    assert capture_started.wait(timeout=1.0)

    with pytest.raises(RuntimeError, match="did not stop"):
        recorder.abort()
    assert recorder._monitor_thread is not None
    assert recorder._monitor_thread.is_alive()

    release_capture.set()
    recorder._monitor_thread.join(timeout=1.0)
    recorder.abort()
    assert [row["event"] for row in recorder.history] == ["start"]


def test_resource_history_verifier_requires_complete_tail_and_exact_interval_limit():
    first = datetime(2026, 7, 14, tzinfo=timezone.utc)

    def row(
        event,
        seconds,
        available=0.30,
        disk_gib=100.0,
        processors=8,
        estimated_peak_gib=1.0,
        estimated_output_gib=1.0,
    ):
        result = {
            "event": event,
            **_snapshot(
                available_fraction=available,
                disk_gib=disk_gib,
                processors=processors,
            ).to_dict(),
            "timestamp": (first + timedelta(seconds=seconds)).isoformat(),
        }
        if event == "start":
            result.update(
                estimated_peak_gib=estimated_peak_gib,
                estimated_output_gib=estimated_output_gib,
                numerical_thread_limit=1,
                reserved_logical_processors=2,
            )
        return result

    history = [row("start", 0), row("background_monitor", 15), row("finish", 30)]
    verified = verify_resource_history_rows(history, RESOURCE_CONFIG, require_finish=True)
    assert verified["sample_count"] == 3
    assert verified["maximum_gap_seconds"] == 15.0

    with pytest.raises(ValueError, match="finish"):
        verify_resource_history_rows(history[:-1], RESOURCE_CONFIG, require_finish=True)
    with pytest.raises(ValueError, match="gap"):
        verify_resource_history_rows(
            [row("start", 0), row("finish", 15.6)],
            RESOURCE_CONFIG,
            require_finish=True,
        )
    with pytest.raises(ValueError, match="running-memory"):
        verify_resource_history_rows(
            [row("start", 0), row("finish", 1, available=0.19)],
            RESOURCE_CONFIG,
            require_finish=True,
        )
    with pytest.raises(ValueError, match="running-disk"):
        verify_resource_history_rows(
            [row("start", 0, estimated_output_gib=20.0), row("finish", 1, disk_gib=59.9)],
            RESOURCE_CONFIG,
            require_finish=True,
        )
    with pytest.raises(ValueError, match="estimated peak"):
        verify_resource_history_rows(
            [row("start", 0, estimated_peak_gib=6.01), row("finish", 1)],
            RESOURCE_CONFIG,
            require_finish=True,
        )
    with pytest.raises(ValueError, match="logical processors"):
        verify_resource_history_rows(
            [row("start", 0, processors=2), row("finish", 1)],
            RESOURCE_CONFIG,
            require_finish=True,
        )
    with pytest.raises(ValueError, match="positive"):
        verify_resource_history_rows(
            [
                row("start", 0, estimated_peak_gib=0.0, estimated_output_gib=0.0),
                row("finish", 1),
            ],
            RESOURCE_CONFIG,
            require_finish=True,
        )
    with pytest.raises(ValueError, match="contract resource estimate"):
        verify_resource_history_rows(
            history,
            RESOURCE_CONFIG,
            require_finish=True,
            run_kind="contract",
        )
    exact_contract_history = [
        row("start", 0, estimated_peak_gib=0.75, estimated_output_gib=0.5),
        row("background_monitor", 15),
        row("finish", 30),
    ]
    assert verify_resource_history_rows(
        exact_contract_history,
        RESOURCE_CONFIG,
        require_finish=True,
        run_kind="contract",
    )["estimated_peak_gib"] == 0.75


def test_run_log_verifier_binds_complete_resource_tail_to_fresh_artifact_verification(
    tmp_path, monkeypatch
):
    artifact = tmp_path / "artifact"
    artifact.mkdir()
    (artifact / "contract_manifest.json").write_text("{}\n", encoding="utf-8")
    (artifact / "config_snapshot.json").write_text(
        json.dumps({"resource": RESOURCE_CONFIG}) + "\n", encoding="utf-8"
    )
    expected_verification = {"status": "verified", "contract_id": "contract_v01"}
    monkeypatch.setattr(
        orchestrator_module,
        "verify_contract_package",
        lambda path: expected_verification if Path(path) == artifact else None,
    )
    log_directory = tmp_path / "log"
    log_directory.mkdir()
    first = datetime(2026, 7, 14, tzinfo=timezone.utc)
    history = []
    for event, seconds in (("start", 0), ("after_contract_verification", 15), ("finish", 16)):
        row = {
                "event": event,
                **_snapshot().to_dict(),
                "timestamp": (first + timedelta(seconds=seconds)).isoformat(),
            }
        if event == "start":
            row.update(
                estimated_peak_gib=0.75,
                estimated_output_gib=0.5,
                numerical_thread_limit=1,
                reserved_logical_processors=2,
            )
        history.append(row)
    resource_path = log_directory / "resource_history.json"
    resource_path.write_text(json.dumps(history) + "\n", encoding="utf-8")
    (log_directory / "verification.json").write_text(
        json.dumps(expected_verification) + "\n", encoding="utf-8"
    )
    (log_directory / "run_summary.json").write_text(
        json.dumps(
            {
                "status": "verified",
                "contract_id": "contract_v01",
                "output_directory": str(artifact),
                "resource_sample_count": len(history),
                "resource_last_event": "finish",
                "resource_history_sha256": hashlib.sha256(resource_path.read_bytes()).hexdigest(),
                "resource_monitor_covers_packaging_and_verification": True,
            }
        )
        + "\n",
        encoding="utf-8",
    )

    verified = verify_run_log(log_directory)
    assert verified["resource_sample_count"] == 3
    assert verified["artifact_verification"] == expected_verification

    forged_finish = dict(history[-1])
    forged_finish["timestamp"] = (first + timedelta(seconds=15)).isoformat()
    forged_history = [history[0], forged_finish]
    resource_path.write_text(json.dumps(forged_history) + "\n", encoding="utf-8")
    summary_path = log_directory / "run_summary.json"
    summary = json.loads(summary_path.read_text(encoding="utf-8"))
    summary["resource_sample_count"] = len(forged_history)
    summary["resource_history_sha256"] = hashlib.sha256(resource_path.read_bytes()).hexdigest()
    summary_path.write_text(json.dumps(summary) + "\n", encoding="utf-8")
    with pytest.raises(ValueError, match="post-verification"):
        verify_run_log(log_directory)

    resource_path.write_text("[]\n", encoding="utf-8")
    with pytest.raises(ValueError, match="checksum"):
        verify_run_log(log_directory)


def test_command_line_parser_exposes_independent_run_log_verification():
    arguments = build_parser().parse_args(["verify-log", "--log", "logs/example_v01"])

    assert arguments.command == "verify-log"
    assert arguments.log == Path("logs/example_v01")


def test_command_line_exposes_exactly_one_development_basin_smoke_contract(tmp_path):
    pilot_path = tmp_path / "pilot.csv"
    pilot_path.write_text("basin_id\n04015330\n12375900\n", encoding="utf-8")
    config = {"pilot_basin_file": "pilot.csv"}

    selected = _load_smoke_table(tmp_path, config, "04015330")
    assert selected.to_dict("records") == [{"gauge_id": "04015330"}]
    with pytest.raises(ValueError, match="development basin"):
        _load_smoke_table(tmp_path, config, "99999999")

    arguments = build_parser().parse_args(
        ["prepare-smoke", "--contract-id", "smoke_v01", "--basin-id", "04015330"]
    )
    assert arguments.command == "prepare-smoke"
    assert arguments.contract_id == "smoke_v01"
    assert arguments.basin_id == "04015330"


def test_prepare_formal_defers_pilot_verification_to_monitored_preparation(
    tmp_path, monkeypatch
):
    pilot = tmp_path / "pilot_contract"
    pilot.mkdir()
    (pilot / "basins.csv").write_text(
        "gauge_id\n12375900\n09035800\n", encoding="utf-8"
    )
    interaction = {"selected_mode": "full", "uses_evaluation_discharge": False}
    (pilot / "interaction_audit.json").write_text(
        json.dumps(interaction) + "\n", encoding="utf-8"
    )
    formal = pd.DataFrame([{"gauge_id": "12143600"}])
    formal.to_csv(tmp_path / "formal.csv", index=False)
    captured = {}

    monkeypatch.setattr(
        run_multilead_module,
        "load_base_config",
        lambda _root: {"formal_basin_file": "formal.csv"},
    )
    monkeypatch.setattr(
        run_multilead_module,
        "_load_and_verify_formal_table",
        lambda *_args, **_kwargs: (_ for _ in ()).throw(
            AssertionError("formal selection ran before resource monitoring")
        ),
    )
    monkeypatch.setattr(
        run_multilead_module,
        "verify_contract_package",
        lambda _path: (_ for _ in ()).throw(
            AssertionError("pilot verification ran before resource monitoring")
        ),
    )

    def fake_prepare(root, contract_id, basin_table, **kwargs):
        captured.update(
            root=root,
            contract_id=contract_id,
            basin_table=basin_table,
            kwargs=kwargs,
        )
        return {"status": "verified"}

    monkeypatch.setattr(run_multilead_module, "prepare_contract_package", fake_prepare)

    status = run_multilead_module.main(
        [
            "--repo-root",
            str(tmp_path),
            "prepare-formal",
            "--contract-id",
            "formal_v01",
            "--pilot-contract",
            str(pilot),
        ]
    )

    assert status == 0
    assert captured["basin_table"].equals(formal)
    assert captured["kwargs"]["interaction_audit"] == interaction
    assert captured["kwargs"]["prerequisite_contract"] == pilot.resolve()
    assert captured["kwargs"]["prerequisite_basin_ids"] == ["12375900", "09035800"]


def test_prerequisite_contract_verification_starts_after_resource_monitor(
    tmp_path, monkeypatch
):
    events = []

    class FakeRegistry:
        def __init__(self, *_args, **_kwargs):
            pass

        def reserve(self, *_args, **_kwargs):
            pass

        def update(self, *_args, **_kwargs):
            pass

    class FakeRecorder:
        def __init__(self, **_kwargs):
            self.history = []

        def start(self, **_kwargs):
            events.append("resource_start")

        def checkpoint(self, event, **_kwargs):
            events.append(event)

        def abort(self):
            events.append("resource_abort")

    monkeypatch.setattr(
        orchestrator_module,
        "load_base_config",
        lambda _root, config_path=None: {
            "results_root": "results",
            "logs_root": "logs",
            "resource": RESOURCE_CONFIG,
        },
    )
    monkeypatch.setattr(orchestrator_module, "RunRegistry", FakeRegistry)
    monkeypatch.setattr(orchestrator_module, "ResourceRecorder", FakeRecorder)
    monkeypatch.setattr(
        orchestrator_module,
        "collect_contract_snapshot_files",
        lambda *_args, **_kwargs: (
            events.append("snapshot_collect") or [],
            [],
        ),
    )
    monkeypatch.setattr(
        orchestrator_module,
        "_execution_signature",
        lambda *_args, **_kwargs: events.append("execution_signature_start") or {},
    )

    def stop_after_observing_order(_path):
        events.append("prerequisite_verify")
        raise RuntimeError("verification sentinel")

    monkeypatch.setattr(
        orchestrator_module, "verify_contract_package", stop_after_observing_order
    )

    with pytest.raises(RuntimeError, match="verification sentinel"):
        prepare_contract_package(
            tmp_path,
            "formal_v01",
            pd.DataFrame([{"gauge_id": "12143600"}]),
            interaction_audit={
                "selected_mode": "full",
                "uses_evaluation_discharge": False,
            },
            prerequisite_contract=tmp_path / "pilot_contract",
            prerequisite_basin_ids=["12375900"],
        )

    assert events[:5] == [
        "resource_start",
        "snapshot_collect",
        "execution_signature_start",
        "before_prerequisite_contract_verification",
        "prerequisite_verify",
    ]


@pytest.mark.parametrize(
    ("saved_basin", "saved_mode", "error_pattern"),
    [
        ("99999999", "full", "basins differ"),
        ("12375900", "none", "interaction audit differs"),
    ],
)
def test_monitored_formal_preparation_rejects_prerequisite_content_mismatch(
    tmp_path, monkeypatch, saved_basin, saved_mode, error_pattern
):
    pilot = tmp_path / "pilot_contract"
    pilot.mkdir()
    (pilot / "basins.csv").write_text(
        f"gauge_id\n{saved_basin}\n", encoding="utf-8"
    )
    (pilot / "interaction_audit.json").write_text(
        json.dumps(
            {
                "selected_mode": saved_mode,
                "uses_evaluation_discharge": False,
            }
        )
        + "\n",
        encoding="utf-8",
    )

    class FakeRegistry:
        def __init__(self, *_args, **_kwargs):
            pass

        def reserve(self, *_args, **_kwargs):
            pass

        def update(self, *_args, **_kwargs):
            pass

    class FakeRecorder:
        def __init__(self, **_kwargs):
            self.history = []

        def start(self, **_kwargs):
            pass

        def checkpoint(self, *_args, **_kwargs):
            pass

        def abort(self):
            pass

    monkeypatch.setattr(
        orchestrator_module,
        "load_base_config",
        lambda _root, config_path=None: {
            "results_root": "results",
            "logs_root": "logs",
            "resource": RESOURCE_CONFIG,
        },
    )
    monkeypatch.setattr(orchestrator_module, "RunRegistry", FakeRegistry)
    monkeypatch.setattr(orchestrator_module, "ResourceRecorder", FakeRecorder)
    monkeypatch.setattr(
        orchestrator_module,
        "collect_contract_snapshot_files",
        lambda *_args, **_kwargs: ([], []),
    )
    monkeypatch.setattr(
        orchestrator_module, "_execution_signature", lambda *_args, **_kwargs: {}
    )
    monkeypatch.setattr(
        orchestrator_module,
        "verify_contract_package",
        lambda _path: {"contract_id": "pilot_v01"},
    )

    with pytest.raises(ValueError, match=error_pattern):
        prepare_contract_package(
            tmp_path,
            "formal_v01",
            pd.DataFrame([{"gauge_id": "12143600"}]),
            interaction_audit={
                "selected_mode": "full",
                "uses_evaluation_discharge": False,
            },
            prerequisite_contract=pilot,
            prerequisite_basin_ids=["12375900"],
        )


@pytest.mark.parametrize(
    ("saved_ids", "saved_mode", "error_pattern"),
    [
        (["04015330"], "full", "frozen six development basins"),
        (
            ["12375900", "09035800", "01580000", "11481200", "08109700", "04015330"],
            "none",
            "full interaction",
        ),
    ],
)
def test_formal_preparation_rejects_self_consistent_wrong_prerequisite(
    tmp_path, monkeypatch, saved_ids, saved_mode, error_pattern
):
    frozen_ids = [
        "12375900",
        "09035800",
        "01580000",
        "11481200",
        "08109700",
        "04015330",
    ]
    pd.DataFrame({"basin_id": frozen_ids}).to_csv(
        tmp_path / "pilot_six.csv", index=False
    )
    pilot = tmp_path / "pilot_contract"
    pilot.mkdir()
    pd.DataFrame({"gauge_id": saved_ids}).to_csv(pilot / "basins.csv", index=False)
    saved_interaction = {
        "selected_mode": saved_mode,
        "uses_evaluation_discharge": False,
    }
    (pilot / "interaction_audit.json").write_text(
        json.dumps(saved_interaction) + "\n", encoding="utf-8"
    )
    (pilot / "checksums.json").write_text("{}\n", encoding="utf-8")

    class FakeRegistry:
        def __init__(self, *_args, **_kwargs):
            pass

        def reserve(self, *_args, **_kwargs):
            pass

        def update(self, *_args, **_kwargs):
            pass

    class FakeRecorder:
        def __init__(self, **_kwargs):
            self.history = []

        def start(self, **_kwargs):
            pass

        def checkpoint(self, *_args, **_kwargs):
            pass

        def abort(self):
            pass

    monkeypatch.setattr(
        orchestrator_module,
        "load_base_config",
        lambda _root, config_path=None: {
            "results_root": "results",
            "logs_root": "logs",
            "resource": RESOURCE_CONFIG,
            "pilot_basin_file": "pilot_six.csv",
            "formal_prerequisite_contract": {
                "contract_id": "pilot_contract_six_v02",
                "checksums_sha256": "frozen-checksum",
            },
        },
    )
    monkeypatch.setattr(orchestrator_module, "RunRegistry", FakeRegistry)
    monkeypatch.setattr(orchestrator_module, "ResourceRecorder", FakeRecorder)
    monkeypatch.setattr(
        orchestrator_module,
        "collect_contract_snapshot_files",
        lambda *_args, **_kwargs: ([], []),
    )
    monkeypatch.setattr(
        orchestrator_module, "_execution_signature", lambda *_args, **_kwargs: {}
    )
    monkeypatch.setattr(
        orchestrator_module,
        "verify_contract_package",
        lambda _path: {
            "contract_id": "pilot_contract_six_v02",
            "basin_count": len(saved_ids),
            "interaction_mode": saved_mode,
        },
    )
    monkeypatch.setattr(orchestrator_module, "sha256_file", lambda _path: "frozen-checksum")
    monkeypatch.setattr(
        orchestrator_module,
        "audit_basin_inputs",
        lambda *_args, **_kwargs: (_ for _ in ()).throw(
            AssertionError("formal basin audit began before prerequisite identity rejection")
        ),
    )

    with pytest.raises(ValueError, match=error_pattern):
        prepare_contract_package(
            tmp_path,
            "formal_v01",
            pd.DataFrame([{"gauge_id": "12143600"}]),
            interaction_audit=saved_interaction,
            prerequisite_contract=pilot,
            prerequisite_basin_ids=saved_ids,
        )


def test_recorder_limits_numerical_libraries_to_one_thread_and_releases_limit(
    tmp_path, monkeypatch
):
    events = []

    class LimitContext:
        def __enter__(self):
            events.append("entered")
            return self

        def __exit__(self, *_args):
            events.append("exited")

    monkeypatch.setattr(monitor_module, "capture_resource_snapshot", lambda _path: _snapshot())
    monkeypatch.setattr(
        monitor_module,
        "threadpool_limits",
        lambda limits: LimitContext() if limits == 1 else None,
    )
    recorder = ResourceRecorder(tmp_path, RESOURCE_CONFIG)

    recorder.start(estimated_peak_gib=1.0, estimated_output_gib=1.0)
    assert events == ["entered"]
    assert recorder.history[0]["numerical_thread_limit"] == 1
    assert recorder.history[0]["estimated_peak_gib"] == 1.0
    assert recorder.history[0]["estimated_output_gib"] == 1.0
    recorder.finish()
    assert events == ["entered", "exited"]


def test_post_publish_failure_is_quarantined_before_any_optional_log_cleanup(tmp_path):
    published = tmp_path / "result_v01"
    failed = tmp_path / "result_v01.failed"
    published.mkdir()
    (published / "payload.txt").write_text("verified payload\n", encoding="utf-8")

    target = _quarantine_published_artifact(published, failed, RuntimeError("tail failed"))

    assert target == failed
    assert not published.exists()
    assert (failed / "failure.json").is_file()
    marker = json.loads((failed / "failure.json").read_text(encoding="utf-8"))
    assert marker["status"] == "failed_after_publish"
    assert marker["message"] == "tail failed"
