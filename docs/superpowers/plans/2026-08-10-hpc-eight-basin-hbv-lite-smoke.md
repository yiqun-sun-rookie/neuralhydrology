# HPC Eight-Basin HBV-Lite Smoke Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Execute this plan inline in the current session. No subagent or source-code commit is authorized.

**Goal:** Run one predeclared HBV-lite candidate through both development protocols on the frozen eight-basin development set using the validated cluster sandbox source.

**Architecture:** Derive a new eight-basin development-only source from the existing 64-basin source that already attests `1999-10-01` through `2008-09-30` and `sealed_final_evaluation_present=false`. Build a new frozen package and candidate run under one fail-if-present attempt root, then independently count denials and hash every output.

**Tech Stack:** Python 3.11 virtual environment, pandas 2.2.3, PyArrow 17.0.0, NumPy 1.26.4, Slurm central-processing-unit job, Python audit hooks, SHA-256 manifests.

## Global Constraints

- Run exactly one named candidate: `hbv-lite-calibrated-v1`.
- Use exactly the eight basin identifiers frozen in `development_basins_v1.json`.
- Do not run a 64-basin or 531-basin formal search.
- Do not open raw CAMELS-US archives; read only the existing development-only source root.
- Do not read the sealed interval from 1989-10-01 through 1999-09-30.
- Do not run `src/fair_benchmark/score.py`.
- Do not modify the shared `nh_final` environment, `/data1/home/sunyiq/neuralhydrology`, or prior outputs.
- Fail if `/data1/home/sunyiq/autoresearch64/runs/unified_autoresearch/hbv_lite_8_hpc_smoke_20260810_seq36` already exists.
- Preserve every failed artifact and Slurm log; do not clean or overwrite anything.
- Stop after the first failed Slurm attempt; do not widen the sandbox or resubmit.
- Do not stage or commit the source worktree.

---

### Task 1: Freeze the source and output boundary

**Files:**
- Read: `src/unified_autoresearch/selection/development_basins_v1.json`
- Read: `src/unified_autoresearch/runtime/bootstrap.py`
- Read: `src/unified_autoresearch/runtime/runner.py`
- Create: `docs/superpowers/plans/2026-08-10-hpc-eight-basin-hbv-lite-smoke.md`

**Interfaces:**
- Consumes: validated source snapshot `dlopen_timezone_fix_validation_20260809_seq24/src`.
- Produces: exact local-to-cluster SHA-256 agreement for candidate, workflow, package, and runtime files.

- [x] **Step 1: Confirm the cluster source contains development data only**

Require the source manifest to report:

```text
date_bounds=[1999-10-01, 2008-09-30]
sealed_final_evaluation_present=false
source_kind=explicitly_pre_sliced_development_only
```

- [x] **Step 2: Confirm relevant source hashes match the local worktree**

Compare the nine files listed in mailbox result 35. All nine hashes must agree before submission.

- [x] **Step 3: Confirm the output root is absent**

Require `output_exists=false` for the exact attempt root named in the global constraints.

### Task 2: Build the eight-basin package and run the candidate

**Files:**
- Create: `inbox/autoresearch-64/hbv_lite_8_smoke_seq36.slurm` on the mailbox branch.
- Modify: `inbox/autoresearch-64/cmd.sh` on the mailbox branch.
- Modify: `inbox/autoresearch-64/seq` from 35 to 36 on the mailbox branch.

**Interfaces:**
- Consumes: `/data1/home/sunyiq/autoresearch64/runs/unified_autoresearch/development_source_real_64_hpc`.
- Produces: `source_8`, `packages_8`, `candidate_run`, and `evidence` beneath the unique attempt root.

- [x] **Step 1: Submit one central-processing-unit Slurm job**

Use one node, one task, one central-processing-unit core, partition `hcpu48`, and a 30-minute limit. The login-node command may only call `sbatch`, `squeue`, `sacct`, and read the exact job logs.

- [x] **Step 2: Derive a development-only eight-basin source**

The batch job verifies all source-file hashes against `SOURCE_MANIFEST.json`, filters features, targets, and static attributes to the frozen eight identifiers, and writes a new source manifest. It refuses any date outside `1999-10-01` through `2008-09-30`.

- [x] **Step 3: Build the two frozen development protocols**

Call `build_development_packages` with `development_v1.json` and `development_basins_v1.json`. Require eight basins and both `forward` and `reverse` protocols.

- [x] **Step 4: Run only HBV-lite with the cluster dependency declaration**

Run:

```bash
python -u src/unified_autoresearch/scripts/run_single_candidate.py \
  --candidate hbv_lite \
  --dependencies cluster \
  --repo-root /data1/home/sunyiq/autoresearch64 \
  --package-root packages_8 \
  --output-root candidate_run \
  --monitor-sample-interval-seconds 1.0 \
  --monitor-reason "restricted eight-basin end-to-end sandbox smoke; one predeclared candidate"
```

### Task 3: Validate the evidence independently

**Files:**
- Create: `evidence/SMOKE_SUMMARY.json` under the attempt root.
- Create: `evidence/MANIFEST.sha256` under the attempt root.

**Interfaces:**
- Consumes: four runtime results and every `access.jsonl` file from `candidate_run`.
- Produces: one auditable summary and a complete relative-path SHA-256 manifest.

- [x] **Step 1: Require the declared result counts**

Require `basin_count=8`, `cell_count=8`, `registered_run_count=4`, and `score_report_count=2`.

- [x] **Step 2: Independently count access denials**

Parse every access log and require the total number of events whose decision is `deny` to equal zero.

- [x] **Step 3: Require four successful runtime results**

Read each runtime result and require status `succeeded`, process exit code zero, normalized exit code zero, and a valid output contract.

- [x] **Step 4: Hash the complete attempt root**

Create `evidence/MANIFEST.sha256` using paths relative to the attempt root and verify it with `sha256sum -c`.

### Task 4: Preserve the protected worktree and stop

**Files:**
- Review: source worktree status only.

**Interfaces:**
- Consumes: the Slurm result and immutable evidence.
- Produces: a GO or HOLD report without source staging or commits.

- [x] **Step 1: Recheck the source worktree**

Require commit `d1e93d46`, no staged files, and the pre-existing protected changes plus this plan only.

- [x] **Step 2: Stop after the first result**

If the job fails or any denial appears, report HOLD and preserve all outputs. Do not resubmit, clean, modify code, or relax the sandbox.

## Verified Outcome

- Slurm job `202243` completed on `icn201` with exit code `0:0` in 1 minute 48 seconds.
- The derived development-only source contains 8 basins and 26,304 rows; its manifest SHA-256 is `59d333daa833a5d67167ad96f8203328b96990b1a0efc470777b22c84319c8d7`.
- The two-protocol package manifest SHA-256 is `f877e7932d33dc2db35f25026b425dd69755dda1338649020db40a1f4d5b38ea`.
- All four registered train/predict runtimes succeeded with process and normalized exit codes zero, complete required outputs, and zero independently counted denials.
- The attempt manifest contains 151 entries and passes `sha256sum -c`.
- No second experiment, source commit, formal 64/531-basin search, sealed evaluation read, shared environment change, or log cleanup was performed.
