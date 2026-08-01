# Milestone 2 repair 8 independent full review

OVERALL: FAIL

Reviewed frozen snapshot:
`runs/unified_autoresearch_audits/milestone2_repair8_0e3573e4295627d7_clean`

Expected and independently recomputed fingerprint root:
`0e3573e4295627d75dc5949742e1338de81fe5a5b72ee08f34d2a3b0233ea81e`

## Admission blockers

1. Real candidate executions are not appended to the immutable registry and do not receive a final fingerprint.
   `runtime/runner.py:80` has no registry, experiment identity, run identity, or scheduler-lock interface. A fresh
   candidate probe completed with status `succeeded`, normalized and process exit codes of zero, and a valid output
   contract, but the associated registry still contained zero records and zero receipts. The run root had no
   `fingerprint.json`; therefore its prediction and seven log files were not bound by a final fingerprint. The eight
   frozen registry records belong only to the evidence-package self-check.

2. External registry receipts cannot be created directly under a deep Windows path.
   `registry/store.py:132` passes an ordinary path to `os.open`. A fresh probe used a 229-character database path,
   a 222-character receipt directory, and an expected 281-character receipt path. `append_candidate()` raised
   `FileNotFoundError` and the transaction rolled back to zero records. The snapshot's eight 280-character receipts
   were created under the shorter run root and then copied with long-path-safe code, so they do not prove direct
   deep-path creation. The existing deep-path manifest test also creates a simulated receipt with a long-path prefix
   instead of exercising `Registry`.

## Confirmed repairs and evidence

- The descriptor now requires checkpoint retention `keep: "all"`; legacy `keep: 2` is rejected.
- Checkpoint publication is non-overwriting and preserves three distinct versions, all of which re-verify.
- Existing ordinary input, output, exact dependency, task-level processor/memory/disk preflight, controlled stop,
  checkpoint promotion, and resume checks passed code and test review.
- The eight fingerprint components and 165 fingerprint manifest entries recomputed without mismatch.
- Saved Git diff bytes were empty; saved Git status was 4,686 bytes with 73 entries. Both hashes matched the
  fingerprint.
- SQLite integrity was `ok`; eight registry records, their chain, exported records, eight receipts, and scheduler-lock
  proofs were consistent.
- Snapshot: 102 physical files, 101 manifest entries plus the manifest itself, zero mismatches.
- Run package: 23 physical files, 22 manifest entries plus the manifest itself, zero mismatches.
- Fresh snapshot command `python -B -m pytest src/unified_autoresearch/tests -q -p no:cacheprovider --tb=short`
  returned 100 passed, 1 skipped, and 5 warnings. The snapshot remained unchanged afterward; its manifest digest was
  `37adca88397309b33ca2bc732f4f944b9ad424c56e700aec4731b27772fc807a`.

The reviewer did not read or score the sealed final evaluation period, run the fair benchmark scoring program, run a
64- or 531-basin formal search, or make a baseline-superiority claim.
