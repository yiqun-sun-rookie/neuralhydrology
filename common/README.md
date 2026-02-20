# Common HPC Guide

Root `common/` keeps **cross-idea shared utilities**.

## Shared files in root `common/`

- `submit.sh`: unified job submit helper (maps task names to per-idea SLURM scripts)
- `logs.sh`: inspect/tail/clean logs under `logs/<task>/`
- `install_mamba_ssm.sh`: install CUDA-backed `mamba-ssm` on HPC

These are the only active root-level `common/` executables.

## Idea-specific HPC scripts

Keep idea-owned scripts under each idea folder:

- `src/caravan_global/hpc/`
- `src/full_531_basins/hpc/`
- `src/mamba_camels_us/hpc/`
- `src/mamba_camelsh/hpc/`
- `src/mts_mamba_global_transfer/hpc/`

## Legacy files

Deprecated HPC files are kept for traceability only:

- `common/archive/legacy/`

Do not use archived files as active entrypoints.

## Maintenance Rule

- Do not add idea-specific logic to `common/`.
- If a script only serves one idea, move it to `src/<idea>/hpc/`.
- If a new truly shared script is needed, document it here first.

## Quick usage

```bash
# Submit by task alias
./common/submit.sh mamba_quick
./common/submit.sh mamba_camels_us
./common/submit.sh caravan

# Check logs
./common/logs.sh
./common/logs.sh tail mamba_quick
```

