# Unified Launcher Design (train.py)

> Goal: Replace multiple legacy runner scripts with a single, consistent, extensible command-line entry point for training (and later evaluation) in NeuralHydrology.

## 1. Motivation
Currently there are several overlapping scripts (`simple_train.py`, `run_training.py`, `gpu_training.py`, `run_gpu_training.py`, `full_data_train.py`, `train_with_config.py`, etc.). They:
- Duplicate logic (GPU detection, config selection, YAML generation)
- Risk configuration drift (hard-coded hyperparameters vs YAML)
- Confuse newcomers (which script is canonical?)

A unified launcher provides: clarity, single help surface, easier documentation, lower maintenance.

## 2. Non-Goals (Initial Phase)
- Not implementing distributed multi-GPU (may add later)
- Not modifying original YAML in-place (only derive new ones)
- Not providing automated hyperparameter search (future enhancement)

## 3. Functional Scope (Phase 1)
Core responsibilities:
1. Invoke `neuralhydrology/nh_run.py train` with a user-supplied YAML.
2. Provide ergonomic GPU selection / fallback.
3. Optional generation of an auto-optimized derivative config (batch size, hidden size, workers, device, logging adjustments) without overwriting the original.
4. Optional lightweight GPU monitoring (nvidia-smi loop) for manual observation.
5. Print sanity diagnostics (python path, torch version, CUDA availability) before launching.
6. Support dry-run and final effective config inspection.
7. Provide simple listing of candidate YAML files in a directory.

## 4. CLI Specification
Command: `python train.py [FLAGS]`

| Flag | Type | Default | Description |
|------|------|---------|-------------|
| `--config, -c` | path | (required unless `--list-configs`) | Base YAML config file |
| `--gpu, -g` | int / -1 | auto (0 if CUDA; else -1) | GPU id; -1 forces CPU |
| `--device` | {auto,cuda,cpu} | auto | Override auto detection (mutually exclusive with explicit `--gpu` except -1) |
| `--list-configs` | bool | false | List YAML files in a target directory (default examples) and exit |
| `--config-dir` | path | examples/01-Introduction | Directory scanned by `--list-configs` |
| `--auto-optimize` | bool | false | Enable generation of optimized YAML (naming pattern) |
| `--batch-size` | int | 512 (only if auto-opt) | Override batch size in derived config |
| `--hidden-size` | int | 128 (only if auto-opt) | Override hidden size in derived config |
| `--num-workers` | int | 8 (only if auto-opt) | Data loader workers in derived config |
| `--no-cudalstm` | bool | false | Prevent switching `lstm`→`cudalstm` when auto-opt enabled |
| `--monitor` | bool | false | Spawn `nvidia-smi -l 1` until training ends |
| `--print-final-config` | bool | false | Dump effective YAML (original or derived) to stdout before run |
| `--dry-run` | bool | false | Do not invoke training; just show command & effective config path |
| `--out-dir` | path | same as base config dir | Where to write derived YAML |
| `--force` | bool | false | Overwrite existing derived YAML |
| `--seed` | int | (optional) | If set and base YAML lacks seed, inject it (not persisted unless auto-opt) |
| `--tag` | str | (optional) | Append tag to experiment name (only in derived config) |
| `--log-level` | str | info | Logging verbosity for launcher (not training) |

Derived config naming pattern: `<stem>_gpuopt_bs{B}_hs{H}.yml` (append `_tag{TAG}` if `--tag` set).

## 5. Behavioral Rules
1. If `--list-configs` given: ignore other flags except `--config-dir`.
2. If neither `--config` nor `--list-configs` provided: exit with usage error.
3. GPU selection precedence:
   - If `--gpu` supplied (>=0), use it (fail if cuda not available unless user forces `--device cpu` conflict -> error)
   - Else if `--device` is `cuda` and cuda available -> GPU 0
   - Else if auto -> pick GPU 0 if available else CPU (-1)
4. Auto-opt logic only triggers if `--auto-optimize` true; original YAML is never modified.
5. When auto-opt is active, base config fields overwritten in memory (and written out): `device`, `batch_size`, `hidden_size`, `num_workers`, optional `model` switch to `cudalstm`, plus modest logging adjustments (if not already set): increase `log_interval`, reduce `save_weights_every` collisions.
6. If derived file exists and no `--force`: abort with message.
7. `--monitor` spawns background process; ensure termination on normal or error exit.
8. If `--print-final-config` used with `--dry-run`, still exit code 0.
9. If user supplies a field already present (e.g., YAML has `batch_size` 1024 and `--batch-size 512`), CLI overrides with a warning line.

## 6. Validation & Error Cases
| Condition | Response |
|-----------|----------|
| Missing base YAML | Exit 1 with clear message |
| CUDA requested but not available | Exit 1 (suggest CPU mode) unless user forces -1 |
| Derived YAML path exists w/o --force | Exit 1 |
| Invalid integer for `--gpu` | Exit 2 |
| `--gpu` and `--device cpu` used together | Exit 2 |

## 7. Example Flows
### Basic
```
python train.py -c examples/01-Introduction/full_training.yml --gpu 0
```
### Auto Optimize
```
python train.py -c full_training.yml --auto-optimize --batch-size 1024 --hidden-size 256 --monitor
```
Produces: `full_training_gpuopt_bs1024_hs256.yml` and trains with GPU monitoring.

### Dry Run & Inspect
```
python train.py -c full_training.yml --auto-optimize --batch-size 512 --print-final-config --dry-run
```

### List Configs
```
python train.py --list-configs --config-dir examples/01-Introduction
```

## 8. Internal Structure (Proposed)
```
train.py
  parse_args()
  main():
    if list: list_configs(); return
    base_cfg = load_yaml()
    device, gpu_id = resolve_device(args)
    final_cfg, derived_path = maybe_auto_optimize(base_cfg, args, device, gpu_id)
    if print_final: dump_yaml_stdout(final_cfg)
    if dry_run: show_command(); return
    proc = maybe_start_monitor(args.monitor)
    run_training_subprocess(final_cfg_path, gpu_id)
    cleanup_monitor(proc)
```

Helper modules (optional refactor later):
- `launcher/utils.py` for device logic & YAML patching.

## 9. Migration Mapping
| Old Script | Replacement Command |
|-----------|---------------------|
| `simple_train.py` | `train.py --config ...` |
| `gpu_training.py` | `train.py --config ... --auto-optimize [--monitor]` |
| `run_training.py` | `train.py --config ...` |
| `run_gpu_training.py` (interactive) | (Dropped initially or future `--interactive`) |
| `full_data_train.py` | Pre-create YAML then `train.py --config new.yml` |
| `train_with_config.py` | Edit YAML directly + `train.py` |

## 10. Future Extensions (Phase 2+)
- `--eval` mode to evaluate existing run (loading weights directory)
- `--resume` to resume interrupted training (auto-detect last checkpoint)
- `--export-config-json` for downstream tooling ingest
- `--interactive` to display menu (optional add-on)
- Multi-GPU / DDP: flags like `--distributed --world-size N` (deferred)

## 11. Testing Strategy
1. Unit: parse_args combinations (dry-run) via small dummy YAML.
2. Integration: Launch a short training (1 basin, epochs=1) CPU mode to ensure subprocess call success.
3. Auto-opt: verify new file written and contains overrides.
4. Monitor: ensure process terminated (Windows + Linux differences considered).

## 12. Risks & Mitigations
| Risk | Mitigation |
|------|------------|
| Overwriting user configs | Always write to new filename; require --force to overwrite derived file |
| Hidden mismatch between YAML + CLI overrides | Print all overridden keys before run |
| Long subprocess blocking monitor cleanup | Wrap in try/finally to terminate monitor |
| Windows path issues | Normalize with `Path` and convert to string only on final cmd assembly |

## 13. Implementation Steps
1. Add `train.py` with full CLI and minimal helpers inside single file.
2. Inject DeprecationWarning into old scripts (1–2 lines + forward import optional).
3. Update docs (`PROJECT_OVERVIEW.md`, README, guides) referencing new launcher.
4. Provide migration table in README.
5. Remove/Archive old scripts in future commit after grace period.

## 14. Acceptance Criteria
- Single file < ~400 lines, no external dependencies beyond stdlib + yaml + torch presence checks.
- Running with base config unchanged reproduces old simple_train behavior.
- Auto-opt path writes derived YAML and trains with it.
- Dry-run never launches training.
- Monitor cleaned up reliably.

---
_Last updated: 2025-10-05_
