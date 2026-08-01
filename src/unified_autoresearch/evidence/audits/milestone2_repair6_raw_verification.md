# Milestone 2 repair 6 raw-evidence verification

- Frozen snapshot: `runs/unified_autoresearch_audits/milestone2_repair6_c79d25a37c93f5fd_clean`
- Fingerprint root: `c79d25a37c93f5fd6be9838dcf190a9dcc1dbf6aece6fdf17cac282f1b21d3a6`
- Verifier context: fresh task without implementation history
- Overall result: **CONFIRMED_FAIL**

The verifier independently confirmed the dependency repair and all four remaining ordinary functional blockers:
impossible CPU and GPU requests launch, three checkpoints remain, a successful candidate run leaves its registry
unchanged, and a 296-character Windows receipt path raises `FileNotFoundError` and rolls back.

The raw evidence check matched 97 snapshot-manifest entries, 22 package-manifest entries, 97 JUnit cases with one skip,
the expected root fingerprint, eight database records, and eight receipts. No frozen file changed, and no
final-evaluation data, scoring program, or formal basin search was used.

Both valid independent contexts rejected repair 6, so it is permanently non-admitting and must not be overwritten.
