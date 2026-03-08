# Adversarial Robustness Full Experiment Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Scale adversarial robustness evaluation from 15 pilot basins to all 540 CAMELS-US training basins on HPC, producing publication-ready results for a WRR/HESS paper.

**Architecture:** Refactor the existing runner to support chunked HPC execution (SLURM array jobs), then run 5 experiment blocks covering the full attack × constraint × target matrix. A merge + analysis pipeline produces tables and figures.

**Tech Stack:** PyTorch, neuralhydrology, SLURM, matplotlib/seaborn, CAMELS-US dataset on HPC

---

## Background & Current State

### What Exists
- 10 attack methods (APGD, FGSM, C&W, CausalTrigger, Spectral, Sparse, UAP, Gaussian, MultBias, TempCorr)
- 3 constraint levels (Lp, Physical, Statistical)
- 3 attack targets (untargeted, flood, lowflow)
- 56 passing tests in `test/test_adversarial/`
- Pilot v3: 15 basins × 7 methods × 3 ε = 315 results (JSON)
- Target model: CudaLSTM 128h, 50ep, daymet 5-feature, trained on 539 CAMELS-US basins

### Key Pilot Timing (CPU, per basin-sample)
| Method | Time | Type |
|--------|------|------|
| FGSM | 0.1s | single-step |
| Gaussian/MultBias/TempCorr | 0.2-0.3s | non-gradient |
| AutoPGD (50 iter) | 3.0s | iterative |
| CausalTrigger (100 iter) | 7.0s | iterative |
| Spectral (100 iter) | ~7s | iterative |
| C&W (200 iter × 5 binary search) | 74s | optimization |

### File Locations
- Code: `src/adversarial/`
- Config: `src/adversarial/configs/adversarial_eval.yaml`
- Runner: `src/adversarial/scripts/run_adversarial_eval.py`
- Model: `results/05_full_531_basins/full_training_nse_2025_1025_1821_ep50`
- Basin splits: `src/full_531_basins/data/splits/`
- Pilot results: `results/adversarial_eval/pilot_v3_*.json`
- Tests: `test/test_adversarial/`

---

## Experiment Design

### Paper Table/Figure → Experiment Mapping

| Paper Element | Experiment | Methods | ε values | Constraint | Target | Basins |
|---|---|---|---|---|---|---|
| **Table 1: Core comparison** | Exp 1 | APGD, FGSM, Gauss, MultBias, TempCorr | 0.01, 0.05, 0.1, 0.2 | lp | untargeted | 540 |
| **Figure 1: ε–ΔNSE curve** | from Exp 1 | — | — | — | — | — |
| **Figure 2: Basin vulnerability map** | from Exp 1 | APGD @ ε=0.1 | — | — | — | — |
| **Table 2: Constraint ablation** | Exp 2 | APGD | 0.05, 0.1, 0.2 | lp, phys, stat | untargeted | 540 |
| **Table 3: Targeted attacks** | Exp 3 | APGD | 0.1 | lp | untarg, flood, lowflow | 540 |
| **Figure 3: Causal window** | Exp 4 | CausalTrigger | 0.1 | lp | untargeted | 540 |
| **Figure 4: Min perturbation (C&W)** | Exp 5 | C&W | 0.1 | lp | untargeted | 540 |
| **Figure 5: Detectability** | from all | KS-test p-values | — | — | — | — |

### Timing Budget (CPU, 1 sample/basin)

| Experiment | Formula | Serial Time | 10-way Parallel |
|---|---|---|---|
| Exp 1 | 5 methods × 4 ε × 540 × avg 2.5s | 27,000s ≈ 7.5h | ~45min |
| Exp 2 | 3 ε × 3 constraints × 540 × 3s | 14,580s ≈ 4h | ~24min |
| Exp 3 | 3 targets × 540 × 3s | 4,860s ≈ 1.4h | ~8min |
| Exp 4 | 4 windows × 540 × 7s | 15,120s ≈ 4.2h | ~25min |
| Exp 5 | 540 × 74s | 39,960s ≈ 11h | ~66min |
| **Total** | | **~28h serial** | **~2.7h parallel** |

### Decision: n_samples per basin

Pilot 用了 5 samples/basin（15 basins 共 75 个点），统计量有限。
Full experiment 用 540 basins × **1 sample/basin**，统计量来自流域间变异（540 个独立点），已足够。

若审稿人要求 within-basin robustness，后续可跑 subset 50 basins × 5 samples 作 supplementary。

---

## Implementation Tasks

### Task 1: Refactor Runner for HPC Chunked Execution

**Files:**
- Modify: `src/adversarial/scripts/run_adversarial_eval.py`
- Modify: `src/adversarial/configs/adversarial_eval.yaml`

**目标**: 支持 `--basin-file`, `--basin-range`, `--output-suffix`, 逐流域处理（不一次性缓存 540 流域到内存）

**Step 1: Add `--basin-file` and `--basin-range` CLI args**

在 `main()` 的 argparse 中增加：
```python
parser.add_argument("--basin-file", default=None, help="Text file with basin IDs, one per line")
parser.add_argument("--basin-range", default=None, help="Start:end index for chunked execution, e.g. 0:50")
parser.add_argument("--output-suffix", default=None, help="Suffix for output filename, e.g. 'chunk_00'")
parser.add_argument("--n-samples", type=int, default=1, help="Samples per basin")  # 默认改为 1
```

Basin resolution 逻辑：
```python
# Resolve basins
if args.basin:
    basins = [args.basin]
elif args.basin_file:
    with open(args.basin_file) as f:
        basins = [line.strip() for line in f if line.strip()]
else:
    basins = cfg["data"]["basins"]

# Apply range filter
if args.basin_range:
    start, end = map(int, args.basin_range.split(":"))
    basins = basins[start:end]
```

**Step 2: Change basin loading from cache-all to one-at-a-time**

当前 runner 一次性把所有 basin 数据加载到 `basin_cache` dict。540 basins 的内存可能过大。改为在循环内逐 basin 加载 + 释放：

```python
# 外层循环改为 basin-first（当前是 attack-first）
for basin_id in basins:
    logger.info(f"Loading basin {basin_id}...")
    x_d, x_s, y_obs = load_basin_data(...)
    sample_indices = select_basin_samples(x_d, x_s, y_obs, n_samples=args.n_samples)
    with torch.no_grad():
        y_cleans = {i: wrapper.forward(x_d[i:i+1], x_s[i:i+1]) for i in sample_indices}

    for attack_name in attacks_to_run:
        for epsilon in epsilons:
            # ... run attack ...
            all_results.append(record)

    # Free memory
    del x_d, x_s, y_obs, y_cleans
```

**Step 3: Support `--output-suffix` for per-chunk output**

```python
if args.output_suffix:
    results_file = output_dir / f"results_{args.output_suffix}.json"
else:
    results_file = output_dir / "results.json"
```

**Step 4: Add incremental save (每 100 个 basin 写一次)**

```python
if len(all_results) % 100 == 0:
    _save_checkpoint(all_results, results_file)
```

**Step 5: Run existing tests**

```bash
pytest test/test_adversarial/ -x -q
```
Expected: All 56 tests PASS (refactor does not change attack logic).

**Step 6: Commit**

```bash
git add src/adversarial/scripts/run_adversarial_eval.py
git commit -m "feat(adversarial): refactor runner for HPC chunked execution"
```

---

### Task 2: Create Full Experiment Config + Basin List

**Files:**
- Create: `src/adversarial/configs/full_eval.yaml`
- Create: `src/adversarial/data/train_540_basins.txt` (copy from splits)

**Step 1: Copy basin list**

```bash
cp src/full_531_basins/data/splits/full_674_basins_train_basins.txt \
   src/adversarial/data/train_540_basins.txt
```

**Step 2: Create `full_eval.yaml`**

```yaml
model:
  run_dir: "results/05_full_531_basins/full_training_nse_2025_1025_1821_ep50"
  device: "cuda:0"

data:
  data_dir: "data/CAMELS_US"  # HPC 上调整为实际路径
  period: "test"
  basin_file: "src/adversarial/data/train_540_basins.txt"

experiments:
  # Exp 1: Core attack comparison (Table 1 + Figure 1-2)
  exp1_core:
    attacks: [auto_pgd, fgsm, gaussian_noise, multiplicative_bias, temporal_correlated_noise]
    epsilons: [0.01, 0.05, 0.1, 0.2]
    constraint_levels: [lp]
    targets: [untargeted]

  # Exp 2: Constraint ablation (Table 2)
  exp2_constraint:
    attacks: [auto_pgd]
    epsilons: [0.05, 0.1, 0.2]
    constraint_levels: [lp, physical, statistical]
    targets: [untargeted]

  # Exp 3: Targeted attacks (Table 3)
  exp3_target:
    attacks: [auto_pgd]
    epsilons: [0.1]
    constraint_levels: [lp]
    targets: [untargeted, flood, lowflow]

  # Exp 4: Causal trigger window (Figure 3)
  exp4_causal:
    attacks: [causal_trigger]
    epsilons: [0.1]
    constraint_levels: [lp]
    targets: [untargeted]

  # Exp 5: C&W minimum perturbation (Figure 4)
  exp5_cw:
    attacks: [cw_regression]
    epsilons: [0.1]
    constraint_levels: [lp]
    targets: [untargeted]

attack_params:
  auto_pgd: {n_iter: 50, n_restarts: 1}
  fgsm: {}
  gaussian_noise: {}
  multiplicative_bias: {}
  temporal_correlated_noise: {}
  causal_trigger: {pre_windows: [1, 3, 7, 14], n_iter: 100}
  cw_regression: {n_iter: 200, target_nse: 0.0, lr: 0.01, binary_search_steps: 5}

output_dir: "results/adversarial_eval/full"
```

**Step 3: Commit**

```bash
git add src/adversarial/configs/full_eval.yaml src/adversarial/data/train_540_basins.txt
git commit -m "feat(adversarial): add full experiment config and 540-basin list"
```

---

### Task 3: Create SLURM Submission Scripts

**Files:**
- Create: `src/adversarial/hpc/submit_exp1.slurm`
- Create: `src/adversarial/hpc/submit_exp5_cw.slurm`
- Create: `src/adversarial/hpc/submit_all.sh`

**Step 1: Create Exp 1-4 array job (fast/medium methods)**

```bash
#!/bin/bash
#SBATCH --job-name=adv-exp1
#SBATCH --partition=hgpu8
#SBATCH --gres=gpu:1
#SBATCH --cpus-per-task=4
#SBATCH --mem=16G
#SBATCH --time=02:00:00
#SBATCH --array=0-10
#SBATCH --output=logs/05_adversarial/exp1_%a.out
#SBATCH --error=logs/05_adversarial/exp1_%a.err

# 540 basins / 11 chunks ≈ 50 basins per chunk
CHUNK_SIZE=50
START=$((SLURM_ARRAY_TASK_ID * CHUNK_SIZE))
END=$((START + CHUNK_SIZE))

cd ~/neuralhydrology

python -m src.adversarial.scripts.run_adversarial_eval \
    --config src/adversarial/configs/full_eval.yaml \
    --basin-file src/adversarial/data/train_540_basins.txt \
    --basin-range ${START}:${END} \
    --n-samples 1 \
    --output-suffix "exp1_chunk_$(printf '%02d' $SLURM_ARRAY_TASK_ID)"
```

**Step 2: Create C&W separate job (slow method)**

```bash
#!/bin/bash
#SBATCH --job-name=adv-cw
#SBATCH --partition=hgpu8
#SBATCH --gres=gpu:1
#SBATCH --cpus-per-task=4
#SBATCH --mem=16G
#SBATCH --time=04:00:00
#SBATCH --array=0-10
#SBATCH --output=logs/05_adversarial/cw_%a.out
#SBATCH --error=logs/05_adversarial/cw_%a.err

CHUNK_SIZE=50
START=$((SLURM_ARRAY_TASK_ID * CHUNK_SIZE))
END=$((START + CHUNK_SIZE))

cd ~/neuralhydrology

python -m src.adversarial.scripts.run_adversarial_eval \
    --config src/adversarial/configs/full_eval.yaml \
    --attack cw_regression \
    --basin-file src/adversarial/data/train_540_basins.txt \
    --basin-range ${START}:${END} \
    --n-samples 1 \
    --output-suffix "cw_chunk_$(printf '%02d' $SLURM_ARRAY_TASK_ID)"
```

**Step 3: Create master submission script**

```bash
#!/bin/bash
# submit_all.sh — submit all adversarial experiments
mkdir -p logs/05_adversarial

JOB1=$(sbatch --parsable src/adversarial/hpc/submit_exp1.slurm)
echo "Exp 1-4 submitted: $JOB1"

JOB2=$(sbatch --parsable src/adversarial/hpc/submit_exp5_cw.slurm)
echo "Exp 5 C&W submitted: $JOB2"

echo "Monitor: squeue -u $USER"
```

**Step 4: Commit**

```bash
git add src/adversarial/hpc/
git commit -m "feat(adversarial): add SLURM submission scripts for full experiment"
```

---

### Task 4: Create Results Merge Script

**Files:**
- Create: `src/adversarial/scripts/merge_results.py`

**Step 1: Write merge script**

```python
"""Merge per-chunk adversarial results into a single JSON."""
import argparse
import json
from pathlib import Path

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--input-dir", required=True, help="Directory with chunk result files")
    parser.add_argument("--pattern", default="results_*.json", help="Glob pattern for chunk files")
    parser.add_argument("--output", required=True, help="Output merged JSON path")
    args = parser.parse_args()

    input_dir = Path(args.input_dir)
    all_results = []
    files = sorted(input_dir.glob(args.pattern))
    for f in files:
        with open(f) as fh:
            chunk = json.load(fh)
        print(f"  {f.name}: {len(chunk)} records")
        all_results.extend(chunk)

    # Deduplicate by (attack, epsilon, constraint, target, basin, sample_idx)
    seen = set()
    unique = []
    for r in all_results:
        key = (r["attack"], r["epsilon"], r.get("constraint", "lp"),
               r.get("target", "untargeted"), r["basin"], r["sample_idx"])
        if key not in seen:
            seen.add(key)
            unique.append(r)

    with open(args.output, "w") as f:
        json.dump(unique, f, indent=2)
    print(f"Merged {len(unique)} unique records from {len(files)} files -> {args.output}")

if __name__ == "__main__":
    main()
```

**Step 2: Write test**

```python
# test/test_adversarial/test_merge_results.py
def test_merge_deduplicates(tmp_path):
    import json
    from src.adversarial.scripts.merge_results import main
    # Create 2 chunk files with overlap
    chunk1 = [{"attack": "fgsm", "epsilon": 0.1, "basin": "01", "sample_idx": 0, "delta_nse": -0.1}]
    chunk2 = [{"attack": "fgsm", "epsilon": 0.1, "basin": "01", "sample_idx": 0, "delta_nse": -0.1},
              {"attack": "fgsm", "epsilon": 0.1, "basin": "02", "sample_idx": 0, "delta_nse": -0.2}]
    (tmp_path / "results_chunk_00.json").write_text(json.dumps(chunk1))
    (tmp_path / "results_chunk_01.json").write_text(json.dumps(chunk2))

    output = tmp_path / "merged.json"
    import sys
    sys.argv = ["merge", "--input-dir", str(tmp_path), "--output", str(output)]
    main()

    merged = json.loads(output.read_text())
    assert len(merged) == 2  # deduplicated
```

**Step 3: Commit**

```bash
git add src/adversarial/scripts/merge_results.py test/test_adversarial/test_merge_results.py
git commit -m "feat(adversarial): add results merge script with deduplication"
```

---

### Task 5: Create Analysis & Plotting Script

**Files:**
- Create: `src/adversarial/scripts/analyze_results.py`

**Step 1: Write analysis script**

生成以下输出：
1. **Table 1**: Attack comparison (ΔNSE mean ± std per method × ε)
2. **Table 2**: Constraint ablation
3. **Table 3**: Targeted attack comparison
4. **Figure 1**: ε–ΔNSE curves (line plot, one line per method)
5. **Figure 2**: Basin vulnerability map (scatter plot on CONUS, color = ΔNSE)
6. **Figure 3**: Causal trigger window analysis (bar chart)
7. **Figure 4**: C&W minimum perturbation distribution (histogram)
8. **Figure 5**: Detectability KS p-values vs ΔNSE

核心函数：
```python
def load_results(path: str) -> pd.DataFrame:
    """Load JSON results into DataFrame."""

def table_attack_comparison(df: pd.DataFrame) -> pd.DataFrame:
    """Pivot: rows=method, cols=epsilon, values=mean ΔNSE."""

def table_constraint_ablation(df: pd.DataFrame) -> pd.DataFrame:
    """Pivot: rows=constraint, cols=epsilon, values=mean ΔNSE (APGD only)."""

def fig_epsilon_curve(df: pd.DataFrame, output_path: Path):
    """Line plot: x=epsilon, y=mean ΔNSE, one line per method."""

def fig_basin_vulnerability_map(df: pd.DataFrame, attr_path: Path, output_path: Path):
    """Scatter map: longitude × latitude, color = ΔNSE for APGD@ε=0.1."""

def fig_causal_window(df: pd.DataFrame, output_path: Path):
    """Bar chart: x=pre_window days, y=mean ΔNSE."""

def fig_cw_distribution(df: pd.DataFrame, output_path: Path):
    """Histogram: L2 perturbation norm from C&W results."""
```

**Step 2: Commit**

```bash
git add src/adversarial/scripts/analyze_results.py
git commit -m "feat(adversarial): add analysis and plotting pipeline"
```

---

### Task 6: Local Smoke Test (Before HPC Submission)

**Step 1: Run dry-run to validate config**

```bash
python src/adversarial/scripts/run_adversarial_eval.py \
    --config src/adversarial/configs/full_eval.yaml \
    --basin-file src/adversarial/data/train_540_basins.txt \
    --basin-range 0:2 \
    --attack fgsm \
    --epsilon 0.1 \
    --n-samples 1 \
    --dry-run
```

Expected: Print experiment matrix "1 attacks x 1 eps x ... x 2 basins" and exit.

**Step 2: Run 2-basin smoke test**

```bash
python src/adversarial/scripts/run_adversarial_eval.py \
    --config src/adversarial/configs/full_eval.yaml \
    --basin-file src/adversarial/data/train_540_basins.txt \
    --basin-range 0:2 \
    --attack fgsm \
    --epsilon 0.1 \
    --n-samples 1 \
    --output-suffix smoke_test
```

Expected: `results/adversarial_eval/full/results_smoke_test.json` with 2 records.

**Step 3: Run 2-basin APGD smoke test**

```bash
python src/adversarial/scripts/run_adversarial_eval.py \
    --config src/adversarial/configs/full_eval.yaml \
    --basin-file src/adversarial/data/train_540_basins.txt \
    --basin-range 0:2 \
    --attack auto_pgd \
    --epsilon 0.1 \
    --n-samples 1 \
    --output-suffix smoke_apgd
```

Expected: JSON with 2 records, ΔNSE should be negative.

---

### Task 7: HPC Deployment & Execution

**Step 1: Sync to HPC**

```bash
# 从 WSL（记住 Windows 本机不支持 ControlMaster）
rsync -avz --exclude '.git' --exclude 'results/4*' --exclude '__pycache__' \
    /mnt/g/github/pycharm/projects/neuralhydrology/ \
    sunyiq@hpcbh.hhu.edu.cn:~/neuralhydrology/
```

**Step 2: Verify on HPC**

```bash
ssh sunyiq@hpcbh.hhu.edu.cn
cd ~/neuralhydrology
python src/adversarial/scripts/run_adversarial_eval.py \
    --config src/adversarial/configs/full_eval.yaml \
    --basin-file src/adversarial/data/train_540_basins.txt \
    --basin-range 0:2 --attack fgsm --epsilon 0.1 --n-samples 1 \
    --output-suffix hpc_smoke --dry-run
```

**Step 3: Submit jobs**

```bash
bash src/adversarial/hpc/submit_all.sh
squeue -u sunyiq
```

**Step 4: Monitor**

```bash
# 检查进度
tail -f logs/05_adversarial/exp1_0.out
# 检查错误
cat logs/05_adversarial/exp1_0.err
```

---

### Task 8: Collect Results & Generate Paper Figures

**Step 1: Download results from HPC**

```bash
rsync -avz sunyiq@hpcbh.hhu.edu.cn:~/neuralhydrology/results/adversarial_eval/full/ \
    /mnt/g/github/pycharm/projects/neuralhydrology/results/adversarial_eval/full/
```

**Step 2: Merge chunks**

```bash
python src/adversarial/scripts/merge_results.py \
    --input-dir results/adversarial_eval/full \
    --output results/adversarial_eval/full/merged_all.json
```

**Step 3: Generate tables and figures**

```bash
python src/adversarial/scripts/analyze_results.py \
    --input results/adversarial_eval/full/merged_all.json \
    --output-dir results/adversarial_eval/full/figures
```

**Step 4: Commit results and figures**

```bash
git add results/adversarial_eval/full/merged_all.json results/adversarial_eval/full/figures/
git commit -m "results(adversarial): full 540-basin experiment results and figures"
```

---

## Risk & Mitigation

| Risk | Impact | Mitigation |
|---|---|---|
| HPC 上 CAMELS_US 数据路径不同 | 所有 job 失败 | config 中 `data_dir` 可 override；先跑 2-basin smoke |
| 某些 basin 数据质量差导致 NaN | 单个 basin crash | runner 已有 NaN mask；增加 try-except per-basin |
| C&W 74s/basin × 540 = 11h 超 wall time | 需更多 chunks | 把 540 拆成 20 chunks (27 basins/chunk)，每 chunk ~33min |
| GPU 内存不足 | 切回 CPU | CudaLSTM 128h 极小，不应该 OOM；config 设 `device: cpu` 兜底 |
| 审稿人要求更多 sample/basin | 需要追加实验 | 选 50 个代表性 basin × 5 samples 作 supplement |

---

## 不做的事

1. **不跑 Spectral / SparseTemp / UAP** — pilot 显示它们与 APGD 的对比价值不大，保留在 supplement 即可
2. **不做防御 baseline** — 对抗训练/输入平滑是独立实验，可在审稿后补充
3. **不用 test basins (67个)** — in-distribution 评估已足够；out-of-distribution 可作 supplement
4. **不写论文** — 本 plan 只覆盖到 figures，写作是下一步
