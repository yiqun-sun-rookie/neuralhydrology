# Dependency Initialization Current-Process Handle Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. That skill is not installed in this session, so the primary agent executes the same red-green steps inline without delegation.

**Goal:** Allow only `ctypes.dlopen(None)` while the sandbox initializes exact declared dependencies, while preserving every path-based and post-initialization denial.

**Architecture:** Keep the existing audit hook and phase boundary. Split the current initialization exception into two explicit cases: the existing fixed Windows system libraries and the new current-process handle represented by the exact value `None`. Do not allow any other library value or any call after dependency initialization completes.

**Tech Stack:** Python 3.11, Python audit hooks, pytest, Slurm batch execution on the 河海大学 high-performance computing cluster.

## Global Constraints

- Write and run failing tests before changing executable behavior.
- Do not run the 64-basin or 531-basin formal search.
- Do not read sealed evaluation data or run `src/fair_benchmark/score.py`.
- Do not modify the shared `nh_final` conda environment.
- Do not delete or overwrite prior diagnostic artifacts.
- Do not create a source-code Git commit without explicit user authorization.
- Validate on the cluster only with the three minimal single-dependency candidates: NumPy, pandas, and PyArrow.

---

### Task 1: Pin the minimum security boundary with red tests

**Files:**
- Modify: `src/unified_autoresearch/tests/test_restricted_runtime.py`
- Test: `src/unified_autoresearch/tests/test_restricted_runtime.py`

**Interfaces:**
- Consumes: the existing runtime policy keys `allowed_dependency_imports` and `dependency_initialization_read_roots`.
- Produces: regression tests proving that only a `ctypes.dlopen` event whose library argument is exactly `None` is allowed during dependency initialization.

- [ ] **Step 1: Add an allowed initialization test**

Create a fake declared dependency whose `__init__.py` calls:

```python
import sys
sys.audit("ctypes.dlopen", None)
```

Run it through the real bootstrap and assert exit code zero plus one allowed event with `library is None` and reason `declared dependency initialization requires the current-process handle`.

- [ ] **Step 2: Add a path-based initialization denial test**

Create a fake declared dependency whose `__init__.py` calls:

```python
import sys
sys.audit("ctypes.dlopen", "/tmp/unified-autoresearch-forbidden.so")
```

Run it through the real bootstrap and assert exit code two plus a denied `ctypes.dlopen` event.

- [ ] **Step 3: Add a post-initialization denial test**

Run candidate entrypoint code that calls:

```python
import sys
sys.audit("ctypes.dlopen", None)
```

Assert normalized exit code two and a denied `ctypes.dlopen` event.

- [ ] **Step 4: Run the three tests and prove the intended allow case is red**

Run:

```powershell
$env:PYTHONPATH=(Resolve-Path 'src').Path
python -m pytest src/unified_autoresearch/tests/test_restricted_runtime.py -k "dlopen" -q
```

Expected before implementation: the initialization `None` test fails because the sandbox exits with code two; both denial tests pass.

### Task 2: Implement the minimum allow rule

**Files:**
- Modify: `src/unified_autoresearch/runtime/bootstrap.py`
- Test: `src/unified_autoresearch/tests/test_restricted_runtime.py`

**Interfaces:**
- Consumes: `dependency_initialization: bool`, audit event name, and the raw library argument.
- Produces: an allowed audit record only when `dependency_initialization is True`, event is `ctypes.dlopen`, and library is exactly `None`.

- [ ] **Step 1: Add the exact current-process condition**

Implement the equivalent of:

```python
allowed_current_process_handle = event == "ctypes.dlopen" and library is None
allowed_initialization_event = dependency_initialization and (
    allowed_current_process_handle
    or (event == "ctypes.dlopen" and library in allowed_initialization_libraries)
    or (event == "ctypes.dlsym" and symbol in allowed_initialization_symbols)
)
```

Record `library` as JSON `null` for this case and keep the existing Windows-library behavior unchanged.

- [ ] **Step 2: Run the focused red-green test set**

Run the same `-k "dlopen"` command. Expected: all three new boundary tests pass.

- [ ] **Step 3: Run the complete restricted-runtime test file**

Run:

```powershell
$env:PYTHONPATH=(Resolve-Path 'src').Path
python -m pytest src/unified_autoresearch/tests/test_restricted_runtime.py -q
```

Expected: zero failures.

- [ ] **Step 4: Verify the source diff contains only the planned rule and tests**

Run `git diff --check` and inspect `git diff -- src/unified_autoresearch/runtime/bootstrap.py src/unified_autoresearch/tests/test_restricted_runtime.py`.

### Task 3: Validate the fix on the cluster without formal search

**Files:**
- Read: `src/unified_autoresearch/runtime/bootstrap.py`
- Reuse: the preserved three-candidate diagnostic design from mailbox sequence 19.

**Interfaces:**
- Consumes: the locally tested bootstrap file and the existing cluster virtual environment.
- Produces: three isolated runtime results and immutable access logs for NumPy 1.26.4, pandas 2.2.3, and PyArrow 17.0.0.

- [ ] **Step 1: Copy the tested source into a new isolated cluster diagnostic snapshot**

Do not modify `/data1/home/sunyiq/autoresearch64/src` or any shared environment. Create a new diagnostic root and fail if it already exists.

- [ ] **Step 2: Run the three minimal candidates through Slurm**

Each candidate declares exactly one dependency. Expected minimum result: dependency preflight launches, `ctypes.dlopen(None)` is logged as allowed during initialization, and no path-based dynamic-loading event is allowed.

- [ ] **Step 3: Stop on any new denial or unexpected event**

If any candidate reaches a different denied dynamic-loading event, preserve all evidence and stop without broadening the rule.

- [ ] **Step 4: Report the decision evidence**

Report job identifier, exit codes, allowed and denied dynamic-loading events, source hashes, summary path, manifest path, and whether all three candidates completed.

### Task 4: Preserve the commit boundary

**Files:**
- Review: all modified and untracked files in the isolated worktree.

**Interfaces:**
- Consumes: passing local and cluster evidence.
- Produces: a GO, HOLD, or NO-GO recommendation without a source-code commit.

- [ ] **Step 1: Re-run `git status --porcelain`**

Confirm all pre-existing user changes remain present and identify only the newly added plan, tests, and bootstrap edit.

- [ ] **Step 2: Stop before any source-code commit**

Ask the user for explicit authorization if a commit is desired. Do not stage or commit by default.
