"""Synthetic resource preflight (stage S3).

The point of this preflight is that it can prove a memory ceiling without ever touching the
sealed inputs. The strongest test here is therefore not the numbers -- it is that a worker
has no way to name a path at all.
"""
from pathlib import Path
import inspect
import json
import sys

import pytest

IDEA_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(IDEA_ROOT))

# Small enough to run the real thing on CPU inside a unit test.
_SMALL = {"batch_size": 4, "recent_days": 12, "window_days": 3562, "statics": 27, "features": 5}


def test_the_four_frozen_workloads_cover_the_pair_and_all_three_families():
    from resource_preflight_formal_v09 import WORKLOADS_V09

    names = [w.name for w in WORKLOADS_V09]
    assert names == [
        "strict_nesting_pair",
        "classic_lstm_256_clean",
        "classic_lstm_369_capacity",
        "continuous_multiscale_history",
    ]
    pair = WORKLOADS_V09[0]
    assert pair.variants == ("classic_lstm_256_clean", "nested_history_disabled")
    assert [w.needs_history for w in WORKLOADS_V09] == [False, False, False, True]


def test_worker_command_line_accepts_no_path_of_any_kind():
    import resource_preflight_formal_v09 as module

    source = inspect.getsource(module._worker_main)
    # every option the worker exposes, and none of them may carry a path
    for option in ("--workload", "--device", "--batch-size", "--recent-days",
                   "--window-days", "--statics", "--features"):
        assert option in source
    for forbidden in ("--input", "--output", "--report", "--path", "--root", "--formal"):
        assert forbidden not in source


def test_worker_rejects_an_unknown_workload_and_stray_arguments():
    import resource_preflight_formal_v09 as module

    with pytest.raises(SystemExit):
        module._worker_main(["--workload", "not_a_workload", "--device", "cpu",
                             "--batch-size", "4", "--recent-days", "12",
                             "--window-days", "3562", "--statics", "27", "--features", "5"])
    with pytest.raises(SystemExit):
        module._worker_main(["--workload", "classic_lstm_256_clean", "--device", "cpu",
                             "--batch-size", "4", "--recent-days", "12",
                             "--window-days", "3562", "--statics", "27", "--features", "5",
                             "--report", "/tmp/x.json"])


@pytest.mark.parametrize("workload", [
    "strict_nesting_pair",
    "classic_lstm_256_clean",
    "classic_lstm_369_capacity",
    "continuous_multiscale_history",
])
def test_two_in_process_runs_agree_on_every_array(workload):
    from resource_preflight_formal_v09 import compare_preflight_runs_v09, run_workload_in_process_v09

    first = run_workload_in_process_v09(workload, device="cpu", profile=_SMALL)
    second = run_workload_in_process_v09(workload, device="cpu", profile=_SMALL)
    summary = compare_preflight_runs_v09(first, second)
    assert summary["arrays_identical"] is True
    assert summary["workload"] == workload
    assert all(m["trainable_parameters"] > 0 for m in summary["models"])


def test_comparison_rejects_a_drifting_parameter_hash():
    from resource_preflight_formal_v09 import (
        ResourcePreflightError,
        compare_preflight_runs_v09,
        run_workload_in_process_v09,
    )

    first = run_workload_in_process_v09("classic_lstm_256_clean", device="cpu", profile=_SMALL)
    second = json.loads(json.dumps(first))
    second["models"][0]["parameter_sha256"] = "0" * 64
    with pytest.raises(ResourcePreflightError, match="models"):
        compare_preflight_runs_v09(first, second)


def test_peak_memory_and_pid_are_allowed_to_differ():
    from resource_preflight_formal_v09 import compare_preflight_runs_v09, run_workload_in_process_v09

    first = run_workload_in_process_v09("classic_lstm_256_clean", device="cpu", profile=_SMALL)
    second = json.loads(json.dumps(first))
    second["peak_allocated_bytes"] = 123
    second["peak_reserved_bytes"] = 456
    second["process_id"] = first["process_id"] + 1
    assert compare_preflight_runs_v09(first, second)["arrays_identical"] is True


def test_history_workload_consumes_the_full_causal_window():
    from resource_preflight_formal_v09 import run_workload_in_process_v09

    payload = run_workload_in_process_v09("continuous_multiscale_history", device="cpu", profile=_SMALL)
    assert payload["input_shapes"]["windows"] == [4, 3562, 5]
    assert payload["models"][0]["trainable_parameters"] == 596_737


def test_report_is_written_once_and_never_inside_the_sealed_inputs(tmp_path):
    from resource_preflight_formal_v09 import run_resource_preflight_v09

    calls = []

    def launcher(name, *, device, profile, python=None):
        calls.append(name)
        return {
            "workload": name, "device_type": "cpu", "input_shapes": {"recent": [4, 12, 5]},
            "models": [{"variant": "v", "trainable_parameters": 1, "loss_sha256": "a",
                        "gradient_norm_sha256": "b", "parameter_sha256": "c", "adam_state_sha256": "d"}],
            "rng_state_sha256": "e", "determinism": {"cudnn_deterministic": True},
            "peak_allocated_bytes": None, "peak_reserved_bytes": None,
            "received_formal_input_path": False, "received_formal_output_path": False,
            "process_id": len(calls), "exit_code": 0,
        }

    formal = tmp_path / "formal_v09"
    formal.mkdir()
    protocol = IDEA_ROOT / "configs/formal_v09_protocol.json"
    report_path = formal / "training_resource_preflight.external_audit.json"

    report = run_resource_preflight_v09(
        protocol, device="cpu", report_path=report_path, profile=_SMALL, launcher=launcher)
    assert report["status"] == "complete_resource_preflight"
    assert report["workload_count"] == 4
    assert len(calls) == 8, "each workload must run in two separate processes"
    assert report["opened_formal_inputs"] is False and report["wrote_formal_outputs"] is False

    with pytest.raises(FileExistsError, match="already exists"):
        run_resource_preflight_v09(
            protocol, device="cpu", report_path=report_path, profile=_SMALL, launcher=launcher)

    sealed = formal / "input_attempt_01"
    sealed.mkdir()
    with pytest.raises(ValueError, match="outside the sealed"):
        run_resource_preflight_v09(
            protocol, device="cpu", report_path=sealed / "r.json", profile=_SMALL, launcher=launcher)


def test_a_failing_worker_stops_the_preflight(tmp_path):
    from resource_preflight_formal_v09 import ResourcePreflightError, run_preflight_workloads_v09

    def launcher(name, *, device, profile, python=None):
        raise ResourcePreflightError(f"preflight worker for {name} exited 1")

    with pytest.raises(ResourcePreflightError, match="exited 1"):
        run_preflight_workloads_v09(device="cpu", profile=_SMALL, launcher=launcher)


def test_real_subprocess_round_trip_on_cpu():
    """One genuine subprocess launch, so the CLI contract is exercised end to end."""
    from resource_preflight_formal_v09 import _launch_worker_v09

    payload = _launch_worker_v09("classic_lstm_256_clean", device="cpu", profile=_SMALL)
    assert payload["workload"] == "classic_lstm_256_clean"
    assert payload["exit_code"] == 0
    assert payload["models"][0]["trainable_parameters"] == 297_217
    assert payload["received_formal_input_path"] is False
