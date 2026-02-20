# Top-Level Folder Status

This file records whether each root folder is idea-owned, shared, or local-only.

## Kept (Active)

- `src/`: idea code roots (`src/<idea>/...`) plus shared test/template helpers.
- `results/`: canonical long-term outputs by idea.
- `logs/`: logs by idea.
- `data/`: datasets (shared physical storage, idea ownership documented in `data/README.md`).
- `draft/`: research/idea docs and paper-oriented writing.
- `docs/`: project operation/engineering docs.
- `common/`: shared HPC utilities only; idea-specific HPC scripts live in `src/<idea>/hpc/`.
- `test/`: package test suite for `neuralhydrology`.
- `external/`: local external resources/backups (local-only, ignored by git).
- `runs/`: temporary run staging directory.

## Transitional / Empty

- `pipelines/`: root-level legacy folder; active pipelines are now under idea roots (for example `src/haihe_river/pipelines/`).
- `results/backups`, `results/models`, `results/outputs`, `results/reports`: legacy root buckets; active content has been moved under idea-specific results folders.

## Removed from Active Root Convention

- root `configs/`: replaced by `src/<idea>/configs/`.
- root `experiments/`: replaced by `src/<idea>/...`.
- root `projects/`: replaced by `src/<idea>/...`.
- root `artifacts/`: replaced by idea-specific `results/<ID>_<idea>/...` and data workspace folders.
- root `tools/`: removed; runnable tooling has been consolidated into `src/<idea>/scripts/` (and `src/<idea>/hpc/` for cluster jobs).
- root `scripts/`: removed; run scripts directly from `src/<idea>/scripts/`.
