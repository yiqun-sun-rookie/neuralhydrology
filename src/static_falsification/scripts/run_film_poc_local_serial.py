"""Serial local GPU runner for FiLM POC (24 configs). Skips already-completed runs.

Usage:
    python src/static_falsification/scripts/run_film_poc_local_serial.py

A run is considered complete if runs/{experiment_name}_*/model_epoch030.pt exists.
Each run's stdout/stderr is tee'd to logs/11_static_falsification/{experiment_name}_local.log.
Failures are logged but do not stop the batch.
"""
import subprocess
import sys
import time
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[3]
CONFIGS_DIR = REPO_ROOT / 'src/static_falsification/configs/film_poc'
RUNS_DIR = REPO_ROOT / 'runs'
LOGS_DIR = REPO_ROOT / 'logs/11_static_falsification'
RUNNER = REPO_ROOT / 'src/static_falsification/scripts/run_film_poc.py'
FINAL_CKPT = 'model_epoch030.pt'


def is_complete(experiment_name: str) -> bool:
    for run_dir in RUNS_DIR.glob(f'{experiment_name}_*'):
        if (run_dir / FINAL_CKPT).is_file():
            return True
    return False


def main():
    configs = sorted(CONFIGS_DIR.glob('*.yml'))
    assert len(configs) == 24, f'expected 24 configs, found {len(configs)}'
    LOGS_DIR.mkdir(parents=True, exist_ok=True)

    pending, done = [], []
    for cfg in configs:
        (pending if not is_complete(cfg.stem) else done).append(cfg)

    print(f'[Batch] total=24 already_done={len(done)} pending={len(pending)}')
    for cfg in done:
        print(f'  skip (done): {cfg.stem}')

    batch_start = time.time()
    failures = []
    for i, cfg in enumerate(pending, 1):
        log_file = LOGS_DIR / f'{cfg.stem}_local.log'
        print(f'\n[{i}/{len(pending)}] === {cfg.stem} ===')
        print(f'  log: {log_file}')
        run_start = time.time()

        cmd = [sys.executable, str(RUNNER), '--config-file', str(cfg), '--gpu', '0']
        with open(log_file, 'w', encoding='utf-8', buffering=1) as lf:
            lf.write(f'CMD: {" ".join(cmd)}\n\n')
            lf.flush()
            proc = subprocess.run(cmd, stdout=lf, stderr=subprocess.STDOUT)

        dt = time.time() - run_start
        status = 'OK' if proc.returncode == 0 else f'FAIL rc={proc.returncode}'
        print(f'  {status} in {dt/60:.1f} min')
        if proc.returncode != 0:
            failures.append(cfg.stem)

    total_min = (time.time() - batch_start) / 60
    print(f'\n[Batch] wall time {total_min:.1f} min, {len(failures)} failure(s)')
    for name in failures:
        print(f'  FAIL: {name} (see logs/11_static_falsification/{name}_local.log)')
    return 1 if failures else 0


if __name__ == '__main__':
    sys.exit(main())
