# Environment Files

This directory keeps conda environment definitions.

## Recommended
- `environment_cpu.yml`: standard CPU environment.
- `environment_cuda11_8.yml`: standard GPU environment (CUDA 11.8).

## Optional
- `environment_gpu_clean.yml`: lightweight local variant (`nh-gpu`), useful for fast local setup.

## Usage
```bash
# CPU
conda env create -f environments/environment_cpu.yml

# GPU (CUDA 11.8)
conda env create -f environments/environment_cuda11_8.yml
```

For pip-based install, dependency source is consolidated:
- shared: `requirements-base.txt`
- CPU entry: `requirements-cpu.txt`
- GPU entry: `requirements-gpu.txt`
- default entry: `requirements.txt` (points to CPU)

Notes:
- `environment_cpu.yml` and `environment_cuda11_8.yml` are the recommended conda env files.
- `environment_gpu_clean.yml` is a local lightweight variant and optional.
