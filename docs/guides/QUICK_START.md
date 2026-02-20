# NeuralHydrology Quick Start

## 1. Environment

```bash
conda create -n neuralhydrology python=3.10 -y
conda activate neuralhydrology

# choose one dependency set
pip install -r requirements-gpu.txt
# or
pip install -r requirements-cpu.txt
```

## 2. Sanity Check

```python
import torch
print(torch.__version__)
print(torch.cuda.is_available())
```

## 3. Run a Small Test

```bash
python -m neuralhydrology.nh_run train --config-file src/test_data/configs/quick_test.yml --gpu 0
# CPU only
python -m neuralhydrology.nh_run train --config-file src/test_data/configs/quick_test.yml --gpu -1
```

## 4. Run Idea Configs

```bash
# Mamba CAMELS-US quick run
python -m neuralhydrology.nh_run train --config-file src/mamba_camels_us/configs/mamba_daily_quick.yml --gpu 0

# Full 531 baseline (long run)
python -m neuralhydrology.nh_run train --config-file src/full_531_basins/configs/camels_us/full_training/full_training_531_temporal_with_static.yml --gpu 0
```

## 5. Inspect Outputs

- Prefer idea-owned output folders in `results/<ID>_<idea>/`.
- If a config still writes to `runs/`, use that path as transitional output.

TensorBoard:

```bash
tensorboard --logdir results
```

## Next

- `INSTALLATION_GUIDE.md`
- `DATA_USAGE_GUIDE.md`
- `../hpc/HPC_QUICK_START.md` (for cluster execution)