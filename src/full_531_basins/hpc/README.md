# Full 531 Basins HPC Scripts

This folder stores HPC scripts for idea `05_full_531_basins`.

## Active Files

- `hpc_quick_test.slurm`: quick validation run on HPC.
- `hpc_full_training.slurm`: full training run on HPC.
- `hpc_deploy.sh`: convenience deploy/submit helper.
- `setup_hpc_environment.sh`: environment bootstrap script on HPC.

## Legacy/Optional Helpers

- `hpc_optimized_config.py`
- `hpc_slurm_job.sh`
- `setup_permissions.bat`

These helpers are kept for reference or local workflow support.

## Recommended Commands

```bash
# Setup
bash src/full_531_basins/hpc/setup_hpc_environment.sh

# Submit jobs
sbatch src/full_531_basins/hpc/hpc_quick_test.slurm
sbatch src/full_531_basins/hpc/hpc_full_training.slurm
```
