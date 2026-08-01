import json
import subprocess
import sys
import time
from pathlib import Path

import psutil
import pytest


MODULE_ROOT = Path(__file__).resolve().parents[1]
STOP_POLICY = json.loads((MODULE_ROOT / "protocols" / "resource_safety_v3.json").read_text(encoding="utf-8"))


def _target_for(process: subprocess.Popen, run_id: str = "monitor-run-0001"):
    from unified_autoresearch.runtime.monitor import MonitorTarget

    handle = psutil.Process(process.pid)
    return MonitorTarget(
        process_id=process.pid,
        create_time=handle.create_time(),
        executable_path=handle.exe(),
        run_id=run_id,
    )


def _sample(**overrides) -> dict:
    record = {
        "process_memory_gb": 0.05,
        "system_available_memory_gb": 16.0,
        "system_memory_total_gb": 32.0,
        "free_disk_gb": 500.0,
        "disk_total_gb": 1000.0,
    }
    record.update(overrides)
    return record


def test_monitor_refuses_a_process_whose_creation_time_does_not_match(tmp_path):
    from unified_autoresearch.runtime.monitor import MonitorTarget, verify_process_ownership

    process = subprocess.Popen([sys.executable, "-c", "import time; time.sleep(30)"])
    try:
        genuine = _target_for(process)
        foreign = MonitorTarget(
            process_id=genuine.process_id,
            create_time=genuine.create_time + 5.0,
            executable_path=genuine.executable_path,
            run_id=genuine.run_id,
        )
        assert verify_process_ownership(genuine) is True
        assert verify_process_ownership(foreign) is False
    finally:
        process.kill()
        process.wait()


def test_monitor_refuses_a_process_identifier_that_no_longer_exists():
    from unified_autoresearch.runtime.monitor import MonitorTarget, verify_process_ownership

    process = subprocess.Popen([sys.executable, "-c", "pass"])
    target = _target_for(process)
    process.wait()
    for _ in range(50):
        if not psutil.pid_exists(target.process_id):
            break
        time.sleep(0.1)

    assert verify_process_ownership(target) is False


def test_monitor_requires_consecutive_near_out_of_memory_samples_before_stopping():
    from unified_autoresearch.runtime.monitor import evaluate_stop_reason

    healthy = _sample()
    # Below the v3 near-out-of-memory floor (1.5 GB), which sits under the normal band.
    low = _sample(system_available_memory_gb=1.0)

    assert evaluate_stop_reason([healthy, low], policy=STOP_POLICY) is None
    assert evaluate_stop_reason([low, healthy, low], policy=STOP_POLICY) is None
    reason = evaluate_stop_reason([healthy, low, low], policy=STOP_POLICY)
    assert reason is not None and "memory" in reason


def test_external_system_pressure_does_not_stop_a_small_candidate():
    """Regression for the real v2 false positive: a 26 MB candidate is not stopped for
    system-wide memory pressure that dipped into the old absolute floor but that the candidate
    itself did not cause and cannot relieve."""
    from unified_autoresearch.runtime.monitor import evaluate_stop_reason

    pressured = _sample(system_available_memory_gb=3.7, process_memory_gb=0.026)
    samples = [pressured, pressured, pressured]

    assert evaluate_stop_reason(samples, policy=STOP_POLICY, declared_memory_budget_gb=0.60) is None


def test_candidate_that_exceeds_its_declared_envelope_is_stopped():
    """Task-relative danger the candidate can relieve: its own footprint has grown past the
    envelope it reserved, while system memory is healthy."""
    from unified_autoresearch.runtime.monitor import evaluate_stop_reason

    healthy = _sample(system_available_memory_gb=16.0, process_memory_gb=0.05)
    ballooned = _sample(system_available_memory_gb=16.0, process_memory_gb=1.2)

    assert (
        evaluate_stop_reason([healthy, ballooned], policy=STOP_POLICY, declared_memory_budget_gb=0.60)
        is None
    )
    reason = evaluate_stop_reason(
        [healthy, ballooned, ballooned], policy=STOP_POLICY, declared_memory_budget_gb=0.60
    )
    assert reason is not None and "candidate" in reason and "memory" in reason


def test_monitor_stops_immediately_when_free_disk_falls_below_the_floor():
    from unified_autoresearch.runtime.monitor import evaluate_stop_reason

    reason = evaluate_stop_reason([_sample(free_disk_gb=1.0)], policy=STOP_POLICY)

    assert reason is not None and "disk" in reason


def test_undeclared_budget_degrades_to_system_only_supervision():
    """With no declared candidate memory budget the candidate-relative brake has no envelope to
    judge against and is intentionally inert -- but the system near-out-of-memory floor still
    stops the run. An undeclared budget therefore degrades to system-only supervision, never to
    no supervision at all. This pins the otherwise-untested default (infinite) budget branch."""
    from unified_autoresearch.runtime.monitor import evaluate_stop_reason

    huge_but_healthy_system = _sample(process_memory_gb=100.0, system_available_memory_gb=16.0)
    assert (
        evaluate_stop_reason(
            [huge_but_healthy_system, huge_but_healthy_system, huge_but_healthy_system],
            policy=STOP_POLICY,
        )
        is None
    )

    near_out_of_memory = _sample(process_memory_gb=100.0, system_available_memory_gb=1.0)
    reason = evaluate_stop_reason([near_out_of_memory, near_out_of_memory], policy=STOP_POLICY)
    assert reason is not None and "system" in reason and "memory" in reason


def test_publish_monitor_target_serializes_an_undeclared_budget_as_strict_json(tmp_path):
    """An undeclared (infinite) memory budget must serialize as strict JSON -- never the
    non-standard ``Infinity`` token -- and must round-trip back to an infinite budget."""
    import math

    from unified_autoresearch.runtime.monitor import (
        MonitorTarget,
        await_monitor_target,
        publish_monitor_target,
    )

    target = MonitorTarget(
        process_id=4321,
        create_time=1234.5,
        executable_path=sys.executable,
        run_id="monitor-run-0001",
    )  # declared_memory_budget_gb defaults to math.inf
    target_path = tmp_path / "MONITOR_TARGET.json"
    publish_monitor_target(target_path, target)

    raw = target_path.read_text(encoding="utf-8")
    assert "Infinity" not in raw

    def _reject(token):
        raise AssertionError(f"non-standard JSON constant emitted: {token}")

    json.loads(raw, parse_constant=_reject)

    restored = await_monitor_target(target_path, timeout_seconds=1.0, poll_seconds=0.01)
    assert restored is not None
    assert math.isinf(restored.declared_memory_budget_gb)


def test_publish_monitor_target_round_trips_a_declared_finite_budget(tmp_path):
    """A declared finite budget serializes as a plain number and round-trips exactly."""
    from unified_autoresearch.runtime.monitor import (
        MonitorTarget,
        await_monitor_target,
        publish_monitor_target,
    )

    target = MonitorTarget(
        process_id=4321,
        create_time=1234.5,
        executable_path=sys.executable,
        run_id="monitor-run-0001",
        declared_memory_budget_gb=0.60,
    )
    target_path = tmp_path / "MONITOR_TARGET.json"
    publish_monitor_target(target_path, target)

    restored = await_monitor_target(target_path, timeout_seconds=1.0, poll_seconds=0.01)
    assert restored is not None
    assert restored.declared_memory_budget_gb == 0.60


def test_monitor_resource_log_is_append_only_json_lines_with_ownership_fields(tmp_path):
    from unified_autoresearch.runtime.monitor import MonitorTarget, append_resource_sample

    target = MonitorTarget(
        process_id=4321,
        create_time=1234.5,
        executable_path=sys.executable,
        run_id="monitor-run-0001",
    )
    log_path = tmp_path / "resource-monitor.jsonl"

    append_resource_sample(log_path, target=target, sample_index=0, sample=_sample())
    first_bytes = log_path.read_bytes()
    append_resource_sample(log_path, target=target, sample_index=1, sample=_sample(free_disk_gb=499.0))

    content = log_path.read_bytes()
    assert content.startswith(first_bytes)
    records = [json.loads(line) for line in content.decode("utf-8").splitlines() if line]
    assert [record["sample_index"] for record in records] == [0, 1]
    for record in records:
        assert record["schema_version"] == "resource_sample_v1"
        assert record["process_id"] == 4321
        assert record["create_time"] == 1234.5
        assert record["executable_path"] == sys.executable
        assert record["run_id"] == "monitor-run-0001"


def test_monitor_writes_the_frozen_controlled_stop_request_when_a_limit_trips(tmp_path):
    from unified_autoresearch.runtime.monitor import supervise

    control_root = tmp_path / "control"
    control_root.mkdir()
    log_path = tmp_path / "resource-monitor.jsonl"
    tripping_policy = json.loads(json.dumps(STOP_POLICY))
    tripping_policy["runtime_stop"]["disk"]["stop_new_writes_free_gb_floor"] = 10**9

    process = subprocess.Popen([sys.executable, "-c", "import time; time.sleep(30)"])
    try:
        summary = supervise(
            target=_target_for(process),
            log_path=log_path,
            control_root=control_root,
            policy=tripping_policy,
            sample_interval_seconds=0.01,
            max_samples=3,
        )
    finally:
        process.kill()
        process.wait()

    assert summary["ownership_verified"] is True
    assert summary["stopped"] is True
    assert "disk" in summary["stop_reason"]
    request = json.loads((control_root / "STOP_REQUEST.json").read_text(encoding="utf-8"))
    assert request["schema_version"] == "controlled_stop_request_v1"
    assert log_path.is_file()


def test_monitor_never_stops_a_process_it_cannot_verify(tmp_path):
    from unified_autoresearch.runtime.monitor import MonitorTarget, supervise

    control_root = tmp_path / "control"
    control_root.mkdir()
    tripping_policy = json.loads(json.dumps(STOP_POLICY))
    tripping_policy["runtime_stop"]["disk"]["stop_new_writes_free_gb_floor"] = 10**9

    process = subprocess.Popen([sys.executable, "-c", "import time; time.sleep(30)"])
    try:
        genuine = _target_for(process)
        foreign = MonitorTarget(
            process_id=genuine.process_id,
            create_time=genuine.create_time + 5.0,
            executable_path=genuine.executable_path,
            run_id=genuine.run_id,
        )
        summary = supervise(
            target=foreign,
            log_path=tmp_path / "resource-monitor.jsonl",
            control_root=control_root,
            policy=tripping_policy,
            sample_interval_seconds=0.01,
            max_samples=3,
        )
    finally:
        process.kill()
        process.wait()

    assert summary["ownership_verified"] is False
    assert summary["stopped"] is False
    assert not (control_root / "STOP_REQUEST.json").exists()


def test_supervised_candidate_runs_and_records_an_independent_resource_log(tmp_path):
    from test_restricted_runtime import _prediction_parquet_bytes, _prepare_prediction_run
    from unified_autoresearch.runtime.runner import run_candidate

    payload = _prediction_parquet_bytes()
    source = (
        "import os, base64, time\n"
        "time.sleep(0.6)\n"
        f"data = base64.b64decode({base64_literal(payload)!r})\n"
        "with open(os.path.join(os.environ['UNIFIED_OUTPUT_ROOT'], 'predictions.parquet'), 'wb') as stream:\n"
        "    stream.write(data)\n"
    )
    descriptor, layout = _prepare_prediction_run(
        tmp_path,
        source,
        resource_overrides={
            "independent_monitor_enabled": True,
            "monitor_reason": "supervised vertical walkthrough on a short task",
        },
    )

    result = run_candidate(
        descriptor=descriptor,
        layout=layout,
        mode="predict",
        monitor_sample_interval_seconds=0.05,
    )

    assert result.status == "succeeded"
    log_path = layout.log_root / "resource-monitor.jsonl"
    records = [json.loads(line) for line in log_path.read_text(encoding="utf-8").splitlines() if line]
    assert records, "the independent monitor must record at least one sample"
    assert all(record["run_id"] for record in records)
    assert [record["sample_index"] for record in records] == list(range(len(records)))


def test_supervised_candidate_refuses_to_launch_when_the_monitor_cannot_start(tmp_path, monkeypatch):
    from test_restricted_runtime import _prediction_parquet_bytes, _prepare_prediction_run
    from unified_autoresearch.runtime.runner import run_candidate

    payload = _prediction_parquet_bytes()
    source = (
        "import os, base64\n"
        f"data = base64.b64decode({base64_literal(payload)!r})\n"
        "with open(os.path.join(os.environ['UNIFIED_OUTPUT_ROOT'], 'predictions.parquet'), 'wb') as stream:\n"
        "    stream.write(data)\n"
    )
    descriptor, layout = _prepare_prediction_run(
        tmp_path,
        source,
        resource_overrides={
            "independent_monitor_enabled": True,
            "monitor_reason": "supervised vertical walkthrough on a short task",
        },
    )

    def _refuse(*args, **kwargs):
        raise OSError("monitor process cannot start")

    monkeypatch.setattr("unified_autoresearch.runtime.runner.start_resource_monitor", _refuse)

    with pytest.raises(RuntimeError, match="independent resource monitor is required but did not start"):
        run_candidate(descriptor=descriptor, layout=layout, mode="predict")

    assert not (layout.log_root / "access.jsonl").exists(), "the candidate must never start without a supervisor"
    assert (layout.log_root / "stdout.txt").read_bytes() == b""
    assert not (layout.output_root / "predictions.parquet").exists()


def test_registered_run_forwards_the_task_specific_sample_interval(tmp_path, monkeypatch):
    """The supervisor interval is a per-task decision, so it must reach the runner."""
    import unified_autoresearch.runtime.orchestrator as orchestrator
    from test_registered_runtime import _prepare_registered_prediction
    from unified_autoresearch.runtime.resources import ResourceSnapshot
    from unified_autoresearch.runtime.runner import run_candidate as real_run_candidate

    repo, descriptor, layout = _prepare_registered_prediction(tmp_path)
    seen: dict = {}

    def _capture(**kwargs):
        seen.update(kwargs)
        return real_run_candidate(**kwargs)

    monkeypatch.setattr(orchestrator, "run_candidate", _capture)

    orchestrator.run_registered_candidate(
        repo_root=repo,
        descriptor=descriptor,
        layout=layout,
        mode="predict",
        run_id="registered-monitor-interval-001",
        code_paths=[repo / "code-version.txt"],
        configuration_paths=[repo / "configuration.json"],
        dependency_paths=[repo / "requirements.txt"],
        data_manifest_paths=[repo / "data-manifest.txt"],
        resource_snapshot=ResourceSnapshot(
            available_cpu_cores=4,
            available_gpu_count=0,
            available_memory_gb=4.0,
            free_disk_gb=10.0,
        ),
        monitor_sample_interval_seconds=0.05,
    )

    assert seen["monitor_sample_interval_seconds"] == 0.05


def base64_literal(payload: bytes) -> str:
    import base64

    return base64.b64encode(payload).decode("ascii")
