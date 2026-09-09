"""Validation-only screening and five-new-seed confirmation, with provenance."""
from __future__ import annotations

from dataclasses import asdict, dataclass
import copy
from decimal import Decimal, ROUND_HALF_EVEN
from pathlib import Path

import deploy_remote as deploy
from audit_stage import load_admission
from evidence_contract import (FAMILY, METRIC, canonical, digest, file_hash, immutable,
                               read_json, require, sealed, verify_seal)

CONFIG_FIELDS = ("hidden_size", "num_layers", "in_out_mult", "lr")
LIMITATIONS = [
    "Five seeds do not establish statistical equivalence or absence of overfitting.",
    "Overlapping 800-hour validation windows are not independent observations.",
    "A boundary winner is best only under this registered finite budget.",
    "The previously viewed test period cannot reopen configuration or seed selection.",
]


@dataclass(frozen=True, order=True)
class Configuration:
    hidden_size: int
    num_layers: int
    in_out_mult: int
    lr: Decimal

    @classmethod
    def from_dict(cls, value):
        integers = [value[name] for name in CONFIG_FIELDS[:3]]
        require(all(type(x) is int and x > 0 for x in integers), "Invalid architecture")
        lr = Decimal(str(value["lr"]))
        require(lr.is_finite() and lr > 0, "Invalid learning rate")
        return cls(*integers, lr)

    def json(self):
        return dict(zip(CONFIG_FIELDS, (self.hidden_size, self.num_layers, self.in_out_mult, str(self.lr))))


@dataclass(frozen=True)
class ValidationRecord:
    config: Configuration
    seed: int
    run_id: str
    index: int
    stage: str
    outcome: str
    score: Decimal | None
    checkpoint_path: str | None
    checkpoint_sha256: str | None
    provenance: dict
    metric: str = METRIC

    def __post_init__(self):
        require(self.metric == METRIC, "Only corrected pooled validation metric admitted")
        require(self.stage in ("reference", "A", "B", "C"), "Forbidden test-labelled stage")
        require(self.outcome in ("SUCCESS", "NUMERIC_FAILURE", "MISSING"), "Unsupported run outcome")
        require(type(self.seed) is int and type(self.index) is int and self.run_id, "Missing run identity")
        require(isinstance(self.provenance, dict) and self.provenance, "Missing provenance")
        require(self.provenance.get("split", "validation") == "validation", "Forbidden test provenance")
        if self.outcome == "SUCCESS":
            require(isinstance(self.score, Decimal) and self.score.is_finite(), "Missing/nonfinite score")
            require(self.checkpoint_path and self.checkpoint_sha256 and len(self.checkpoint_sha256) == 64, "Missing checkpoint provenance")
        else:
            require(self.score is None and self.checkpoint_path is None and self.checkpoint_sha256 is None, "Failed/missing run carries score or checkpoint")

    def json(self):
        result = asdict(self)
        result["config"] = self.config.json()
        result["score"] = str(self.score) if self.score is not None else None
        return result


def reference_records(path=FAMILY / "REMOTE_BASELINE.json", *, local_root=None):
    """30 success chains and two failures; no inferred local checkpoint copies."""
    require(file_hash(path) == deploy.INPUT_HASHES["REMOTE_BASELINE.json"], "Reference baseline hash mismatch")
    baseline = read_json(path)
    deploy.validate_baseline(baseline)
    if local_root is None:
        local_root = FAMILY.parent / "wrr_hp_extension_20260902/hpc_results"
    records, local = [], []
    for row in baseline["references"]:
        combo = row["combo"]
        provenance = {key: value for key, value in row.items() if key.endswith(("_path", "_sha256"))}
        provenance.update(reference_family=row["family"], baseline_sha256=file_hash(path), split="validation")
        records.append(ValidationRecord(Configuration.from_dict(combo), combo["seed"], row["run_id"], row["index"],
                       "reference", "SUCCESS", Decimal(str(row["score"])), row["checkpoint_path"], row["checkpoint_sha256"], provenance))
        if local_root is not None and row["family"] == "extension":
            relative = row["cell_path"].split("/runs/", 1)[1]
            local_path = Path(local_root) / "runs" / relative
            if local_path.exists():
                require(file_hash(local_path) == row["cell_sha256"], "Older local cell hash mismatch")
                local.append({"path": str(local_path), "sha256": row["cell_sha256"]})
    for row in baseline["failed_runs"]:
        records.append(ValidationRecord(Configuration(32, 1, 10, Decimal("0.05")), row["seed"],
                       f"WRR-HPEXT-20260902-I{row['index']:02d}", row["index"], "reference", "NUMERIC_FAILURE", None, None, None,
                       dict(row, baseline_sha256=file_hash(path), split="validation")))
    require(len([r for r in records if r.outcome == "SUCCESS"]) == 30, "Reference count mismatch")
    return records, {"baseline_sha256": file_hash(path), "verified_local_cells": local,
                     "replication_source_references": [r.json() for r in records if r.provenance.get("reference_family") == "replication"],
                     "failures": baseline["failed_runs"]}


def admitted_records(path, stage, *, expected_hash=None):
    cert, evidence = load_admission(path, stage, expected_hash=expected_hash)
    require(evidence.get("evidence_origin") == "REMOTE_READ_ONLY_COLLECTOR", "Synthetic evidence cannot enter model selection")
    records = []
    for item in cert["report"]["records"]:
        combo = item["combo"]
        provenance = dict(item["provenance"], admission_sha256=file_hash(path), split="validation",
                          input_hashes=evidence["file_hashes"])
        records.append(ValidationRecord(Configuration.from_dict(combo), combo["seed"], combo["run_id"], combo["index"], stage,
                       item["outcome"], Decimal(item["score"]) if item["outcome"] == "SUCCESS" else None,
                       item.get("checkpoint_path"), item.get("checkpoint_sha256"), provenance))
    return records


def group_records(records, seeds, stages):
    groups, identities, runs = {}, set(), set()
    for row in records:
        require(row.stage in stages and row.seed in seeds, "Wrong stage/seed for selection phase")
        identity = (row.config, row.seed)
        run = (row.stage, row.run_id)
        require(identity not in identities and run not in runs, "Duplicate tuple+seed or run identity")
        identities.add(identity)
        runs.add(run)
        groups.setdefault(row.config, {})[row.seed] = row
    complete, completeness = [], []
    for config, rows in groups.items():
        missing = [seed for seed in seeds if seed not in rows or rows[seed].outcome == "MISSING"]
        failed = [seed for seed in seeds if seed in rows and rows[seed].outcome == "NUMERIC_FAILURE"]
        values = {str(seed): str(row.score) for seed, row in rows.items() if row.outcome == "SUCCESS"}
        summary = {"config": config.json(), "successful_seed_values": values, "missing_seeds": missing,
                   "failed_seeds": failed, "complete": not missing and not failed}
        completeness.append(summary)
        if summary["complete"]:
            mean = sum((rows[seed].score for seed in seeds), Decimal(0)) / Decimal(len(seeds))
            complete.append({"config": config.json(), "mean": str(mean), "seed_values": values,
                             "records": [rows[seed].json() for seed in seeds]})
    complete.sort(key=lambda item: (-Decimal(item["mean"]), Configuration.from_dict(item["config"])))
    return complete, completeness


def screen(records):
    ranked, completeness = group_records(records, (42, 43, 44), {"reference", "A", "B"})
    status = "READY"
    if len(ranked) < 3:
        status = "INSUFFICIENT_COMPLETE_CANDIDATES"
    elif len(ranked) > 3 and Decimal(ranked[2]["mean"]) == Decimal(ranked[3]["mean"]):
        status = "THIRD_PLACE_TIE_GATE"
    return {"status": status, "ranking": ranked, "completeness": completeness,
            "metric": METRIC, "arithmetic": "decimal_unrounded_mean_of_reported_source_scores"}


def parameter_count(config):
    h, e, layers = config.hidden_size, config.in_out_mult, config.num_layers
    return (14 + e) * h * h + (149 + 58 * e) * h + 83 * e + 203 + (layers - 1) * (16 * h * h + 16 * h + 16)


def verify_parameter_formula(configurations):
    """Exact frozen class, CPU shape initialization only; no forward or loads."""
    import types
    import linecache
    import torch
    import build_package as package
    files, _ = package.load_and_validate_source_package()
    member = "repo/knet/dl/nn_kalman_clamp_5.py"
    module = types.ModuleType("frozen_shape_only_model")
    # TorchScript decorators inspect source during import. Retain exact archive
    # source in the standard inspection cache without editing/extracting it.
    source = files[member].decode("utf-8")
    linecache.cache[member] = (len(source), None, source.splitlines(True), member)
    exec(compile(files[member], member, "exec"), module.__dict__)
    verified = []
    for config in sorted(set(configurations)):
        args = types.SimpleNamespace(device="cpu", activation_function="relu", n_batch=1,
               in_mult_KNet=config.in_out_mult, out_mult_KNet=config.in_out_mult,
               d_hidden_Q=config.hidden_size, d_hidden_Sigma=config.hidden_size,
               num_layers_GRU_Q=config.num_layers, num_layers_GRU_Sigma=config.num_layers,
               num_layers_GRU_S=config.num_layers, dropout_prob=0.0)
        system = types.SimpleNamespace(f=None, h=None, m=5, n=1, prior_q=torch.eye(5), prior_state_cov=torch.eye(5), prior_r=torch.eye(1))
        model = module.KalmanNet()
        model.build_nn(system, args)
        actual = sum(p.numel() for p in model.parameters() if p.requires_grad)
        require(actual == parameter_count(config), "Frozen model parameter formula mismatch")
        verified.append({"config": config.json(), "parameters": actual})
    return {"kind": "CPU_SHAPE_ONLY_PARAMETER_VERIFICATION", "model_member": member,
            "model_sha256": digest(files[member]), "source_archive_sha256": package.SOURCE_ARCHIVE_SHA256,
            "forward_passes": 0, "data_or_checkpoint_loads": 0, "counts": verified}


def lock_top_three(a_path, b_path, output, *, local_reference_root=None):
    references, reference = reference_records(local_root=local_reference_root)
    records = references + admitted_records(a_path, "A") + admitted_records(b_path, "B")
    result = screen(records)
    require(result["status"] == "READY", result["status"])
    top = copy.deepcopy(result["ranking"][:3])
    verification = verify_parameter_formula([Configuration.from_dict(item["config"]) for item in top])
    for rank, row in enumerate(top, 1):
        row.update(rank=rank, parameters=parameter_count(Configuration.from_dict(row["config"])))
    lock = sealed({"kind": "TOP_THREE_LOCK", "metric": METRIC, "new_seeds": [45, 46, 47, 48, 49],
                   "top_three": top, "screening": result, "reference": reference,
                   "admissions": {"A": file_hash(a_path), "B": file_hash(b_path)},
                   "parameter_verification": verification, "limitations": LIMITATIONS})
    immutable(output, canonical(lock))
    return lock


def confirmation(records, lock, *, timing=None):
    verify_seal(lock, kind="TOP_THREE_LOCK")
    from stage_c import combos_from_lock
    combos_from_lock(lock)
    if timing is not None:
        require(timing.get("split") == "validation" and timing.get("kind") == "VALID_INFERENCE_TIMING", "Test-labelled or invalid timing input forbidden")
    allowed = {Configuration.from_dict(row["config"]) for row in lock["top_three"]}
    require(len(allowed) == 3 and all(row.config in allowed for row in records), "C configuration outside locked top three")
    ranked, completeness = group_records(records, (45, 46, 47, 48, 49), {"C"})
    for config in sorted(allowed - {row.config for row in records}):
        completeness.append({"config": config.json(), "complete": False, "missing_seeds": [45, 46, 47, 48, 49], "failed_seeds": [], "successful_seed_values": {}})
    if not ranked:
        return {"status": "NO_FULL_CONFIRMATION_CANDIDATE", "recommendation": None, "completeness": completeness}
    precision = Decimal("0.000001")
    best = max(Decimal(row["mean"]).quantize(precision, rounding=ROUND_HALF_EVEN) for row in ranked)
    tied = [row for row in ranked if Decimal(row["mean"]).quantize(precision, rounding=ROUND_HALF_EVEN) == best]
    minimum = min(parameter_count(Configuration.from_dict(row["config"])) for row in tied)
    tied = [row for row in tied if parameter_count(Configuration.from_dict(row["config"])) == minimum]
    if len(tied) > 1:
        if timing is None:
            return {"status": "MEASURED_INFERENCE_RUNTIME_REQUIRED", "recommendation": None, "completeness": completeness, "ranking": ranked}
        require(timing.get("kind") == "VALID_INFERENCE_TIMING" and timing.get("exclusive_gpu") is True
                and timing.get("split") == "validation" and timing.get("warmup") == 10 and timing.get("repeats") == 30
                and timing.get("representative_seed") == 45 and timing.get("window_hours") == 800
                and timing.get("forecast_leads") == list(range(1, 25)) and timing.get("synchronized") is True
                and isinstance(timing.get("gpu_uuid"), str) and timing["gpu_uuid"],
                "Invalid inference runtime evidence")
        samples = {}
        for sample in timing["configurations"]:
            config = Configuration.from_dict(sample["config"])
            require(config not in samples and config in allowed, "Timing configuration duplicate/outside lock")
            samples[config] = sample
        scores = {}
        for row in tied:
            config = Configuration.from_dict(row["config"])
            sample = samples[config]
            seed45 = next(r for r in row["records"] if r["seed"] == 45)
            require(sample.get("checkpoint_path") == seed45["checkpoint_path"] and sample.get("checkpoint_sha256") == seed45["checkpoint_sha256"], "Timing checkpoint identity mismatch")
            require(isinstance(sample.get("evidence_sha256"), str) and len(sample["evidence_sha256"]) == 64, "Missing measured runtime provenance")
            durations = {}
            for batch in (1, 256):
                values = [Decimal(str(value)) for value in sample[f"seconds_batch{batch}"]]
                require(len(values) == 30 and all(v.is_finite() and v > 0 for v in values), "Invalid timing repeats")
                durations[batch] = sorted(values)
            # Batch one represents one-at-a-time forecasting. Batch256 is
            # retained throughput evidence and cannot replace this tiebreak.
            scores[config] = (durations[1][14] + durations[1][15]) / 2
        fastest = min(scores.values())
        tied = [row for row in tied if scores[Configuration.from_dict(row["config"])] == fastest]
        if len(tied) != 1:
            return {"status": "FINAL_RUNTIME_TIE_GATE", "recommendation": None, "completeness": completeness, "ranking": ranked}
    return {"status": "SELECTED", "recommendation": tied[0], "ranking": ranked, "completeness": completeness,
            "representative_seed": 45, "confirmation_seeds": [45, 46, 47, 48, 49],
            "precision": "0.000001", "rounding": "ROUND_HALF_EVEN", "timing": timing}


def lock_final(c_path, top_path, output, *, timing=None):
    top = read_json(top_path)
    cert, evidence = load_admission(c_path, "C")
    require(evidence["top_three_lock"] == top, "C admission lock mismatch")
    result = confirmation(admitted_records(c_path, "C"), top, timing=timing)
    require(result["status"] == "SELECTED", result["status"])
    lock = sealed({"kind": "FINAL_SELECTION_LOCK", "selection": result, "metric": METRIC,
                   "top_three_lock_sha256": file_hash(top_path), "c_admission_sha256": file_hash(c_path),
                   "all_successful_c_checkpoints": [{"combo": row["combo"], "path": row["checkpoint_path"], "sha256": row["checkpoint_sha256"]}
                                                   for row in cert["report"]["records"] if row["outcome"] == "SUCCESS"],
                   "screening_42_44_separate": top["screening"], "representative_seed": 45,
                   "test_may_change_selection": False, "limitations": LIMITATIONS})
    immutable(output, canonical(lock))
    return lock
