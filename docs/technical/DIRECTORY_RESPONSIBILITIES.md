# Directory Responsibilities

This file defines the canonical ownership for top-level folders.

## Core Package

- `neuralhydrology/`: importable library code (`nh_run`, training, modelzoo, utils).
- `test/`: automated tests for `neuralhydrology/`.
- `examples/`: tutorial notebooks and sample configs only (no production dependencies).
- `common/`: shared HPC shell helpers only (submit/log tail/install); no idea business logic.

## Idea Workspaces

- `src/<idea>/`: idea-scoped code, configs, scripts, docs, and HPC assets.
- `src/test_data/`: shared lightweight test-data generator/configs for quick sanity checks.
- `results/<ID>_<slug>/`: persisted outputs.
- `logs/<ID>_<slug>/`: run logs.
- `draft/ideas/`: idea planning/paper drafts.

## Data and External Assets

- `data/`: local datasets.
- `external/`: local-only external resources (ignored by git).

## Rules

1. New runnable commands go to `src/<idea>/...`; do not add root-level wrapper layers.
2. `examples/` must not be required by production configs under `src/`.
3. Do not add new business logic outside idea folders; add it under `src/<idea>/...`.
4. Use `src/<idea>/scripts/` as the runtime script entrypoint; do not reintroduce `src/<idea>/tools/`.
