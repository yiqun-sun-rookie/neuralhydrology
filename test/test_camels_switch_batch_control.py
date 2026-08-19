from concurrent.futures import Future
from pathlib import Path
import sys

import pytest


REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT / "src"))

from camels_switch_confirmation.batch_control import execute_fail_fast  # noqa: E402


def successful_worker(item):
    basin_id, seed = item
    return {
        "basin_id": basin_id,
        "seed": seed,
        "run_status": "success",
        "error_message": "",
    }


def worker_that_fails_b1(item):
    basin_id, seed = item
    if basin_id == "b1":
        return {
            "basin_id": basin_id,
            "seed": seed,
            "run_status": "failed",
            "error_message": "registered task failure",
        }
    return successful_worker(item)


def worker_that_fails_b2(item):
    basin_id, seed = item
    if basin_id == "b2":
        return {
            "basin_id": basin_id,
            "seed": seed,
            "run_status": "failed",
            "error_message": "second task failure",
        }
    return successful_worker(item)


def worker_that_raises(_item):
    raise RuntimeError("worker boom")


class ImmediateExecutor:
    """Executor double that completes submitted work immediately."""

    def __init__(self):
        self.submitted = []
        self.shutdown_calls = []

    def submit(self, worker, item):
        self.submitted.append(item)
        future = Future()
        try:
            future.set_result(worker(item))
        except BaseException as error:  # match Future's exception transport
            future.set_exception(error)
        return future

    def shutdown(self, wait=True, *, cancel_futures=False):
        self.shutdown_calls.append((wait, cancel_futures))


class ScriptedExecutor:
    """Executor double with exact Future states and optional shutdown hook."""

    def __init__(self, futures, *, shutdown_hook=None, submit_error_at=None):
        self.futures = list(futures)
        self.shutdown_hook = shutdown_hook
        self.submit_error_at = submit_error_at
        self.submitted = []
        self.shutdown_calls = []

    def submit(self, _worker, item):
        submission_index = len(self.submitted)
        self.submitted.append(item)
        if submission_index == self.submit_error_at:
            raise RuntimeError("submit boom")
        return self.futures[submission_index]

    def shutdown(self, wait=True, *, cancel_futures=False):
        self.shutdown_calls.append((wait, cancel_futures))
        if self.shutdown_hook is not None:
            self.shutdown_hook()


def executor_factory(executor):
    def build(*, max_workers):
        executor.requested_max_workers = max_workers
        return executor

    return build


def completed_future(result):
    future = Future()
    future.set_result(result)
    return future


def test_execute_fail_fast_stops_submitting_after_returned_failure():
    executor = ImmediateExecutor()

    execution = execute_fail_fast(
        work=[("b1", 0), ("b2", 0), ("b3", 0)],
        worker=worker_that_fails_b1,
        task_key=lambda item: item,
        max_workers=1,
        executor_factory=executor_factory(executor),
    )

    assert execution.execution_status == "failed_early"
    assert execution.n_submitted == 1
    assert execution.n_not_submitted_after_failure == 2
    assert executor.submitted == [("b1", 0)]


def test_execute_fail_fast_success_path_runs_every_task():
    executor = ImmediateExecutor()

    execution = execute_fail_fast(
        work=[("b1", 0), ("b2", 0)],
        worker=successful_worker,
        task_key=lambda item: item,
        max_workers=2,
        executor_factory=executor_factory(executor),
    )

    assert execution.execution_status == "complete"
    assert [record["run_status"] for record in execution.records] == [
        "success",
        "success",
    ]
    assert [record["task_index"] for record in execution.records] == [0, 1]
    assert execution.first_failure is None
    assert execution.n_submitted == execution.n_planned == 2


def test_execute_fail_fast_processes_completed_batch_before_stopping():
    executor = ImmediateExecutor()

    execution = execute_fail_fast(
        work=[("b1", 0), ("b2", 0), ("b3", 0)],
        worker=worker_that_fails_b2,
        task_key=lambda item: item,
        max_workers=2,
        executor_factory=executor_factory(executor),
    )

    assert execution.n_submitted == 2
    assert [record["task_index"] for record in execution.records] == [0, 1, 2]
    assert [record["run_status"] for record in execution.records] == [
        "success",
        "failed",
        "not_submitted_after_failure",
    ]
    assert execution.first_failure["task_index"] == 1


def test_execute_fail_fast_converts_future_exception_to_failure():
    executor = ImmediateExecutor()

    execution = execute_fail_fast(
        work=[("b1", 0), ("b2", 0)],
        worker=worker_that_raises,
        task_key=lambda item: item,
        max_workers=1,
        executor_factory=executor_factory(executor),
    )

    assert execution.first_failure["run_status"] == "failed"
    assert execution.first_failure["error_type"] == "RuntimeError"
    assert "RuntimeError: worker boom" in execution.first_failure["error_message"]
    assert execution.first_failure["failure_stage"] == "worker_future"


def test_execute_fail_fast_converts_submission_exception_to_failure():
    executor = ScriptedExecutor([], submit_error_at=0)

    execution = execute_fail_fast(
        work=[("b1", 0), ("b2", 0)],
        worker=successful_worker,
        task_key=lambda item: item,
        max_workers=1,
        executor_factory=executor_factory(executor),
    )

    assert execution.execution_status == "failed_early"
    assert execution.n_submitted == 0
    assert execution.n_not_submitted_after_failure == 1
    assert execution.first_failure["failure_stage"] == "submission"
    assert "RuntimeError: submit boom" in execution.first_failure["error_message"]


@pytest.mark.parametrize("worker_result", [{}, {"run_status": "unknown"}])
def test_execute_fail_fast_rejects_malformed_worker_status(worker_result):
    executor = ScriptedExecutor([completed_future(worker_result)])

    execution = execute_fail_fast(
        work=[("b1", 0), ("b2", 0)],
        worker=successful_worker,
        task_key=lambda item: item,
        max_workers=1,
        executor_factory=executor_factory(executor),
    )

    assert execution.execution_status == "failed_early"
    assert execution.first_failure["failure_stage"] == "worker_result_contract"
    assert "run_status must be 'success' or 'failed'" in (
        execution.first_failure["error_message"]
    )


def test_execute_fail_fast_cancels_pending_and_records_unsubmitted_tasks():
    failed = completed_future(worker_that_fails_b1(("b1", 0)))
    pending = Future()
    executor = ScriptedExecutor([failed, pending])

    execution = execute_fail_fast(
        work=[("b1", 0), ("b2", 0), ("b3", 0)],
        worker=successful_worker,
        task_key=lambda item: item,
        max_workers=2,
        executor_factory=executor_factory(executor),
    )

    assert execution.n_cancelled_before_start == 1
    assert execution.n_not_submitted_after_failure == 1
    assert [record["run_status"] for record in execution.records] == [
        "failed",
        "cancelled_before_start",
        "not_submitted_after_failure",
    ]
    assert executor.shutdown_calls == [(True, True)]


def test_execute_fail_fast_collects_running_completion_after_stop():
    failed = completed_future(worker_that_fails_b1(("b1", 0)))
    running = Future()
    assert running.set_running_or_notify_cancel()

    def finish_running_task():
        running.set_result(successful_worker(("b2", 0)))

    executor = ScriptedExecutor(
        [failed, running],
        shutdown_hook=finish_running_task,
    )

    execution = execute_fail_fast(
        work=[("b1", 0), ("b2", 0), ("b3", 0)],
        worker=successful_worker,
        task_key=lambda item: item,
        max_workers=2,
        executor_factory=executor_factory(executor),
    )

    late = [record for record in execution.records if record.get("completed_after_stop")]
    assert len(late) == 1
    assert late[0]["task_index"] == 1
    assert late[0]["run_status"] == "success"
    assert execution.n_completed_after_stop == 1
    assert execution.n_not_submitted_after_failure == 1


def test_execute_fail_fast_requires_positive_max_workers():
    with pytest.raises(ValueError, match="max_workers must be a positive integer"):
        execute_fail_fast(
            work=[("b1", 0)],
            worker=successful_worker,
            task_key=lambda item: item,
            max_workers=0,
        )
