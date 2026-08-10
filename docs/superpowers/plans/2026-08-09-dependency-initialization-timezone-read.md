# Dependency Initialization System Timezone Read Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. That skill is unavailable in this session, so the primary agent executes the same red-green steps inline without delegation.

**Goal:** Permit declared dependencies to read only trusted UTC timezone files during dependency initialization, while preserving all write, sibling-path, and post-initialization denials.

**Architecture:** The trusted parent checks Python's compiled `TZPATH` plus fixed platform timezone directories, resolves only existing `UTC` and `Etc/UTC` files, and records those exact canonical files in the runtime policy. The bootstrap grants those files a read-only exception only while `dependency_initialization` is true; it never adds a timezone directory to the candidate's general read roots.

**Tech Stack:** Python 3.11, Python audit hooks, `sysconfig`, pytest, Slurm batch execution on the 河海大学 high-performance computing cluster.

## Global Constraints

- Write and run failing tests before changing executable behavior.
- Do not allow the whole `/usr/share` directory or any candidate-supplied path.
- Do not permit writes, deletes, renames, directory creation, sibling-file reads, or post-initialization reads through the timezone exception.
- Do not run the 64-basin or 531-basin formal search.
- Do not read sealed evaluation data or run `src/fair_benchmark/score.py`.
- Do not modify the shared `nh_final` conda environment or `/data1/home/sunyiq/autoresearch64/src`.
- Do not delete or overwrite prior diagnostic artifacts.
- Do not create a source-code Git commit without explicit user authorization.
- Stop after the next unexpected cluster denial instead of widening the sandbox again.

---

### Task 1: Pin the phase-scoped boundary with red tests

**Files:**
- Modify: `src/unified_autoresearch/tests/test_restricted_runtime.py`
- Test: `src/unified_autoresearch/tests/test_restricted_runtime.py`

**Interfaces:**
- Consumes: `_run_bootstrap_with_dependency_source`, the bootstrap audit hook, and a policy key named `dependency_initialization_system_read_paths`.
- Produces: one trusted-path derivation test plus four behavioral tests for initialization read, sibling-file read, post-initialization read, and initialization write.

- [ ] **Step 1: Extend the bootstrap test helper**

Add keyword arguments equivalent to:

```python
def _run_bootstrap_with_dependency_source(
    tmp_path: Path,
    dependency_source: str,
    *,
    dependency_initialization_system_read_paths: tuple[Path, ...] = (),
    entrypoint_source: str = "pass\n",
):
```

Write the canonical file paths to `dependency_initialization_system_read_paths` in the test policy and write `entrypoint_source` to `predict.py`.

- [ ] **Step 2: Add the allowed initialization-read test**

Create a temporary timezone directory containing `UTC`, import a fake declared dependency that calls `Path(utc_path).read_bytes()`, and assert process exit code zero plus an allowed read event for the exact file.

- [ ] **Step 3: Add three denial tests**

Assert process exit code two for each independent case:

```python
# During initialization, but for a sibling file that was not approved.
Path(outside_path).read_bytes()

# After initialization, inside the timezone root.
Path(utc_path).read_bytes()

# During initialization, attempting to overwrite a timezone file.
Path(utc_path).write_text("tampered", encoding="utf-8")
```

The write test must also assert that the original bytes are unchanged.

- [ ] **Step 4: Run the four tests and prove only the intended allow case is red**

Run:

```powershell
$env:PYTHONPATH=(Resolve-Path 'src').Path
python -m pytest src/unified_autoresearch/tests/test_restricted_runtime.py -k "timezone" -q
```

Expected before implementation: the initialization-read test fails with process exit code two; all three denial tests pass.

### Task 2: Derive trusted UTC paths and implement the minimum read rule

**Files:**
- Modify: `src/unified_autoresearch/runtime/runner.py`
- Modify: `src/unified_autoresearch/runtime/bootstrap.py`
- Test: `src/unified_autoresearch/tests/test_restricted_runtime.py`

**Interfaces:**
- Produces: `_system_timezone_read_paths() -> list[str]` and runtime policy key `dependency_initialization_system_read_paths`.
- Consumes: Python's compiled `sysconfig.get_config_var("TZPATH")`, `os.pathsep`, canonical paths, and the existing `dependency_initialization` flag.

- [ ] **Step 1: Add the trusted-parent root derivation**

Implement the equivalent of:

```python
_DEFAULT_SYSTEM_TIMEZONE_ROOTS = (
    "/usr/share/zoneinfo",
    "/usr/lib/zoneinfo",
    "/usr/share/lib/zoneinfo",
    "/etc/zoneinfo",
)


def _system_timezone_read_paths() -> list[str]:
    raw_value = sysconfig.get_config_var("TZPATH")
    configured_roots = [] if not isinstance(raw_value, str) else raw_value.split(os.pathsep)
    trusted_paths = set()
    for value in [*configured_roots, *_DEFAULT_SYSTEM_TIMEZONE_ROOTS]:
        root = Path(value)
        if not root.is_absolute():
            continue
        resolved_root = root.resolve()
        if resolved_root == Path(resolved_root.anchor) or not resolved_root.is_dir():
            continue
        for marker in (resolved_root / "UTC", resolved_root / "Etc" / "UTC"):
            if marker.is_file():
                trusted_paths.add(str(marker.resolve()))
    return sorted(trusted_paths)
```

Record the returned list in the runtime policy. Do not consult a candidate environment variable.

- [ ] **Step 2: Add the bootstrap's phase-scoped read exception**

Normalize the new exact paths and make `path_allowed` return true only when all conditions hold:

```python
operation == "read"
and dependency_initialization
and inside(path, dependency_initialization_system_read_paths)
```

All writes continue to use only `write_roots`. General candidate reads continue to use only `read_roots` after initialization.

- [ ] **Step 3: Run the focused red-green tests**

Run the same `-k "timezone"` command. Expected: all four tests pass.

- [ ] **Step 4: Run the complete restricted-runtime test file and diff checks**

Run:

```powershell
$env:PYTHONPATH=(Resolve-Path 'src').Path
python -m pytest src/unified_autoresearch/tests/test_restricted_runtime.py -q
git diff --check
```

Expected: zero test failures and no whitespace errors.

### Task 3: Validate all three dependencies in an isolated cluster snapshot

**Files:**
- Read: `src/unified_autoresearch/runtime/bootstrap.py`
- Read: `src/unified_autoresearch/runtime/runner.py`
- Reuse: the preserved three-candidate diagnostic driver.

**Interfaces:**
- Consumes: the locally tested source patch and the existing NumPy 1.26.4, pandas 2.2.3, and PyArrow 17.0.0 environment.
- Produces: immutable per-candidate runtime results, access logs, a summary, and a manifest in a new cluster evidence root.

- [ ] **Step 1: Create a new isolated source snapshot**

Copy the existing cluster source to a new fail-if-present diagnostic root, then apply only the tested local changes. Verify local and cluster SHA-256 hashes for both modified runtime files.

- [ ] **Step 2: Submit one Slurm validation job**

Run the three minimal candidates serially, each declaring exactly one dependency. Do not run real-basin search or scoring.

- [ ] **Step 3: Enforce the stop condition**

Require process exit code zero, normalized exit code zero, zero denied events, and complete minimal outputs for each candidate. If any candidate exposes another denied event, preserve the evidence and stop without another sandbox change.

- [ ] **Step 4: Report only decision evidence**

Report the job identifier, three outcomes, denied-event counts, source hashes, summary path, manifest path, remaining unknowns, and GO/HOLD/NO-GO status.

### Task 4: Preserve the commit boundary

**Files:**
- Review: the isolated worktree status.

**Interfaces:**
- Consumes: local and cluster validation evidence.
- Produces: a final recommendation without staging or committing source code.

- [ ] **Step 1: Confirm protected changes remain present**

Run `git status --short` and compare against the protected pre-existing edits plus the explicitly added runtime, test, and plan changes.

- [ ] **Step 2: Stop before a source commit**

Do not stage or commit. A source-code commit still requires a separate explicit instruction.

## Verified Outcome

- Local boundary suite: 5 passed; complete restricted-runtime file: 49 passed.
- Cluster job 202085: NumPy 1.26.4, pandas 2.2.3, and PyArrow 17.0.0 all completed with process exit code zero, normalized exit code zero, zero denied events, and complete required outputs.
- Evidence manifest: 58 entries, all verified by `sha256sum -c`.
- No source-code commit, formal basin search, sealed evaluation read, shared environment change, or shared cluster source change was performed.
