"""Running one declared candidate through both protocols, at whatever basin count is frozen.

This is not a search: one candidate is named up front, run, and scored. The basin count comes
from the package manifest, so the same path serves 8, 64, or 531 basins.
"""

import hashlib
import json
from pathlib import Path

import pytest

from unified_autoresearch.runtime.resources import ResourceSnapshot
from unified_autoresearch.tests.test_scaleup_64_data_base import (
    build_packages,
    build_source,
    frozen_64_basins,
    write_camels_tree,
)


MODULE_ROOT = Path(__file__).resolve().parents[1]
REPO_ROOT = MODULE_ROOT.parents[1]


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _remove_tree(path: Path) -> None:
    """Run layouts are written read-only, so plain rmtree silently leaves them behind."""
    import shutil
    import stat

    def _clear_readonly(function, target, _excinfo):
        Path(target).chmod(stat.S_IWRITE)
        function(target)

    shutil.rmtree(path, onerror=_clear_readonly)


def _snapshot() -> ResourceSnapshot:
    return ResourceSnapshot(
        available_cpu_cores=8,
        available_gpu_count=0,
        available_memory_gb=16.0,
        free_disk_gb=500.0,
    )


@pytest.fixture(scope="module")
def real_packages(tmp_path_factory) -> Path:
    """The runner requires inputs inside the repository, so the fixture builds them there."""
    scratch = REPO_ROOT / "runs" / "unified_autoresearch" / "pytest_single_candidate_packages"
    if scratch.exists():
        _remove_tree(scratch)
    scratch.mkdir(parents=True)
    camels_root = write_camels_tree(tmp_path_factory.mktemp("camels") / "camels_us", frozen_64_basins())
    build_source(scratch / "development_source", camels_root)
    build_packages(scratch / "development_source", scratch / "packages")
    yield scratch / "packages"
    _remove_tree(scratch)


def _reference_conceptual(*, output_root):
    from unified_autoresearch.candidates.catalog import materialize_reference_candidate

    return materialize_reference_candidate(category="conceptual_rainfall_runoff", output_root=output_root)


def _run(package_root: Path, output_root: Path, materialize=_reference_conceptual):
    from unified_autoresearch.workflow.candidate_development import run_single_candidate_development

    return run_single_candidate_development(
        repo_root=REPO_ROOT,
        package_root=package_root,
        expected_package_manifest_sha256=_sha256(package_root / "PACKAGE_MANIFEST.json"),
        materialize=materialize,
        output_root=output_root,
        resource_snapshot=_snapshot(),
    )


def test_a_single_reference_candidate_produces_one_cell_per_frozen_basin(real_packages, tmp_path):
    workspace = REPO_ROOT / "runs" / "unified_autoresearch" / "pytest_single_candidate"
    if workspace.exists():
        _remove_tree(workspace)
    try:
        result = _run(real_packages, workspace)
    finally:
        if workspace.exists():
            _remove_tree(workspace)

    assert result["basin_count"] == 64
    assert result["cell_count"] == 64
    assert result["registered_run_count"] == 4
    assert result["score_report_count"] == 2
    assert result["formal_basin_search_run"] is False
    assert result["baseline_outperformance_claimed"] is False
    assert {cell["basin"] for cell in result["cells"]} == set(frozen_64_basins())


def test_the_declared_candidate_identity_is_carried_into_every_cell(real_packages, tmp_path):
    workspace = REPO_ROOT / "runs" / "unified_autoresearch" / "pytest_single_candidate_identity"
    if workspace.exists():
        _remove_tree(workspace)
    try:
        result = _run(real_packages, workspace)
    finally:
        if workspace.exists():
            _remove_tree(workspace)

    assert all(cell["candidate_id"] == "reference-conceptual-rainfall-runoff-v1" for cell in result["cells"])
    assert all(cell["category"] == "conceptual_rainfall_runoff" for cell in result["cells"])


def test_the_runner_refuses_to_overwrite_an_existing_output_root(real_packages, tmp_path):
    workspace = REPO_ROOT / "runs" / "unified_autoresearch" / "pytest_single_candidate_exists"
    workspace.mkdir(parents=True, exist_ok=True)
    try:
        with pytest.raises(FileExistsError):
            _run(real_packages, workspace)
    finally:
        if workspace.exists():
            _remove_tree(workspace)
