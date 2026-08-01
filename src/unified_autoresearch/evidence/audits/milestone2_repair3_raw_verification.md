# Milestone 2 repair 3 raw-evidence verification

- Frozen snapshot: `runs/unified_autoresearch_audits/milestone2_repair3_6c90c4c8fa2d3b1e_clean`
- Fingerprint root: `6c90c4c8fa2d3b1e16e59c911239fd1fdf5c22f342a088a5baaaa7e3c34c83ca`
- Verifier context: fresh task without implementation history
- Overall result: **CONFIRMED_FAIL**

The verifier independently reproduced five admission-blocking functional defects using synthetic files outside the
snapshot:

1. A directory or plain text file named `predictions.parquet`, and a run with an additional undeclared output, all
   completed with exit code 0 and status `succeeded`.
2. Declarations of 999,999 CPU cores and 999,999 GPUs still launched successfully; the preflight contains only
   memory, disk, and monitoring capacity.
3. A candidate declaring `packaging==0.0.0` loaded installed `packaging` version 25.0 and succeeded.
4. A synthetic candidate run produced a successful result while the attached immutable registry record count and
   receipt count remained unchanged.
5. A Windows registry database path of 239 characters initialized, but the expected 291-character receipt path
   raised `FileNotFoundError`; the transaction rolled back to zero records and zero receipts.

Raw evidence checks also passed: the root fingerprint matched, snapshot and package manifests were complete, JUnit
recorded 89 tests with 88 passes and one skip, and all eight registry records matched the eight external receipts.
No final-evaluation data, fair-benchmark scoring program, or formal basin search was used.

Because both independent contexts rejected repair 3, it is permanently non-admitting and must not be overwritten.
