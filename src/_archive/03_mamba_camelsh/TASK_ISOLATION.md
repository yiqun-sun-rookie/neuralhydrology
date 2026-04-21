# Task Isolation Rules (Mamba CAMELS-H)

This file defines isolation boundaries for the CAMELS-H hourly Mamba task in this conversation.

## 1) Code Isolation

- All task-specific code/config/scripts live under `src/mamba_camelsh/`.
- LSTM baseline config for this task is isolated at:
  - `src/mamba_camelsh/configs/camelsh_lstm_mini.yml`
- Do not depend on `src/mamba_camelsh/configs/camelsh_lstm_mini.yml` for this task anymore.

## 2) Result and Log Isolation

- All outputs for this task are written to:
  - `results/03_mamba_camelsh/`
- All SLURM logs for this task are written to:
  - `logs/03_mamba_camelsh/`
- Analysis outputs are written to:
  - `results/03_mamba_camelsh/analysis/`

## 3) Data List Isolation

- Basin lists used by this task are under:
  - `src/mamba_camelsh/data/`
  - `src/mamba_camelsh/data/filtered/`
- This avoids coupling with basin lists in other experiment directories.

## 4) HPC Submission Isolation

On this HPC, `sbatch` may be aliased to `xbatch`. Use the real binary:

```bash
/usr/local/globle/softs/slurm/19.05.4.1/bin/sbatch src/mamba_camelsh/hpc/submit_mini.slurm
/usr/local/globle/softs/slurm/19.05.4.1/bin/sbatch src/mamba_camelsh/hpc/submit_lstm_mini.slurm
/usr/local/globle/softs/slurm/19.05.4.1/bin/sbatch src/mamba_camelsh/hpc/submit_full.slurm
/usr/local/globle/softs/slurm/19.05.4.1/bin/sbatch src/mamba_camelsh/hpc/submit_longseq.slurm
```

## 5) Cross-platform Line Endings

- Before submitting on HPC, normalize line endings:

```bash
sed -i 's/\r$//' src/mamba_camelsh/hpc/*.slurm
```

- Repository-level guard is enabled via `.gitattributes`:
  - `*.slurm text eol=lf`
  - `*.sh text eol=lf`

## 6) Naming Convention

- This task uses project prefix `03_` to separate from:
  - `01_caravan_global`
  - `02_mamba_camels_us`
  - `03_mamba_camelsh` (this task)
