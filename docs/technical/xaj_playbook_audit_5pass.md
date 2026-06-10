# XAJ+PDD Playbook — 5-Pass Independent Audit (2026-06-04)

Audit of the claim **"XAJ-PDD playbook → 531 median NSE = 0.6372, beats SAC-SMA /
our HBV-lite ensemble"**. Each finding was independently verified. **No fixes
applied** (per directive) — this is a findings register only. Anchored to the
user's judgment handbook (J7/J8/J9, H9).

## Verdicts by pass

| Pass | Scope | Verdict |
|---|---|---|
| 1 | Reproducibility (H9) | **PASS** (verified post-hoc) |
| 2 | Data split & fairness | **PASS** w/ caveats |
| 3 | Results validity | **2 real issues** |
| 4 | Data↔code↔result correspondence | **PASS** |
| 5 | Code logic & root cause | **root cause VERIFIED; 2 scope caveats** |

## What passed (independently verified)

- **Reproducibility (H9)**: 3 basins re-run with identical config → **bit-exact**
  (|ΔNSE|=0, param L1=0, state L1=0). Deterministic (CMA-ES seed 42+restart*1000).
- **Split disjoint**: eval 1989-10..1999-09 entirely *before* cal 1999-10..2008-09.
- **Same basin set**: XAJ-final, HBV-v1, HBV-mega are the identical 531 ids, 0 dups.
- **Metric identical to HBV**: both use `xaj_global_pilot.metrics.compute_metrics`
  (`concat().dropna()` + isfinite guard). Manual NSE recompute matched CSV (iter0).
- **Knobs applied / warmup active**: metadata = oudin/warmup/v1; warmup eval-init
  states differ from cal-final by L1 64–198 (not a silent 0-day fallback).
- **Params**: 20 cols in correct PDD_XAJ order; 531/531 success; median re-derived 0.6372.
- **Subset not easy-biased (J7)**: subset p10 NSE 0.343 < full p10 0.41; covers hard
  basins (4/39 <0.3 vs full 7%). Subset runs ~0.01 optimistic vs full — headline is
  on full 531 so this does not inflate the claim.
- **Root cause VERIFIED (not inferred)**: `git show 36a337b:...data_loading.py`
  (the commit the original run used) lines 145–146:
  `ra_mm = srad*0.0864/2.45; pet = 0.0023*ra_mm*sqrt(dT)*(tmean+17.8)` — Hargreaves
  using **surface srad as Ra** (2–5× too low). `pet_method` param absent there;
  `_oudin_pet_mm` added later in 81a7c2f. Confirms the +0.19 = PET-bug fix.

## Findings (NOT fixed)

### HIGH
1. **Bound saturation in the FINAL config (J9).** With v1 bounds, the 531 optimum
   pins **kc@hi 35%**, ci@hi 31%, cg@hi 28%, wum@hi 27%, and @lo: temp_snow 41%,
   imp 42%, ex 27%, wdm 21%. Per J9 the 0.6372 rides on params jammed against
   bounds → physically suspect on ≥1/3 of basins (the optimizer wants more PET
   scaling than kc≤1.8 allows — same PET-starvation that PT was meant to relieve
   but didn't, because kc absorbs it).
2. **Bounds-widening test was INCOMPLETE.** `v2_wide` only widened the @hi pins
   (kc/wum/ci/cg); it never tested widening the @lo pins (temp_snow 41%, imp 42%,
   ex, wdm). So the conclusion "wide bounds don't help" is half-tested.
3. **Negative-eval tail with GOOD cal (J8).** 3 basins calibrate well but crash on
   eval: 09306242 (cal 0.65 → eval −3.45), 06470800 (0.64 → −0.84), 09378170
   (0.95 → −0.14). The single −3.45 drags the mean to 0.5915. Not investigated
   per-basin; candidate causes = cal/eval regime shift, warmup giving a bad init
   for these, or finding #4.

### MEDIUM
4. **obs-NaN forcing-gap telescoping.** Default `keep_obs_nan_days=False`
   (data_loading.py L289–291) *drops* obs-NaN forcing rows → forcing becomes
   non-contiguous → `simulate_pdd_xaj` propagates state across multi-day gaps as
   if 1 day. Corrupts absolute NSE on gappy-obs basins (possible cause of #3).
   **Shared with HBV-lite** (same loader, same default) → does NOT bias the
   XAJ-vs-HBV comparison, but is a latent correctness issue for both.
5. **PET mismatch in the comparison.** XAJ uses Oudin; HBV's headline ensemble uses
   PT. The comparison is best-config-vs-best-config, not same-PET. Defensible but
   must be stated. (Even current Oudin underestimates PET 2–5× per the loader's own
   comment — so XAJ's result is partly "right NSE via kc over-scaling under-est PET".)
6. **Trial-budget mismatch.** XAJ 2000×2 vs HBV 5000×3. Argued conservative for XAJ
   (fewer trials), but not an identical-budget comparison.

### LOW (process / scope)
7. **H9 ordering violation.** The "goal met / 0.6372" claim was made *before* the
   bit-exact repro check (now done, passes). Handbook H9 requires it first. No
   committed `verify_rerun` script for XAJ (HBV has one).
8. **Root cause verified by git, not by controlled re-run.** The broken-PET formula
   is proven present at 36a337b, but I did not re-run a basin with the old PET to
   reproduce 0.4458 exactly (gold standard). Evidence is strong but circumstantial-
   adjacent.
9. **Lever conclusions are subset-only.** PT<Oudin, ensemble-useless, wide-bounds-
   neutral were all decided on the 39-basin subset; only the final Oudin+warmup
   config was confirmed on full 531.

## Post-fix 3-pass audit (2026-06-05, on the v3_wide corrected run)

After fixing the bugs (gap-telescoping #4, J9 via `v3_wide`, verify script #7, and a
tool bug in `saturation_audit.py` that hardcoded v1 bounds), the corrected run
`xaj_pdd_cma_FINAL_v3wide` (Oudin+warmup+v3_wide, 2000×2) was audited 3×:

- **Pass 1 — reproducibility & correspondence: PASS.** 4 basins re-run bit-exact
  (NSE/params/state diff 0). Metadata knobs correct; same 531 basin set; median
  re-derives to 0.6402.
- **Pass 2 — J9 relief & no-regression: PASS w/ caveat.** kc@hi 35%→**5%** on full
  531 (wum 27%→7%, ci 31%→19%, cg 28%→16%) — the dominant PET-starvation pin is
  relieved. Median 0.6372→**0.6402** (no regression), mean 0.5915→**0.6068**.
  **Caveat:** it is a *redistribution* — 286 basins improve, **218 get worse**,
  27 same.
- **Pass 3 — tail & new-bug check: PASS w/ caveat.** Catastrophic tail RESCUED:
  `<-1` count 2→**0**, min −3.45→−0.48 (09306242 −3.45→+0.29, 06409000 −1.55→+0.27).
  Same basin set, metric unchanged. **Caveat:** 4 new *mild* negatives, worst
  regression 07299670 −0.54.

**Regression mechanism (diagnosed):** the 218 worse basins split into (a) **under-
convergence** — wider v3_wide space at fixed 2000×2 budget lands CMA-ES in a worse
optimum (07299670: v3 cal 0.344 < v1 cal 0.481, totally different cg regime), and
(b) **overfitting** — wider bounds fit cal better but generalize worse (01669520:
v3 cal 0.707 > v1 0.696 but eval 0.434 < 0.693). So v1's bound-pinning and v3_wide's
overfitting are two sides of the same coin.

**Headline decision:** v3_wide (**0.6402**) is adopted as the corrected, J9-compliant,
bit-exact headline (relieves pinning, better median/mean, rescues the catastrophic
tail). v1 (0.6372) is retained as the pre-J9 reference (H10). The redistribution is
disclosed; a 5000×3 paper-grade run is recommended to remove the under-convergence
component before any publication claim.

## Net assessment
The headline (0.6372, full 531, reproducible, same split/metric/basin-set as HBV)
is **sound and bit-exact reproducible**, and the root-cause story (PET bug) is
**git-verified**. The real weaknesses are (a) physical validity on the ~1/3 of
basins where params pin against bounds (J9), (b) a small negative-eval tail tied to
a shared loader gap-handling issue, and (c) several comparison caveats (PET method,
trial budget, subset-only lever attributions) that should be stated, not hidden.
