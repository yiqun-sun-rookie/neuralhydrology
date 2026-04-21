# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

NeuralHydrology is a deep learning framework for hydrological modeling (rainfall-runoff, streamflow prediction). The repository contains the core `neuralhydrology` package plus multiple isolated research idea workspaces under `src/`.

**Version**: 1.12.0 | **Python**: >=3.8 (3.10 recommended) | **PyTorch**: >=2.0.0

## Common Commands

```bash
# Install (development mode)
pip install -e .

# Install dependencies (pick one)
pip install -r requirements-cpu.txt
pip install -r requirements-gpu.txt

# Run tests
pytest                          # full suite
pytest --smoke-test             # faster CI subset
pytest --cov=neuralhydrology    # with coverage
pytest test/test_config_runs.py # single test file

# Train a model
python -m neuralhydrology.nh_run train --config-file <config.yml> --gpu 0
python -m neuralhydrology.nh_run train --config-file <config.yml> --gpu -1  # CPU

# Continue training from checkpoint
python -m neuralhydrology.nh_run continue_training --run-dir <run_dir>

# Finetune a pretrained model
python -m neuralhydrology.nh_run finetune --config-file <config.yml>

# Evaluate a model
python -m neuralhydrology.nh_run evaluate --run-dir <run_dir> --period test --epoch <N>

# Format code (YAPF, Google style, 120 char limit)
yapf -r neuralhydrology/ --style=.style.yapf
```

## Architecture

### Core Package (`neuralhydrology/`)

The package uses **registry/factory patterns** throughout. Each subsystem has a factory function that maps config strings to implementations:

- **`modelzoo/`** — Model architectures. `get_model(cfg)` dispatches to CudaLSTM, EALSTM, CustomLSTM, GRU, Mamba, Transformer, MCLSTM, ARLSTM, ODE-LSTM, etc. All models extend `BaseModel`. Output heads (regression, GMM, CMAL, UMAL) are in `head.py`.
- **`datasetzoo/`** — Dataset loaders. `get_dataset(cfg, ...)` dispatches to CAMELS variants (US/GB/AUS/BR/CL/IND/DE), Caravan, LamaH, HourlyCamelsUS, GenericDataset. All extend `BaseDataset` (PyTorch Dataset). New datasets can be added via `register_dataset()`.
- **`training/`** — Training loop in `basetrainer.py`. Factories: `get_optimizer()`, `get_loss_obj()`, `get_regularization_obj()`. Supports gradient clipping, LR scheduling, early stopping, TensorBoard logging.
- **`evaluation/`** — `get_tester()` returns `RegressionTester` or `UncertaintyTester`. Hydrological metrics (NSE, KGE, Alpha-NSE, Beta-NSE) in `metrics.py`.
- **`utils/config.py`** — `Config` class loads YAML configs with auto type coercion: keys containing 'dir'/'file'/'path' become `pathlib.Path`, keys ending in '_date' become `pd.Timestamp` (DD/MM/YYYY format).

### Entry Point

`nh_run.py` is the single CLI entry point with modes: `train`, `evaluate`, `finetune`, `continue_training`. Console scripts: `nh-run`, `nh-schedule-runs`, `nh-results-ensemble`.

### Multi-Workspace Layout

```
neuralhydrology/     Core importable package
src/<id>_<name>/     Idea-specific workspaces (configs/, scripts/, hpc/, docs/)
results/<id>_<name>/ Experiment outputs (checkpoints, plots, logs)
logs/<id>_<name>/    Run and SLURM logs
test/                Package tests (pytest collects ONLY from here)
data/                Raw datasets only (no results)
draft/               Research writing; RESEARCH_INDEX.md is the master idea index
docs/                Shared project documentation
external/            External dependencies (superflexpy)
```

### Test Infrastructure

Tests live in `test/` with configs in `test/test_configs/` and data in `test/test_data/`. `conftest.py` provides a `get_config(tmpdir)` fixture and `single_timescale_model` parameterized fixture. The `--smoke-test` flag enables faster CI runs. `setup.cfg` restricts pytest collection to `test/` only.

## Project Conventions

- **Language**: Reply in Chinese (Simplified). Code identifiers in English.
- **Formatting**: YAPF with Google style, 120 char line limit (`.style.yapf`)
- **Paths**: Always use `pathlib`. No hardcoded absolute paths.
- **Decision priority**: Simplicity > Testability > Readability > Reversibility
- **Stop rule**: If stuck on the same problem 5 times, stop and re-evaluate the approach.
- **Complex tasks**: Create `IMPLEMENTATION_PLAN.md` with 3-5 stages (Goal, Success Criteria, Tests, Status).
- **New ideas**: Register in `draft/RESEARCH_INDEX.md`, create `draft/ideas/<id>_<slug>.md`, scaffold `src/<slug>/` and `results/<id>_<slug>/`.
- **Legacy code**: `knet/` and `experiments/` are read-only. Do not modify.
- **Scripts**: Place runnable scripts in `src/<idea>/scripts/`, not as root-level wrappers.
- **Configs**: Production configs go in `src/<idea>/configs/`, not `examples/`.
- **src/ packages**: `src/` 下的独立包（如 `hydroagent`）不在默认 Python path 中。脚本中需 `sys.path.insert(0, '.../src')` 或从 `src/` 目录运行 `python -m <pkg>.module`。
