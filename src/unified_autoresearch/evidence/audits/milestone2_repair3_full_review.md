# Milestone 2 repair 3 full independent review

- Frozen snapshot: `runs/unified_autoresearch_audits/milestone2_repair3_6c90c4c8fa2d3b1e_clean`
- Fingerprint root: `6c90c4c8fa2d3b1e16e59c911239fd1fdf5c22f342a088a5baaaa7e3c34c83ca`
- Reviewer context: fresh task without implementation history
- Verdict: **FAIL**

## Admission-blocking findings

1. `candidate_contract_v1.json` requires `predictions.parquet` columns `basin`, `date`, and `qsim`, but
   `runtime/runner.py` only checks that the declared path exists. A directory, arbitrary bytes, and an output root with
   an extra undeclared file were all accepted as successful predictions.
2. Candidate code can overwrite the pre-opened access log descriptor and leave a forged allow-only log while the
   parent records a successful run. The child-written access log is therefore not a trustworthy audit record.
3. A hard link from a read-only input into the writable checkpoint staging root can be made writable and used to
   modify the original input. The run still succeeds.
4. `cpu_cores` and `gpu_count` declarations are validated syntactically but do not participate in launch admission.
   A synthetic declaration of 1,000,000 CPU cores and 999 GPUs was accepted.
5. A dependency such as `packaging==0.0.0` is admitted even when the imported installed version is 25.0. Exact
   dependency versions are not bound to the environment used by the candidate.
6. Input authorization checks mapping aliases but not source provenance. A synthetic truth-like payload can be
   supplied under the `predict_features.parquet` alias and is accepted.
7. `run_candidate()` writes ordinary result and log files but does not append the candidate, experiment, state, or
   run identity to the immutable registry chain. The frozen registry contains an evidence-package self-check rather
   than an actual restricted candidate run.
8. In a sufficiently deep Windows temporary root, registry receipt creation fails because `registry/store.py` uses
   a normal-path `os.open()` call. The short-path full suite passed, but three evidence-package tests failed at the
   receipt-writing path under the deeper root.

## Evidence confirmed by the reviewer

- Fresh short-path test run: 88 passed, 1 skipped, 5 warnings.
- Snapshot: 90 physical files and 89 manifest entries, with no missing, extra, or mismatched entry.
- Evidence package: 23 physical files and 22 manifest entries, with no missing, extra, or mismatched entry.
- Recomputed eight-component fingerprint root matched the expected root.
- Eight database records, eight receipts, the exported records, scheduler proof, and final state were consistent.
- The skipped test was the Windows symbolic-link branch for which the account lacked permission.
- The reviewer did not read final-evaluation data, run the fair-benchmark scorer, or run a formal basin search.

## Unknowns

- The reviewer did not perform writes against the frozen snapshot itself.
- The evidence metadata cannot independently prove the absence of every pre-generation final-evaluation read.
- Linux behavior, real long-running training peak resources, and the symbolic-link branch were not verified.
