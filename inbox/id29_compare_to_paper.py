"""Rebuild the headline table of Nearing et al. (2022) from our run directories and diff it against the paper.

Mirrors ``analysis_time_split.ipynb`` of grey-nearing/lstm-data-assimilation, including its one non-obvious rule:

    Runs with a non-zero holdout fraction have holes punched in the observation record itself, so the metrics for
    *every* arm are computed against the complete observation record taken from the simulation run (notebook cell 21).

Usage
-----
    python src/29_nearing2022_da_ar/scripts/compare_to_paper.py \
        --simulation <sim_run_dir> [--autoregression <ar_run_dir>] [--assimilation <da_run_dir>] \
        [--epoch 30] [--out results/29_nearing2022_da_ar/headline_table.csv]
"""
import argparse
import pickle
import sys
from pathlib import Path
from typing import Dict, Optional

import numpy as np
import pandas as pd

REPO_ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(REPO_ROOT))

from neuralhydrology.evaluation.metrics import calculate_metrics  # noqa: E402

METRICS = ['NSE', 'KGE', 'Alpha-NSE', 'Pearson-r', 'Beta-NSE', 'Peak-Timing', 'Missed-Peaks']

# Table 2 of the paper / results/tables/zero_lag_zero_holdout_metrics_table.txt of the reproduction repo.
# Single seed (seed 0), lag 1 day, zero test holdout.
PAPER = pd.DataFrame(
    {
        'Simulation': [0.796, 0.795, 0.874, 0.902, -0.027, 0.263, 0.352],
        'AR 0.0 holdout': [0.879, 0.896, 0.942, 0.939, -0.007, 0.385, 0.250],
        'Assimilation': [0.862, 0.878, 0.913, 0.932, -0.014, 0.444, 0.250],
    },
    index=METRICS)


def _find_results_file(run_dir: Path, epoch: Optional[int], assimilation: bool) -> Path:
    stem = 'test_results_data_assimilation.p' if assimilation else 'test_results.p'
    if epoch is not None:
        candidate = run_dir / 'test' / f'model_epoch{epoch:03d}' / stem
        if not candidate.is_file():
            raise FileNotFoundError(f'No {stem} for epoch {epoch} in {run_dir}')
        return candidate
    candidates = sorted((run_dir / 'test').glob(f'model_epoch*/{stem}'))
    if not candidates:
        raise FileNotFoundError(f'No {stem} anywhere under {run_dir / "test"}')
    return candidates[-1]


def _load(run_dir: Path, epoch: Optional[int], assimilation: bool = False) -> dict:
    path = _find_results_file(run_dir, epoch, assimilation)
    print(f'  reading {path}')
    with path.open('rb') as fp:
        return pickle.load(fp)


def _series(results: dict, basin: str, variable: str):
    """Pull one variable for one basin as a 1-D, date-indexed series.

    The author stacked ('date', 'time_step') into one axis. Current neuralhydrology keeps `time_step` as its own
    dimension of size `predict_last_n`, and stacking leaves several coordinates containing 'date', which
    `calculate_metrics` refuses. With `predict_last_n: 1` (what this reproduction uses) dropping the axis is exactly
    equivalent; the general case is flattened by hand.
    """
    freq = next(iter(results[basin]))
    array = results[basin][freq]['xr'][variable]
    if 'time_step' not in array.dims:
        return array
    if array.sizes['time_step'] == 1:
        return array.isel(time_step=0, drop=True)

    import xarray
    stacked = array.stack(datetime=['date', 'time_step'])
    return xarray.DataArray(stacked.values, coords={'date': stacked.coords['date'].values}, dims='date')


def _score(results: dict, reference: dict, target: str) -> pd.DataFrame:
    """Per-basin metrics, always against the observation record of `reference` (the complete one)."""
    rows = {}
    for basin in results:
        if basin not in reference:
            print(f'  WARNING: basin {basin} missing from the reference run, skipped')
            continue
        try:
            sim = _series(results, basin, f'{target}_sim')
            obs = _series(reference, basin, f'{target}_obs')
            rows[basin] = calculate_metrics(obs=obs, sim=sim, metrics=METRICS, datetime_coord='date')
        except Exception as exc:  # a basin with no valid observations must not kill the whole table
            print(f'  WARNING: basin {basin} failed ({type(exc).__name__}: {exc})')
    return pd.DataFrame(rows).T


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--simulation', type=Path, required=True,
                        help='Simulation run directory. Also supplies the complete observation record.')
    parser.add_argument('--autoregression', type=Path, default=None)
    parser.add_argument('--assimilation', type=Path, default=None)
    parser.add_argument('--target', type=str, default='QObs(mm/d)')
    parser.add_argument('--epoch', type=int, default=None, help='Defaults to the last evaluated epoch.')
    parser.add_argument('--out', type=Path, default=None, help='Optional CSV to write the table to.')
    args = parser.parse_args()

    print('Loading simulation (also the reference observation record):')
    simulation = _load(args.simulation, args.epoch)

    arms: Dict[str, pd.DataFrame] = {}
    print('Scoring simulation:')
    arms['Simulation'] = _score(simulation, simulation, args.target)

    if args.autoregression is not None:
        print('Loading autoregression:')
        arms['AR 0.0 holdout'] = _score(_load(args.autoregression, args.epoch), simulation, args.target)
    if args.assimilation is not None:
        print('Loading assimilation:')
        arms['Assimilation'] = _score(_load(args.assimilation, args.epoch, assimilation=True), simulation, args.target)

    table = pd.DataFrame({name: df[METRICS].median() for name, df in arms.items()}).loc[METRICS]
    counts = {name: len(df) for name, df in arms.items()}

    print()
    print('=' * 78)
    print('Median over basins   ' + '   '.join(f'{k}: n={v}' for k, v in counts.items()))
    print('=' * 78)
    combined = table.round(3)
    for arm in table.columns:
        if arm in PAPER.columns:
            combined[f'{arm} (paper)'] = PAPER[arm]
            combined[f'{arm} (diff)'] = (table[arm] - PAPER[arm]).round(3)
    print(combined.to_string())

    print()
    if 'Simulation' in table.columns:
        for arm in ['AR 0.0 holdout', 'Assimilation']:
            if arm in table.columns:
                gain = table.loc['NSE', arm] - table.loc['NSE', 'Simulation']
                paper_gain = PAPER.loc['NSE', arm] - PAPER.loc['NSE', 'Simulation']
                print(f'NSE gain over simulation, {arm:16s}: ours {gain:+.3f}  paper {paper_gain:+.3f}')

    if args.out is not None:
        args.out.parent.mkdir(parents=True, exist_ok=True)
        combined.to_csv(args.out)
        print(f'\nwritten to {args.out}')
    return 0


if __name__ == '__main__':
    sys.exit(main())
