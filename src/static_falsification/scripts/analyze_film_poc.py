"""Analyze FiLM-LSTM POC results and apply pre-registered threshold B.

Aggregates per-run test NSE from runs/film_poc_*/test/, computes:
    ΔArch         = NSE(filmlstm, real) - NSE(ealstm, real)
    ΔPhys_FiLM    = NSE(filmlstm, real) - NSE(filmlstm, shuffle)
    ΔPhys_EA      = NSE(ealstm, real)   - NSE(ealstm, shuffle)
Prints verdict: go / no-go / reconsider.
"""
import pickle
from collections import defaultdict
from pathlib import Path
from typing import Dict, Tuple

import numpy as np

# Key: (model, condition, fold) -> median test NSE across basins × seeds
PerRunKey = Tuple[str, str, int]


def collect_nse_from_runs(runs_root: Path) -> Dict[PerRunKey, float]:
    """Walk runs/ and extract median test NSE per (model, condition, fold), averaged over seeds."""
    grouped = defaultdict(list)

    for run_dir in runs_root.glob('*_poc_*_fold*_seed*'):
        name = run_dir.name
        parts = name.split('_')
        # Expected: {model}_poc_{condition}_fold{F}_seed{S}_{date}_{time}
        try:
            model = parts[0]
            condition = parts[2]
            fold = int(parts[3].replace('fold', ''))
        except (ValueError, IndexError):
            print(f'[WARN] skipping unparseable run dir: {name}')
            continue

        test_results = list(run_dir.glob('test/model_epoch*/test_results.p'))
        if not test_results:
            print(f'[WARN] no test_results.p in {name}')
            continue
        # Pick the last epoch
        with open(sorted(test_results)[-1], 'rb') as f:
            results = pickle.load(f)

        # results schema: {basin_id: {target_var: {'NSE': value, ...}}}
        nses = []
        for basin_id, target_dict in results.items():
            for target_var, metrics in target_dict.items():
                if 'NSE' in metrics:
                    nses.append(metrics['NSE'])
        if not nses:
            print(f'[WARN] no NSE values extracted from {name}')
            continue
        grouped[(model, condition, fold)].append(np.median(nses))

    # Average across seeds
    return {k: float(np.mean(v)) for k, v in grouped.items()}


def compute_verdict(per_run_nse: Dict[PerRunKey, float], threshold: str = 'B') -> dict:
    """Compute verdict under the given threshold."""
    # Aggregate across folds (mean)
    def _mean(model, condition):
        vals = [v for (m, c, f), v in per_run_nse.items() if m == model and c == condition]
        if not vals:
            raise ValueError(f'Missing data for ({model}, {condition})')
        return float(np.mean(vals))

    ea_real = _mean('ealstm', 'real')
    ea_shuffle = _mean('ealstm', 'shuffle')
    film_real = _mean('filmlstm', 'real')
    film_shuffle = _mean('filmlstm', 'shuffle')

    delta_arch = film_real - ea_real
    delta_phys_film = film_real - film_shuffle
    delta_phys_ea = ea_real - ea_shuffle

    # Per-fold consistency
    folds = sorted(set(f for _, _, f in per_run_nse.keys()))
    per_fold_deltas = []
    for fold in folds:
        try:
            ea_r = per_run_nse[('ealstm', 'real', fold)]
            film_r = per_run_nse[('filmlstm', 'real', fold)]
            per_fold_deltas.append(film_r - ea_r)
        except KeyError:
            continue
    fold_sign_conflict = (
        len(per_fold_deltas) >= 2
        and max(per_fold_deltas) > 0.05
        and min(per_fold_deltas) < -0.03
    )

    if threshold == 'B':
        pass_arch = delta_arch >= 0.02
        pass_phys = delta_phys_film > delta_phys_ea
        go = pass_arch and pass_phys and not fold_sign_conflict
    else:
        raise ValueError(f'Unknown threshold: {threshold}')

    return {
        'go': go,
        'delta_arch': delta_arch,
        'delta_phys_film': delta_phys_film,
        'delta_phys_ea': delta_phys_ea,
        'per_fold_deltas': per_fold_deltas,
        'fold_sign_conflict': fold_sign_conflict,
        'raw': {
            'ea_real': ea_real, 'ea_shuffle': ea_shuffle,
            'film_real': film_real, 'film_shuffle': film_shuffle,
        },
    }


def main():
    runs_root = Path('runs')
    per_run_nse = collect_nse_from_runs(runs_root)

    print('\n--- Per-(model, condition, fold) median NSE (averaged over seeds) ---')
    for key in sorted(per_run_nse.keys()):
        print(f'  {key}: {per_run_nse[key]:.4f}')

    verdict = compute_verdict(per_run_nse, threshold='B')

    print('\n--- Deltas ---')
    print(f'  ΔArch        = {verdict["delta_arch"]:+.4f}   (need >= +0.02)')
    print(f'  ΔPhys_FiLM   = {verdict["delta_phys_film"]:+.4f}')
    print(f'  ΔPhys_EA     = {verdict["delta_phys_ea"]:+.4f}')
    print(f'  Per-fold deltas: {[f"{d:+.4f}" for d in verdict["per_fold_deltas"]]}')
    print(f'  Fold sign conflict: {verdict["fold_sign_conflict"]}')

    print('\n--- Verdict under threshold B ---')
    print('  GO ✓ — upgrade to full 5-fold experiment' if verdict['go']
          else '  NO-GO ✗ — reconsider per decision branches in spec §10')


if __name__ == '__main__':
    main()
