# Milestone 2 repair 10 independent raw-evidence verification

OVERALL: CONFIRMED_PASS

## A. Outer evidence — CONFIRMED

- All eight outer fingerprint components and 203 referenced files independently recomputed with zero mismatches.
- Saved and recomputed root:
  `367edaf567049707152fb7e4b0e21638ea2b8161140a72e327ac082be6b276ae`.
- Saved Git diff and status byte hashes matched the fingerprint.
- Frozen JUnit: 109 cases, 108 passed, 1 skipped, 0 failures, 0 errors.
- Outer registry: eight records and eight receipts with zero verification failures.
- Run package: 23 physical files and 22 manifest entries. Snapshot: 134 physical files and 133 manifest entries.
  Both had zero missing, extra, or mismatched files.

## B. Frozen real candidate probe — CONFIRMED

- The probe had 26 physical files; the outer fingerprint and snapshot sealed all 26.
- Its registry had eight records, eight receipts, and five states: registered, validated, queued, running, succeeded.
- Running and terminal records contained the real scheduler-lock proof; the live lock was released after completion.
- The result had process and normalized exit codes zero, valid dependency/resource/output contracts, one output, and seven
  logs.
- The inner eight-component fingerprint and 184 referenced files recomputed without mismatch. Root:
  `ca6d0572ae14c186f0802b53f094f07e98521fb5594d79cfadaa47879f5d7385`.
- The fingerprint covered eight output/log files, three candidate files plus the implementation source set, seven
  configuration/descriptor files, and six ordinary/data inputs.

## C. Fresh targeted execution — CONFIRMED

Command:

`python -B -m pytest src/unified_autoresearch/tests/test_registered_runtime.py src/unified_autoresearch/tests/test_registry.py -q -p no:cacheprovider --tb=short`

Result: 15 passed, 0 failed, 1 warning in 14.83 seconds.

The cases covered registered success, runtime failure, output-contract failure, checkpointed completion, prelaunch
resource refusal, resume-input fingerprint binding, ordinary registry integrity, and a receipt path beyond 260
characters.

## D. Post-test snapshot — CONFIRMED

- Long-path-safe re-enumeration after the targeted tests remained 134 physical files and 133 manifest entries.
- Missing files: 0. Hash mismatches: 0. Extra files other than the manifest itself: 0.
- No bytecode, pytest cache, or other files were added. The run package remained 23/22 and the real probe remained 26
  files. Both outer and inner roots were unchanged.

The verifier did not read or score the sealed final evaluation period, run the fair benchmark scoring program, run a
64- or 531-basin formal search, or make a baseline-superiority claim.
