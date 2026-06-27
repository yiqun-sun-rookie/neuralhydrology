"""One-time builder for the Track-0 held observation answer key + secret holdout.

Extracts the per-basin evaluation-period observed discharge from the frozen
LSTM baseline run (obs is identical across seeds), writes it as the scoring
service's held answer key, and deterministically carves a ~20% secret holdout.

Run once:
    python -m fair_benchmark.build_frozen_obs
The obs parquet is the answer key — keep it where challengers cannot read it.
"""
import glob
import pickle
from pathlib import Path

import pandas as pd

FROZEN = Path(__file__).resolve().parent / "frozen"
TRACK = "track0_forcing_only"
HOLDOUT_EVERY = 5  # every 5th sorted basin -> secret holdout (~20%)
SEED_RUN_GLOB = "results/18_lstm_fair_531/lstm_cudalstm_maurer_s100*/test/model_epoch*/test_results.p"


def build(repo_root: Path) -> None:
    src = sorted(glob.glob(str(repo_root / SEED_RUN_GLOB)))
    if not src:
        raise FileNotFoundError(f"no baseline test_results.p under {SEED_RUN_GLOB}")
    results = pickle.load(open(src[0], "rb"))

    frames = []
    for basin, v in results.items():
        da = v["1D"]["xr"]["QObs(mm/d)_obs"].isel(time_step=0)
        s = da.to_series()
        frames.append(pd.DataFrame({"basin": str(basin), "date": s.index, "qobs": s.to_numpy()}))
    obs = pd.concat(frames, ignore_index=True)

    FROZEN.mkdir(parents=True, exist_ok=True)
    obs_path = FROZEN / f"{TRACK}_obs_eval.parquet"
    obs.to_parquet(obs_path, index=False)

    basins = sorted({str(b) for b in results})
    holdout = [b for i, b in enumerate(basins) if i % HOLDOUT_EVERY == 0]
    (FROZEN / f"{TRACK}_secret_holdout_basins.txt").write_text("\n".join(holdout) + "\n", encoding="utf-8")

    print(f"obs answer key: {obs_path}  ({len(basins)} basins, {len(obs)} rows)")
    print(f"secret holdout: {len(holdout)} basins, public: {len(basins) - len(holdout)}")


if __name__ == "__main__":
    build(Path(__file__).resolve().parents[2])
