# CAMELS Parameter-Switch 531-Basin Design Run Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Run the approved exploratory 531-basin parameter-switch design analysis with design seeds 0 and 1, without modifying or occupying existing experiments.

**Architecture:** Keep the Windows worktree as the only writable source checkout and use a task-specific Git mailbox channel for cluster control. If the cluster is used, create a fresh isolated clone and output root under `~/camels_g2_design_20260808`; link only the shared read-only CAMELS-US data, copy required ignored input tables into the isolated clone, and submit all computation through the batch scheduler.

**Tech Stack:** Python 3.11, NumPy, pandas, the existing HBV-lite interacting multiple-model runner, Git mailbox v2, SLURM.

## Global Constraints

- The main repository at `G:\github\pycharm\projects\neuralhydrology` is read-only.
- The only writable source worktree is `G:\wt\camels-rising` on branch `codex/camels-rising-half-recal`.
- This run is exploratory and uses design seeds `{0,1}` only; it cannot support validation claims.
- Use the existing candidate parameter factors `0.5`, `1.0`, and `2.0` and filter process-variance scale `1e-7`; do not tune them during the run.
- Do not freeze the second preregistration version in this task.
- Do not modify, cancel, overwrite, or reuse any existing local or cluster experiment directory or job.
- Stop on any failed pre-flight, failed task, clipping event, non-finite result, or protocol mismatch; preserve evidence and do not silently retry.

---

### Task 1: Confirm resource placement and reserve isolated names

**Files:**
- Read: `results/23_camels_switch_confirmation/g2_switch_confirmation_v01_widebank_q1e7/g2_events.csv`
- Read: `G:\github\pycharm\projects\neuralhydrology\.worktrees\hpc-mailbox\CHANNELS.md`
- Modify: `G:\github\pycharm\projects\neuralhydrology\.worktrees\hpc-mailbox\CHANNELS.md`
- Create: `G:\github\pycharm\projects\neuralhydrology\.worktrees\hpc-mailbox\inbox\camels-g2-design\cmd.sh`
- Create: `G:\github\pycharm\projects\neuralhydrology\.worktrees\hpc-mailbox\inbox\camels-g2-design\seq`

**Interfaces:**
- Consumes: Existing 40-task elapsed-time evidence and current local process/memory status.
- Produces: Unique channel `camels-g2-design`, cluster root `~/camels_g2_design_20260808`, job name `camg2d01`, and output tag `design531_widebank_q1e7_s01_20260808`.

- [ ] **Step 1: Record the scale estimate**

Use the existing event file to verify 40 tasks, mean task time, and the projected 1,062-task wall time at six workers.

- [ ] **Step 2: Check local resource contention**

List active Python processes and record total/free physical memory without terminating anything.

- [ ] **Step 3: Register the channel**

Add `camels-g2-design` to `CHANNELS.md`; do not touch any other channel directory.

- [ ] **Step 4: Commit and push only the new channel files**

Run `git add CHANNELS.md inbox/camels-g2-design`, commit with `core.autocrlf=false`, pull with rebase, then push `hpc-mailbox`.

### Task 2: Perform a read-only cluster pre-flight

**Files:**
- Modify: `G:\github\pycharm\projects\neuralhydrology\.worktrees\hpc-mailbox\inbox\camels-g2-design\cmd.sh`
- Modify: `G:\github\pycharm\projects\neuralhydrology\.worktrees\hpc-mailbox\inbox\camels-g2-design\seq`

**Interfaces:**
- Consumes: The registered channel.
- Produces: A mailbox result containing current jobs, partition state, isolated-directory existence, shared data availability, required ignored input availability, branch availability, and environment import status.

- [ ] **Step 1: Write the read-only probe**

The command must run only `squeue`, `sinfo`, `test`, `ls`, `du`, `git ls-remote`, and lightweight Python import/version checks on the login node.

- [ ] **Step 2: Push the next sequence number**

Increment `seq` with `printf` semantics and push only this channel.

- [ ] **Step 3: Require a result within 60 seconds**

If no result arrives, stop and ask the user to restart the mailbox runner; do not attempt an interactive login.

- [ ] **Step 4: Apply the placement gate**

Proceed only if the isolated root is absent, shared data and both ignored input tables are available, the branch is reachable, and the existing job list shows that a six-core CPU batch job will not displace or modify current work.

### Task 3: Create an isolated cluster checkout and batch script

**Files:**
- Create on cluster: `~/camels_g2_design_20260808/repo/`
- Create on cluster: `~/camels_g2_design_20260808/submit_camels_g2_design.slurm`
- Create on cluster: `~/camels_g2_design_20260808/logs/`
- Create on cluster: `~/camels_g2_design_20260808/run_manifest.txt`

**Interfaces:**
- Consumes: Branch `codex/camels-rising-half-recal`, shared read-only data, and the two required ignored input tables.
- Produces: A detached task-specific checkout, linked data path, copied immutable inputs, batch script, and manifest hashes.

- [ ] **Step 1: Create the isolated root only if absent**

Use `test ! -e ~/camels_g2_design_20260808` as a hard guard before `mkdir`; never remove or reuse an existing path.

- [ ] **Step 2: Clone only the approved branch**

Clone into `~/camels_g2_design_20260808/repo` without changing `~/neuralhydrology`.

- [ ] **Step 3: Link data and copy ignored inputs**

Link `repo/data` to the shared CAMELS-US data root and copy the rising-kernel parameter table plus first-stage precheck CSV/metadata into matching paths under the isolated checkout.

- [ ] **Step 4: Write the SLURM script**

Request one node, one task, six processor cores, no GPU, no explicit memory, partition `hgpu2p`, time limit `02:00:00`, and exclude `ngu002`. Use `set -eo pipefail`, activate `nh_final`, set the two MKL environment variables, and run:

```bash
python -u -X utf8 -m src.camels_switch_confirmation.g2_switch_confirmation \
  --workers 6 \
  --q-scale 1e-7 \
  --out-tag design531_widebank_q1e7_s01_20260808
```

- [ ] **Step 5: Add hard pre-flight checks**

Check the checkout commit, branch, data directory, parameter-table SHA-256, first-stage precheck SHA-256, module import, output-path absence, and that the script constants still specify two seeds.

### Task 4: Run one-basin smoke test as a batch job

**Files:**
- Create on cluster: `~/camels_g2_design_20260808/smoke/`
- Create on cluster: `~/camels_g2_design_20260808/logs/smoke-<jobid>.{out,err}`

**Interfaces:**
- Consumes: The isolated checkout and batch environment.
- Produces: Two successful design-seed tasks for one basin, 12 event rows, zero truth clipping, and finite probabilities.

- [ ] **Step 1: Submit the smoke job**

Run the same module with `--limit 1`, `--workers 2`, `--q-scale 1e-7`, and a smoke-only output tag.

- [ ] **Step 2: Verify scheduler completion**

Require SLURM state `COMPLETED` and exit code `0:0`.

- [ ] **Step 3: Verify the smoke artifacts**

Require 2 successful tasks, 0 failed tasks, 0 truth clipping events, 12 evaluated switch events, finite posterior probabilities, and no writes outside the isolated root.

### Task 5: Submit and verify the full exploratory design run

**Files:**
- Create on cluster: `~/camels_g2_design_20260808/repo/results/23_camels_switch_confirmation/g2_switch_confirmation_v01_design531_widebank_q1e7_s01_20260808/`
- Create on cluster: `~/camels_g2_design_20260808/logs/full-<jobid>.{out,err}`

**Interfaces:**
- Consumes: A passing smoke test.
- Produces: 1,062 task records, 6,372 event decisions, per-task probability archives, a summary JSON, and scheduler resource evidence.

- [ ] **Step 1: Confirm no duplicate output root and no conflicting job name**

Stop if the full output root already exists or `squeue` already contains `camg2d01`.

- [ ] **Step 2: Submit one six-core batch job**

Use `sbatch --parsable`; record the returned job identifier in `run_manifest.txt`.

- [ ] **Step 3: Monitor without changing other jobs**

Query only this job identifier with `squeue` and `sacct`; never call `scancel` or update another job.

- [ ] **Step 4: Enforce completion gates**

Require `COMPLETED`, exit code `0:0`, 1,062 successes, 0 failures, 0 clipping events, exactly 6,372 events, finite probability arrays, and output paths confined to the isolated root.

- [ ] **Step 5: Archive provenance**

Record the source commit, command, environment versions, hashes of inputs, job identifier, elapsed time, maximum resident memory, result file counts, and result hashes in the manifest.

### Task 6: Retrieve evidence and preserve claim boundaries

**Files:**
- Copy to Windows worktree: `results/23_camels_switch_confirmation/g2_switch_confirmation_v01_design531_widebank_q1e7_s01_20260808/`
- Copy to Windows worktree: `logs/23_camels_switch_confirmation/camels_g2_design_20260808/`

**Interfaces:**
- Consumes: Completed cluster artifacts and manifest.
- Produces: Local read-only evidence for second-version preregistration design, clearly labeled exploratory.

- [ ] **Step 1: Package only the task-specific result and log roots**

Do not package the shared repository, data, or any other experiment.

- [ ] **Step 2: Transfer and verify hashes**

Compare the local package hash with the cluster manifest before extraction.

- [ ] **Step 3: Independently recompute decisive counts**

Reload the event CSV and probability archives to recompute task count, success/failure count, clipping count, event count, and direction-stratified exploratory rates.

- [ ] **Step 4: Report with the correct evidence label**

Label every numerical result from seeds `{0,1}` as exploratory and state that it cannot establish validation, state accuracy, real-observation assimilation value, or forecast value.
