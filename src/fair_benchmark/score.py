"""Scoring service: predictions in, verdict out.

The service holds the only copy of the evaluation observations. A challenger
submits a per-basin daily hydrograph; the service recomputes NSE itself (never
trusts a self-reported number), checks coverage (so hard days cannot be NaN'd
away), compares against the frozen baseline on a public set AND a secret
holdout with paired statistics, logs the attempt to the append-only portfolio
ledger, and returns PASS / HOLD / REJECT.
"""
import argparse
import json
from pathlib import Path

from .gate import decide
from .io import load_predictions, sha256_file
from .ledger import append_attempt
from .leakage import scan_for_forbidden_access
from .metrics import nse, per_basin_score
from .stats import paired_comparison


def coverage_ok(obs: dict, sim: dict, min_ratio: float) -> bool:
    """Every basin's predicted finite-day count must cover >= min_ratio of obs days."""
    for basin, o in obs.items():
        n_obs = int(o.notna().sum())
        if n_obs == 0:
            continue
        s = sim.get(basin)
        if s is None:
            return False
        ao, as_ = o.align(s, join="inner")
        n_both = int((ao.notna() & as_.notna()).sum())
        if n_both / n_obs < min_ratio:
            return False
    return True


def score_submission(*, predictions_path, track, ledger_path, experiment_id,
                     timestamp, contract_ok: bool = True,
                     coverage_min_ratio: float = 0.99, experiment_dir=None) -> dict:
    predictions_path = Path(predictions_path)
    has_predictions = predictions_path.exists()
    if has_predictions:
        sim = load_predictions(predictions_path)
        predictions_sha = sha256_file(predictions_path)
    else:
        sim = {}
        predictions_sha = ""

    # Level-1 data-tap teeth: scan the challenger's code for forbidden reads.
    leakage_detail = (
        scan_for_forbidden_access(experiment_dir, track.forbidden_patterns)
        if experiment_dir is not None else []
    )
    leakage_ok = len(leakage_detail) == 0

    obs = track.obs
    cov = coverage_ok(obs, sim, coverage_min_ratio) if has_predictions else True
    challenger_nse = per_basin_score(obs, sim, track.metric or nse)

    baseline = track.baseline_nse
    public_ids = [b for b in baseline if b not in track.secret_holdout]
    secret_ids = [b for b in baseline if b in track.secret_holdout]

    def _cmp(ids):
        return paired_comparison(
            {b: challenger_nse.get(b, float("nan")) for b in ids},
            {b: baseline[b] for b in ids},
        )

    public = _cmp(public_ids)
    holdout = _cmp(secret_ids)

    decision = decide(has_predictions=has_predictions, contract_ok=contract_ok,
                      coverage_ok=cov, public=public, holdout=holdout, cfg=track.gate_cfg,
                      leakage_ok=leakage_ok)

    record = {
        "timestamp": timestamp, "experiment_id": experiment_id, "track": track.name,
        "verdict": decision["verdict"],
        "median_paired_delta": public["median_paired_delta"],
        "wilcoxon_p": public["wilcoxon_p"], "n": public["n"],
        "challenger_median": public["challenger_median"],
        "baseline_median": public["baseline_median"],
        "predictions_sha": predictions_sha,
    }
    append_attempt(ledger_path, record)

    return {
        "verdict": decision["verdict"], "reasons": decision["reasons"],
        "experiment_id": experiment_id, "track": track.name,
        "challenger_median": public["challenger_median"],
        "baseline_median": public["baseline_median"],
        "coverage_ok": cov, "has_predictions": has_predictions,
        "leakage_hits": len(leakage_detail), "leakage_detail": leakage_detail[:20],
        "predictions_sha": predictions_sha,
        "public": public, "holdout": holdout,
    }


def main(argv=None):
    from datetime import datetime
    from .tracks import load_track

    p = argparse.ArgumentParser(description="Fair-benchmark scoring service")
    p.add_argument("--predictions", required=True, help="per-basin long CSV/parquet: basin,date,qsim")
    p.add_argument("--experiment", required=True, help="experiment id, e.g. 001_my_idea")
    p.add_argument("--track", default="track0_forcing_only")
    p.add_argument("--frozen-dir", default=str(Path(__file__).resolve().parent / "frozen"))
    p.add_argument("--ledger", default=str(Path(__file__).resolve().parent / "registry" / "portfolio_ledger.csv"))
    p.add_argument("--experiment-dir", default=None,
                   help="challenger code dir to scan for forbidden data access (default: predictions' parent)")
    p.add_argument("--allow-unconfirmed", action="store_true",
                   help="score against a spec that has not been human-confirmed (explore mode)")
    p.add_argument("--out", default=None, help="optional path to write the report JSON")
    args = p.parse_args(argv)

    exp_dir = args.experiment_dir or str(Path(args.predictions).resolve().parent)
    track = load_track(args.track, args.frozen_dir, require_confirmed=not args.allow_unconfirmed)
    report = score_submission(
        predictions_path=args.predictions, track=track, ledger_path=args.ledger,
        experiment_id=args.experiment, timestamp=datetime.now().isoformat(timespec="seconds"),
        experiment_dir=exp_dir,
    )
    if args.out:
        Path(args.out).write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(f"GATE: {report['verdict']}  reasons={report['reasons']}  "
          f"challenger_median={report['challenger_median']:.4f} vs baseline={report['baseline_median']:.4f}")
    return report


if __name__ == "__main__":
    main()
