# G3 state-weight factorial formal attempt v02 — packaging failure

Date: 2026-07-26.

## Status

`g3_state_weight_factorial_param_switch_v02` completed the scientific
calculation and wrote an incomplete evidence directory, but failed while
copying the source snapshot. It did not produce a finalized formal result.
The external preregistration, both process logs, machine-readable failure
record, and complete `.incomplete` directory are retained and immutable.

## Frozen attempt identity

- Git commit: `985e61a2fea0fdb2828dfa35152b5879933bf353`.
- Config SHA-256:
  `925842cf445abc3a377265d99f681b94abdf45d4a1d1451cee51018c483c4c73`.
- Preregistration SHA-256:
  `63949dcd0c87175c3f4343b75736d864923acfc6bb29618cad39774b42ffc57d`.
- Standard-error log SHA-256:
  `aeb979a249cab262704c2f4ed01f5893fb1554a69f6657c463a2cb3694d2a73c`.
- Empty standard-output log SHA-256:
  `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855`.
- Incomplete `evidence.npz` SHA-256:
  `f22c3c9f5b264df993563631ed402392f7e5d99d8f4497044d7be0aac0f63ba3`.
- Machine-readable failure record:
  `results/23_hbv_multilead_joint_uncertainty/g3_state_weight_factorial_param_switch_v02.failed.json`.

## Failure and root cause

The runner failed in `_source_snapshot` before writing the summary,
protected-artifact integrity record, checksums, or final output directory.
The target file path had 267 characters. Python used the ordinary Windows
path namespace, so `shutil.copy2` raised `FileNotFoundError` even though the
parent directory structure was valid.

This was a packaging-path failure. The saved `cross_checks.json` reports that
all scientific identity and reconstruction checks passed, including maximum
frozen-probability errors of `0` for full state interaction and
`1.1102230246251565e-16` for no state interaction. However, the incomplete
evidence is not a formal result because the pre-run protected hashes were not
persisted and final package integrity was never completed.

## Recovery boundary

The replacement experiment is
`g3_state_weight_factorial_param_switch_v03`. It keeps all truth inputs,
candidate definitions, assimilation settings, forecast settings, seeds,
bootstrap resamples, comparison baselines, decision rules, and the
`1e-12` frozen-probability validation unchanged.

Only the evidence-packaging implementation changes:

- source snapshots use the Windows extended-length path namespace;
- the original relative source-file hierarchy is retained;
- checksum traversal and final directory replacement use the same long-path
  namespace;
- a regression test covers a source-snapshot target longer than 260
  characters and a network-share path.

The v02 registry status remains `failed` permanently. The v02 incomplete
directory must not be finalized, edited, deleted, or used as a formal result.
The v03 run must use a new preregistration and output directory and protect all
v02 failure artifacts.
