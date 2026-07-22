import json
import inspect
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path

import numpy as np
import pytest


REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT / "src"))

from hbv_multilead_joint_uncertainty.reproduction import (  # noqa: E402
    REPRODUCTION_RESOURCE_ESTIMATES_GIB,
    _verify_resource_history,
    aggregate_reproduction_shards,
    compare_npz_exact,
    prepare_reproduction_session,
    run_reproduction_shard,
    validate_verified_shard_set,
    verify_reproduction_shard,
)
from hbv_multilead_joint_uncertainty.scripts.run_reproduction import build_parser  # noqa: E402


def _thirty_six_arrays():
    return {
        f"array_{index:02d}": np.asarray([index, index + 1], dtype=np.float64)
        for index in range(36)
    }


def test_exact_reproduction_comparison_requires_all_thirty_six_arrays_equal(tmp_path):
    reference = tmp_path / "reference.npz"
    reproduced = tmp_path / "reproduced.npz"
    arrays = _thirty_six_arrays()
    np.savez_compressed(reference, **arrays)
    np.savez_compressed(reproduced, **arrays)

    comparison = compare_npz_exact(reference, reproduced)

    assert comparison["exact_equal"] is True
    assert comparison["array_count"] == 36
    assert comparison["numeric_element_count"] == 72
    assert comparison["maximum_absolute_difference"] == 0.0

    changed = dict(arrays)
    changed["array_11"] = changed["array_11"].copy()
    changed["array_11"][0] += 1.0
    np.savez_compressed(reproduced, **changed)
    with pytest.raises(ValueError, match="array_11"):
        compare_npz_exact(reference, reproduced)

    changed = dict(arrays)
    changed["array_11"] = changed["array_11"].astype(np.float32)
    np.savez_compressed(reproduced, **changed)
    with pytest.raises(ValueError, match="dtype"):
        compare_npz_exact(reference, reproduced)


def test_exact_reproduction_comparison_rejects_missing_or_extra_arrays(tmp_path):
    reference = tmp_path / "reference.npz"
    reproduced = tmp_path / "reproduced.npz"
    arrays = _thirty_six_arrays()
    np.savez_compressed(reference, **arrays)
    missing = dict(arrays)
    missing.pop("array_35")
    np.savez_compressed(reproduced, **missing)

    with pytest.raises(ValueError, match="array names"):
        compare_npz_exact(reference, reproduced)

    arrays["array_36"] = np.asarray([0.0])
    np.savez_compressed(reference, **arrays)
    np.savez_compressed(reproduced, **arrays)
    with pytest.raises(ValueError, match="exactly 36"):
        compare_npz_exact(reference, reproduced)


def _verified_rows(basin_ids, fingerprint="session-sha"):
    return [
        {
            "status": "verified",
            "basin_id": basin_id,
            "shard_id": f"shard_{basin_id}",
            "session_checksums_sha256": fingerprint,
            "array_count": 36,
            "numeric_element_count": 366_960,
            "maximum_absolute_difference": 0.0,
        }
        for basin_id in basin_ids
    ]


def test_aggregation_requires_exactly_sixteen_unique_verified_formal_basins():
    basin_ids = [f"{index:08d}" for index in range(1, 17)]
    ordered = validate_verified_shard_set(
        expected_basin_ids=basin_ids,
        shard_verifications=_verified_rows(reversed(basin_ids)),
        session_checksums_sha256="session-sha",
    )
    assert [row["basin_id"] for row in ordered] == basin_ids
    assert sum(row["array_count"] for row in ordered) == 576

    with pytest.raises(ValueError, match="exactly 16"):
        validate_verified_shard_set(
            basin_ids,
            _verified_rows(basin_ids[:-1]),
            "session-sha",
        )
    duplicated = _verified_rows(basin_ids[:-1] + [basin_ids[-2]])
    with pytest.raises(ValueError, match="unique"):
        validate_verified_shard_set(basin_ids, duplicated, "session-sha")
    wrong_session = _verified_rows(basin_ids)
    wrong_session[3]["session_checksums_sha256"] = "wrong"
    with pytest.raises(ValueError, match="session"):
        validate_verified_shard_set(basin_ids, wrong_session, "session-sha")
    failed = _verified_rows(basin_ids)
    failed[5]["status"] = "failed"
    with pytest.raises(ValueError, match="verified"):
        validate_verified_shard_set(basin_ids, failed, "session-sha")


def test_failed_or_incomplete_shard_can_never_verify_as_success(tmp_path):
    failed = tmp_path / "shard_00000001.failed"
    failed.mkdir()
    (failed / "failure.json").write_text(
        json.dumps({"status": "failed"}) + "\n", encoding="utf-8"
    )
    with pytest.raises(ValueError, match="failed"):
        verify_reproduction_shard(failed, tmp_path / "session", tmp_path)

    incomplete = tmp_path / ".shard_00000001.incomplete"
    incomplete.mkdir()
    with pytest.raises(ValueError, match="incomplete"):
        verify_reproduction_shard(incomplete, tmp_path / "session", tmp_path)


def test_reproduction_commands_and_fixed_resource_estimates_are_exposed():
    assert REPRODUCTION_RESOURCE_ESTIMATES_GIB["session"] == {
        "estimated_peak_gib": 1.0,
        "estimated_output_gib": 0.1,
    }
    assert REPRODUCTION_RESOURCE_ESTIMATES_GIB["shard"] == {
        "estimated_peak_gib": 0.5,
        "estimated_output_gib": 0.05,
    }
    assert REPRODUCTION_RESOURCE_ESTIMATES_GIB["aggregation"] == {
        "estimated_peak_gib": 0.5,
        "estimated_output_gib": 0.1,
    }

    session = build_parser().parse_args(
        [
            "prepare-reproduction-session",
            "--contract",
            "contract",
            "--reference",
            "reference",
            "--session-id",
            "session_v01",
        ]
    )
    assert session.command == "prepare-reproduction-session"
    shard = build_parser().parse_args(
        [
            "run-reproduction-shard",
            "--session",
            "session",
            "--shard-root",
            "shards",
            "--shard-id",
            "shard_v01",
            "--basin-id",
            "12143600",
        ]
    )
    assert shard.command == "run-reproduction-shard"
    aggregation = build_parser().parse_args(
        [
            "aggregate-reproduction-shards",
            "--session",
            "session",
            "--shard-root",
            "shards",
            "--aggregation-id",
            "aggregate_v01",
        ]
    )
    assert aggregation.command == "aggregate-reproduction-shards"


def test_resource_log_must_cover_content_verification_before_finish():
    resource_config = {
        "minimum_start_available_fraction": 0.25,
        "minimum_running_available_fraction": 0.20,
        "maximum_estimated_peak_fraction_of_available": 0.60,
        "minimum_free_disk_gib": 50.0,
        "minimum_output_space_multiplier": 3.0,
        "monitor_interval_seconds": 15.0,
        "reserved_logical_processors": 2,
    }
    first = datetime(2026, 7, 15, tzinfo=timezone.utc)

    def row(event, seconds):
        result = {
            "event": event,
            "timestamp": (first + timedelta(seconds=seconds)).isoformat(),
            "available_memory_fraction": 0.30,
            "available_memory_gib": 10.0,
            "process_rss_gib": 0.1,
            "process_peak_working_set_gib": 0.2,
            "cpu_load_percent": 10.0,
            "disk_free_gib": 100.0,
            "logical_processors": 8,
        }
        if event == "start":
            result.update(
                estimated_peak_gib=0.5,
                estimated_output_gib=0.05,
                numerical_thread_limit=1,
                reserved_logical_processors=2,
            )
        return result

    history = [
        row("start", 0),
        row("after_shard_content_verification", 10),
        row("finish", 20),
    ]
    verified = _verify_resource_history(history, {"resource": resource_config}, "shard")
    assert verified["maximum_gap_seconds"] == 10.0

    with pytest.raises(ValueError, match="content verification"):
        _verify_resource_history(
            [row("start", 0), row("reference_comparison_complete", 10), row("finish", 20)],
            {"resource": resource_config},
            "shard",
        )


@pytest.mark.parametrize(
    ("runner", "full_verifier", "closure_verifier"),
    [
        (
            prepare_reproduction_session,
            "verify_reproduction_session(",
            "verify_reproduction_session_closure(",
        ),
        (
            run_reproduction_shard,
            "verify_reproduction_shard(",
            "verify_reproduction_shard_closure(",
        ),
        (
            aggregate_reproduction_shards,
            "verify_reproduction_aggregation(",
            "verify_reproduction_aggregation_closure(",
        ),
    ],
)
def test_finish_is_followed_only_by_closure_verification(runner, full_verifier, closure_verifier):
    source = inspect.getsource(runner)
    after_finish = source.split("recorder.finish", maxsplit=1)[1]

    assert full_verifier not in after_finish
    assert closure_verifier in after_finish
