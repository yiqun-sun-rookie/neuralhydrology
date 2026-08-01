# Milestone 2 repair 4 full independent review

- Frozen snapshot: `runs/unified_autoresearch_audits/milestone2_repair4_0a2056ac7d458291_clean`
- Fingerprint root: `0a2056ac7d458291534b6ba9a18f1b5be8f13546049ec1b9680a03b593378342`
- Reviewer context: fresh task without implementation history
- Verdict: **FAIL**

The output-contract repair was confirmed: a valid Parquet file containing `basin`, `date`, and `qsim` succeeds,
while a directory, plain text, missing columns, a missing output, or an extra top-level output fails. The reviewer also
confirmed the 93-test JUnit result, both complete manifests, the fingerprint root, eight database records, and eight
matching receipts.

Admission remained blocked by independently reproduced functional defects: a sibling `helper.py` cannot be imported;
declared dependency versions are not checked against the loaded environment; CPU and GPU requests do not participate
in admission; input provenance is not bound; candidate event logging can be redirected; read-only inputs can be
modified through a hard link into checkpoint staging; `keep: 2` is not enforced; actual candidate runs are not added
to the immutable registry; and receipt creation fails at deep Windows paths. The ordinary-file output check also
follows symbolic links, but the local Windows account could not exercise that branch.

The reviewer did not use final-evaluation data, the fair-benchmark scoring program, or a formal basin search.
