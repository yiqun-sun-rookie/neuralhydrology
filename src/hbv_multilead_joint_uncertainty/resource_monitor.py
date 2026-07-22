"""Exact start/running gates with an independent background monitor."""

from __future__ import annotations

import json
import math
import os
import threading
import time
from datetime import datetime
from pathlib import Path
from typing import Mapping

from threadpoolctl import threadpool_limits

from hbv_joint_uncertainty.resource_monitor import (
    ResourceGateError,
    ResourceSnapshot,
    capture_resource_snapshot,
)


RUN_RESOURCE_ESTIMATES_GIB = {
    "contract": {"estimated_peak_gib": 0.75, "estimated_output_gib": 0.5},
    "evaluation": {"estimated_peak_gib": 1.0, "estimated_output_gib": 1.5},
}


def _percentage_label(fraction: float) -> str:
    return f"{100.0 * float(fraction):g}%"


def enforce_start_gate(
    snapshot: ResourceSnapshot,
    resource_config: Mapping,
    estimated_peak_gib: float,
    estimated_output_gib: float,
) -> None:
    peak = float(estimated_peak_gib)
    output = float(estimated_output_gib)
    if not math.isfinite(peak) or peak <= 0.0:
        raise ResourceGateError("estimated peak memory must be a positive finite value")
    if not math.isfinite(output) or output <= 0.0:
        raise ResourceGateError("estimated output size must be a positive finite value")
    minimum_start = float(resource_config["minimum_start_available_fraction"])
    if snapshot.available_memory_fraction < minimum_start:
        raise ResourceGateError(
            f"available memory is below the {_percentage_label(minimum_start)} start threshold"
        )
    maximum_peak = float(resource_config["maximum_estimated_peak_fraction_of_available"])
    if peak > maximum_peak * snapshot.available_memory_gib:
        raise ResourceGateError(
            "estimated peak memory exceeds "
            f"{_percentage_label(maximum_peak)} of currently available memory"
        )
    required_disk = max(
        float(resource_config["minimum_free_disk_gib"]),
        float(resource_config["minimum_output_space_multiplier"]) * output,
    )
    if snapshot.disk_free_gib < required_disk:
        raise ResourceGateError(
            f"free disk is {snapshot.disk_free_gib:.3f} GiB; the disk gate requires {required_disk:.3f} GiB"
        )
    reserved = int(resource_config["reserved_logical_processors"])
    if snapshot.logical_processors <= reserved:
        raise ResourceGateError("at least one worker plus two logical processors reserved is required")


def enforce_running_gate(
    snapshot: ResourceSnapshot,
    resource_config: Mapping,
    estimated_output_gib: float,
) -> None:
    minimum_running = float(resource_config["minimum_running_available_fraction"])
    if snapshot.available_memory_fraction < minimum_running:
        raise ResourceGateError(
            "available memory is below the "
            f"{_percentage_label(minimum_running)} running threshold; stop safely"
        )
    required_disk = max(
        float(resource_config["minimum_free_disk_gib"]),
        float(resource_config["minimum_output_space_multiplier"]) * float(estimated_output_gib),
    )
    if snapshot.disk_free_gib < required_disk:
        raise ResourceGateError(
            f"free disk is {snapshot.disk_free_gib:.3f} GiB; "
            f"the running disk gate requires {required_disk:.3f} GiB"
        )


def verify_resource_history_rows(
    history,
    resource_config: Mapping,
    require_finish: bool = False,
    run_kind: str | None = None,
) -> dict:
    rows = [dict(row) for row in history]
    if not rows:
        raise ValueError("resource history is empty")
    if rows[0].get("event") != "start":
        raise ValueError("resource history does not begin with a start sample")
    if require_finish and rows[-1].get("event") != "finish":
        raise ValueError("resource history does not end with a finish sample")
    try:
        timestamps = [datetime.fromisoformat(str(row["timestamp"])) for row in rows]
    except (KeyError, TypeError, ValueError) as error:
        raise ValueError("resource history contains an invalid timestamp") from error
    gaps = [(right - left).total_seconds() for left, right in zip(timestamps, timestamps[1:])]
    if any(gap < 0.0 for gap in gaps):
        raise ValueError("resource history timestamps are not chronological")
    maximum_gap = max(gaps, default=0.0)
    maximum_allowed = float(resource_config["monitor_interval_seconds"]) + 0.5
    if maximum_gap > maximum_allowed:
        raise ValueError(f"resource monitoring gap exceeds {maximum_allowed:.1f} seconds")
    required_numeric = (
        "available_memory_fraction",
        "available_memory_gib",
        "process_rss_gib",
        "process_peak_working_set_gib",
        "cpu_load_percent",
        "disk_free_gib",
    )
    for row in rows:
        try:
            values = [float(row[name]) for name in required_numeric]
        except (KeyError, TypeError, ValueError) as error:
            raise ValueError("resource history contains an invalid numeric field") from error
        if not all(math.isfinite(value) and value >= 0.0 for value in values):
            raise ValueError("resource history contains a non-finite or negative field")
    start = rows[0]
    try:
        estimated_peak_gib = float(start["estimated_peak_gib"])
        estimated_output_gib = float(start["estimated_output_gib"])
        numerical_thread_limit = int(start["numerical_thread_limit"])
        reserved_logical_processors = int(start["reserved_logical_processors"])
        logical_processors = int(start["logical_processors"])
    except (KeyError, TypeError, ValueError) as error:
        raise ValueError("resource history lacks a valid recorded start-gate input") from error
    if not all(
        math.isfinite(value) and value > 0.0
        for value in (estimated_peak_gib, estimated_output_gib)
    ):
        raise ValueError("resource history start estimates must be positive finite values")
    if run_kind is not None:
        if run_kind not in RUN_RESOURCE_ESTIMATES_GIB:
            raise ValueError(f"unknown resource run kind: {run_kind}")
        expected = RUN_RESOURCE_ESTIMATES_GIB[run_kind]
        if (
            estimated_peak_gib != expected["estimated_peak_gib"]
            or estimated_output_gib != expected["estimated_output_gib"]
        ):
            raise ValueError(f"resource history does not match the fixed {run_kind} resource estimate")
    if numerical_thread_limit != 1:
        raise ValueError("resource history does not record the one-thread numerical limit")
    configured_reserved = int(resource_config["reserved_logical_processors"])
    if reserved_logical_processors != configured_reserved:
        raise ValueError("resource history records the wrong reserved logical processor count")
    if float(rows[0]["available_memory_fraction"]) < float(
        resource_config["minimum_start_available_fraction"]
    ):
        raise ValueError("resource history violates the start-memory gate")
    maximum_peak_fraction = float(resource_config["maximum_estimated_peak_fraction_of_available"])
    if estimated_peak_gib > maximum_peak_fraction * float(start["available_memory_gib"]):
        raise ValueError("resource history estimated peak violates the start-memory gate")
    if logical_processors <= configured_reserved:
        raise ValueError("resource history violates the start logical processors gate")
    required_disk_gib = max(
        float(resource_config["minimum_free_disk_gib"]),
        float(resource_config["minimum_output_space_multiplier"]) * estimated_output_gib,
    )
    if float(start["disk_free_gib"]) < required_disk_gib:
        raise ValueError("resource history violates the start-disk gate")
    if any(
        float(row["available_memory_fraction"])
        < float(resource_config["minimum_running_available_fraction"])
        for row in rows[1:]
    ):
        raise ValueError("resource history violates the running-memory gate")
    if any(float(row["disk_free_gib"]) < required_disk_gib for row in rows[1:]):
        raise ValueError("resource history violates the running-disk gate")
    return {
        "sample_count": len(rows),
        "maximum_gap_seconds": float(maximum_gap),
        "first_event": rows[0]["event"],
        "last_event": rows[-1]["event"],
        "estimated_peak_gib": estimated_peak_gib,
        "estimated_output_gib": estimated_output_gib,
    }


class ResourceRecorder:
    """Sample resources in the background and surface failures at the next safe checkpoint."""

    def __init__(self, probe_path: Path, resource_config: Mapping, history_path: Path | None = None):
        self.probe_path = Path(probe_path).resolve()
        self.config = dict(resource_config)
        self.history_path = None if history_path is None else Path(history_path).resolve()
        self.history: list[dict] = []
        self._last_sample_monotonic: float | None = None
        self._lock = threading.RLock()
        self._monitor_stop = threading.Event()
        self._monitor_thread: threading.Thread | None = None
        self._background_error: ResourceGateError | None = None
        self._threadpool_limit_context = None
        self._estimated_peak_gib: float | None = None
        self._estimated_output_gib: float | None = None

    def _enforce_running_gate(self, snapshot: ResourceSnapshot) -> None:
        if self._estimated_output_gib is None:
            raise RuntimeError("resource recorder has not recorded an output-size estimate")
        enforce_running_gate(snapshot, self.config, self._estimated_output_gib)

    def _release_thread_limit(self) -> None:
        context = self._threadpool_limit_context
        if context is None:
            return
        context.__exit__(None, None, None)
        self._threadpool_limit_context = None

    def _persist_locked(self) -> None:
        if self.history_path is None:
            return
        self.history_path.parent.mkdir(parents=True, exist_ok=True)
        temporary = self.history_path.with_name(f".{self.history_path.name}.{os.getpid()}.tmp")
        temporary.write_text(json.dumps(self.history, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        os.replace(temporary, self.history_path)

    def _append(self, event: str, snapshot: ResourceSnapshot, **context) -> None:
        with self._lock:
            self.history.append({"event": str(event), **context, **snapshot.to_dict()})
            self._last_sample_monotonic = time.monotonic()
            self._persist_locked()

    def _monitor(self) -> None:
        interval = float(self.config["monitor_interval_seconds"])
        maximum_probe = float(self.config.get("maximum_resource_probe_seconds", 5.0))
        wait_interval = min(interval, max(0.01, interval - maximum_probe - 0.5))
        while not self._monitor_stop.wait(wait_interval):
            try:
                snapshot = capture_resource_snapshot(self.probe_path)
                if self._monitor_stop.is_set():
                    return
                self._append("background_monitor", snapshot)
                self._enforce_running_gate(snapshot)
            except ResourceGateError as error:
                with self._lock:
                    self._background_error = error
                self._monitor_stop.set()
                return
            except Exception as error:
                with self._lock:
                    self._background_error = ResourceGateError(
                        f"background resource monitor failed: {type(error).__name__}: {error}"
                    )
                self._monitor_stop.set()
                return

    def _raise_background_error(self) -> None:
        with self._lock:
            error = self._background_error
        if error is not None:
            raise error

    def _stop_monitor(self) -> None:
        self._monitor_stop.set()
        thread = self._monitor_thread
        if thread is not None and thread is not threading.current_thread():
            thread.join(timeout=max(1.0, float(self.config["monitor_interval_seconds"]) + 1.0))
            if thread.is_alive():
                raise RuntimeError("background resource monitor did not stop")
        self._monitor_thread = None

    def start(self, estimated_peak_gib: float, estimated_output_gib: float, **context) -> ResourceSnapshot:
        snapshot = capture_resource_snapshot(self.probe_path)
        enforce_start_gate(snapshot, self.config, estimated_peak_gib, estimated_output_gib)
        self._estimated_peak_gib = float(estimated_peak_gib)
        self._estimated_output_gib = float(estimated_output_gib)
        self._threadpool_limit_context = threadpool_limits(limits=1)
        self._threadpool_limit_context.__enter__()
        try:
            self._append(
                "start",
                snapshot,
                estimated_peak_gib=self._estimated_peak_gib,
                estimated_output_gib=self._estimated_output_gib,
                numerical_thread_limit=1,
                reserved_logical_processors=int(self.config["reserved_logical_processors"]),
                **context,
            )
            self._monitor_stop.clear()
            self._monitor_thread = threading.Thread(
                target=self._monitor,
                name="resource-monitor",
                daemon=True,
            )
            self._monitor_thread.start()
        except Exception:
            self._release_thread_limit()
            raise
        return snapshot

    def checkpoint(self, event: str, force: bool = False, **context) -> ResourceSnapshot | None:
        self._raise_background_error()
        now = time.monotonic()
        interval = float(self.config["monitor_interval_seconds"])
        if not force and self._last_sample_monotonic is not None and now - self._last_sample_monotonic < interval:
            return None
        snapshot = capture_resource_snapshot(self.probe_path)
        self._append(event, snapshot, **context)
        self._enforce_running_gate(snapshot)
        return snapshot

    def finish(self, **context) -> ResourceSnapshot:
        self._stop_monitor()
        try:
            self._raise_background_error()
            snapshot = capture_resource_snapshot(self.probe_path)
            self._append("finish", snapshot, **context)
            self._enforce_running_gate(snapshot)
            if snapshot is None:
                raise RuntimeError("forced finish resource sample was not recorded")
            return snapshot
        finally:
            self._release_thread_limit()

    def abort(self) -> None:
        """Stop monitoring during failure cleanup without masking the original error."""
        self._monitor_stop.set()
        thread = self._monitor_thread
        if thread is not None and thread is not threading.current_thread():
            thread.join(timeout=max(1.0, float(self.config["monitor_interval_seconds"]) + 1.0))
            if thread.is_alive():
                raise RuntimeError("background resource monitor did not stop during abort")
        self._monitor_thread = None
        self._release_thread_limit()
