import json
from pathlib import Path


def test_resource_policy_v2_uses_task_specific_fit_without_uniform_floors():
    policy_path = Path(__file__).resolve().parents[1] / "protocols" / "resource_safety_v2.json"

    policy = json.loads(policy_path.read_text(encoding="utf-8"))

    assert policy["schema_version"] == "resource_safety_v2"
    assert policy["decision_basis"] == "declared task request, task-specific reserve, and current capacity"
    assert policy["launch_rule"]["cpu"] == "cpu_cores <= current_available_cpu_cores"
    assert policy["launch_rule"]["gpu"] == "gpu_count <= current_available_gpu_count"
    assert policy["monitoring"]["decision"] == "per_task"
    assert policy["monitoring"]["fixed_sample_interval"] is False
    assert policy["monitoring"]["fixed_summary_interval"] is False
    serialized = json.dumps(policy)
    assert "launch_free_gb_floor" not in serialized
    assert "launch_free_fraction_floor" not in serialized


def test_resource_fit_accepts_exact_capacity_boundary():
    from unified_autoresearch.runtime.resources import ResourceRequest, ResourceSnapshot, assess_resource_fit

    assessment = assess_resource_fit(
        ResourceRequest(
            cpu_cores=4,
            gpu_count=1,
            estimated_peak_memory_gb=3.0,
            memory_safety_reserve_gb=1.0,
            estimated_output_gb=2.0,
            disk_safety_reserve_gb=1.0,
            independent_monitor_enabled=False,
            monitor_reason="short deterministic contract test",
        ),
        ResourceSnapshot(
            available_cpu_cores=4,
            available_gpu_count=1,
            available_memory_gb=4.0,
            free_disk_gb=3.0,
        ),
    )

    assert assessment.decision == "launch"
    assert assessment.cpu_fit is True
    assert assessment.gpu_fit is True
    assert assessment.memory_fit is True
    assert assessment.disk_fit is True


def test_resource_fit_denies_when_actual_available_memory_cannot_cover_estimate_and_reserve():
    from unified_autoresearch.runtime.resources import ResourceCapacityError, ResourceRequest, ResourceSnapshot
    from unified_autoresearch.runtime.resources import require_resource_fit

    request = ResourceRequest(
        cpu_cores=2,
        gpu_count=0,
        estimated_peak_memory_gb=3.0,
        memory_safety_reserve_gb=1.0,
        estimated_output_gb=0.1,
        disk_safety_reserve_gb=0.1,
        independent_monitor_enabled=True,
        monitor_reason="variable multi-process workload",
    )
    snapshot = ResourceSnapshot(
        available_cpu_cores=8,
        available_gpu_count=0,
        available_memory_gb=3.9,
        free_disk_gb=100.0,
    )

    try:
        require_resource_fit(request, snapshot)
    except ResourceCapacityError as error:
        assert error.assessment.decision == "deny"
        assert error.assessment.memory_fit is False
        assert error.assessment.disk_fit is True
    else:
        raise AssertionError("resource preflight must deny an unsafe memory fit")
