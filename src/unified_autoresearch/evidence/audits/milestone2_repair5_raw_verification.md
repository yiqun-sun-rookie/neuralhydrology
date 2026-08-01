# Milestone 2 repair 5 raw-evidence verification

- Frozen snapshot: `runs/unified_autoresearch_audits/milestone2_repair5_bbc7bc9930fa98a1_clean`
- Fingerprint root: `bbc7bc9930fa98a1d6d43491ed560235612155a572b98a9cdfad8a310a0d3c8f`
- Verifier context: fresh task without implementation history
- Overall result: **CONFIRMED_FAIL**

The verifier independently confirmed the multi-file and Parquet fixes and four remaining blockers: an impossible
declared dependency version is accepted, impossible CPU and GPU requests launch, three checkpoints remain despite
`keep: 2`, and the frozen registry contains only the evidence self-check rather than an actual candidate run.

The verifier called the deep-path finding refuted after checking the eight existing 280-character receipt paths, but
did not reproduce the first reviewer's 296-character case. That narrower observation does not resolve the deeper-path
case and is not needed for the repair-5 failure verdict. The raw checks otherwise matched 94 snapshot-manifest entries,
22 package-manifest entries, 94 JUnit cases, the expected fingerprint root, eight database records, and eight receipts.
The snapshot remained unchanged, and no final-evaluation data, scoring program, or formal basin search was used.

Both valid independent contexts rejected repair 5, so it is permanently non-admitting and must not be overwritten.
