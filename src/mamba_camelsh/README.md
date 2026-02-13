# Mamba CAMELS-H Hourly Hydrological Modeling (HPC)

This directory contains the HPC deployment configuration for Mamba-based hourly streamflow prediction on CAMELS-H dataset.

## Directory Structure

```
src/mamba_camelsh/
├── __init__.py
├── README.md
├── configs/
│   ├── camelsh_mini.yml       # Mini benchmark (50 basins, 10 epochs, seq=168)
│   ├── camelsh_full.yml       # Full training (all basins, 30 epochs, seq=336)
│   ├── camelsh_longseq.yml    # Long sequence test (50 basins, 10 epochs, seq=3000)
│   └── camelsh_lstm_mini.yml  # Isolated LSTM baseline config
├── data/
│   └── test_50_basins.txt     # 50 basins subset for mini/longseq experiments
└── hpc/
    ├── submit_mini.slurm      # Mini benchmark SLURM script
    ├── submit_full.slurm      # Full training SLURM script
    ├── submit_longseq.slurm   # Long sequence test SLURM script
    └── submit_lstm_mini.slurm # LSTM mini baseline SLURM script
```

## Quick Start

### 1. Local Preparation (Windows)

All files are already prepared. Verify the structure:

```bash
# Check directory structure
ls -R src/mamba_camelsh/
```

### 2. HPC Deployment

#### Step 1: Check CAMELS-H Data on HPC

SSH to HPC and verify data exists:

```bash
# Check common data locations
ls -la ~/neuralhydrology/data/camelsh/
ls -la /data1/home/$USER/neuralhydrology/data/camelsh/
```

If data doesn't exist, upload it using WinSCP or rsync (approximately 50GB+).

#### Step 2: Sync Files to HPC (WinSCP)

Sync the entire `src/mamba_camelsh/` directory to HPC:
- Local: `src/mamba_camelsh/`
- HPC: `~/neuralhydrology/src/mamba_camelsh/`

#### Step 3: Fix Line Endings and Submit

On HPC terminal:

```bash
cd ~/neuralhydrology

# Fix Windows line endings (CRITICAL!)
sed -i 's/\r$//' src/mamba_camelsh/hpc/*.slurm

# Create log directories
mkdir -p logs/03_mamba_camelsh results/03_mamba_camelsh

# Submit Mini benchmark (start with this for validation)
/usr/local/globle/softs/slurm/19.05.4.1/bin/sbatch src/mamba_camelsh/hpc/submit_mini.slurm
```

> Note: On this HPC, `sbatch` may be aliased to `xbatch`. Use the full real sbatch path above to avoid wrapper-side submission issues.

### 3. Monitor Jobs

```bash
# Check job status
squeue -u $USER

# View logs (replace JOBID with actual job ID)
tail -f logs/03_mamba_camelsh/JOBID.out
tail -f logs/03_mamba_camelsh/JOBID.err

# Cancel job if needed
scancel <JOBID>
```

## Experiment Phases

| Phase | Config | SLURM Script | Time Limit | Purpose |
|-------|--------|--------------|------------|---------|
| **Mini** | `camelsh_mini.yml` | `submit_mini.slurm` | 48h | Validate HPC environment |
| **LSTM-mini** | `camelsh_lstm_mini.yml` | `submit_lstm_mini.slurm` | 24h | Isolated baseline comparison |
| **Full** | `camelsh_full.yml` | `submit_full.slurm` | 168h | Full benchmark vs LSTM |
| **Long-seq** | `camelsh_longseq.yml` | `submit_longseq.slurm` | 120h | Demonstrate Mamba's O(N) advantage |

## Data Filtering (Training-Ready Basins)

To ensure stable hourly training, basins were filtered with this rule:
- **2010–2020** hourly coverage **>= 95%** for **every year** (8760/8784 hours)
- Basin appears in `available_basins.txt`
- Basin has an hourly `.nc` time series file

Filtered lists are stored in:
`src/mamba_camelsh/data/filtered/`

Main outputs:
- `filtered_basins_2010_2020_95pct.txt`
- `train_basins_2010_2020_95pct.txt`
- `val_basins_2010_2020_95pct.txt`
- `test_basins_2010_2020_95pct.txt`
- `summary_2010_2020_95pct.md`

The **Full** config already uses these filtered train/val/test lists.

## Key Configuration Differences (Local vs HPC)

| Parameter | Local (Windows) | HPC |
|-----------|----------------|-----|
| `device` | `cpu` | `cuda:0` |
| `batch_size` | `16` | `128` (mini) / `256` (full) |
| `num_workers` | `0` | `4` |
| `data_dir` | `data\camelsh` | `data/camelsh` |
| `train_basin_file` | `src/mamba_camelsh/data/...` | `src/mamba_camelsh/data/...` |

## Mamba Backend

The scripts automatically detect available Mamba backend:

1. **mamba_ssm** (preferred): Fast CUDA kernel, 10-50x faster
   - Install: `bash hpc/install_mamba_ssm.sh` (on HPC)
   
2. **transformers** (fallback): HuggingFace implementation, slower but universal
   - Already available if `transformers>=4.39` is installed

The scripts will use whichever backend is available and print a warning if only the slower backend is available.

## Results Location

All results will be saved to:
- **Training outputs**: `results/03_mamba_camelsh/<experiment_name>/`
- **SLURM logs**: `logs/03_mamba_camelsh/<JOBID>.out` and `.err`

**Note**: The `03_` prefix follows the project's naming convention:
- `01_caravan_global` - Caravan global daily model
- `02_mamba_camels_us` - Mamba CAMELS-US daily model
- `03_mamba_camelsh` - Mamba CAMELS-H hourly model (this project)

## Troubleshooting

### Job Fails Immediately (No Logs)
- **Cause**: Windows line endings (CRLF)
- **Fix**: Run `sed -i 's/\r$//' src/mamba_camelsh/hpc/*.slurm` on HPC

### FileNotFoundError: Data Path
- **Cause**: Wrong data directory path or case sensitivity
- **Fix**: Verify `data_dir: data/camelsh` in config (Linux is case-sensitive)

### OOM (Out of Memory)
- **Cause**: Batch size too large for GPU memory
- **Fix**: Reduce `batch_size` in config (e.g., 256 → 128)

### MKL/iJIT_NotifyEvent Error
- **Cause**: MKL threading conflict
- **Fix**: Already handled in SLURM scripts with `export MKL_THREADING_LAYER=GNU`

## Next Steps After Mini Benchmark

1. **If Mini succeeds**: Submit Full training for complete benchmark
2. **If performance is slow**: Install `mamba_ssm` CUDA kernel for 10-50x speedup
3. **If Full succeeds**: Submit Long-seq test to demonstrate Mamba's advantage

## Related Documentation

- Task Isolation Rules: `src/mamba_camelsh/TASK_ISOLATION.md`
- HPC Workflow Guide: `HPC_WORKFLOW_FINAL.md`
- Mamba Research: `src/mamba_camelsh/docs/MAMBA_RESEARCH.md`
- Mamba HPC Setup: `hpc/README_MAMBA.md`
