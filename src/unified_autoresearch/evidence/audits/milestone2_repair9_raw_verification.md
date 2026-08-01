# Milestone 2 repair 9 independent raw-evidence verification

OVERALL: CONFIRMED_FAIL

## A. Windows long-path receipts — CONFIRMED

- Fresh deep case: 241-character database path and 293-character receipt path. One record and one 329-byte receipt
  were created and read; `verify()` returned one record and zero failures; SQLite integrity was `ok`.
- Ordinary-path control: 79-character database path and 131-character receipt path, again one record, one receipt,
  and zero failures.

## B. Real candidate registry integration — CONFIRMED MISSING

- A fresh candidate completed with process and normalized exit codes zero, status `succeeded`, a valid output contract,
  no denied events, one real model file, and seven log files.
- A real scheduler lock was acquired and released for the external probe, but the candidate function did not use it.
- The associated registry remained at zero records and zero receipts before and after execution; there were no final
  fingerprint records. The one output and seven logs therefore had no eight-component fingerprint binding.
- `runtime/runner.py:80` accepts no registry, experiment identity, run identity, or scheduler lock and only writes the
  runtime result before returning. The frozen registry is the evidence-package self-check.

## C. Other ordinary runtime functions — CONFIRMED

- `keep: "all"` was accepted and legacy `keep: 2` was rejected.
- Three checkpoint versions remained with distinct hashes; repeat publication was rejected without changing bytes.
- Exact installed dependency version launched; a fictitious version was denied.
- Exact processor, graphics processor, memory, and disk capacity boundaries launched; each individual shortage denied.

## D. Frozen evidence — CONFIRMED

- The saved, recomputed, and expected fingerprint root all equal
  `17d8bd76126fe0ecb975c8340afef1013f498c015ca587e1f7726d7a51a96731`.
- Eight fingerprint components and 169 grouped file entries recomputed with zero mismatches.
- Saved Git diff was 0 bytes; saved Git status was 4,847 bytes and 75 null-delimited records. Both hashes matched.
- Frozen JUnit: 102 cases, 101 passed, 1 skipped, 0 failures, 0 errors.
- SQLite integrity was `ok`; eight records, eight receipts, the record chain, state transitions, and two lock-required
  state proofs were consistent.
- Run package: 23 physical files and 22 manifest entries, zero mismatches.
- Snapshot: 104 physical files and 103 manifest entries, zero mismatches. Full fresh tests returned 101 passed and
  1 skipped. The final snapshot remained 104/103 with no cache or bytecode additions. Snapshot manifest digest:
  `6c564af9c8298ab90e5ef0a058b75b7ba1d0761077e8f9f7bca973ec1aaef72e`.

Temporary cases were preserved in the system temporary directory. The verifier did not read or score the sealed final
evaluation period, run the fair benchmark scoring program, run a 64- or 531-basin formal search, or make a
baseline-superiority claim.
