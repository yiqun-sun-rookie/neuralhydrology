"""End-to-end integration: predictions file -> verdict + ledger row.

Uses a synthetic in-memory Track so it depends on no external CAMELS data;
it exercises the real wiring (load predictions, recompute NSE from held obs,
coverage, public/holdout split, gate, ledger)."""
import numpy as np
import pandas as pd

from fair_benchmark.gate import GateConfig
from fair_benchmark.score import score_submission
from fair_benchmark.tracks import Track

IDX = pd.date_range("1990-01-01", periods=120, freq="D")
RNG = np.random.default_rng(7)


def _obs_dict(n_basins):
    obs = {}
    for i in range(n_basins):
        signal = np.abs(np.sin(np.linspace(0, 12, len(IDX))) * (i + 1) + RNG.normal(0, 0.1, len(IDX)))
        obs[f"{i:08d}"] = pd.Series(signal + 0.5, index=IDX)
    return obs


def _write_predictions(path, obs, noise):
    rows = []
    for basin, o in obs.items():
        sim = o.to_numpy() + RNG.normal(0, noise, len(o))
        for d, v in zip(o.index, sim):
            rows.append({"basin": basin, "date": d.strftime("%Y-%m-%d"), "qsim": v})
    pd.DataFrame(rows).to_csv(path, index=False)


def _track(obs, baseline_value, holdout):
    return Track(
        name="track0_forcing_only",
        baseline_nse={b: baseline_value for b in obs},
        obs=obs,
        secret_holdout=set(holdout),
        gate_cfg=GateConfig(),
        allow_observed_q=False,
    )


def test_strong_challenger_is_valid_and_logged(tmp_path):
    obs = _obs_dict(30)
    preds = tmp_path / "predictions.csv"
    _write_predictions(preds, obs, noise=0.02)          # near-perfect sim -> high NSE
    track = _track(obs, baseline_value=0.60, holdout=list(obs)[:6])
    ledger = tmp_path / "ledger.csv"

    report = score_submission(
        predictions_path=preds, track=track, ledger_path=ledger,
        experiment_id="001_strong", timestamp="2026-06-25T10:00:00",
    )
    assert report["verdict"] in {"PASS", "HOLD", "REJECT"}
    assert report["verdict"] != "REJECT"               # valid submission, big margin
    assert report["public"]["n"] == 24                 # 30 - 6 holdout
    assert report["holdout"]["n"] == 6
    assert report["predictions_sha"]                   # hash recorded
    # ledger got exactly one data row
    assert (ledger.read_text().strip().count("\n")) == 1  # header + 1 row -> one newline at join... see count
    from fair_benchmark.ledger import count_attempts
    assert count_attempts(ledger) == 1


def test_missing_predictions_file_is_rejected_and_logged(tmp_path):
    obs = _obs_dict(10)
    track = _track(obs, baseline_value=0.60, holdout=list(obs)[:2])
    ledger = tmp_path / "ledger.csv"
    report = score_submission(
        predictions_path=tmp_path / "does_not_exist.csv", track=track,
        ledger_path=ledger, experiment_id="002_missing", timestamp="2026-06-25T10:00:00",
    )
    assert report["verdict"] == "REJECT"
    from fair_benchmark.ledger import count_attempts
    assert count_attempts(ledger) == 1                 # rejected attempts are logged too


def test_dropping_hard_days_fails_coverage(tmp_path):
    obs = _obs_dict(12)
    preds = tmp_path / "predictions.csv"
    # only emit the first 40% of days per basin -> coverage ~0.4 < 0.99
    rows = []
    for basin, o in obs.items():
        for d, v in list(zip(o.index, o.to_numpy()))[:48]:
            rows.append({"basin": basin, "date": d.strftime("%Y-%m-%d"), "qsim": v})
    pd.DataFrame(rows).to_csv(preds, index=False)
    track = _track(obs, baseline_value=0.60, holdout=list(obs)[:2])
    report = score_submission(
        predictions_path=preds, track=track, ledger_path=tmp_path / "l.csv",
        experiment_id="003_drop", timestamp="2026-06-25T10:00:00",
    )
    assert report["verdict"] == "REJECT"
    assert "coverage" in " ".join(report["reasons"]).lower()


def test_leakage_in_experiment_dir_forces_hold(tmp_path):
    # a strong (would-PASS) challenger whose code reads observed streamflow
    # must be HELD for audit, not silently PASS.
    obs = _obs_dict(30)
    expdir = tmp_path / "exp"
    expdir.mkdir()
    preds = expdir / "predictions.csv"
    _write_predictions(preds, obs, noise=0.02)
    (expdir / "model.py").write_text(
        "q = open('data/camels_us/usgs_streamflow/01/01022500_streamflow_qc.txt')\n",
        encoding="utf-8")
    track = _track(obs, baseline_value=0.60, holdout=list(obs)[:6])
    report = score_submission(
        predictions_path=preds, track=track, ledger_path=tmp_path / "l.csv",
        experiment_id="005_leak", timestamp="2026-06-25T10:00:00", experiment_dir=expdir,
    )
    assert report["verdict"] == "HOLD"
    assert report["leakage_hits"] >= 1


def test_score_uses_track_metric_not_hardcoded_nse(tmp_path):
    # engine is metric-agnostic: a Track with a custom metric must be honoured
    obs = _obs_dict(20)
    preds = tmp_path / "predictions.csv"
    _write_predictions(preds, obs, noise=0.02)
    track = _track(obs, baseline_value=0.60, holdout=list(obs)[:4])
    track.metric = lambda o, s: 0.5  # constant metric for every basin
    report = score_submission(
        predictions_path=preds, track=track, ledger_path=tmp_path / "l.csv",
        experiment_id="006_metric", timestamp="2026-06-26T10:00:00",
    )
    assert report["challenger_median"] == 0.5


def test_recomputes_nse_from_obs_not_self_report(tmp_path):
    # challenger ships predictions; the report's challenger_median must come from
    # OUR recomputation against held obs, so a near-perfect sim yields a high median.
    obs = _obs_dict(20)
    preds = tmp_path / "predictions.csv"
    _write_predictions(preds, obs, noise=0.02)
    track = _track(obs, baseline_value=0.60, holdout=list(obs)[:4])
    report = score_submission(
        predictions_path=preds, track=track, ledger_path=tmp_path / "l.csv",
        experiment_id="004_recompute", timestamp="2026-06-25T10:00:00",
    )
    assert report["challenger_median"] > 0.9
