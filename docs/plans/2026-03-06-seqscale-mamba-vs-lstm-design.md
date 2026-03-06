# Phase 2v3: Sequence Length Scaling -- Mamba vs LSTM

**Date**: 2026-03-06
**Idea**: 41 (MTS-Mamba Global Transfer)
**Status**: Ready for HPC submission

## Research Question

At what sequence length does Mamba outperform LSTM for hourly streamflow prediction?

Phase 2v2 showed MTSMamba ≈ MTSLSTM at seq=336h (14 days). Mamba's theoretical advantage is on longer sequences where LSTM suffers gradient vanishing. This experiment systematically varies sequence length to find the crossover point.

## Experiment Matrix

| seq_length | abs. duration | CudaLSTM | Mamba |
|------------|---------------|----------|-------|
| 336h       | 14 days       | run      | run   |
| 720h       | 30 days       | run      | run   |
| 1440h      | 60 days       | run      | run   |
| 2160h      | 90 days       | run      | run   |
| 4320h      | 180 days      | run      | run   |

**Total: 10 HPC jobs** (all single-frequency hourly)

## Controlled Variables

- 10 CAMELS-Hourly basins (same as Phase 2v2)
- Train: 2000-2015, Val: 2016-2018, Test: 2019-2020
- hidden_size=64, epochs=10, batch_size=256
- predict_last_n=24 (always predict last 24 hours)
- 11 dynamic + 13 static features
- seed=111

## Files

```
src/mts_mamba_global_transfer/
├── configs/seqscale/           # 10 YAML configs
│   ├── seqscale_cudalstm_{336,720,1440,2160,4320}h.yml
│   └── seqscale_mamba_{336,720,1440,2160,4320}h.yml
├── hpc/
│   ├── submit_seqscale.slurm   # Parameterized SLURM script
│   └── submit_all_seqscale.sh  # Submit all 10 jobs
└── scripts/
    └── compare_seqscale.py     # Results comparison + crossover analysis
```

## HPC Sync Checklist

### Submit (local -> HPC)
```bash
# 1. LOCAL: commit and push
git add src/mts_mamba_global_transfer/configs/seqscale/ \
        src/mts_mamba_global_transfer/hpc/submit_seqscale.slurm \
        src/mts_mamba_global_transfer/hpc/submit_all_seqscale.sh \
        src/mts_mamba_global_transfer/scripts/compare_seqscale.py
git commit -m "feat(41): add Phase 2v3 seq-length scaling configs and HPC scripts"
git push origin master

# 2. HPC: pull and submit
cd ~/neuralhydrology
git pull origin master
sed -i 's/\r$//' src/mts_mamba_global_transfer/hpc/submit_seqscale.slurm
sed -i 's/\r$//' src/mts_mamba_global_transfer/hpc/submit_all_seqscale.sh
bash src/mts_mamba_global_transfer/hpc/submit_all_seqscale.sh
```

### Collect (HPC -> local)
```bash
# 3. HPC: commit results and push
cd ~/neuralhydrology
git add results/41_mts_mamba_global_transfer/41_seqscale_*/
git commit -m "feat(41): add Phase 2v3 seq-length scaling results"
git push origin master

# 4. LOCAL: pull and compare
git pull origin master
python src/mts_mamba_global_transfer/scripts/compare_seqscale.py
```

## Expected Outcomes

- **If crossover found**: Mamba > LSTM beyond N hours → paper contribution: "SSMs outperform RNNs for long-range hydrological modeling"
- **If no crossover**: LSTM robust across all lengths → Mamba not suitable for hydrology at these scales, consider extending to 8760h (1 year)

## Risk: GPU OOM at long sequences

seq=4320h with batch=256 may OOM. If so, reduce batch_size in the config and re-submit that specific job.
