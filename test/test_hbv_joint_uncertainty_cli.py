import sys
from pathlib import Path

import pytest


REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT / "src"))

from hbv_joint_uncertainty.orchestrator import run_preflight_experiment  # noqa: E402
from hbv_joint_uncertainty.resource_monitor import ResourceSnapshot  # noqa: E402
from hbv_joint_uncertainty.scripts.run_preflight import build_parser  # noqa: E402


def _snapshot():
    return ResourceSnapshot(
        timestamp="2026-07-14T20:00:00+08:00",
        total_memory_gib=32.0,
        available_memory_gib=16.0,
        available_memory_fraction=0.5,
        cpu_load_percent=20.0,
        logical_processors=32,
        disk_free_gib=100.0,
        gpu_name=None,
        gpu_memory_total_mib=None,
        gpu_memory_free_mib=None,
        gpu_utilization_percent=None,
        process_rss_gib=0.2,
        process_peak_working_set_gib=0.3,
    )


def test_dry_run_verifies_contract_without_creating_experiment(monkeypatch):
    monkeypatch.setattr(
        "hbv_joint_uncertainty.orchestrator.capture_resource_snapshot",
        lambda path: _snapshot(),
    )
    result = run_preflight_experiment(
        repo_root=REPO_ROOT,
        experiment_id="unit_dry_run_v01",
        basin_ids=["12375900"],
        dry_run=True,
    )
    assert result["status"] == "dry-run-passed"
    assert result["basins"] == ["12375900"]
    assert result["candidate_count_per_basin"] == 9
    assert result["resource"]["available_memory_fraction"] == 0.5


def test_orchestrator_rejects_basin_outside_frozen_six(monkeypatch):
    monkeypatch.setattr(
        "hbv_joint_uncertainty.orchestrator.capture_resource_snapshot",
        lambda path: _snapshot(),
    )
    with pytest.raises(ValueError, match="frozen six-basin set"):
        run_preflight_experiment(
            repo_root=REPO_ROOT,
            experiment_id="invalid_basin_v01",
            basin_ids=["01013500"],
            dry_run=True,
        )


def test_cli_parser_exposes_bounded_smoke_and_verification_controls():
    parser = build_parser()
    args = parser.parse_args(
        [
            "--experiment-id",
            "smoke_v01",
            "--basin-id",
            "12375900",
            "--max-days",
            "30",
            "--dry-run",
        ]
    )
    assert args.experiment_id == "smoke_v01"
    assert args.basin_id == ["12375900"]
    assert args.max_days == 30
    assert args.dry_run is True
