# Prospective Promotion Gate Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Execute this plan inline in the current session. Do not delegate work to subagents.

**Goal:** Prevent an existing scale result from being presented as a fresh post-recommendation confirmation while retaining a separate technical scale-up decision.

**Architecture:** Add a pure promotion assessor with two independent gates. The technical gate checks candidate identity, dependency and source equality, runtime success, output completeness, access denials, and protected-boundary flags; the prospective-independence gate additionally requires trusted chronology showing the scale job started after the recommendation was frozen and that no materially equivalent result was available during proposal. Persist an exclusive JSON audit record and document the current retrospective comparison.

**Tech Stack:** Python 3.11, JSON, ISO-8601 timestamps, pytest, SHA-256 evidence references.

## Global Constraints

- Do not read or score the sealed period from 1989-10-01 through 1999-09-30.
- Do not run `src/fair_benchmark/score.py`.
- Do not run a 64-basin or 531-basin formal search.
- Do not retrain or rerun any candidate for this gate implementation.
- Keep technical scalability separate from prospective independence and scientific superiority.
- A promotion result is `PASS` only if both the technical gate and prospective-independence gate pass.
- Filesystem modification times may support a retrospective chronology finding but may never independently satisfy the prospective gate.
- An identical rerun cannot satisfy the prospective gate when the same candidate, seed, basin set, protocols, and runtime-source result is already known.
- Write audit outputs exclusively and refuse an existing destination.

---

### Task 1: Freeze the promotion policy and failing tests

**Files:**
- Create: `src/unified_autoresearch/protocols/promotion_v1.json`
- Create: `src/unified_autoresearch/tests/test_promotion_gate.py`
- Create: `src/unified_autoresearch/workflow/promotion.py`

**Interfaces:**
- Consumes: `assess_promotion(record: dict) -> dict` where `record` contains automatic-recommendation evidence, scale evidence, descriptor identity checks, runtime-source checks, and chronology.
- Produces: `technical_scaleup_gate`, `prospective_independence_gate`, and `promotion_decision`, each equal to `PASS` or `HOLD`.

- [x] **Step 1: Write a failing retrospective-chronology test.**

```python
result = assess_promotion(retrospective_record)
assert result["technical_scaleup_gate"] == "PASS"
assert result["prospective_independence_gate"] == "HOLD"
assert result["promotion_decision"] == "HOLD"
```

- [x] **Step 2: Write a failing fresh-post-recommendation test.**

```python
result = assess_promotion(fresh_record)
assert result["prospective_independence_gate"] == "PASS"
assert result["promotion_decision"] == "PASS"
```

- [x] **Step 3: Write failing identity, denial, output-contract, boundary, untrusted-time, known-equivalent-result, and unknown-field tests.**
- [x] **Step 4: Run `python -m pytest src/unified_autoresearch/tests/test_promotion_gate.py -q` and require failure because the assessor does not exist.**

### Task 2: Implement the pure promotion assessor

**Files:**
- Modify: `src/unified_autoresearch/workflow/promotion.py`
- Modify: `src/unified_autoresearch/tests/test_promotion_gate.py`

**Interfaces:**
- Consumes: exact schema `promotion_evidence_record_v1` and policy `promotion_v1.json`.
- Produces: deterministic gate failures, trusted chronology classification, and one overall decision without opening prediction or target data.

- [x] **Step 1: Validate exact record fields and parse timezone-aware ISO-8601 timestamps.**
- [x] **Step 2: Implement technical identity, runtime, output, denial, and protected-boundary checks.**
- [x] **Step 3: Require trusted recommendation and scheduler timestamps, scale start after recommendation finalization, and no known materially equivalent scale result.**
- [x] **Step 4: Return explicit failure lists and verify all focused tests pass.**

### Task 3: Add exclusive persistence and the current audit record

**Files:**
- Modify: `src/unified_autoresearch/workflow/promotion.py`
- Create: `src/unified_autoresearch/evidence/AUTOMATIC_REHEARSAL_PROMOTION_AUDIT_20260811.json`
- Modify: `src/unified_autoresearch/tests/test_promotion_gate.py`

**Interfaces:**
- Consumes: `write_promotion_audit(record: dict, output_path: str | Path) -> dict`.
- Produces: one immutable audit file whose current decision is technical `PASS`, prospective `HOLD`, overall `HOLD`.

- [x] **Step 1: Test exclusive creation and refusal to overwrite an existing path.**
- [x] **Step 2: Save job identifiers, evidence roots, manifest hashes, nine equal runtime-source hashes, descriptor equality, dependencies, chronology, and current 8/64-basin metrics.**
- [x] **Step 3: Load the saved record through the assessor and require the expected three gate decisions.**

### Task 4: Regression verification and handoff

**Files:**
- Review: all files above plus the existing three-candidate rehearsal plan.

**Interfaces:**
- Consumes: focused tests and existing automatic-rehearsal tests.
- Produces: a clean source commit and an evidence-led continuation boundary.

- [x] **Step 1: Run the focused promotion tests.**
- [x] **Step 2: Run `test_automatic_rehearsal.py`, `test_single_candidate_development.py`, and `test_reference_candidates.py`.**
- [x] **Step 3: Run `git diff --check` and verify no scoring-service, sealed-data, sandbox, or candidate-method file changed.**
- [ ] **Step 4: Commit and push the gate and audit record after source-commit approval.**
- [x] **Step 5: Report that prospective confirmation requires an outcome that is not materially equivalent to the already-known 64-basin result.**
