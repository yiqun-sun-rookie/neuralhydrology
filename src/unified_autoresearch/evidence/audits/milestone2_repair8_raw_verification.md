# Milestone 2 repair 8 independent raw-evidence verification

OVERALL: CONFIRMED_FAIL

Reviewed frozen snapshot:
`runs/unified_autoresearch_audits/milestone2_repair8_0e3573e4295627d7_clean`

## A. Checkpoint retention — CONFIRMED

- A fresh temporary case accepted `keep: "all"` and rejected legacy `keep: 2` with `ValueError`.
- `checkpoint-0001`, `checkpoint-0002`, and `checkpoint-0003` all remained and re-verified with distinct root hashes.
- Republish of `checkpoint-0001` raised `FileExistsError`; its original payload bytes did not change.

## B. Real candidate registry integration — CONFIRMED MISSING

- A fresh real training-mode candidate completed with status `succeeded`, process and normalized exit codes zero, a
  valid output contract, one model file, and seven log files.
- Its colocated registry remained at zero records and zero receipts. No scheduler-lock file or `fingerprint.json`
  existed. The real output and runtime-result hashes therefore had no final fingerprint binding.
- `runtime/runner.py:80` exposes no registry, experiment identity, run identity, or scheduler-lock parameter and only
  writes the runtime result before returning. The frozen eight-record registry is from the evidence-package self-check.

## C. Direct deep-path receipt creation — CONFIRMED MISSING

- A fresh Windows case used a 229-character database path, 222-character receipt directory, and 281-character
  expected receipt path.
- `append_candidate()` raised `FileNotFoundError`; the transaction rolled back to zero records and zero receipts.
- `registry/store.py:132` still calls `os.open` with an ordinary path.

## D. Frozen evidence — CONFIRMED

- Eight fingerprint components and 165 file entries recomputed without mismatch. Root:
  `0e3573e4295627d75dc5949742e1338de81fe5a5b72ee08f34d2a3b0233ea81e`.
- Saved Git diff: 0 bytes; saved Git status: 4,686 bytes and 73 null-delimited entries. Both hashes matched.
- JUnit: 101 tests, 100 passed, 1 skipped, 0 failures, 0 errors; saved standard output reported 5 warnings.
- SQLite integrity was `ok`; eight records, eight receipts, the record chain, and lock proofs were consistent.
- Run package: 23 physical files and 22 manifest entries. Snapshot: 102 physical files and 101 manifest entries.
  Both had zero mismatches.
- Seven fresh targeted functional tests passed with bytecode and pytest cache disabled. Afterward the snapshot remained
  102/101 with zero mismatches and manifest digest
  `37adca88397309b33ca2bc732f4f944b9ad424c56e700aec4731b27772fc807a`.

Temporary raw-verification cases were preserved outside the repository under the system temporary directory. The
reviewer did not read or score the sealed final evaluation period, run the fair benchmark scoring program, run a 64-
or 531-basin formal search, or make a baseline-superiority claim.
