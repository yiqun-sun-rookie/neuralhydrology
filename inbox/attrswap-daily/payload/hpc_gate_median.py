"""Public-422 median for one finished arm (+ the preregistered C0 parity gate for the calibration arm).

Usage (cwd = experiment root on the HPC):  python hpc_gate_median.py <run_dir> <arm_name>
Writes logs/<arm>.public_median.txt ('<median> <n>') and, for the parity arm, logs/<arm>.gate.txt
('CLEAN|FLAG|HARDFAIL <median>'); exits 1 on HARDFAIL so SLURM afterok-dependents are cancelled.
Bands from PREREG_20260901 section 6: CLEAN [0.7174, 0.7334], FLAG [0.7069, 0.7439].
"""
import pathlib
import sys

import pandas as pd

rd, arm = sys.argv[1], sys.argv[2]
PARITY = 'attrswap_ref27_parity_s900'
d = pd.read_csv(f'{rd}/test/model_epoch030/test_metrics.csv', dtype={'basin': str})
d['basin'] = d['basin'].str.zfill(8)
hold = {l.strip().zfill(8) for l in open('basin_lists/holdout_107.txt') if l.strip()}
pub = d[~d['basin'].isin(hold)]
if len(d) != 529 or len(pub) != 422:
    print(f'STOP: rows={len(d)} public={len(pub)} (expected 529 / 422) -- preregistered basin count violated')
    sys.exit(2)
m = float(pub['NSE'].median())
pathlib.Path('logs').mkdir(exist_ok=True)
open(f'logs/{arm}.public_median.txt', 'w').write(f'{m:.6f} {len(pub)}\n')
print(f'RESULT {arm} public_median_n: {m:.6f} {len(pub)}  (full529 median {d["NSE"].median():.6f})')
if arm == PARITY:
    v = 'CLEAN' if 0.7174 <= m <= 0.7334 else ('FLAG' if 0.7069 <= m <= 0.7439 else 'HARDFAIL')
    open(f'logs/{arm}.gate.txt', 'w').write(f'{v} {m:.6f}\n')
    print(f'PARITY GATE median={m:.6f} verdict={v}')
    if v == 'HARDFAIL':
        sys.exit(1)
