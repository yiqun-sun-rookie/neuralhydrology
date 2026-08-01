import hashlib
import json
import math
import os
import subprocess
from pathlib import Path

import pandas as pd
import pytest

from unified_autoresearch.selection.basins import APPROVED_STATIC_ATTRIBUTES


MODULE_ROOT = Path(__file__).resolve().parents[1]


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _initialize_repo(repo: Path) -> None:
    repo.mkdir()
    subprocess.run(["git", "init", "-q"], cwd=repo, check=True)
    subprocess.run(["git", "config", "user.email", "test@example.invalid"], cwd=repo, check=True)
    subprocess.run(["git", "config", "user.name", "Test User"], cwd=repo, check=True)
    (repo / ".gitignore").write_text("runs/\n", encoding="utf-8")


def _build_synthetic_development_packages(repo: Path) -> Path:
    from unified_autoresearch.data.packages import build_development_packages

    source_root = repo / "synthetic-development-source"
    source_root.mkdir()
    basins = json.loads((MODULE_ROOT / "selection" / "development_basins_v1.json").read_text(encoding="utf-8"))[
        "basins"
    ]
    dates = pd.to_datetime(
        ["1999-10-01", "2002-09-30", "2002-10-01", "2005-09-30", "2005-10-01", "2008-09-30"]
    )
    feature_rows = []
    target_rows = []
    for basin_index, basin in enumerate(basins):
        for date_index, date in enumerate(dates):
            feature_rows.append(
                {
                    "basin": basin,
                    "date": date,
                    "prcp": float(date_index + 1),
                    "tmin": float(basin_index),
                    "tmax": float(basin_index + 10),
                    "srad": float(date_index + 100),
                    "vp": float(date_index + 1000),
                }
            )
            target_rows.append(
                {"basin": basin, "date": date, "qobs": float(basin_index * 10 + date_index + 1)}
            )
    pd.DataFrame(feature_rows).to_parquet(source_root / "features.parquet", index=False)
    pd.DataFrame(target_rows).to_parquet(source_root / "targets.parquet", index=False)
    (source_root / "static_attributes.json").write_text(
        json.dumps(
            {
                "schema_version": "development_static_attributes_v1",
                "basins": {
                    basin: {
                        name: float(basin_index + attribute_index + 1)
                        for attribute_index, name in enumerate(APPROVED_STATIC_ATTRIBUTES)
                    }
                    for basin_index, basin in enumerate(basins)
                },
            },
            sort_keys=True,
        ),
        encoding="utf-8",
    )
    source_manifest = source_root / "SOURCE_MANIFEST.json"
    source_manifest.write_text(
        json.dumps(
            {
                "schema_version": "development_source_v1",
                "source_kind": "explicitly_pre_sliced_development_only",
                "forcing_product": "maurer",
                "date_bounds": ["1999-10-01", "2008-09-30"],
                "sealed_final_evaluation_present": False,
                "files": {
                    name: _sha256(source_root / name)
                    for name in ("features.parquet", "targets.parquet", "static_attributes.json")
                },
            },
            sort_keys=True,
        ),
        encoding="utf-8",
    )
    package_root = repo / "synthetic-development-packages"
    build_development_packages(
        source_root=source_root,
        source_manifest_path=source_manifest,
        protocol_path=MODULE_ROOT / "protocols" / "development_v1.json",
        selection_path=MODULE_ROOT / "selection" / "development_basins_v1.json",
        output_root=package_root,
    )
    return package_root


def test_registered_recovery_matches_a_clean_deterministic_training_run(tmp_path):
    from unified_autoresearch.registry.store import Registry
    from unified_autoresearch.runtime.checkpoints import verify_checkpoint
    from unified_autoresearch.runtime.resources import ResourceSnapshot
    from unified_autoresearch.workflow.recovery import run_recovery_reproducibility_cycle

    repo = tmp_path / "repo"
    _initialize_repo(repo)
    package_root = _build_synthetic_development_packages(repo)
    subprocess.run(["git", "add", "."], cwd=repo, check=True)
    subprocess.run(["git", "commit", "-q", "-m", "synthetic development package"], cwd=repo, check=True)
    output_root = repo / "runs" / "recovery-cycle"
    snapshot = ResourceSnapshot(
        available_cpu_cores=4,
        available_gpu_count=0,
        available_memory_gb=4.0,
        free_disk_gb=10.0,
    )

    result = run_recovery_reproducibility_cycle(
        repo_root=repo,
        package_root=package_root,
        expected_package_manifest_sha256=_sha256(package_root / "PACKAGE_MANIFEST.json"),
        category="custom_python",
        output_root=output_root,
        resource_snapshot=snapshot,
    )

    assert result["schema_version"] == "development_recovery_cycle_v1"
    assert result["candidate_id"] == "reference-custom-python-v1"
    assert result["protocol"] == "forward"
    assert result["registered_run_count"] == 3
    assert result["interrupted_status"] == "checkpointed"
    assert result["resumed_status"] == result["clean_status"] == "succeeded"
    assert result["resumed_model_sha256"] == result["clean_model_sha256"]
    assert result["model_bytes_equal"] is True
    assert json.loads((output_root / "RECOVERY_SUMMARY.json").read_text(encoding="utf-8")) == result

    checkpoint_path = output_root / result["checkpoint_path"]
    checkpoint = verify_checkpoint(checkpoint_path, expected_candidate_id=result["candidate_id"])
    assert checkpoint.root_sha256 == result["checkpoint_root_sha256"]
    resumed_model = output_root / result["resumed_model_path"]
    clean_model = output_root / result["clean_model_path"]
    assert resumed_model.read_bytes() == clean_model.read_bytes()

    for value in result["runs"].values():
        run_root = output_root / value["run_root"]
        registry = Registry(
            run_root / "registry" / "registry.sqlite",
            scheduler_lock_path=run_root / "registry" / "scheduler.lock",
            receipt_dir=run_root / "registry" / "receipts",
        )
        assert registry.verify() == {"record_count": 8, "failure_count": 0, "failures": []}
        assert len(list((run_root / "registry" / "receipts").glob("*.json"))) == 8
        assert value["fingerprint_root_sha256"] == json.loads(
            (run_root / "fingerprint.json").read_text(encoding="utf-8")
        )["root_sha256"]

    with pytest.raises(FileExistsError):
        run_recovery_reproducibility_cycle(
            repo_root=repo,
            package_root=package_root,
            expected_package_manifest_sha256=_sha256(package_root / "PACKAGE_MANIFEST.json"),
            category="custom_python",
            output_root=output_root,
            resource_snapshot=snapshot,
        )


@pytest.mark.skipif(os.name != "nt", reason="Windows extended-length paths are Windows-specific")
def test_recovery_summary_manifest_includes_deep_checkpoint_metadata(tmp_path):
    from unified_autoresearch.workflow.recovery import _artifact_manifest

    root = tmp_path / "recovery-root"
    relative = Path("runs") / "forward-checkpoint" / "checkpoints" / ("x" * 120)
    checkpoint = root / relative
    os.makedirs("\\\\?\\" + str(checkpoint.resolve()))
    expected = {
        "model.json": b"model",
        "CHECKPOINT_REQUEST.json": b"request",
        "CHECKPOINT_VERIFIED.json": b"verified",
    }
    for name, content in expected.items():
        with open("\\\\?\\" + str((checkpoint / name).resolve()), "xb") as stream:
            stream.write(content)
    assert len(str(checkpoint / "CHECKPOINT_VERIFIED.json")) > 260

    manifest = {entry["path"]: entry for entry in _artifact_manifest(root)}

    for name, content in expected.items():
        label = (relative / name).as_posix()
        assert manifest[label]["bytes"] == len(content)


def test_full_development_loop_produces_exactly_32_finite_registered_cells(tmp_path):
    from unified_autoresearch.candidates.catalog import REFERENCE_CATEGORIES
    from unified_autoresearch.registry.store import Registry
    from unified_autoresearch.runtime.resources import ResourceSnapshot
    from unified_autoresearch.workflow.development_loop import run_full_development_loop

    repo = tmp_path / "repo"
    _initialize_repo(repo)
    package_root = _build_synthetic_development_packages(repo)
    subprocess.run(["git", "add", "."], cwd=repo, check=True)
    subprocess.run(["git", "commit", "-q", "-m", "synthetic development package"], cwd=repo, check=True)
    output_root = repo / "runs" / "full-development-loop"

    result = run_full_development_loop(
        repo_root=repo,
        package_root=package_root,
        expected_package_manifest_sha256=_sha256(package_root / "PACKAGE_MANIFEST.json"),
        output_root=output_root,
        resource_snapshot=ResourceSnapshot(
            available_cpu_cores=4,
            available_gpu_count=0,
            available_memory_gb=4.0,
            free_disk_gb=10.0,
        ),
    )

    assert result["schema_version"] == "full_development_loop_v1"
    assert result["candidate_count"] == 4
    assert result["protocol_count"] == 2
    assert result["registered_run_count"] == 16
    assert result["score_report_count"] == 8
    assert result["cell_count"] == 32
    assert set(result["candidates"]) == set(REFERENCE_CATEGORIES)
    assert len({(cell["category"], cell["basin"]) for cell in result["cells"]}) == 32
    assert all(
        math.isfinite(cell[metric])
        for cell in result["cells"]
        for metric in ("forward_nse", "reverse_nse", "mean_nse")
    )
    assert json.loads((output_root / "LOOP_SUMMARY.json").read_text(encoding="utf-8")) == result

    for candidate in result["candidates"].values():
        for protocol in ("forward", "reverse"):
            protocol_result = candidate["protocols"][protocol]
            score = json.loads((output_root / protocol_result["score_path"]).read_text(encoding="utf-8"))
            assert score["registered_run_id"] == protocol_result["predict_run_id"]
            assert score["row_count"] == 16
            assert len(score["basin_metrics"]) == 8
            for mode in ("train", "predict"):
                run = output_root / protocol_result[f"{mode}_run_root"]
                registry = Registry(
                    run / "registry" / "registry.sqlite",
                    scheduler_lock_path=run / "registry" / "scheduler.lock",
                    receipt_dir=run / "registry" / "receipts",
                )
                assert registry.verify() == {"record_count": 8, "failure_count": 0, "failures": []}
                assert len(list((run / "registry" / "receipts").glob("*.json"))) == 8

    with pytest.raises(FileExistsError):
        run_full_development_loop(
            repo_root=repo,
            package_root=package_root,
            expected_package_manifest_sha256=_sha256(package_root / "PACKAGE_MANIFEST.json"),
            output_root=output_root,
            resource_snapshot=ResourceSnapshot(
                available_cpu_cores=4,
                available_gpu_count=0,
                available_memory_gb=4.0,
                free_disk_gb=10.0,
            ),
        )


def test_full_development_loop_supervises_every_registered_run_when_declared(tmp_path):
    from unified_autoresearch.runtime.resources import ResourceSnapshot
    from unified_autoresearch.workflow.development_loop import run_full_development_loop

    repo = tmp_path / "repo"
    _initialize_repo(repo)
    package_root = _build_synthetic_development_packages(repo)
    subprocess.run(["git", "add", "."], cwd=repo, check=True)
    subprocess.run(["git", "commit", "-q", "-m", "synthetic development package"], cwd=repo, check=True)
    output_root = repo / "runs" / "supervised-development-loop"

    result = run_full_development_loop(
        repo_root=repo,
        package_root=package_root,
        expected_package_manifest_sha256=_sha256(package_root / "PACKAGE_MANIFEST.json"),
        output_root=output_root,
        resource_snapshot=ResourceSnapshot(
            available_cpu_cores=4,
            available_gpu_count=0,
            available_memory_gb=4.0,
            free_disk_gb=10.0,
        ),
        monitor_sample_interval_seconds=0.05,
        monitor_reason="synthetic supervised full-loop verification",
    )

    # The cardinality invariants must survive the monitored path unchanged.
    assert result["cell_count"] == 32
    assert result["registered_run_count"] == 16
    assert result["independent_monitor_enabled"] is True
    assert result["monitor_sample_interval_seconds"] == 0.05
    assert all(
        math.isfinite(cell[metric])
        for cell in result["cells"]
        for metric in ("forward_nse", "reverse_nse", "mean_nse")
    )

    supervised_run_count = 0
    for candidate in result["candidates"].values():
        candidate_id = candidate["candidate_id"]
        for protocol in ("forward", "reverse"):
            protocol_result = candidate["protocols"][protocol]
            for mode in ("train", "predict"):
                run_root = output_root / protocol_result[f"{mode}_run_root"]
                target = run_root / "control" / "MONITOR_TARGET.json"
                assert target.is_file(), f"missing monitor target for {candidate_id}/{protocol}/{mode}"
                published = json.loads(target.read_text(encoding="utf-8"))
                assert published["run_id"] == f"{candidate_id}-{mode}"

                log_path = run_root / "logs" / "resource-monitor.jsonl"
                assert log_path.is_file(), f"missing monitor log for {candidate_id}/{protocol}/{mode}"
                samples = [
                    json.loads(line)
                    for line in log_path.read_text(encoding="utf-8").splitlines()
                    if line
                ]
                assert samples, f"no supervisor samples for {candidate_id}/{protocol}/{mode}"
                assert [sample["sample_index"] for sample in samples] == list(range(len(samples)))
                assert all(sample["run_id"] == f"{candidate_id}-{mode}" for sample in samples)
                supervised_run_count += 1

    assert supervised_run_count == 16
