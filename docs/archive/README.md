# Archive

Historical documents, migration artifacts, and deprecated content.
These files are kept for reference only and **should not be relied upon** for current workflows.

## Subdirectories

| Directory | Contents |
|-----------|----------|
| `technical_legacy/` | Deprecated technical docs (LAUNCHER_DESIGN, TIME_SPLIT_FIX, DEVELOPMENT_REPORT, etc.) |
| `guides_legacy/` | Old training guides (TRAINING_GUIDE, QUICK_TRAIN, RESUME_TRAINING, GPU_TRAINING_README) |
| `deprecated_guides/` | Redirect stubs for removed guides (SIMPLE_TRAIN_*) |
| `hpc_legacy/` | Previous HPC deployment docs (superseded by `docs/hpc/`) |
| `dependency_sets/` | Old conda environment files and rtd_requirements (replaced by root `requirements*.txt` and `docs/requirements.txt`) |
| `examples_legacy/` | Removed example scripts (test_enc, test_encoding) |
| `migration_backups/` | Backup snapshots from past reorganizations |
| `legacy_docs_projects/` | Archived per-project docs |
| `legacy_experiments/` | Historical experiment records |
| `legacy_projects/` | Old project-level files |

## Root-level archive files

Miscellaneous historical docs (project overviews, config analyses, cleanup summaries, training logs) from earlier development phases. See filenames for context.

## Policy

- Do not add new content here unless deprecating an existing active doc.
- When deprecating, move the file and leave a redirect stub at the original location.
- Periodically review and prune files older than 12 months with no references.
