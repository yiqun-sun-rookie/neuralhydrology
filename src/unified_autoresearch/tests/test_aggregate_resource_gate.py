"""Parallel launches must be judged on the sum of what runs at once, not one task at a time.

The aggregate gate keeps the same headroom the supervisor uses to stop a run, so a batch is
never admitted into a state the supervisor would immediately stop it in.
"""

import json
from pathlib import Path

import pytest

from unified_autoresearch.runtime.resources import ResourceRequest, ResourceSnapshot


MODULE_ROOT = Path(__file__).resolve().parents[1]
PROTOCOL_V4 = MODULE_ROOT / "protocols" / "resource_safety_v4.json"


def _request(*, cores: int = 1, gpus: int = 0, peak: float = 1.0, reserve: float = 0.5, output: float = 1.0, disk_reserve: float = 1.0) -> ResourceRequest:
    return ResourceRequest(
        cpu_cores=cores,
        gpu_count=gpus,
        estimated_peak_memory_gb=peak,
        memory_safety_reserve_gb=reserve,
        estimated_output_gb=output,
        disk_safety_reserve_gb=disk_reserve,
        independent_monitor_enabled=True,
        monitor_reason="aggregate gate test",
    )


def _snapshot(*, cores: int = 8, gpus: int = 0, memory: float = 16.0, disk: float = 500.0) -> ResourceSnapshot:
    return ResourceSnapshot(
        available_cpu_cores=cores,
        available_gpu_count=gpus,
        available_memory_gb=memory,
        free_disk_gb=disk,
    )


def _margins(*, memory: float = 1.5, disk: float = 10.0):
    from unified_autoresearch.runtime.resources import AggregateHeadroom

    return AggregateHeadroom(memory_headroom_gb=memory, disk_headroom_gb=disk)


def test_protocol_v4_declares_the_aggregate_rules_and_keeps_the_v3_stop_floors():
    protocol = json.loads(PROTOCOL_V4.read_text(encoding="utf-8"))
    v3 = json.loads((MODULE_ROOT / "protocols" / "resource_safety_v3.json").read_text(encoding="utf-8"))

    assert protocol["schema_version"] == "resource_safety_v4"
    assert protocol["supersedes"] == "resource_safety_v3"
    assert protocol["runtime_stop"] == v3["runtime_stop"]
    assert protocol["prelaunch"]["launch_rule"] == v3["prelaunch"]["launch_rule"]
    aggregate = protocol["parallel_launch"]
    assert aggregate["memory_headroom_gb"] == v3["runtime_stop"]["system_memory_critical"]["stop_free_gb_floor"]
    assert aggregate["memory_headroom_fraction"] == v3["runtime_stop"]["system_memory_critical"]["stop_free_fraction_floor"]
    assert aggregate["disk_headroom_gb"] == v3["runtime_stop"]["disk"]["stop_new_writes_free_gb_floor"]
    assert aggregate["disk_headroom_fraction"] == v3["runtime_stop"]["disk"]["stop_new_writes_free_fraction_floor"]
    assert aggregate["max_concurrent_tasks_ceiling"] == 4
    assert "unmeasured" in aggregate["ceiling_basis"]


def test_headroom_resolves_to_the_larger_of_the_absolute_floor_and_the_fraction():
    from unified_autoresearch.runtime.resources import resolve_aggregate_headroom

    protocol = json.loads(PROTOCOL_V4.read_text(encoding="utf-8"))

    small = resolve_aggregate_headroom(protocol, total_memory_gb=10.0, total_disk_gb=100.0)
    large = resolve_aggregate_headroom(protocol, total_memory_gb=100.0, total_disk_gb=4000.0)

    assert small.memory_headroom_gb == 1.5
    assert small.disk_headroom_gb == 10.0
    assert large.memory_headroom_gb == 4.0
    assert large.disk_headroom_gb == 200.0


def test_a_batch_that_fits_in_the_sum_is_admitted():
    from unified_autoresearch.runtime.resources import assess_aggregate_resource_fit

    requests = [_request(cores=2, peak=2.0, reserve=1.0) for _ in range(3)]

    assessment = assess_aggregate_resource_fit(requests, _snapshot(cores=8, memory=16.0), margins=_margins())

    assert assessment.decision == "launch"
    assert assessment.cpu_cores_required == 6
    assert assessment.memory_required_gb == pytest.approx(9.0)
    assert assessment.memory_available_gb == pytest.approx(14.5)


def test_tasks_that_each_pass_alone_are_refused_together():
    from unified_autoresearch.runtime.resources import assess_aggregate_resource_fit, assess_resource_fit

    snapshot = _snapshot(cores=8, memory=10.0)
    single = _request(peak=6.0, reserve=1.0)

    assert assess_resource_fit(single, snapshot).decision == "launch"
    assessment = assess_aggregate_resource_fit([single, single], snapshot, margins=_margins())

    assert assessment.decision == "deny"
    assert assessment.memory_fit is False
    assert assessment.memory_required_gb == pytest.approx(14.0)


def test_the_headroom_the_supervisor_would_stop_in_is_not_available_for_launch():
    from unified_autoresearch.runtime.resources import assess_aggregate_resource_fit

    snapshot = _snapshot(memory=8.0)
    requests = [_request(peak=6.0, reserve=1.0)]

    assessment = assess_aggregate_resource_fit(requests, snapshot, margins=_margins(memory=1.5))

    assert assessment.memory_available_gb == pytest.approx(6.5)
    assert assessment.decision == "deny"


def test_processor_and_disk_sums_are_gated_too():
    from unified_autoresearch.runtime.resources import assess_aggregate_resource_fit

    too_many_cores = assess_aggregate_resource_fit(
        [_request(cores=5), _request(cores=5)], _snapshot(cores=8), margins=_margins()
    )
    too_many_gpus = assess_aggregate_resource_fit(
        [_request(gpus=1), _request(gpus=1)], _snapshot(gpus=1), margins=_margins()
    )
    too_much_disk = assess_aggregate_resource_fit(
        [_request(output=200.0, disk_reserve=50.0), _request(output=200.0, disk_reserve=50.0)],
        _snapshot(disk=400.0),
        margins=_margins(),
    )

    assert (too_many_cores.decision, too_many_cores.cpu_fit) == ("deny", False)
    assert (too_many_gpus.decision, too_many_gpus.gpu_fit) == ("deny", False)
    assert (too_much_disk.decision, too_much_disk.disk_fit) == ("deny", False)


def test_planning_packs_tasks_into_batches_that_each_pass_the_aggregate_gate():
    from unified_autoresearch.runtime.resources import assess_aggregate_resource_fit, plan_parallel_batches

    snapshot = _snapshot(cores=8, memory=16.0)
    requests = [_request(cores=2, peak=3.0, reserve=1.0) for _ in range(5)]

    batches = plan_parallel_batches(requests, snapshot, margins=_margins(), max_parallel=4)

    assert [index for batch in batches for index in batch] == list(range(5))
    for batch in batches:
        assert assess_aggregate_resource_fit([requests[index] for index in batch], snapshot, margins=_margins()).decision == "launch"


def test_planning_never_exceeds_the_declared_parallel_ceiling():
    from unified_autoresearch.runtime.resources import plan_parallel_batches

    snapshot = _snapshot(cores=64, memory=256.0, disk=10_000.0)
    requests = [_request(cores=1, peak=0.2, reserve=0.1, output=0.1, disk_reserve=0.1) for _ in range(9)]

    batches = plan_parallel_batches(requests, snapshot, margins=_margins(), max_parallel=4)

    assert [len(batch) for batch in batches] == [4, 4, 1]


def test_planning_is_deterministic_and_preserves_declared_order():
    from unified_autoresearch.runtime.resources import plan_parallel_batches

    snapshot = _snapshot(cores=8, memory=16.0)
    requests = [_request(cores=2, peak=float(index % 3) + 1.0, reserve=0.5) for index in range(7)]

    first = plan_parallel_batches(requests, snapshot, margins=_margins(), max_parallel=3)
    second = plan_parallel_batches(requests, snapshot, margins=_margins(), max_parallel=3)

    assert first == second
    assert [index for batch in first for index in batch] == list(range(7))


def test_planning_refuses_a_task_that_cannot_run_even_alone():
    from unified_autoresearch.runtime.resources import ResourceCapacityError, plan_parallel_batches

    snapshot = _snapshot(memory=8.0)
    requests = [_request(peak=1.0, reserve=0.5), _request(peak=100.0, reserve=1.0)]

    with pytest.raises(ResourceCapacityError):
        plan_parallel_batches(requests, snapshot, margins=_margins(), max_parallel=2)


def test_planning_rejects_a_ceiling_below_one():
    from unified_autoresearch.runtime.resources import plan_parallel_batches

    with pytest.raises(ValueError, match="parallel ceiling must be at least one"):
        plan_parallel_batches([_request()], _snapshot(), margins=_margins(), max_parallel=0)


def test_serial_planning_reproduces_todays_one_task_at_a_time_behaviour():
    from unified_autoresearch.runtime.resources import plan_parallel_batches

    snapshot = _snapshot(cores=64, memory=256.0)
    requests = [_request(cores=1, peak=0.2, reserve=0.1) for _ in range(3)]

    batches = plan_parallel_batches(requests, snapshot, margins=_margins(), max_parallel=1)

    assert batches == [[0], [1], [2]]
