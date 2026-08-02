"""Protocol-bound host and accelerator estimates for formal version-09 actions."""
from __future__ import annotations

from collections.abc import Mapping
from dataclasses import dataclass
import hashlib
import json
import math

from formal_v09_protocol import validate_protocol_v09
from memory_safety_v09 import (
    GIB,
    MIB,
    MemorySafetyError,
    build_peak_estimate_v09,
    validate_peak_estimate_v09,
)


_ACTION_METHODS = {
    "formal_target_bundle_generation": "analytical_target_bundle_working_set_v1",
    "training": "analytical_training_working_set_v1",
    "formal_prediction_generation": "analytical_prediction_working_set_v1",
}
_VARIANT_GEOMETRY = {
    "strict_nesting_pair": {
        "parameter_key": "classic_parameter_count",
        "parameter_multiplier": 2,
        "recent_hidden_key": "classic_hidden_size",
        "recent_hidden_multiplier": 2,
        "history_steps": 0,
        "history_hidden_size": 0,
    },
    "classic_lstm_256_clean": {
        "parameter_key": "classic_parameter_count",
        "recent_hidden_key": "classic_hidden_size",
        "history_steps": 0,
        "history_hidden_size": 0,
    },
    "classic_lstm_369_capacity": {
        "parameter_key": "capacity_control_parameter_count",
        "recent_hidden_key": "capacity_control_hidden_size",
        "history_steps": 0,
        "history_hidden_size": 0,
    },
    "continuous_multiscale_history": {
        "parameter_key": "candidate_parameter_count",
        "recent_hidden_key": "classic_hidden_size",
        "history_steps": 120,
        "history_hidden_key": "history_hidden_size",
    },
}
_FLOAT_BYTES = 4
_RECENT_STEPS = 270


@dataclass(frozen=True)
class AcceleratorMemorySnapshot:
    """Available and total memory for one accelerator at one decision point."""

    device_index: int
    device_name: str
    total_bytes: int
    available_bytes: int

    def __post_init__(self) -> None:
        if self.device_index < 0:
            raise ValueError("device_index must be nonnegative")
        if not self.device_name:
            raise ValueError("device_name must be nonempty")
        if self.total_bytes <= 0:
            raise ValueError("accelerator total_bytes must be positive")
        if not 0 <= self.available_bytes <= self.total_bytes:
            raise ValueError("accelerator available_bytes must be within total memory")


def _canonical_sha256(value: Mapping) -> str:
    payload = json.dumps(
        value,
        sort_keys=True,
        separators=(",", ":"),
        ensure_ascii=False,
        allow_nan=False,
    ).encode("utf-8")
    return hashlib.sha256(payload).hexdigest()


def _variant_geometry(config: Mapping, variant: str) -> dict:
    if variant not in _VARIANT_GEOMETRY:
        raise ValueError(f"unsupported formal version-09 variant: {variant}")
    frozen = _VARIANT_GEOMETRY[variant]
    return {
        "variant": variant,
        "parameter_count": int(config[frozen["parameter_key"]]) * int(frozen.get("parameter_multiplier", 1)),
        "recent_hidden_size": int(config[frozen["recent_hidden_key"]]) * int(frozen.get("recent_hidden_multiplier", 1)),
        "history_steps": int(frozen["history_steps"]),
        "history_hidden_size": (
            int(config[frozen["history_hidden_key"]])
            if "history_hidden_key" in frozen
            else int(frozen["history_hidden_size"])
        ),
    }


def _common_model_fields(config: Mapping, variant: str) -> dict:
    return {
        "protocol_canonical_sha256": _canonical_sha256(config),
        **_variant_geometry(config, variant),
        "forcing_rows": int(config["expected_forcing_rows"]),
        "dynamic_input_count": int(config["dynamic_input_count"]),
        "float_bytes": _FLOAT_BYTES,
        "basin_count": int(config["basin_count"]),
        "static_attribute_count": int(config["static_attribute_count"]),
        "batch_size": int(config["batch_size"]),
        "causal_window_days": int(config["causal_window_days"]),
        "recent_steps": _RECENT_STEPS,
    }


def _model_peak_values(fields: Mapping, resources: Mapping, *, training: bool) -> tuple[int, int]:
    forcing_bytes = fields["forcing_rows"] * fields["dynamic_input_count"] * _FLOAT_BYTES
    static_bytes = fields["basin_count"] * fields["static_attribute_count"] * _FLOAT_BYTES
    window_bytes = (
        fields["batch_size"]
        * fields["causal_window_days"]
        * fields["dynamic_input_count"]
        * _FLOAT_BYTES
    )
    host_peak = (
        resources["host_fixed_overhead_mib"] * MIB
        + forcing_bytes * resources["forcing_copy_count"]
        + static_bytes * resources["static_copy_count"]
        + window_bytes * resources["window_copy_count"]
        + fields["parameter_count"] * resources["parameter_bytes_upper_bound"]
    )
    if training:
        target_bytes = fields["forcing_rows"] * _FLOAT_BYTES
        host_peak += target_bytes * resources["target_copy_count"]
    else:
        host_peak += (
            resources["prediction_chunk_rows"]
            * resources["prediction_row_bytes_upper_bound"]
        )
    state_elements = fields["batch_size"] * (
        fields["recent_steps"] * fields["recent_hidden_size"]
        + fields["history_steps"] * fields["history_hidden_size"]
    )
    accelerator_peak = (
        resources["accelerator_fixed_overhead_mib"] * MIB
        + window_bytes * resources["accelerator_input_copy_count"]
        + state_elements * _FLOAT_BYTES * resources["accelerator_activation_multiplier"]
        + fields["parameter_count"] * resources["accelerator_parameter_bytes_upper_bound"]
    )
    return int(host_peak), int(accelerator_peak)


def build_formal_action_peak_estimate_v09(
    config: Mapping,
    action: str,
    *,
    variant: str | None = None,
) -> dict:
    """Build the unique protocol-bound estimate for one formal action."""
    validate_protocol_v09(config)
    if action not in _ACTION_METHODS:
        raise ValueError(f"unsupported formal action: {action}")
    resources = config["formal_action_resources"]
    protocol_hash = _canonical_sha256(config)
    if action == "formal_target_bundle_generation":
        if variant is not None:
            raise ValueError("variant is not accepted for target-bundle generation")
        spec = resources["target_bundle"]
        fields = {
            "protocol_canonical_sha256": protocol_hash,
            "action": action,
            "formula": (
                "fixed_overhead_bytes + source_rows_per_basin*source_row_bytes_upper_bound "
                "+ target_rows_per_basin*target_row_bytes_upper_bound + serialization_buffer_bytes"
            ),
            "writer": spec["writer"],
            "fixed_overhead_bytes": int(spec["fixed_overhead_mib"]) * MIB,
            "source_rows_per_basin": int(spec["source_rows_per_basin"]),
            "source_row_bytes_upper_bound": int(spec["source_row_bytes_upper_bound"]),
            "target_rows_per_basin": int(spec["target_rows_per_basin"]),
            "target_row_bytes_upper_bound": int(spec["target_row_bytes_upper_bound"]),
            "serialization_buffer_bytes": int(spec["serialization_buffer_mib"]) * MIB,
        }
        peak = (
            fields["fixed_overhead_bytes"]
            + fields["source_rows_per_basin"] * fields["source_row_bytes_upper_bound"]
            + fields["target_rows_per_basin"] * fields["target_row_bytes_upper_bound"]
            + fields["serialization_buffer_bytes"]
        )
    else:
        if variant is None:
            raise ValueError(f"variant is required for {action}")
        resource_key = "training" if action == "training" else "prediction"
        spec = resources[resource_key]
        common = _common_model_fields(config, variant)
        training = action == "training"
        peak, accelerator_peak = _model_peak_values(common, spec, training=training)
        fields = {
            "protocol_canonical_sha256": protocol_hash,
            "action": action,
            **common,
            "formula": (
                "host_fixed_overhead_bytes + forcing_bytes*forcing_copy_count + "
                "target_bytes*target_copy_count + static_bytes*static_copy_count + "
                "window_bytes*window_copy_count + parameter_count*parameter_bytes_upper_bound"
                if training
                else "host_fixed_overhead_bytes + forcing_bytes*forcing_copy_count + "
                "static_bytes*static_copy_count + window_bytes*window_copy_count + "
                "prediction_chunk_rows*prediction_row_bytes_upper_bound + "
                "parameter_count*parameter_bytes_upper_bound"
            ),
            "accelerator_formula": (
                "accelerator_fixed_overhead_bytes + window_bytes*accelerator_input_copy_count + "
                "state_elements*float_bytes*accelerator_activation_multiplier + "
                "parameter_count*accelerator_parameter_bytes_upper_bound"
            ),
            "host_fixed_overhead_bytes": int(spec["host_fixed_overhead_mib"]) * MIB,
            "forcing_copy_count": int(spec["forcing_copy_count"]),
            "static_copy_count": int(spec["static_copy_count"]),
            "window_copy_count": int(spec["window_copy_count"]),
            "parameter_bytes_upper_bound": int(spec["parameter_bytes_upper_bound"]),
            "accelerator_fixed_overhead_bytes": (
                int(spec["accelerator_fixed_overhead_mib"]) * MIB
            ),
            "accelerator_input_copy_count": int(spec["accelerator_input_copy_count"]),
            "accelerator_activation_multiplier": int(spec["accelerator_activation_multiplier"]),
            "accelerator_parameter_bytes_upper_bound": int(
                spec["accelerator_parameter_bytes_upper_bound"]
            ),
            "accelerator_estimated_peak_bytes": accelerator_peak,
        }
        if training:
            fields["target_copy_count"] = int(spec["target_copy_count"])
        else:
            fields.update({
                "prediction_rows": int(config["expected_evaluation_predictions"]),
                "prediction_chunk_rows": int(spec["prediction_chunk_rows"]),
                "prediction_row_bytes_upper_bound": int(
                    spec["prediction_row_bytes_upper_bound"]
                ),
            })
    return build_peak_estimate_v09(
        method=_ACTION_METHODS[action],
        estimated_peak_bytes=peak,
        evidence_fields=fields,
    )


def validate_formal_action_peak_estimate_v09(
    config: Mapping,
    action: str,
    estimate: Mapping,
    *,
    variant: str | None = None,
) -> dict:
    """Reject a validly hashed estimate unless it equals the frozen action estimate."""
    validate_protocol_v09(config)
    validated = validate_peak_estimate_v09(estimate, long_running=True)
    evidence_variant = (estimate.get("evidence") or {}).get("variant")
    if action == "formal_target_bundle_generation":
        if variant is not None or evidence_variant is not None:
            raise MemorySafetyError("target-bundle estimates do not accept a model variant")
    else:
        if variant is None:
            raise MemorySafetyError(f"expected model variant is required for {action}")
        if evidence_variant != variant:
            raise MemorySafetyError(
                f"formal action estimate variant differs from the requested {action} variant"
            )
    expected = build_formal_action_peak_estimate_v09(
        config,
        action,
        variant=variant,
    )
    if dict(estimate) != expected:
        raise MemorySafetyError("formal action peak estimate differs from the frozen protocol")
    return validated


def sample_cuda_memory_v09(device_index: int = 0) -> AcceleratorMemorySnapshot:
    """Read live memory for the fixed formal CUDA device without allocating tensors."""
    import torch

    if not torch.cuda.is_available():
        raise MemorySafetyError("CUDA is unavailable for the formal model action")
    if type(device_index) is not int or device_index != 0:
        raise MemorySafetyError("formal model resource sampling is fixed to CUDA device 0")
    available_bytes, total_bytes = torch.cuda.mem_get_info(device_index)
    return AcceleratorMemorySnapshot(
        device_index=device_index,
        device_name=str(torch.cuda.get_device_name(device_index)),
        total_bytes=int(total_bytes),
        available_bytes=int(available_bytes),
    )


def assert_accelerator_safe_v09(
    config: Mapping,
    action: str,
    estimate: Mapping,
    snapshot: AcceleratorMemorySnapshot | None,
    *,
    variant: str | None = None,
) -> dict:
    """Require live accelerator headroom for formal training and prediction."""
    validate_formal_action_peak_estimate_v09(
        config,
        action,
        estimate,
        variant=variant,
    )
    if action == "formal_target_bundle_generation":
        if snapshot is not None:
            raise ValueError("target-bundle generation does not accept an accelerator snapshot")
        return {"required": False, "safe": True}
    if snapshot is None:
        raise MemorySafetyError(f"accelerator snapshot is required for {action}")
    resource_key = "training" if action == "training" else "prediction"
    resources = config["formal_action_resources"][resource_key]
    peak = int(estimate["evidence"]["accelerator_estimated_peak_bytes"])
    guarded = math.ceil(peak * float(resources["accelerator_safety_factor"]))
    reserve = math.ceil(float(resources["accelerator_reserve_gib"]) * GIB)
    remaining = snapshot.available_bytes - guarded
    if remaining < reserve:
        raise MemorySafetyError(
            f"guarded {action} estimate would cross the accelerator reserve: "
            f"{remaining} < {reserve}"
        )
    return {
        "required": True,
        "safe": True,
        "device_index": snapshot.device_index,
        "device_name": snapshot.device_name,
        "estimated_peak_bytes": peak,
        "guarded_estimated_peak_bytes": guarded,
        "available_after_guarded_peak_bytes": remaining,
        "reserve_bytes": reserve,
    }


def assert_accelerator_runtime_safe_v09(
    config: Mapping,
    action: str,
    estimate: Mapping,
    snapshot: AcceleratorMemorySnapshot | None,
    *,
    variant: str | None = None,
) -> dict:
    """At chunk boundaries, retain the reserve without double-counting resident tensors."""
    validate_formal_action_peak_estimate_v09(
        config,
        action,
        estimate,
        variant=variant,
    )
    if action == "formal_target_bundle_generation":
        if snapshot is not None:
            raise ValueError("target-bundle generation does not accept an accelerator snapshot")
        return {"required": False, "safe": True}
    if snapshot is None:
        raise MemorySafetyError(f"accelerator snapshot is required for {action}")
    resource_key = "training" if action == "training" else "prediction"
    resources = config["formal_action_resources"][resource_key]
    reserve = math.ceil(float(resources["accelerator_reserve_gib"]) * GIB)
    if snapshot.available_bytes < reserve:
        raise MemorySafetyError(
            f"accelerator memory is below the runtime reserve: "
            f"{snapshot.available_bytes} < {reserve}"
        )
    return {
        "required": True,
        "safe": True,
        "device_index": snapshot.device_index,
        "device_name": snapshot.device_name,
        "available_bytes": snapshot.available_bytes,
        "reserve_bytes": reserve,
    }
