# Milestone 2 repair 4 raw-evidence verification

- Frozen snapshot: `runs/unified_autoresearch_audits/milestone2_repair4_0a2056ac7d458291_clean`
- Fingerprint root: `0a2056ac7d458291534b6ba9a18f1b5be8f13546049ec1b9680a03b593378342`
- Verifier context: fresh task without implementation history
- Overall result: **CONFIRMED_FAIL**

The verifier independently confirmed the prediction Parquet and extra-output rules, then reproduced six remaining
functional blockers: sibling-module import fails; an impossible exact dependency version is ignored; impossible CPU
and GPU requests launch; three checkpoints remain despite `keep: 2`; a successful candidate run leaves an attached
registry unchanged; and a 294-character Windows receipt path raises `FileNotFoundError` and rolls the transaction back.

The raw snapshot checks matched 92 manifest entries, 22 package entries, 93 JUnit tests with one skip, the expected
fingerprint root, eight database records, and eight matching receipts. No frozen file changed during verification.
The verifier did not use final-evaluation data, the fair-benchmark scoring program, or a formal basin search.

Both valid independent contexts rejected repair 4, so it is permanently non-admitting and must not be overwritten.
