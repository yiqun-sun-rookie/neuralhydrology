"""Execution spine: turn a candidate experiment into a REAL scored ledger entry.

This is the piece that makes the benchmark actually DO research instead of just
ranking ideas: given an experiment dir, it runs the candidate's training (if any)
and its prediction code, then scores the emitted hydrograph through the gate +
ledger. Real PASS/HOLD/REJECT, not an estimate.

Leakage-safe layout (training may read TRAIN-period obs legally; the scanned
submission may not read any obs):

    <exp>/train.py                  # optional: trains on train-period obs, saves weights to <exp>/model/
    <exp>/model/                    # artifacts train.py produces (read by predict.py)
    <exp>/submission/predict.py     # reads ONLY the allowed bundle (+ <exp>/model/); emits predictions.csv
    <exp>/submission/predictions.csv

Only <exp>/submission/ is scanned for forbidden data access, so a clean predict.py
earns a real verdict instead of a leakage HOLD caused by the training code. The
training command is recorded; the auditor inspects train.py separately.

Run from repo root:
    python -m fair_benchmark.run_candidate --exp src/fair_benchmark/experiments/001_xxx
"""
import argparse
import json
import os
import subprocess
import sys
from datetime import datetime
from pathlib import Path

_REPO = Path(__file__).resolve().parents[2]


def _run(cmd, label):
    env = dict(os.environ)
    env["PYTHONPATH"] = str(_REPO / "src") + os.pathsep + env.get("PYTHONPATH", "")
    cmd = [str(c) for c in cmd]
    print(f"[run_candidate] {label}: {' '.join(cmd)}", flush=True)
    r = subprocess.run(cmd, cwd=str(_REPO), env=env)
    if r.returncode != 0:
        raise SystemExit(f"[run_candidate] {label} FAILED (exit {r.returncode})")


def main(argv=None):
    from .governance import governance_preflight
    from .io import sha256_file
    from .score import score_submission
    from .tracks import load_track

    p = argparse.ArgumentParser(description="Run + score a candidate end-to-end")
    p.add_argument("--exp", required=True, help="experiment dir with submission/predict.py (+ optional train.py)")
    p.add_argument("--track", default="track0_forcing_only")
    p.add_argument("--frozen-dir", default=str(Path(__file__).resolve().parent / "frozen"))
    p.add_argument("--ledger", default=str(Path(__file__).resolve().parent / "registry" / "portfolio_ledger.csv"))
    p.add_argument("--skip-train", action="store_true", help="reuse existing <exp>/model/ weights")
    p.add_argument("--allow-unconfirmed", action="store_true")
    a = p.parse_args(argv)

    exp = Path(a.exp).resolve()
    sub = exp / "submission"
    predict_py = sub / "predict.py"
    predictions = sub / "predictions.csv"
    if not predict_py.exists():
        raise SystemExit(f"[run_candidate] missing {predict_py}")

    # Governance preflight (AUTONOMY: no active cages; NOVELTY: validate novelty.yaml)
    pre = governance_preflight(exp)
    for w in pre["warnings"]:
        print(f"[governance][warn] {w}")
    if not pre["ok"]:
        for e in pre["errors"]:
            print(f"[governance][BLOCK] {e}")
        raise SystemExit("[run_candidate] governance preflight failed — aborting before run")
    print(f"[governance] preflight ok (novelty: {pre['novelty_class']})")

    train_py = exp / "train.py"
    if train_py.exists() and not a.skip_train:
        _run([sys.executable, train_py], "train")

    _run([sys.executable, predict_py, "--out", predictions], "predict")
    if not predictions.exists():
        raise SystemExit(f"[run_candidate] predict.py did not produce {predictions}")

    track = load_track(a.track, a.frozen_dir, require_confirmed=not a.allow_unconfirmed)
    report = score_submission(
        predictions_path=predictions, track=track, ledger_path=a.ledger,
        experiment_id=exp.name, timestamp=datetime.now().isoformat(timespec="seconds"),
        experiment_dir=sub,  # scan ONLY the submission code, not train.py
    )
    report["governance"] = pre
    # committed provenance sidecar: the recorded sha survives even when the large
    # predictions file is git-ignored, so the ledger number stays cross-checkable.
    (sub / "predictions.sha256").write_text(sha256_file(predictions) + "\n", encoding="utf-8")
    (exp / "report.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(f"GATE: {report['verdict']}  reasons={report['reasons']}  "
          f"challenger={report['challenger_median']:.4f} vs baseline={report['baseline_median']:.4f}  "
          f"leakage_hits={report['leakage_hits']}", flush=True)
    return report


if __name__ == "__main__":
    main()
