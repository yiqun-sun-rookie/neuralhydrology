# NeuralHydrology Workspace

This repository contains the core `neuralhydrology` package plus multiple idea-specific workspaces.

## Canonical Entry Point

Use the official runner:

```bash
python -m neuralhydrology.nh_run train --config-file <config.yml> --gpu <id>
```

- `--gpu 0`: use GPU 0
- `--gpu -1`: force CPU

## Quick Start

1. Create environment (Python 3.10 recommended)

```bash
python -m venv .venv
# Windows
.venv\Scripts\activate
# Linux/macOS
# source .venv/bin/activate
```

2. Install dependencies

```bash
pip install -r requirements-gpu.txt
# or
pip install -r requirements-cpu.txt
```

3. Run smoke training

```bash
python -m neuralhydrology.nh_run train --config-file src/test_data/configs/quick_test.yml --gpu -1
```

## Project Layout

- `neuralhydrology/`: core importable package
- `src/<idea>/`: idea-owned code/configs/scripts/hpc/docs
- `results/<ID>_<idea>/`: persisted outputs
- `logs/<ID>_<idea>/`: run and SLURM logs
- `draft/`: research writing and idea docs
- `docs/`: shared project/engineering documentation
- `data/`: local datasets
- `examples/`: tutorial notebooks and sample configs only
- `common/`: shared HPC helper scripts
- `test/`: package tests for `neuralhydrology`

## Active Idea Roots

- `src/caravan_global/` (01)
- `src/mamba_camels_us/` (02)
- `src/mamba_camelsh/` (03)
- `src/namou_kuwei/` (04)
- `src/full_531_basins/` (05)
- `src/haihe_river/` (06)
- `src/hydroagent/` (07)
- `src/mts_mamba_global_transfer/` (41)

See `draft/RESEARCH_INDEX.md` for the up-to-date index.

## Useful Commands

```bash
# Continue interrupted training
python -m neuralhydrology.nh_run continue_training --run-dir runs/<run_dir>

# Show smoke command list
# docs/guides/README_smoke.md
```

## Notes

- Do not add new root-level runner wrappers.
- Prefer `src/<idea>/scripts/` for runnable scripts.
- Keep production configs in `src/<idea>/configs/`, not in `examples/`.
