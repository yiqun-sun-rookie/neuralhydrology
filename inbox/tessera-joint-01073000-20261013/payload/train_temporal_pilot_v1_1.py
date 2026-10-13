"""Single previously seen basin, disjoint target dates: small real A/B/C HPC pilot."""
import argparse
import copy
import csv
import importlib.metadata
import json
import os
from pathlib import Path
import platform
import sys
import time

import numpy as np
import torch

ROOT = Path(__file__).resolve().parents[3]
sys.path[:0] = [str(ROOT), str(ROOT / "src")]
from tessera_joint.data import PreparedForecasts, load_target_transform, verify_target_periods, verify_target_transform
from tessera_joint.model import JointRegional, SatelliteEncoder, load_official, load_regional
from train_pilot import evaluate, file_hash, metrics, train_phase, verify_evaluation_targets


def mse(output, data):
    loss = torch.nn.functional.mse_loss(output["y_hat"][:, -1:, :].float(), data["y"].float())
    return loss, {"loss": loss}


def snapshot(model):
    return {name: value.detach().cpu().clone() for name, value in model.satellite.named_parameters()}


def changed(model, reference):
    return {name: float((value.detach().cpu() - reference[name]).abs().max())
            for name, value in model.satellite.named_parameters()}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    args.config = args.config.resolve()
    settings = json.loads(args.config.read_text())
    if settings["track"] != "single_seen_basin_temporal_retrospective" or settings["loss"] != "normalized_mse":
        raise ValueError("This entry point implements only the declared one-basin temporal pilot")
    out = args.output.resolve()
    out.mkdir(parents=True, exist_ok=False)
    (out / "config_snapshot.json").write_text(json.dumps(settings, indent=2))
    report = {"experiment_id": settings["experiment_id"], "track": settings["track"], "status": "RUNNING",
              "arms": {}, "limits": settings["limits"], "old_checkpoint_saw_basin": True}
    started = time.perf_counter()
    try:
        if not torch.cuda.is_available():
            raise RuntimeError("Allocated CUDA GPU not available")
        torch.set_num_threads(int(os.environ.get("SLURM_CPUS_PER_TASK", "4")))
        torch.manual_seed(settings["seed"])
        np.random.seed(settings["seed"])
        torch.backends.cudnn.benchmark = False
        torch.backends.cudnn.deterministic = True
        environment = {"python": sys.version, "platform": platform.platform(), "job_id": os.environ.get("SLURM_JOB_ID"),
                       "gpu": torch.cuda.get_device_name(), "cuda": torch.version.cuda,
                       "packages": {p: importlib.metadata.version(p) for p in ["torch", "numpy", "pandas", "xarray", "scipy", "PyYAML"]}}
        (out / "environment.json").write_text(json.dumps(environment, indent=2))
        source = ROOT / settings["source_run"]
        ckpt = source / settings["source_checkpoint"]
        official = ROOT / settings["official_folder"]
        regional = load_regional(source / "config.yml", ckpt)
        datasets = {name: PreparedForecasts(ROOT / settings[name + "_npz"], regional.cfg)
                    for name in ["train", "validation", "test"]}
        verify_target_periods(datasets, settings["target_day_ranges"])
        normalizer = ROOT / settings["normalizer_file"]
        transform = load_target_transform(normalizer, regional.cfg.target_variables[0])
        if settings["basin"] not in (source / "source_train_basins.txt").read_text().split():
            raise ValueError("Previously seen basin declaration disagrees with old training list")
        for name, dataset in datasets.items():
            if set(dataset.arrays["basins"].tolist()) != {settings["basin"]}:
                raise ValueError("Unexpected basin in temporal pilot")
            if not np.isfinite(dataset.arrays["y"]).all() or dataset.meta["lead_days"] != 1:
                raise ValueError("Only complete finite one-day targets admitted")
            if dataset.meta["normalizer_sha256"] != file_hash(normalizer):
                raise ValueError("Normalizer provenance mismatch")
            verify_target_transform(dataset.meta, transform)
            for stream in ["s2", "s1a", "s1d"]:
                a = dataset.arrays
                valid = a[f"sat_{stream}_mask"].astype(bool)
                cutoff = a["issue_times"][:, None, None]
                if ((a[f"sat_{stream}_available"] > cutoff) & valid).any() or ((a[f"sat_{stream}_acquired"] > cutoff) & valid).any():
                    raise ValueError("Satellite observation postdates forecast cutoff")
        report["counts"] = {k: len(v) for k, v in datasets.items()}
        report["target_transform"] = transform
        files = [args.config, source / "config.yml", ckpt, normalizer, source / "source_train_basins.txt",
                 official / "model.py", official / "ckpt/student_small.pt"]
        files += [ROOT / settings[k + "_npz"] for k in datasets]
        files += [(ROOT / settings[k + "_npz"]).with_suffix(".json") for k in datasets]
        report["input_hashes"] = {p.relative_to(ROOT).as_posix(): file_hash(p) for p in files}
        train, validation, test = [datasets[k] for k in ["train", "validation", "test"]]
        arm_a = JointRegional(regional.to("cuda"))
        torch.manual_seed(settings["seed"])
        encoder, module, _ = load_official(official, "cuda")
        arm_b = JointRegional(load_regional(source / "config.yml", ckpt, "cuda"), SatelliteEncoder(encoder, module)).to("cuda")
        original_encoder = snapshot(arm_b)
        for name, model in [("A", arm_a), ("B", arm_b)]:
            (out / name).mkdir()
            print(f"START {name} stage1", flush=True)
            report["arms"][name] = {"stage1": train_phase(model, train, validation, settings, 1, out / name, mse, "cuda")}
        arm_c = copy.deepcopy(arm_b).to("cuda")
        arm_c.set_stage("partial", settings["last_layers"])
        (out / "C").mkdir()
        report["arms"]["C"] = {"stage1": report["arms"]["B"]["stage1"], "stage1_shared_with_B": True}
        gradients, handles = {}, []
        def capture(name):
            def hook(grad):
                finite = bool(torch.isfinite(grad).all())
                item = gradients.setdefault(name, {"finite_nonzero_seen": False, "nonfinite_seen": False})
                item["finite_nonzero_seen"] |= finite and bool(grad.abs().max() > 0)
                item["nonfinite_seen"] |= not finite
            return hook
        for name, parameter in arm_c.satellite.named_parameters():
            if parameter.requires_grad:
                handles.append(parameter.register_hook(capture(name)))
        arms = [("A", arm_a), ("B", arm_b), ("C", arm_c)]
        for name, model in arms:
            print(f"START {name} stage2", flush=True)
            report["arms"][name]["stage2"] = train_phase(model, train, validation, settings, 2, out / name, mse, "cuda")
        for handle in handles:
            handle.remove()
        b_delta, c_delta = changed(arm_b, original_encoder), changed(arm_c, original_encoder)
        if any(b_delta.values()):
            raise RuntimeError("Frozen B encoder drifted")
        frozen_changed = [name for name, p in arm_c.satellite.named_parameters() if not p.requires_grad and c_delta[name] != 0]
        branch_evidence = {}
        for branch in ["s1_backbone", "s2_backbone"]:
            keys = [k for k in gradients if branch in k and "transformer_encoder" in k]
            branch_evidence[branch] = {"flow_gradient_nonzero": any(gradients[k]["finite_nonzero_seen"] for k in keys),
                                      "selected_checkpoint_updated": any(c_delta[k] > 0 for k in keys)}
        report["encoder_verification"] = {"B_max_abs_change": max(b_delta.values()), "C_frozen_parameters_changed": frozen_changed,
                                          "branches": branch_evidence, "gradient_hooks": gradients, "C_selected_parameter_max_abs_change": c_delta}
        if frozen_changed or not all(all(v.values()) for v in branch_evidence.values()):
            raise RuntimeError("Encoder gradient/update verification failed")
        # Only after all training and validation selection, score the common test days once per arm.
        for name, model in arms:
            loss, records = evaluate(model, test, settings["batch_size"], mse, "cuda")
            verify_evaluation_targets(records, test)
            np.savez_compressed(out / name / "test_predictions.npz", **{k: np.array([r[k] for r in records]) for k in records[0]})
            report["arms"][name]["test_mse_normalized"] = loss
            report["arms"][name]["metrics"] = metrics(records, {"lead_days": 1, **transform})
            with (out / name / "test_predictions.csv").open("w", newline="") as f:
                writer = csv.DictWriter(f, fieldnames=list(records[0]) + ["pred_mm_d", "obs_mm_d"])
                writer.writeheader()
                writer.writerows({**r, "pred_mm_d": r["pred_normalized"] * transform["target_std"] + transform["target_mean"],
                                  "obs_mm_d": r["obs_normalized"] * transform["target_std"] + transform["target_mean"]} for r in records)
        report["status"] = "REAL_TEMPORAL_PILOT_COMPLETE_NO_GENERALIZATION_CLAIM"
        print(json.dumps({"status": report["status"], "metrics": {name: report["arms"][name]["metrics"] for name, _ in arms}}), flush=True)
    except Exception as exc:
        report["status"], report["error"] = "FAILED", repr(exc)
        raise
    finally:
        report["wall_seconds"] = time.perf_counter() - started
        (out / "report.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
        fields = ["exp_id", "type", "hypothesis", "base_config", "changed_factor", "fixed_factors", "seeds", "status", "run_dir", "best_checkpoint", "metrics_path", "paper_name", "notes"]
        with (out / "registry.csv").open("w", newline="") as handle:
            writer = csv.DictWriter(handle, fieldnames=fields)
            writer.writeheader()
            for name in ["A", "B", "C"]:
                writer.writerow(dict(exp_id=settings["experiment_id"] + "_" + name, type="exploratory_ablation",
                    hypothesis="partial encoder tuning may improve daily forecast over frozen encoding", base_config=str(args.config),
                    changed_factor={"A": "no satellite", "B": "frozen satellite", "C": "partial encoder fine tuning"}[name],
                    fixed_factors="basin,dates,forcings,normalizer,seed,batches,epochs,validation selection", seeds=settings["seed"],
                    status=report["status"], run_dir=str(out / name), best_checkpoint=str(out / name / "stage2_best.pt"),
                    metrics_path=str(out / "report.json"), paper_name="none; feasibility pilot", notes="B/C share stage1; one seen basin, fixed satellite snapshot"))


if __name__ == "__main__":
    main()
