# Pretrained LSTM Knowledge Separation Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build the smallest valid experiment that tests whether transferable and domain-specific knowledge are partially separable in a pretrained NeuralHydrology LSTM.

**Architecture:** Use one fixed large-sample LSTM source model, derive two target conditions from an attribute-defined shift space, run four structured adaptation settings, and analyze both predictive outcomes and internal representation drift. The implementation should prefer lightweight scripts and configs over framework refactors.

**Tech Stack:** Python, NeuralHydrology, PyTorch, YAML configs, pytest, pandas, NumPy, scikit-learn or SciPy for descriptor-space distances, Matplotlib/Seaborn for analysis plots.

---

### Task 1: Define the experiment workspace

**Files:**
- Create: `src/pretrained_lstm_knowledge_separation/README.md`
- Create: `src/pretrained_lstm_knowledge_separation/__init__.py`
- Create: `src/pretrained_lstm_knowledge_separation/configs/`
- Create: `src/pretrained_lstm_knowledge_separation/scripts/`
- Create: `src/pretrained_lstm_knowledge_separation/data/`

**Step 1: Write the minimal scaffold**

Create the workspace directories and a short README that states:
- scientific question
- source model assumption
- four adaptation groups
- two target shift conditions

**Step 2: Verify the paths exist**

Run: `Get-ChildItem src\pretrained_lstm_knowledge_separation -Recurse`
Expected: README plus `configs`, `scripts`, and `data` directories are visible.

**Step 3: Commit**

```bash
git add src/pretrained_lstm_knowledge_separation
git commit -m "Phase: scaffold pretrained LSTM knowledge separation workspace"
```

### Task 2: Build a shift-definition script

**Files:**
- Create: `src/pretrained_lstm_knowledge_separation/scripts/build_shift_splits.py`
- Create: `test/test_pretrained_lstm_knowledge_separation_splits.py`

**Step 1: Write the failing test**

Test the script utilities, not the full CLI. Cover:
- loading a basin attribute table
- selecting descriptor columns
- computing source-to-target distances
- returning reproducible `low_shift` and `high_shift` basin sets

Example assertions:
- the low-shift group has smaller mean distance than the high-shift group
- basin counts match requested sizes
- the same seed yields the same result

**Step 2: Run test to verify it fails**

Run: `pytest test/test_pretrained_lstm_knowledge_separation_splits.py -v`
Expected: FAIL because the split builder does not exist yet.

**Step 3: Write minimal implementation**

Implement a script that:
- reads basin descriptors from an existing dataset attribute table
- standardizes descriptor columns
- computes distance from the source distribution center
- emits two basin lists:
  - `src/pretrained_lstm_knowledge_separation/data/low_shift_basins.txt`
  - `src/pretrained_lstm_knowledge_separation/data/high_shift_basins.txt`
- saves a compact CSV summary with per-basin distance scores

**Step 4: Run test to verify it passes**

Run: `pytest test/test_pretrained_lstm_knowledge_separation_splits.py -v`
Expected: PASS

**Step 5: Commit**

```bash
git add test/test_pretrained_lstm_knowledge_separation_splits.py src/pretrained_lstm_knowledge_separation/scripts/build_shift_splits.py src/pretrained_lstm_knowledge_separation/data
git commit -m "Phase: add attribute-based shift split builder"
```

### Task 3: Add adaptation configs

**Files:**
- Create: `src/pretrained_lstm_knowledge_separation/configs/source_pretrain.yml`
- Create: `src/pretrained_lstm_knowledge_separation/configs/adapt_low_shift_head.yml`
- Create: `src/pretrained_lstm_knowledge_separation/configs/adapt_low_shift_embedding.yml`
- Create: `src/pretrained_lstm_knowledge_separation/configs/adapt_low_shift_lstm.yml`
- Create: `src/pretrained_lstm_knowledge_separation/configs/adapt_low_shift_full.yml`
- Create: `src/pretrained_lstm_knowledge_separation/configs/adapt_high_shift_head.yml`
- Create: `src/pretrained_lstm_knowledge_separation/configs/adapt_high_shift_embedding.yml`
- Create: `src/pretrained_lstm_knowledge_separation/configs/adapt_high_shift_lstm.yml`
- Create: `src/pretrained_lstm_knowledge_separation/configs/adapt_high_shift_full.yml`

**Step 1: Write a config validation test**

Add a test to `test/test_pretrained_lstm_knowledge_separation_configs.py` that:
- loads each config with `Config`
- verifies `finetune_modules` matches the intended adaptation group
- verifies target basin file paths point to the generated split files

**Step 2: Run test to verify it fails**

Run: `pytest test/test_pretrained_lstm_knowledge_separation_configs.py -v`
Expected: FAIL because the configs do not exist yet.

**Step 3: Write minimal configs**

Keep the source config minimal and the adaptation configs explicit. The adaptation mapping should be:
- `head-only` -> `finetune_modules: [head]`
- `embedding-only` -> `finetune_modules: [embedding_net]`
- `lstm-only` -> `finetune_modules: [lstm]`
- `full FT` -> use a dedicated training mode or config setting that leaves all modules trainable

Use one consistent source run directory placeholder so later scripts can patch in the actual source model location.

**Step 4: Run test to verify it passes**

Run: `pytest test/test_pretrained_lstm_knowledge_separation_configs.py -v`
Expected: PASS

**Step 5: Commit**

```bash
git add test/test_pretrained_lstm_knowledge_separation_configs.py src/pretrained_lstm_knowledge_separation/configs
git commit -m "Phase: add structured adaptation config matrix"
```

### Task 4: Add a lightweight experiment launcher

**Files:**
- Create: `src/pretrained_lstm_knowledge_separation/scripts/run_matrix.py`
- Create: `test/test_pretrained_lstm_knowledge_separation_runner.py`

**Step 1: Write the failing test**

Test that the runner:
- enumerates the expected configs
- expands a source run path into adaptation jobs
- produces a deterministic manifest for the eight adaptation runs

**Step 2: Run test to verify it fails**

Run: `pytest test/test_pretrained_lstm_knowledge_separation_runner.py -v`
Expected: FAIL because the matrix runner does not exist yet.

**Step 3: Write minimal implementation**

Implement a runner that:
- takes a source run directory as input
- verifies that the source config and weights exist
- materializes a simple job manifest CSV or JSON
- optionally prints the exact `python -m neuralhydrology.nh_run ...` commands needed to execute each run

Do not add scheduling complexity in phase 1.

**Step 4: Run test to verify it passes**

Run: `pytest test/test_pretrained_lstm_knowledge_separation_runner.py -v`
Expected: PASS

**Step 5: Commit**

```bash
git add test/test_pretrained_lstm_knowledge_separation_runner.py src/pretrained_lstm_knowledge_separation/scripts/run_matrix.py
git commit -m "Phase: add structured adaptation experiment runner"
```

### Task 5: Add result summarization for mechanism evidence

**Files:**
- Create: `src/pretrained_lstm_knowledge_separation/scripts/summarize_results.py`
- Create: `test/test_pretrained_lstm_knowledge_separation_summary.py`

**Step 1: Write the failing test**

Use small fake run summaries to verify that the summarizer:
- aggregates target metrics
- computes basin-level gain/loss counts
- reports source-retention delta
- emits a compact table comparing the four adaptation groups across both shift conditions

**Step 2: Run test to verify it fails**

Run: `pytest test/test_pretrained_lstm_knowledge_separation_summary.py -v`
Expected: FAIL because the summarizer does not exist yet.

**Step 3: Write minimal implementation**

Implement a summarizer that:
- reads evaluation outputs from the eight adaptation runs
- produces a machine-readable summary table
- writes one human-readable markdown summary with:
  - mean metrics
  - gain/loss proportions
  - retention metrics

**Step 4: Run test to verify it passes**

Run: `pytest test/test_pretrained_lstm_knowledge_separation_summary.py -v`
Expected: PASS

**Step 5: Commit**

```bash
git add test/test_pretrained_lstm_knowledge_separation_summary.py src/pretrained_lstm_knowledge_separation/scripts/summarize_results.py
git commit -m "Phase: add knowledge separation result summarizer"
```

### Task 6: Add minimal representation-drift analysis

**Files:**
- Create: `src/pretrained_lstm_knowledge_separation/scripts/analyze_representations.py`
- Create: `test/test_pretrained_lstm_knowledge_separation_representations.py`

**Step 1: Write the failing test**

Cover helper functions that:
- load saved intermediate tensors or activation dumps
- compute a simple representation distance metric between source and adapted runs
- aggregate distances by module (`embedding`, `lstm output`, `head input`)

**Step 2: Run test to verify it fails**

Run: `pytest test/test_pretrained_lstm_knowledge_separation_representations.py -v`
Expected: FAIL because the representation analysis helpers do not exist yet.

**Step 3: Write minimal implementation**

Implement a first-pass analysis that favors simplicity:
- cosine or Euclidean representation distance, or CKA if already easy to support
- no heavy interpretability stack
- one output CSV and one figure-ready table

If activations are not already available from standard NH outputs, add a small controlled export path rather than a framework-wide refactor.

**Step 4: Run test to verify it passes**

Run: `pytest test/test_pretrained_lstm_knowledge_separation_representations.py -v`
Expected: PASS

**Step 5: Commit**

```bash
git add test/test_pretrained_lstm_knowledge_separation_representations.py src/pretrained_lstm_knowledge_separation/scripts/analyze_representations.py
git commit -m "Phase: add representation drift analysis"
```

### Task 7: Write the execution README and validation commands

**Files:**
- Modify: `src/pretrained_lstm_knowledge_separation/README.md`

**Step 1: Expand the README**

Document:
- data prerequisites
- split generation command
- source training command
- adaptation matrix command sequence
- summary and representation-analysis commands
- expected artifacts

**Step 2: Smoke-check the commands**

Run the `--help` entry points for each script and at least one config-load test command.

Suggested checks:
- `python src/pretrained_lstm_knowledge_separation/scripts/build_shift_splits.py --help`
- `python src/pretrained_lstm_knowledge_separation/scripts/run_matrix.py --help`
- `python src/pretrained_lstm_knowledge_separation/scripts/summarize_results.py --help`
- `python src/pretrained_lstm_knowledge_separation/scripts/analyze_representations.py --help`

Expected: All commands print help and exit successfully.

**Step 3: Commit**

```bash
git add src/pretrained_lstm_knowledge_separation/README.md
git commit -m "Phase: document pretrained LSTM knowledge separation workflow"
```

### Task 8: Run the validation suite

**Files:**
- Test: `test/test_pretrained_lstm_knowledge_separation_splits.py`
- Test: `test/test_pretrained_lstm_knowledge_separation_configs.py`
- Test: `test/test_pretrained_lstm_knowledge_separation_runner.py`
- Test: `test/test_pretrained_lstm_knowledge_separation_summary.py`
- Test: `test/test_pretrained_lstm_knowledge_separation_representations.py`

**Step 1: Run targeted tests**

Run:

```bash
pytest test/test_pretrained_lstm_knowledge_separation_splits.py test/test_pretrained_lstm_knowledge_separation_configs.py test/test_pretrained_lstm_knowledge_separation_runner.py test/test_pretrained_lstm_knowledge_separation_summary.py test/test_pretrained_lstm_knowledge_separation_representations.py -v
```

Expected: PASS

**Step 2: Record the exact validation commands and outputs**

Append the successful commands to the README or experiment notes.

**Step 3: Commit**

```bash
git add test src/pretrained_lstm_knowledge_separation
git commit -m "Phase: validate pretrained LSTM knowledge separation tooling"
```
