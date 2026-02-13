# Code Ownership Map and Unified Storage Plan

Date: 2026-02-12
Scope: `neuralhydrology`, `src`, `scripts`, `tools`, `hpc`, `configs`, `examples`

## Verdict

The project is **partially unified** and the current architecture is **suitable** for unified storage.

- Good:
  - Research projects are largely isolated under `src/<project_slug>/`.
  - Core framework remains in `neuralhydrology/`.
  - Research index exists in `draft/RESEARCH_INDEX.md`.
- Not yet unified:
  - Project-related files still appear in `hpc/`, `configs/`, and parts of `scripts/`.
  - `scripts/` and `tools/` still mix shared utility scripts and project scripts.

## Target Storage Policy

- `neuralhydrology/`: core framework only (dataset/model/training/evaluation/utils)
- `src/<project>/`: project-specific code/configs/hpc/docs/data-lists
- `scripts/`: shared scripts only (cross-project reusable)
- `tools/`: shared tooling only
- `configs/`: shared baseline or common templates only
- `hpc/`: shared HPC tooling only (environment/bootstrap/sync)
- `draft/ideas/`: planning and progress source of truth

## Ownership Map (Current)

### Core (keep as-is)

- `neuralhydrology/`

### Project-isolated (mostly good)

- `src/caravan_global/`
- `src/mamba_camels_us/`
- `src/mamba_camelsh/`
- `src/namou_kuwei/`
- `src/full_531_basins/`
- `src/haihe_river/`
- `src/hydroagent/`
- `src/41_mts_mamba_global_transfer/`

### Shared utility (keep in place)

- `scripts/analyze_training.py`
- `scripts/check_data_leakage.py`
- `scripts/create_test_data.py`
- `scripts/generate_all_basins.py`
- `scripts/make_basin_splits.py`
- `scripts/training_recovery.py`
- `scripts/transfer_weights.py`
- `tools/run_experiment.py`
- `tools/validate_config.py`
- `tools/gen_config.py`
- `tools/new_site.py`
- `tools/data/data_availability.py`
- `tools/gee/*`

### Mixed / candidates to migrate

- `hpc/submit_mamba_camels_us.slurm` -> `src/mamba_camels_us/hpc/`
- `hpc/submit_mamba_quick.slurm` -> `src/mamba_camels_us/hpc/`
- `hpc/slurm_caravan_global.sh` -> `src/caravan_global/hpc/`
- `configs/caravan/*` -> `src/caravan_global/configs/`
- `configs/camels_us/full_training/*` -> `src/full_531_basins/configs/` (or project subfolder)
- `configs/camels_us/data_splits/*` -> corresponding project `src/.../data/`
- `configs/full_training/*` -> `src/full_531_basins/configs/` (if project-specific)
- `scripts/hpc/hpc_optimized_config.py` -> evaluate: shared vs project-specific
- `scripts/hpc/hpc_slurm_job.sh` -> evaluate: shared template vs project-specific

### Archive-only (do not treat as active code roots)

- `configs/archive/*`
- `docs/archive/*`

## Phase Plan

### Phase A (safe, no behavior change)

1. Add/confirm policy doc and ownership map.
2. Mark `configs/archive` and old roots as archive in docs.
3. Keep only shared scripts in `scripts/` and `tools/` (classification only, no moves yet).

### Phase B (low risk moves)

1. Move project-specific HPC scripts from `hpc/` to matching `src/<project>/hpc/`.
2. Move project-specific configs from `configs/` to matching `src/<project>/configs/`.
3. Update references in README/slurm/yaml paths.

### Phase C (strict normalization)

1. `scripts/` retains only shared scripts.
2. `tools/` retains only shared tools.
3. Add a CI/pre-commit check to block new project-specific files under root-level `scripts/`, `hpc/`, `configs/`.

## Guardrails

- For each move:
  - update path refs (`rg` scan for old path),
  - run import/config smoke check,
  - commit in small batches by project.
- Keep large artifacts out of these commits (`results/`, `logs/`).

## Recommended Next Action

Execute Phase B for two highest-confidence groups first:

1. `caravan_global` (`configs/caravan/*`, `hpc/slurm_caravan_global.sh`)
2. `mamba_camels_us` (`hpc/submit_mamba_*.slurm`)

Then run path validation and continue project-by-project.
