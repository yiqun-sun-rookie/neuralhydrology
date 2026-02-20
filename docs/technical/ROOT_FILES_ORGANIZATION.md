# Root Files Organization

This file defines what should stay in repository root and what should be archived.

## Keep In Root (project metadata/build entry)
- `.gitattributes`
- `.gitignore`
- `.readthedocs.yml`
- `.style.yapf`
- `CITATION.cff`
- `CODEOWNERS`
- `CONTRIBUTING.rst`
- `LICENSE`
- `README.md`
- `requirements.txt` (single active dependency set)
- `setup.py`

## Archive / Relocate
- HPC reference manuals (PDF): move to `docs/hpc/reference/`
- Local sensitive files (credentials/passwords): either keep local in root with `.gitignore`, or move to `external/local_private/` (ignored by git)
- Temporary DB/cache files (e.g. `sync.ffs_db`): keep local-only, never track

## Current Applied Moves
- `河海大学高性能计算平台用户手册V4.1.pdf` -> `docs/hpc/reference/河海大学高性能计算平台用户手册V4.1.pdf`
- `.cdsapirc` -> currently kept in repo root as local-only file (ignored by git)
- `hpc密码.txt` -> currently kept in repo root as local-only file (ignored by git)

