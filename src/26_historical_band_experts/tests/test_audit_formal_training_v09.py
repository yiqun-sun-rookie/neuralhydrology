"""Adversarial tests for the formal version-09 24-run training audit."""
from copy import deepcopy
import json
from pathlib import Path
from types import SimpleNamespace
import sys

import pytest
import torch

IDEA_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(IDEA_ROOT))

_HASHES = {
    "input_seal_sha256": "1" * 64,
    "input_external_audit_sha256": "2" * 64,
    "trusted_source_audit_sha256": "3" * 64,
}


def _model_builder(_variant, seed):
    torch.manual_seed(int(seed))
    return torch.nn.Linear(2, 2)


def _spec(*, seed=100, family="E09-CONTINUOUS", variant="continuous_multiscale_history", position=1):
    return SimpleNamespace(
        position=position,
        seed=seed,
        family=family,
        run_id=f"{family}-S{seed}",
        variant=variant,
        trainable_parameters=6,
        results_root=f"results/26_historical_band_experts/formal_v09/{family.lower()}",
    )


def _write_json(path, value):
    path.write_text(
        json.dumps(value, indent=2, sort_keys=True, ensure_ascii=False, allow_nan=True) + "\n",
        encoding="utf-8",
    )


def _seal_run(run_root):
    from artifact_v09 import canonical_sha256, exact_file_inventory, sha256_file

    seal_path = run_root / "seal.json"
    if seal_path.exists():
        seal_path.unlink()
    names = ["checkpoint_epoch010.pt", "checkpoint_epoch020.pt", "checkpoint_epoch030.pt", "manifest.json"]
    inventory = exact_file_inventory(run_root, names)
    _write_json(
        seal_path, {
            "schema": "historical_multiscale_formal_v09_main_run_seal_v1",
            "status": "sealed",
            "sealed_files": inventory,
            "sealed_files_sha256": canonical_sha256(inventory),
            "manifest_sha256": sha256_file(run_root / "manifest.json"),
        })


def _make_run(tmp_path, *, spec=None, input_bindings=None):
    spec = spec or _spec()
    input_bindings = input_bindings or _HASHES
    run_root = tmp_path / spec.run_id
    run_root.mkdir(parents=True)
    model = _model_builder(spec.variant, spec.seed)
    optimizer = torch.optim.Adam(model.parameters(), lr=0.001)
    epoch_trace = []
    for epoch in range(1, 31):
        permutation = f"{epoch:064x}"
        epoch_trace.append({
            "epoch": epoch,
            "learning_rate": 0.001 if epoch <= 10 else (0.0005 if epoch <= 20 else 0.0001),
            "permutation_sha256": permutation,
            "optimizer_steps": 6_821,
            "mean_training_loss": 1.0 / epoch,
        })
        if epoch in (10, 20, 30):
            torch.save(
                {
                    "schema": "historical_multiscale_formal_v09_run_checkpoint_v1",
                    "epoch": epoch,
                    "model_state_dict": model.state_dict(),
                    "optimizer_state_dict": optimizer.state_dict(),
                    "permutation_sha256": permutation,
                },
                run_root / f"checkpoint_epoch{epoch:03d}.pt",
            )
    history = spec.variant == "continuous_multiscale_history"
    health = []
    if history:
        health = [
            {
                "step": 1,
                "gate_absolute_maximum": 0.0,
                "gate_gradient_norm": 2.0,
                "history_encoder_gradient_norm": 0.0,
                "gate_gradients_present": True,
                "history_encoder_gradients_present": True,
            },
            {
                "step": 2,
                "gate_absolute_maximum": 0.01,
                "gate_gradient_norm": 1.0,
                "history_encoder_gradient_norm": 0.5,
                "gate_gradients_present": True,
                "history_encoder_gradients_present": True,
            },
        ]
    manifest = {
        "schema": "historical_multiscale_formal_v09_main_run_v1",
        "status": "formal_training_complete",
        "formal_execution": True,
        "variant": spec.variant,
        "seed": spec.seed,
        "epochs": 30,
        "batch_size": 256,
        "training_samples": 1_745_928,
        "trainable_parameters": spec.trainable_parameters,
        "optimizer_steps_per_epoch": 6_821,
        "optimizer_steps_total": 204_630,
        "checkpoint_epochs": [10, 20, 30],
        "checkpoint_files": [
            "checkpoint_epoch010.pt",
            "checkpoint_epoch020.pt",
            "checkpoint_epoch030.pt",
        ],
        "epoch_trace": epoch_trace,
        "dropout_rng_binding": {
            "dropout_seed": spec.seed * 1_000_003 + 900_001,
            "cpu_state_sha256": "4" * 64,
            "cuda_state_sha256": "5" * 64,
        },
        "history_health_trace": health,
        "history_encoder_first_nonzero_gradient_step": 2 if history else None,
        "input_bindings": dict(input_bindings),
        "validation_metrics_computed": False,
        "formal_evaluation_observation_reads": 0,
        "formal_period_predictions_generated": False,
    }
    _write_json(run_root / "manifest.json", manifest)
    _seal_run(run_root)
    return run_root, manifest, spec


def _audit(run_root, spec):
    from audit_formal_training_v09 import audit_training_run_v09

    return audit_training_run_v09(
        run_root,
        spec,
        _HASHES,
        {"source_tree_sha256": "6" * 64, "environment_sha256": "7" * 64},
        model_builder=_model_builder,
    )


def test_training_run_audit_rehashes_and_loads_all_three_checkpoints(tmp_path):
    run_root, _, spec = _make_run(tmp_path)
    report = _audit(run_root, spec)
    assert report["status"] == "training_run_audit_passed"
    assert report["checkpoint_epochs_verified"] == [10, 20, 30]
    assert report["final_checkpoint"]["eligible_for_formal_prediction"] is True
    assert report["intermediate_checkpoints"][0]["not_eligible_for_formal_prediction"] is True
    assert report["nonfinite_tensor_count"] == 0


def test_training_run_audit_rejects_any_sealed_byte_drift(tmp_path):
    run_root, _, spec = _make_run(tmp_path)
    with (run_root / "manifest.json").open("ab") as handle:
        handle.write(b" ")
    with pytest.raises(ValueError, match="sealed file drift|manifest hash"):
        _audit(run_root, spec)


@pytest.mark.parametrize(
    ("field", "value", "message"),
    [
        ("epochs", 29, "epochs"),
        ("optimizer_steps_total", 204_629, "optimizer_steps_total"),
        ("validation_metrics_computed", True, "validation"),
        ("formal_evaluation_observation_reads", 1, "observation"),
        ("formal_period_predictions_generated", True, "prediction"),
    ],
)
def test_training_run_audit_rejects_manifest_contract_drift(tmp_path, field, value, message):
    run_root, manifest, spec = _make_run(tmp_path)
    manifest[field] = value
    _write_json(run_root / "manifest.json", manifest)
    _seal_run(run_root)
    with pytest.raises(ValueError, match=message):
        _audit(run_root, spec)


def test_training_run_audit_rejects_nonfinite_loss_even_when_resealed(tmp_path):
    run_root, manifest, spec = _make_run(tmp_path)
    manifest["epoch_trace"][9]["mean_training_loss"] = float("nan")
    _write_json(run_root / "manifest.json", manifest)
    _seal_run(run_root)
    with pytest.raises(ValueError, match="non-finite|finite"):
        _audit(run_root, spec)


def test_training_run_audit_rejects_nonfinite_checkpoint_tensor(tmp_path):
    run_root, _, spec = _make_run(tmp_path)
    checkpoint_path = run_root / "checkpoint_epoch030.pt"
    checkpoint = torch.load(checkpoint_path, map_location="cpu", weights_only=False)
    checkpoint["model_state_dict"]["weight"][0, 0] = float("inf")
    torch.save(checkpoint, checkpoint_path)
    _seal_run(run_root)
    with pytest.raises(ValueError, match="non-finite"):
        _audit(run_root, spec)


def test_continuous_run_requires_the_preregistered_gradient_chain(tmp_path):
    run_root, manifest, spec = _make_run(tmp_path)
    manifest["history_health_trace"][0]["gate_gradient_norm"] = 0.0
    _write_json(run_root / "manifest.json", manifest)
    _seal_run(run_root)
    with pytest.raises(ValueError, match="gate gradient"):
        _audit(run_root, spec)


def _suite_records():
    records = []
    families = (
        ("B09-CLASSIC", "classic_lstm_256_clean"),
        ("B09-CAPACITY", "classic_lstm_369_capacity"),
        ("E09-CONTINUOUS", "continuous_multiscale_history"),
    )
    position = 0
    for seed in (100, 200, 300, 400, 500, 600, 700, 800):
        permutation_hashes = [f"{seed + epoch:064x}" for epoch in range(1, 31)]
        dropout = {
            "dropout_seed": seed * 1_000_003 + 900_001,
            "cpu_state_sha256": f"{seed:064x}",
            "cuda_state_sha256": f"{seed + 1:064x}",
        }
        for family, variant in families:
            position += 1
            records.append({
                "position": position,
                "run_id": f"{family}-S{seed}",
                "family": family,
                "variant": variant,
                "seed": seed,
                "permutation_sha256": list(permutation_hashes),
                "dropout_rng_binding": deepcopy(dropout),
                "input_bindings": dict(_HASHES),
                "run_seal_sha256": f"{position:064x}",
                "checkpoints": [],
            })
    return records


def test_suite_cross_checks_exact_count_identity_permutations_and_dropout():
    from audit_formal_training_v09 import validate_training_suite_records_v09

    records = _suite_records()
    report = validate_training_suite_records_v09(records)
    assert report["run_count"] == 24
    assert report["same_seed_permutations"] is True
    assert report["same_seed_dropout_rng"] is True


@pytest.mark.parametrize("mutation", ["missing", "duplicate", "permutation", "dropout", "input"])
def test_suite_cross_checks_reject_every_cross_run_drift(mutation):
    from audit_formal_training_v09 import validate_training_suite_records_v09

    records = _suite_records()
    if mutation == "missing":
        records.pop()
    elif mutation == "duplicate":
        records[-1] = deepcopy(records[-2])
    elif mutation == "permutation":
        records[1]["permutation_sha256"][5] = "f" * 64
    elif mutation == "dropout":
        records[1]["dropout_rng_binding"]["cpu_state_sha256"] = "f" * 64
    else:
        records[1]["input_bindings"]["input_seal_sha256"] = "f" * 64
    with pytest.raises(ValueError):
        validate_training_suite_records_v09(records)


def _make_formal_suite(tmp_path):
    from artifact_v09 import sha256_file
    from train_formal_v09 import FormalRunSpecV09, load_run_order_v09

    formal_root = tmp_path / "results/26_historical_band_experts/formal_v09"
    input_root = formal_root / "input_attempt_01"
    input_root.mkdir(parents=True)
    _write_json(input_root / "seal.json", {"schema": "test_input_seal", "status": "sealed"})
    _write_json(formal_root / "input_attempt_01.external_audit.json", {"status": "complete_input_audit_passed"})
    _write_json(
        formal_root / "input_attempt_01.trusted_source_external_audit.json",
        {"status": "complete_trusted_training_target_audit"},
    )
    bindings = {
        "input_seal_sha256": sha256_file(input_root / "seal.json"),
        "input_external_audit_sha256": sha256_file(formal_root / "input_attempt_01.external_audit.json"),
        "trusted_source_audit_sha256": sha256_file(
            formal_root / "input_attempt_01.trusted_source_external_audit.json"),
    }
    run_order_path = IDEA_ROOT / "configs/formal_v09_run_order.json"
    production_specs = load_run_order_v09(run_order_path)
    specs = tuple(
        FormalRunSpecV09(
            position=spec.position,
            seed=spec.seed,
            family=spec.family,
            run_id=spec.run_id,
            variant=spec.variant,
            trainable_parameters=6,
            results_root=spec.results_root,
        )
        for spec in production_specs
    )
    _write_json(
        formal_root / "training_progress.json", {
            "schema": "historical_multiscale_formal_v09_training_progress_v1",
            "progress": {
                "total": 24,
                "completed": [spec.run_id for spec in specs],
                "pending": [],
                "dirty": [],
            },
        })
    staging = tmp_path / "staging"
    staging.mkdir()
    for spec in specs:
        source, _, _ = _make_run(staging, spec=spec, input_bindings=bindings)
        destination = formal_root / Path(spec.results_root).name / f"seed_{spec.seed}"
        destination.parent.mkdir(parents=True, exist_ok=True)
        source.rename(destination)
    return formal_root, specs, bindings


def test_suite_audit_writes_one_external_report_after_all_24_runs_pass(tmp_path):
    from audit_formal_training_v09 import audit_training_suite_v09

    formal_root, specs, _ = _make_formal_suite(tmp_path)
    report_path = formal_root / "training_external_audit.json"
    report = audit_training_suite_v09(
        formal_root,
        specs,
        report_path,
        model_builder=_model_builder,
        source_seal={"source_tree_sha256": "6" * 64, "environment_sha256": "7" * 64},
    )
    assert report["status"] == "complete_training_audit"
    assert report["coverage"] == {"expected_runs": 24, "audited_runs": 24, "passed_runs": 24}
    assert report["audit_source_context"]["file_count"] >= 7
    assert len(report["audit_source_context_sha256"]) == 64
    assert report["pre_seal_evidence"]["canonical_four_workload_resource_preflight_report_present"] is False
    assert report["pre_seal_evidence"]["known_blockers"] == [
        "canonical_four_workload_resource_preflight_report_missing"]
    assert report["formal_evaluation_observation_reads"] == 0
    assert report["formal_period_predictions_generated"] is False
    assert json.loads(report_path.read_text(encoding="utf-8")) == report


def test_suite_audit_refuses_extra_run_and_a_preexisting_training_seal(tmp_path):
    from audit_formal_training_v09 import audit_training_suite_v09

    formal_root, specs, _ = _make_formal_suite(tmp_path)
    extra = formal_root / "classic/seed_999"
    extra.mkdir(parents=True)
    with pytest.raises(ValueError, match="run directory coverage"):
        audit_training_suite_v09(
            formal_root,
            specs,
            formal_root / "training_external_audit.json",
            model_builder=_model_builder,
            source_seal={"source_tree_sha256": "6" * 64},
        )
    extra.rmdir()
    _write_json(formal_root / "training_seal.json", {"status": "premature"})
    with pytest.raises(ValueError, match="training seal"):
        audit_training_suite_v09(
            formal_root,
            specs,
            formal_root / "training_external_audit.json",
            model_builder=_model_builder,
            source_seal={"source_tree_sha256": "6" * 64},
        )


def test_suite_audit_report_must_be_outside_every_sealed_run(tmp_path):
    from audit_formal_training_v09 import audit_training_suite_v09

    formal_root, specs, _ = _make_formal_suite(tmp_path)
    report_path = formal_root / "classic/seed_100/training_external_audit.json"
    with pytest.raises(ValueError, match="direct child|outside"):
        audit_training_suite_v09(
            formal_root,
            specs,
            report_path,
            model_builder=_model_builder,
            source_seal={"source_tree_sha256": "6" * 64},
        )


def _make_seal_dependencies(formal_root, specs, audit_report, tmp_path):
    from artifact_v09 import canonical_sha256, sha256_file
    from formal_v09_protocol import load_protocol_v09
    import state_diagnostics_formal_v09 as diagnostics

    diagnostic_root = formal_root / "state_diagnostics"
    diagnostic_root.mkdir()
    children = []
    for seed in range(100, 801, 100):
        child = diagnostic_root / f"E09-CONTINUOUS_s{seed}"
        child.mkdir()
        _write_json(child / "manifest.json", {"seed": seed, "status": "state_diagnostics_complete"})
        binding = diagnostics._directory_binding_v09(child)
        children.append({
            "seed": seed,
            "run_id": f"E09-CONTINUOUS-S{seed}",
            "relative_path": child.name,
            "manifest_sha256": sha256_file(child / "manifest.json"),
            "directory_file_count": binding["file_count"],
            "directory_files_sha256": binding["files_sha256"],
            "array_count": 8,
            "checkpoint_sha256": {},
        })
    root_manifest = {
        "schema": "historical_multiscale_formal_v09_state_diagnostics_root_v1",
        "status": "state_diagnostics_complete",
        "seed_count": 8,
        "seeds": list(range(100, 801, 100)),
        "children": children,
        "training_external_audit_sha256": sha256_file(formal_root / "training_external_audit.json"),
        "training_target_reads": 0,
        "formal_evaluation_observation_reads": 0,
        "recent_path_executed": False,
        "flow_head_executed": False,
        "formal_period_predictions_generated": False,
        "official_score_called": False,
    }
    _write_json(diagnostic_root / "manifest.json", root_manifest)
    state_audit = {
        "schema": "historical_multiscale_formal_v09_state_diagnostics_external_audit_v1",
        "status": "state_diagnostics_external_audit_passed",
        "diagnostic_root_manifest_sha256": sha256_file(diagnostic_root / "manifest.json"),
        "training_external_audit_sha256": sha256_file(formal_root / "training_external_audit.json"),
        "seed_count": 8,
        "array_count": 64,
        "raw_array_sha256_matches": 64,
        "npy_file_sha256_matches": 64,
        "training_target_reads": 0,
        "formal_evaluation_observation_reads": 0,
        "recent_path_executed": False,
        "flow_head_executed": False,
        "formal_period_predictions_generated": False,
        "official_score_called": False,
        "persistent_replay_output_written": False,
    }
    _write_json(formal_root / "state_diagnostics_external_audit.json", state_audit)

    upstream = (
        tmp_path
        / "v09_strict/neuralhydrology/results/26_historical_band_experts/formal_v09"
    )
    files = {
        "R09-NEST-S100.legacy_checkpoint_bridge_external_audit.json": {
            "status": "legacy_checkpoint_bridge_external_audit_passed",
        },
        "R09-NEST-S100.training_resource_preflight_external_audit.json": {
            "status": "resource_preflight_passed",
        },
        "R09-NEST-S100.strict_nesting_external_audit.json": {
            "status": "strict_nesting_checkpoint_prediction_replay_passed",
        },
        "strict_nesting/R09-NEST-S100/seal.json": {"status": "sealed"},
        "authorizations/A09-NEST-01.authorization.json": {"status": "authorized_once"},
        "authorizations/A09-NEST-01.consumption.json": {"status": "consumed_once"},
    }
    for relative, value in files.items():
        path = upstream / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        _write_json(path, value)
    preflight_log_root = upstream.parents[3] / "logs"
    preflight_log_root.mkdir(parents=True, exist_ok=True)
    (preflight_log_root / "preflight_201775.out").write_text(
        "\n".join((
            "node=ngu010",
            "=== REAL GPU PREFLIGHT: 4 workloads x 2 fresh subprocesses, batch 256, window 3562 ===",
            (
                'profile: {"batch_size": 256, "features": 5, "recent_days": 270, '
                '"statics": 27, "window_days": 3562}'
            ),
            (
                "strict_nesting_pair              identical=True params=[297217, 297217] "
                "peak_alloc=984MiB peak_reserved=1142MiB pids=[2604713, 2604771]"
            ),
            (
                "classic_lstm_256_clean           identical=True params=[297217] "
                "peak_alloc=979MiB peak_reserved=1120MiB pids=[2604826, 2604881]"
            ),
            (
                "classic_lstm_369_capacity        identical=True params=[595198] "
                "peak_alloc=1363MiB peak_reserved=1610MiB pids=[2604941, 2604998]"
            ),
            (
                "continuous_multiscale_history    identical=True params=[596737] "
                "peak_alloc=1165MiB peak_reserved=1402MiB pids=[2605053, 2605112]"
            ),
            (
                'determinism: {"cublas_workspace_config": ":4096:8", "cudnn_benchmark": false, '
                '"cudnn_deterministic": true, "deterministic_algorithms_requested": true}'
            ),
            "ALL_WORKLOADS_IDENTICAL: True",
            "done=2026-08-07T21:41:20+08:00",
        )) + "\n",
        encoding="utf-8",
    )
    (preflight_log_root / "preflight_201775.err").write_bytes(b"")
    profile = {"batch_size": 256, "features": 5, "recent_days": 270, "statics": 27, "window_days": 3562}
    variants = {
        "strict_nesting_pair": (("classic_lstm_256_clean", 297_217), ("nested_history_disabled", 297_217)),
        "classic_lstm_256_clean": (("classic_lstm_256_clean", 297_217),),
        "classic_lstm_369_capacity": (("classic_lstm_369_capacity", 595_198),),
        "continuous_multiscale_history": (("continuous_multiscale_history", 596_737),),
    }
    workloads = []
    process_id = 1000
    for name, models in variants.items():
        runs = []
        for _ in range(2):
            process_id += 1
            runs.append({
                "process_id": process_id,
                "peak_allocated_bytes": 900 * 2**20,
                "peak_reserved_bytes": (1610 if name == "classic_lstm_369_capacity" else 1200) * 2**20,
                "exit_code": 0,
            })
        workloads.append({
            "workload": name,
            "input_shapes": (
                {"windows": [256, 3562, 5]}
                if name == "continuous_multiscale_history"
                else {"recent": [256, 270, 5]}
            ),
            "models": [
                {
                    "variant": variant,
                    "trainable_parameters": parameters,
                    "loss_sha256": "1" * 64,
                    "gradient_norm_sha256": "2" * 64,
                    "parameter_sha256": "3" * 64,
                    "adam_state_sha256": "4" * 64,
                }
                for variant, parameters in models
            ],
            "rng_state_sha256": "5" * 64,
            "determinism": {
                "cudnn_deterministic": True,
                "cudnn_benchmark": False,
                "deterministic_algorithms_requested": True,
                "cublas_workspace_config": ":4096:8",
                "cuda_matmul_allow_tf32": False,
                "cudnn_allow_tf32": False,
            },
            "arrays_identical": True,
            "state_array_sha256": "6" * 64 if name == "continuous_multiscale_history" else None,
            "runs": runs,
            "peak_allocated_bytes": max(row["peak_allocated_bytes"] for row in runs),
            "peak_reserved_bytes": max(row["peak_reserved_bytes"] for row in runs),
        })
    protocol = load_protocol_v09(IDEA_ROOT / "configs/formal_v09_protocol.json")
    _write_json(
        formal_root / "training_resource_preflight.external_audit.json",
        {
            "schema": "historical_multiscale_formal_v09_resource_preflight_v1",
            "status": "complete_resource_preflight",
            "device": "cuda:0",
            "protocol_canonical_sha256": canonical_sha256(protocol),
            "profile": profile,
            "workload_count": 4,
            "workloads": workloads,
            "opened_formal_inputs": False,
            "wrote_formal_outputs": False,
        },
    )
    assert len(specs) == len(audit_report["runs"]) == 24
    return upstream


def test_final_training_seal_binds_all_runs_diagnostics_and_strict_evidence(tmp_path):
    from audit_formal_training_v09 import audit_training_suite_v09, seal_training_suite_v09

    formal_root, specs, _ = _make_formal_suite(tmp_path)
    audit_report = audit_training_suite_v09(
        formal_root,
        specs,
        formal_root / "training_external_audit.json",
        model_builder=_model_builder,
        source_seal={"source_tree_sha256": "6" * 64, "environment_sha256": "7" * 64},
    )
    upstream = _make_seal_dependencies(formal_root, specs, audit_report, tmp_path)
    seal = seal_training_suite_v09(
        formal_root,
        audit_report,
        upstream_root=upstream,
        run_order=specs,
        verify_source_checkout=False,
    )
    assert seal["status"] == "formal_training_sealed"
    assert len(seal["runs"]) == 24
    assert len(seal["final_checkpoints"]) == 24
    assert len(seal["intermediate_checkpoints"]) == 48
    assert len(seal["state_diagnostics"]) == 8
    assert seal["four_workload_resource_preflight"]["workload_count"] == 4
    assert seal["four_workload_resource_preflight"]["process_count"] == 8
    assert seal["four_workload_resource_preflight"]["maximum_peak_reserved_mib"] == 1610
    assert seal["canonical_resource_preflight"]["status"] == "complete_resource_preflight"
    assert seal["audit_source_context"] == audit_report["audit_source_context"]
    assert seal["audit_source_context_sha256"] == audit_report["audit_source_context_sha256"]
    assert seal["main_training_authorization"]["required"] is False
    assert seal["formal_prediction_generated"] is False
    assert seal["official_score_called"] is False
    assert json.loads((formal_root / "training_seal.json").read_text(encoding="utf-8")) == seal


def test_final_training_seal_refuses_a_failed_state_replay(tmp_path):
    from audit_formal_training_v09 import audit_training_suite_v09, seal_training_suite_v09

    formal_root, specs, _ = _make_formal_suite(tmp_path)
    audit_report = audit_training_suite_v09(
        formal_root,
        specs,
        formal_root / "training_external_audit.json",
        model_builder=_model_builder,
        source_seal={"source_tree_sha256": "6" * 64},
    )
    upstream = _make_seal_dependencies(formal_root, specs, audit_report, tmp_path)
    audit_path = formal_root / "state_diagnostics_external_audit.json"
    state_audit = json.loads(audit_path.read_text(encoding="utf-8"))
    state_audit["status"] = "failed"
    _write_json(audit_path, state_audit)
    with pytest.raises(ValueError, match="state diagnostic|replay"):
        seal_training_suite_v09(
            formal_root,
            audit_report,
            upstream_root=upstream,
            run_order=specs,
            verify_source_checkout=False,
        )
    assert not (formal_root / "training_seal.json").exists()


@pytest.mark.parametrize("mutation", ["missing", "changed", "stderr", "report"])
def test_final_training_seal_refuses_incomplete_four_workload_preflight(tmp_path, mutation):
    from audit_formal_training_v09 import audit_training_suite_v09, seal_training_suite_v09

    formal_root, specs, _ = _make_formal_suite(tmp_path)
    audit_report = audit_training_suite_v09(
        formal_root,
        specs,
        formal_root / "training_external_audit.json",
        model_builder=_model_builder,
        source_seal={"source_tree_sha256": "6" * 64},
    )
    upstream = _make_seal_dependencies(formal_root, specs, audit_report, tmp_path)
    stdout = upstream.parents[3] / "logs/preflight_201775.out"
    stderr = upstream.parents[3] / "logs/preflight_201775.err"
    if mutation == "missing":
        stdout.unlink()
    elif mutation == "changed":
        stdout.write_text(
            stdout.read_text(encoding="utf-8").replace(
                "ALL_WORKLOADS_IDENTICAL: True", "ALL_WORKLOADS_IDENTICAL: False"),
            encoding="utf-8",
        )
    else:
        if mutation == "stderr":
            stderr.write_text("worker failed\n", encoding="utf-8")
        else:
            (formal_root / "training_resource_preflight.external_audit.json").unlink()
    with pytest.raises((FileNotFoundError, ValueError), match="preflight|resource"):
        seal_training_suite_v09(
            formal_root,
            audit_report,
            upstream_root=upstream,
            run_order=specs,
            verify_source_checkout=False,
        )
    assert not (formal_root / "training_seal.json").exists()
