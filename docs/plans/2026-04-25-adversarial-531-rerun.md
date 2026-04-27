# 531 Benchmark Adversarial Rerun Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Run a fresh adversarial evaluation suite on the local 531-basin temporal benchmark model without modifying or reusing the existing 520/674 result tree.

**Architecture:** Reuse the existing `src/adversarial` attack runner, but isolate the rerun behind a new config, a new output root, and a pinned checkpoint. The cheapest safe path is to add explicit checkpoint selection to the adversarial wrapper/runner, use the existing local 531 model directory as the victim model source, smoke-test on 2 basins, then execute the expensive experiment blocks in phases.

**Tech Stack:** `neuralhydrology`, PyTorch, YAML configs, existing `src/adversarial` scripts, JSON result chunks, local PowerShell and optional SLURM/HPC submission.

---

## Context You Must Preserve

- Do **not** modify or overwrite anything under `results/adversarial_eval/full/`.
- Do **not** rewrite the current manuscript to use 531 results until the new run is complete and audited.
- The victim model source is the existing local run:
  - `results/05_adversarial_robustness/runs/reproduce_531_nse074_2025_1129_2145_ep30`
- The canonical 531 basin list already exists:
  - `src/adversarial/data/531_basins.txt`
- The current adversarial runner loads the **latest** checkpoint by default. If left unchanged, it will silently use `model_epoch030.pt`.
- The cleanest reproducible choice is to pin `model_epoch020.pt`, because it is a saved checkpoint with archived full test output and the strongest saved performance among the already evaluated checkpoints.

### Task 1: Add Explicit Checkpoint Pinning To The Adversarial Runner

**Files:**
- Modify: `src/adversarial/model_wrapper.py`
- Modify: `src/adversarial/scripts/run_adversarial_eval.py`
- Test: `test/test_adversarial/test_model_wrapper.py`

**Step 1: Write the failing test**

Add a test that instantiates `CudaLSTMWrapper(run_dir=..., epoch=20)` and verifies the selected weight file is `model_epoch020.pt`, not the latest checkpoint.

**Step 2: Run test to verify it fails**

Run:

```powershell
pytest test/test_adversarial/test_model_wrapper.py -k epoch -v
```

Expected: no matching test exists yet, or the wrapper/runner cannot pin the epoch end-to-end.

**Step 3: Write minimal implementation**

- In `src/adversarial/model_wrapper.py`, keep the existing `epoch` argument but expose which checkpoint was loaded in a small inspectable attribute such as `self.weight_file`.
- In `src/adversarial/scripts/run_adversarial_eval.py`, read an optional `model.epoch` from YAML and pass it into `CudaLSTMWrapper(...)`.

**Step 4: Run tests to verify it passes**

Run:

```powershell
pytest test/test_adversarial/test_model_wrapper.py -v
```

Expected: PASS.

**Step 5: Commit**

```powershell
git add src/adversarial/model_wrapper.py src/adversarial/scripts/run_adversarial_eval.py test/test_adversarial/test_model_wrapper.py
git commit -m "feat(adversarial): support pinned checkpoints for benchmark reruns"
```

### Task 2: Create A Dedicated 531 Rerun Config And Separate Output Root

**Files:**
- Create: `src/adversarial/configs/full_eval_531_epoch020.yaml`

**Step 1: Create the config**

Use the existing `src/adversarial/configs/full_eval.yaml` as the template, but change:

- `model.run_dir: "results/05_adversarial_robustness/runs/reproduce_531_nse074_2025_1129_2145_ep30"`
- `model.epoch: 20`
- `output_dir: "results/adversarial_eval/531_epoch020"`
- keep `data.basins: []`
- keep the existing experiment matrix unchanged at first

**Step 2: Verify the config is isolated**

Run:

```powershell
Get-Content src/adversarial/configs/full_eval_531_epoch020.yaml
```

Expected: the output path points only to `results/adversarial_eval/531_epoch020`, never to `results/adversarial_eval/full`.

**Step 3: Commit**

```powershell
git add src/adversarial/configs/full_eval_531_epoch020.yaml
git commit -m "feat(adversarial): add isolated 531 benchmark rerun config"
```

### Task 3: Smoke-Test The New 531 Path On Two Basins Before Any Full Run

**Files:**
- Inspect only: `src/adversarial/data/531_basins.txt`
- Output only: `results/adversarial_eval/531_epoch020/`

**Step 1: Dry-run the experiment matrix**

Run:

```powershell
python src/adversarial/scripts/run_adversarial_eval.py --config src/adversarial/configs/full_eval_531_epoch020.yaml --basin-range 0:2 --attack fgsm --epsilon 0.1 --constraint lp --target untargeted --output-suffix smoke_fgsm --dry-run
```

Expected: the runner reports the correct run directory, 2 basins, and writes nothing.

**Step 2: Run a 2-basin FGSM smoke test**

Run:

```powershell
python src/adversarial/scripts/run_adversarial_eval.py --config src/adversarial/configs/full_eval_531_epoch020.yaml --basin-range 0:2 --attack fgsm --epsilon 0.1 --constraint lp --target untargeted --output-suffix smoke_fgsm
```

Expected: `results/adversarial_eval/531_epoch020/results_smoke_fgsm.json`

**Step 3: Run a 2-basin APGD smoke test**

Run:

```powershell
python src/adversarial/scripts/run_adversarial_eval.py --config src/adversarial/configs/full_eval_531_epoch020.yaml --basin-range 0:2 --attack auto_pgd --epsilon 0.1 --constraint lp --target untargeted --output-suffix smoke_apgd
```

Expected: `results/adversarial_eval/531_epoch020/results_smoke_apgd.json`

**Step 4: Audit smoke outputs**

Check:

- both files exist
- each file contains only the 2 chosen basins
- `delta_nse` is finite
- APGD is not weaker than random/FGSM on both basins in an obviously broken way

**Step 5: Commit**

Do not commit generated JSON unless explicitly requested. Commit only code/config fixes if smoke testing required them.

### Task 4: Run The Core Comparison First And Gate The Rest On It

**Files:**
- Output only: `results/adversarial_eval/531_epoch020/`

**Step 1: Run the paper-defining block only**

This block corresponds to the core comparison:

- attacks: `auto_pgd`, `fgsm`, `gaussian_noise`, `multiplicative_bias`, `temporal_correlated_noise`
- epsilons: `0.01, 0.05, 0.1, 0.2`
- constraint: `lp`
- target: `untargeted`
- basins: all 531

Preferred command pattern:

```powershell
python src/adversarial/scripts/run_adversarial_eval.py --config src/adversarial/configs/full_eval_531_epoch020.yaml --basin-file src/adversarial/data/531_basins.txt --attack auto_pgd --constraint lp --target untargeted --output-suffix exp1_apgd
```

Repeat with the other four attack names, or chunk by `--basin-range` if running on limited hardware.

**Step 2: Merge only the core comparison outputs**

Run:

```powershell
python src/adversarial/scripts/merge_results.py --input-dir results/adversarial_eval/531_epoch020 --pattern "results_exp1_*.json" --output results/adversarial_eval/531_epoch020/merged_exp1.json
```

**Step 3: Audit the core comparison before spending more GPU time**

Verify:

- all five attack families are present
- each attack has `531` unique basins for each epsilon
- the APGD/FGSM/random ordering still supports the paper story

**Step 4: Decision gate**

If the 531 core comparison no longer supports the paper’s main claim, stop here and rewrite the paper around the new evidence instead of automatically running Exp 2-5.

### Task 5: Run Follow-Up Blocks Only After Exp 1 Passes

**Files:**
- Output only: `results/adversarial_eval/531_epoch020/`

**Step 1: Run Exp 2 constraint ablation**

- attack: `auto_pgd`
- epsilons: `0.05, 0.1, 0.2`
- constraints: `lp`, `physical`, `statistical`
- target: `untargeted`

**Step 2: Run Exp 3 targeted attacks**

- attack: `auto_pgd`
- epsilon: `0.1`
- constraint: `lp`
- targets: `untargeted`, `flood`, `lowflow`

**Step 3: Run Exp 4 causal trigger**

- attack: `causal_trigger`
- epsilon: `0.1`
- constraint: `lp`
- pre-windows: `1, 3, 7, 14`

**Step 4: Run Exp 5 C&W**

- attack: `cw_regression`
- epsilon: `0.1`
- constraint: `lp`

**Step 5: Keep every block separately named**

Use `--output-suffix` values such as:

- `exp2_apgd_constraints`
- `exp3_apgd_targets`
- `exp4_causal`
- `exp5_cw`

This prevents accidental overlap with the old 540/520 files and makes later merge/audit simpler.

### Task 6: Merge, Audit, And Prove The Final Sample Size Is 531

**Files:**
- Output only: `results/adversarial_eval/531_epoch020/merged_all.json`

**Step 1: Merge all new result chunks**

Run:

```powershell
python src/adversarial/scripts/merge_results.py --input-dir results/adversarial_eval/531_epoch020 --pattern "results_*.json" --output results/adversarial_eval/531_epoch020/merged_all.json
```

**Step 2: Run a basin-count audit**

Use a short Python or PowerShell audit to report:

- total unique basins overall
- unique basins by attack
- unique basins by attack + epsilon
- any missing basin IDs relative to `src/adversarial/data/531_basins.txt`

Expected: the core comparison block should have exactly `531` unique basins. If not, stop and explain every missing basin before touching the paper.

**Step 3: Save the audit**

Write a plain-text provenance note such as:

- `results/adversarial_eval/531_epoch020/README_provenance.txt`

It should state:

- source model run dir
- pinned epoch
- basin list used
- exact output directory
- merged file path
- final basin counts for each experiment block

### Task 7: Analyze The New Suite In A Separate Figure/Table Tree

**Files:**
- Output only: `results/adversarial_eval/531_epoch020/figures/`

**Step 1: Generate figures and printed tables**

Run:

```powershell
python src/adversarial/scripts/analyze_results.py --input results/adversarial_eval/531_epoch020/merged_all.json --output-dir results/adversarial_eval/531_epoch020/figures
```

**Step 2: Capture the headline numbers**

Record at minimum:

- median `delta_nse` for APGD, FGSM, Gaussian at `epsilon=0.1`
- APGD/Gaussian amplification ratio
- catastrophic fraction for APGD at `epsilon=0.1`
- statistical-constraint median `delta_nse`
- causal-trigger 14-day median `delta_nse`

**Step 3: Compare against the current manuscript**

Create a short comparison note:

- `results/adversarial_eval/531_epoch020/RESULT_DIFF_NOTE.txt`

Include only:

- which headline claims survive unchanged
- which numbers moved materially
- whether the paper should now switch to the 531 benchmark version

### Task 8: Only Then Decide Whether To Switch The Paper

**Files:**
- Modify later, not now: `draft/papers/05_adversarial_latex/main.tex`
- Modify later, not now: `draft/papers/05_adversarial_latex/supporting_information.tex`
- Modify later, not now: `draft/papers/05_adversarial_robustness_wrr.md`

**Step 1: Do not edit the manuscript before the 531 rerun is audited**

The paper should stay on the current 520 language until:

- `merged_all.json` exists
- the core comparison is complete
- `531` provenance is documented
- the new results are internally consistent

**Step 2: Switch the manuscript in one pass**

When ready, update:

- title/abstract sample count
- Methods benchmark description
- all result tables/figures
- provenance language in SI

**Step 3: Recompile and re-review claims**

Run LaTeX only after all headline numbers come from the audited 531 output tree.

---

## Recommended Execution Order

1. Add pinned checkpoint support.
2. Create the isolated 531 config.
3. Run the 2-basin smoke tests.
4. Run Exp 1 only.
5. Audit whether Exp 1 still supports the paper.
6. Run Exp 2-5 only if Exp 1 passes.
7. Merge, audit, analyze.
8. Switch the manuscript last.

## First Gating Decision

Use `model_epoch020.pt` as the pinned victim checkpoint for the rerun.

Why this is the safest choice:

- it already has archived full 531-basin test output
- it avoids silently defaulting to the weaker latest checkpoint
- it does not require touching the existing model directory contents
- it gives you a clean answer to reviewer questions about provenance

If you refuse to add pinned-epoch support, then the fallback is to use the current runner unchanged and accept that the rerun is a `model_epoch030.pt` benchmark, not the stronger `epoch020` benchmark.

Plan complete and saved to `docs/plans/2026-04-25-adversarial-531-rerun.md`. Two execution options:

**1. Subagent-Driven (this session)** - I dispatch fresh subagent per task, review between tasks, fast iteration

**2. Parallel Session (separate)** - Open new session with executing-plans, batch execution with checkpoints

Which approach?
