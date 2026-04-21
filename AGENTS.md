# Repository Guidelines

## Project Structure & Module Organization
- `neuralhydrology/`: core importable package (models, datasets, training, evaluation, CLI entrypoint).
- `test/`: all pytest tests (collection is restricted here via `setup.cfg`).
- `src/<idea>/`: idea-specific workspaces with `configs/`, `scripts/`, `hpc/`, and docs.
- `data/`: local datasets only.
- `results/<id>_<idea>/` and `logs/<id>_<idea>/`: run outputs/logs (kept out of version control except `.gitkeep`).
- `docs/`: shared technical and user documentation.
- `draft/`: planning and research notes (`draft/RESEARCH_INDEX.md` tracks active ideas).

## Build, Test, and Development Commands
- Install dependencies:
  - `pip install -r requirements-cpu.txt` or `pip install -r requirements-gpu.txt`
  - `pip install -e .` (editable install for development)
- Run tests:
  - `pytest`
  - `pytest --cov=neuralhydrology`
  - `pytest test/test_config_runs.py` (single file)
- Run training/evaluation (canonical entrypoint):
  - `python -m neuralhydrology.nh_run train --config-file src/test_data/configs/quick_test.yml --gpu -1`
  - `python -m neuralhydrology.nh_run continue_training --run-dir runs/<run_dir>`
  - `python -m neuralhydrology.nh_run evaluate --run-dir <run_dir> --period test`
- Build docs: `cd docs && make html`

## Coding Style & Naming Conventions
- Python style uses YAPF with `.style.yapf` (Google base, `column_limit = 120`).
- Use English for code identifiers (`snake_case` for functions/variables, `PascalCase` for classes).
- Prefer `pathlib` for filesystem paths; avoid hardcoded absolute paths.
- Put runnable scripts under `src/<idea>/scripts/`; keep production configs in `src/<idea>/configs/`.

## Testing Guidelines
- Add/modify tests in `test/` whenever behavior changes.
- Name files `test_*.py`; keep reusable fixtures in `test/conftest.py`.
- Use test configs in `test/test_configs/*.test.yml` and local fixtures in `test/test_data/`.
- Run `pytest --cov=neuralhydrology` before opening a PR; maintain or improve coverage for touched modules.

## Commit & Pull Request Guidelines
- Follow the repository’s commit style prefixes seen in history: `Fix: ...`, `Chore: ...`, `Phase: ...`.
- Keep commits small, runnable, and focused; do not bypass hooks with `--no-verify`.
- PRs should include:
  - clear scope/summary,
  - linked issue or context,
  - exact validation commands run (tests, training smoke checks),
  - result artifacts/metrics when model behavior changes.

## Security & Configuration Tips
- Never commit secrets or local credentials (`.cdsapirc`, `hpc密码.txt` are local-only/ignored).
- Do not commit dataset snapshots or generated artifacts from `data/`, `results/`, `logs/`, or `external/`.
