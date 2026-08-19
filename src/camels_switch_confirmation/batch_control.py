"""Bounded concurrent task execution with auditable fail-fast evidence."""

from __future__ import annotations

from collections.abc import Callable, Iterable, Mapping
from concurrent.futures import FIRST_COMPLETED, ProcessPoolExecutor, wait
from dataclasses import dataclass
from typing import Any, TypeVar


WorkItem = TypeVar("WorkItem")
Record = dict[str, Any]


@dataclass(frozen=True)
class BatchExecution:
    """Complete scheduler outcome, including work suppressed after a failure."""

    records: list[Record]
    execution_status: str
    first_failure: Record | None
    n_planned: int
    n_submitted: int
    n_cancelled_before_start: int
    n_not_submitted_after_failure: int
    n_completed_after_stop: int


def _task_metadata(task_index: int, task_key_value: Any) -> Record:
    metadata: Record = {}
    if isinstance(task_key_value, Mapping):
        metadata.update(task_key_value)
    elif isinstance(task_key_value, (tuple, list)) and len(task_key_value) == 2:
        metadata.update({
            "basin_id": task_key_value[0],
            "seed": task_key_value[1],
        })
    metadata.update({
        "task_index": task_index,
        "task_key": task_key_value,
    })
    return metadata


def _exception_record(
    metadata: Mapping[str, Any],
    error: Exception,
    *,
    failure_stage: str,
) -> Record:
    error_type = type(error).__name__
    return {
        **metadata,
        "run_status": "failed",
        "error_type": error_type,
        "error_message": f"{error_type}: {error}",
        "failure_stage": failure_stage,
    }


def _worker_result_record(result: Any, metadata: Mapping[str, Any]) -> Record:
    if not isinstance(result, Mapping) or result.get("run_status") not in {
        "success",
        "failed",
    }:
        returned_status = result.get("run_status") if isinstance(result, Mapping) else None
        return {
            **metadata,
            "run_status": "failed",
            "error_type": "WorkerResultContractError",
            "error_message": (
                "worker result run_status must be 'success' or 'failed'; "
                f"received {returned_status!r}"
            ),
            "failure_stage": "worker_result_contract",
            "returned_run_status": returned_status,
        }

    record = dict(result)
    record.update(metadata)
    if record["run_status"] == "failed":
        record.setdefault("failure_stage", "worker_return")
        record.setdefault("error_message", "worker returned failure")
    return record


def _resolve_future(future, metadata: Mapping[str, Any]) -> Record:
    try:
        result = future.result()
    except Exception as error:  # noqa: BLE001 - evidence must capture worker errors
        return _exception_record(metadata, error, failure_stage="worker_future")
    return _worker_result_record(result, metadata)


def _suppressed_record(
    metadata: Mapping[str, Any],
    *,
    run_status: str,
    first_failure: Mapping[str, Any],
) -> Record:
    return {
        **metadata,
        "run_status": run_status,
        "error_message": (
            "task suppressed after first observed failure at task_index "
            f"{first_failure['task_index']}"
        ),
        "stop_after_task_index": first_failure["task_index"],
    }


def execute_fail_fast(
    work: Iterable[WorkItem],
    worker: Callable[[WorkItem], Mapping[str, Any]],
    task_key: Callable[[WorkItem], Any],
    max_workers: int,
    executor_factory=ProcessPoolExecutor,
) -> BatchExecution:
    """Execute ordered work without starting new tasks after the first failure.

    At most ``max_workers`` tasks are submitted at once. A worker-returned
    failure, a future exception, a submission exception, or an invalid worker
    status stops queue replenishment. Tasks already running finish safely;
    tasks that can still be cancelled and tasks never submitted are represented
    explicitly in ``records``.
    """
    if isinstance(max_workers, bool) or not isinstance(max_workers, int) or max_workers <= 0:
        raise ValueError("max_workers must be a positive integer")

    work_items = list(work)
    n_planned = len(work_items)
    task_metadata = [
        _task_metadata(index, task_key(item))
        for index, item in enumerate(work_items)
    ]
    if not work_items:
        return BatchExecution(
            records=[],
            execution_status="complete",
            first_failure=None,
            n_planned=0,
            n_submitted=0,
            n_cancelled_before_start=0,
            n_not_submitted_after_failure=0,
            n_completed_after_stop=0,
        )

    executor = executor_factory(max_workers=max_workers)
    pending = {}
    records_by_index: dict[int, Record] = {}
    next_index = 0
    n_submitted = 0
    n_cancelled_before_start = 0
    n_not_submitted_after_failure = 0
    n_completed_after_stop = 0
    first_failure: Record | None = None
    shutdown_called = False

    def submit_until_full() -> None:
        nonlocal next_index, n_submitted, first_failure
        while (
            first_failure is None
            and next_index < n_planned
            and len(pending) < max_workers
        ):
            task_index = next_index
            next_index += 1
            try:
                future = executor.submit(worker, work_items[task_index])
            except Exception as error:  # noqa: BLE001 - submission is run evidence
                failure = _exception_record(
                    task_metadata[task_index],
                    error,
                    failure_stage="submission",
                )
                records_by_index[task_index] = failure
                first_failure = dict(failure)
                return
            pending[future] = task_index
            n_submitted += 1

    try:
        submit_until_full()
        while pending and first_failure is None:
            completed, _ = wait(tuple(pending), return_when=FIRST_COMPLETED)
            for future in sorted(completed, key=lambda item: pending[item]):
                task_index = pending.pop(future)
                record = _resolve_future(future, task_metadata[task_index])
                records_by_index[task_index] = record
                if record["run_status"] == "failed" and first_failure is None:
                    first_failure = dict(record)

            if first_failure is None:
                submit_until_full()

        if first_failure is not None:
            pending_in_task_order = sorted(
                pending.items(),
                key=lambda item: item[1],
            )
            for future, _task_index in pending_in_task_order:
                future.cancel()

            shutdown_called = True
            executor.shutdown(wait=True, cancel_futures=True)

            for future, task_index in pending_in_task_order:
                if future.cancelled():
                    records_by_index[task_index] = _suppressed_record(
                        task_metadata[task_index],
                        run_status="cancelled_before_start",
                        first_failure=first_failure,
                    )
                    n_cancelled_before_start += 1
                else:
                    record = _resolve_future(future, task_metadata[task_index])
                    record["completed_after_stop"] = True
                    records_by_index[task_index] = record
                    n_completed_after_stop += 1

            for task_index in range(next_index, n_planned):
                records_by_index[task_index] = _suppressed_record(
                    task_metadata[task_index],
                    run_status="not_submitted_after_failure",
                    first_failure=first_failure,
                )
                n_not_submitted_after_failure += 1
        else:
            shutdown_called = True
            executor.shutdown(wait=True)
    finally:
        if not shutdown_called:
            executor.shutdown(
                wait=True,
                cancel_futures=first_failure is not None,
            )

    return BatchExecution(
        records=[records_by_index[index] for index in range(n_planned)],
        execution_status="failed_early" if first_failure is not None else "complete",
        first_failure=first_failure,
        n_planned=n_planned,
        n_submitted=n_submitted,
        n_cancelled_before_start=n_cancelled_before_start,
        n_not_submitted_after_failure=n_not_submitted_after_failure,
        n_completed_after_stop=n_completed_after_stop,
    )
