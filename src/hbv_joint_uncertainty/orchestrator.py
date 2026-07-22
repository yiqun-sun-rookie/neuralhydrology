"""Resource-gated orchestration for the frozen six-basin preflight."""

from __future__ import annotations

import json
import platform
import subprocess
from importlib.metadata import PackageNotFoundError, version
from pathlib import Path
from typing import Sequence

from .candidates import (
    build_candidate_definitions,
    extract_center_parameters,
    extract_saved_warmup_state,
    load_preflight_config,
    load_trained_parameter_table,
    sha256_file,
)
from .experiment import verify_experiment, write_experiment
from .preflight import run_basin_preflight
from .resource_monitor import capture_resource_snapshot, enforce_resource_gate


def collect_git_provenance(repo_root: Path) -> dict:
    """Capture read-only repository identity without staging or committing."""
    root = Path(repo_root).resolve()

    def command(*arguments: str) -> str:
        completed = subprocess.run(
            ["git", *arguments],
            cwd=root,
            check=True,
            capture_output=True,
            text=True,
            timeout=30,
        )
        return completed.stdout.strip()

    status_lines = command("status", "--porcelain=v1").splitlines()
    package_versions = {}
    for package in ("numpy", "pandas", "scipy", "psutil", "pytest"):
        try:
            package_versions[package] = version(package)
        except PackageNotFoundError:
            package_versions[package] = None
    return {
        "git_commit": command("rev-parse", "HEAD"),
        "git_branch": command("branch", "--show-current"),
        "dirty": bool(status_lines),
        "changed_path_count": len(status_lines),
        "python_version": platform.python_version(),
        "package_versions": package_versions,
    }


def _selected_basins(config: dict, basin_ids: Sequence[str] | None) -> list[str]:
    frozen = list(config["basins"])
    selected = frozen if basin_ids is None else [str(value).zfill(8) for value in basin_ids]
    if not selected or len(selected) != len(set(selected)):
        raise ValueError("selected basin identifiers must be nonempty and unique")
    outside = sorted(set(selected) - set(frozen))
    if outside:
        raise ValueError(f"selected basins are outside the frozen six-basin set: {outside}")
    return selected


def _resource_probe_path(repo_root: Path, config: dict) -> Path:
    roots = []
    for key in ("results_root", "logs_root"):
        path = Path(config[key])
        roots.append((path if path.is_absolute() else repo_root / path).resolve())
    if roots[0].drive.lower() != roots[1].drive.lower():
        raise ValueError("results_root and logs_root must share one volume for a single disk resource gate")
    probe = roots[0]
    while not probe.exists() and probe != probe.parent:
        probe = probe.parent
    return probe


def collect_reproducibility_files(
    repo_root: Path, basin_ids: Sequence[str], config: dict
) -> tuple[list[Path], list[Path]]:
    """Locate the exact local code and thirteen raw data inputs to snapshot."""
    root = Path(repo_root).resolve()
    idea_root = root / "src" / "hbv_joint_uncertainty"
    source_files = [
        path
        for path in idea_root.rglob("*")
        if path.is_file() and "__pycache__" not in path.parts and path.suffix in {".py", ".json", ".csv", ".md"}
    ]
    source_files.extend(sorted((root / "test").glob("test_hbv_joint_uncertainty_*.py")))
    source_files.extend(
        [
            root / "src" / "scl_hydro" / "hbv_lite_numpy.py",
            root / "src" / "hydroagent" / "data_loading.py",
        ]
    )
    source_files = sorted(set(path.resolve() for path in source_files))
    if not source_files or any(not path.is_file() for path in source_files):
        raise ValueError("reproducibility source snapshot contains a missing file")

    data_root = Path(config["data_root"])
    if not data_root.is_absolute():
        data_root = root / data_root
    input_files = []
    for basin_id in basin_ids:
        forcing_matches = list(
            (data_root / "basin_mean_forcing").rglob(f"{basin_id}_lump_maurer_forcing_leap.txt")
        )
        discharge_matches = list((data_root / "usgs_streamflow").rglob(f"{basin_id}_streamflow_qc.txt"))
        if len(forcing_matches) != 1 or len(discharge_matches) != 1:
            raise ValueError(f"expected one forcing and one discharge input for basin {basin_id}")
        input_files.extend([forcing_matches[0], discharge_matches[0]])
    input_files.extend(
        [
            data_root / "camels_attributes_v2.0" / "camels_topo.txt",
            root / config["parameter_source"]["table_path"],
            root / config["parameter_source"]["metadata_path"],
        ]
    )
    input_files = sorted(set(path.resolve() for path in input_files))
    if len(input_files) != 2 * len(basin_ids) + 3 or any(not path.is_file() for path in input_files):
        raise ValueError("raw input snapshot is incomplete")
    return source_files, input_files


def run_preflight_experiment(
    repo_root: Path,
    experiment_id: str,
    basin_ids: Sequence[str] | None = None,
    max_days: int | None = None,
    config_path: Path | None = None,
    dry_run: bool = False,
) -> dict:
    """Run the bounded experiment or only verify its immutable prerequisites."""
    root = Path(repo_root).resolve()
    config = load_preflight_config(root, config_path=config_path)
    table = load_trained_parameter_table(config, root)
    selected = _selected_basins(config, basin_ids)
    source_files, input_files = collect_reproducibility_files(root, selected, config)
    snapshot_hashes_before = {
        path.relative_to(root).as_posix(): sha256_file(path) for path in source_files + input_files
    }
    if max_days is not None and int(max_days) <= 0:
        raise ValueError("max_days must be positive")

    resource_probe = _resource_probe_path(root, config)
    initial_snapshot = capture_resource_snapshot(resource_probe)
    enforce_resource_gate(initial_snapshot, estimated_peak_gib=0.5, estimated_output_gib=0.1)
    first_center = extract_center_parameters(table, selected[0])
    candidate_count = len(build_candidate_definitions(first_center, config))
    if dry_run:
        return {
            "status": "dry-run-passed",
            "experiment_id": experiment_id,
            "basins": selected,
            "candidate_count_per_basin": candidate_count,
            "resource": initial_snapshot.to_dict(),
        }

    resource_history = [{"event": "before_experiment", **initial_snapshot.to_dict()}]
    basin_results = []
    for basin_id in selected:
        center = extract_center_parameters(table, basin_id)
        saved_center_state = extract_saved_warmup_state(table, basin_id)
        definitions = build_candidate_definitions(center, config)

        def monitor(completed: int, total: int, current_basin=basin_id) -> None:
            snapshot = capture_resource_snapshot(resource_probe)
            enforce_resource_gate(snapshot, estimated_peak_gib=0.5, estimated_output_gib=0.1)
            resource_history.append(
                {
                    "event": "assimilation_monitor",
                    "basin_id": current_basin,
                    "completed_days": completed,
                    "total_days": total,
                    **snapshot.to_dict(),
                }
            )

        basin_results.append(
            run_basin_preflight(
                basin_id=basin_id,
                definitions=definitions,
                config=config,
                repo_root=root,
                max_days=max_days,
                monitor_callback=monitor,
                expected_center_stores=saved_center_state,
            )
        )

    final_snapshot = capture_resource_snapshot(resource_probe)
    enforce_resource_gate(final_snapshot, estimated_peak_gib=0.5, estimated_output_gib=0.1)
    resource_history.append({"event": "after_experiment", **final_snapshot.to_dict()})
    executed_config = dict(config)
    executed_config["execution"] = {"requested_max_days": max_days}
    output = write_experiment(
        repo_root=root,
        experiment_id=experiment_id,
        config=executed_config,
        basin_results=basin_results,
        resource_history=resource_history,
        provenance=collect_git_provenance(root),
        source_files=source_files,
        input_files=input_files,
        expected_snapshot_hashes=snapshot_hashes_before,
    )
    verification = verify_experiment(output)
    log_root = Path(config["logs_root"])
    if not log_root.is_absolute():
        log_root = root / log_root
    verification_path = log_root / experiment_id / "independent_verification.json"
    verification_path.write_text(
        json.dumps(verification, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    return {
        "status": "verified",
        "experiment_id": experiment_id,
        "basins": selected,
        "output_dir": str(output),
        "verification": verification,
        "resource_snapshot_count": len(resource_history),
    }
