# Docs Directory

`docs/` is for **project documentation** only.

## Scope
- Installation, environment, runtime, HPC operations.
- User/developer guides for running and maintaining code.
- Technical architecture and implementation notes.
- Archived legacy technical docs.
- Shared, cross-idea documentation only.

## Out of Scope
- Thesis writing drafts.
- Idea progress logs intended for paper writing.

## Where Thesis Content Lives
- Use `draft/` for thesis-oriented writing and research narrative.
- Main index: `draft/RESEARCH_INDEX.md`
- Per-idea writing: `draft/ideas/*.md`

## Current Layout
- `docs/guides/`: how to run and use the project.
- `docs/technical/`: engineering and architecture notes.
- `docs/hpc/`: cluster/HPC deployment and operations.
- `docs/contributing/`: contribution and coding workflow docs.
- `docs/papers/`: paper references (read-only materials).
- `docs/source/`: Sphinx documentation source.
- `docs/archive/`: legacy and deprecated materials.

## Idea-Specific Docs
- Keep idea-owned docs under `src/<idea>/docs/`.
- Example: `src/mamba_camels_us/docs/MAMBA_CAMELS_US_EXPERIMENT.md`
- Keep `docs/` focused on shared guidance to reduce drift and duplication.

See `docs/technical/TOP_LEVEL_FOLDER_STATUS.md` for current root-folder ownership and cleanup status.
