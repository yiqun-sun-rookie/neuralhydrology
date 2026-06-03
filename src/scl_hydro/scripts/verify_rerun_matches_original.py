"""Verify the patched-runner re-run produces identical NSE numbers
to the original 9-variant ensemble (0.6227 ens_cal_best target).

Compares per-basin eval NSE between:
- ``backups/pre_dump_2026-06-02/`` (original, no p_* columns)
- ``results/10_global_conceptual_model_benchmark/camels_us_531_repro_v01*``
  (post-rerun, with p_* + state_* columns)

Outputs a verdict CSV + console summary. PASS iff the new ens_cal_best median
matches the original 0.6227 within ±0.0001 (deterministic seeds should yield
exact match).

Usage::

    python -X utf8 -m src.scl_hydro.scripts.verify_rerun_matches_original

Run AFTER the rerun script finishes (or partway through to spot-check).
Partial-run mode: only compares basins present in BOTH old and new files.
"""
from __future__ import annotations

import sys
from pathlib import Path

import numpy as np
import pandas as pd

_HERE = Path(__file__).resolve()
_REPO_ROOT = _HERE.parents[3]
for _p in (_REPO_ROOT / "src", _REPO_ROOT):
    if str(_p) not in sys.path:
        sys.path.insert(0, str(_p))


VARIANTS = {
    "v1": ("camels_us_531_repro_v01", "v1_summary.csv"),
    "v5": ("camels_us_531_repro_v01_BEST", "v_BEST_summary.csv"),
    "v6": ("camels_us_531_repro_v01_v6_PT", "v_v6_PT_summary.csv"),
    "v7": ("camels_us_531_repro_v01_v7_PT_tight", "v_v7_PT_tight_summary.csv"),
    "v8": ("camels_us_531_repro_v01_v8_PT_tight_init03", "v_v8_PT_tight_init03_summary.csv"),
    "v9": ("camels_us_531_repro_v01_v9_PT_tight_init07", "v_v9_PT_tight_init07_summary.csv"),
    "v10": ("camels_us_531_repro_v01_v10_PT_tight_init09", "v_v10_PT_tight_init09_summary.csv"),
    "v11": ("camels_us_531_repro_v01_v11_PT_KGE01", "v_v11_PT_KGE01_summary.csv"),
    "v12": ("camels_us_531_repro_v01_v12_PT_sigma05", "v_v12_PT_sigma05_summary.csv"),
}
NEW_BASE = _REPO_ROOT / "results" / "10_global_conceptual_model_benchmark"
OLD_BASE = _REPO_ROOT / "backups" / "pre_dump_2026-06-02"


def _load(path: Path) -> pd.DataFrame:
    df = pd.read_csv(path, dtype={"basin_id": str}, keep_default_na=False)
    df["basin_id"] = df["basin_id"].str.zfill(8)
    df["nse"] = pd.to_numeric(df["nse"], errors="coerce")
    df["_cal_nse"] = pd.to_numeric(df["_cal_nse"], errors="coerce")
    return df


def verify_one_variant(name: str) -> dict:
    new_path = NEW_BASE / VARIANTS[name][0] / "summary" / "hbv_lite_cma_local_full.csv"
    old_path = OLD_BASE / VARIANTS[name][1]
    if not new_path.exists():
        return {"variant": name, "status": "new_missing", "n_compared": 0}
    if not old_path.exists():
        return {"variant": name, "status": "old_missing", "n_compared": 0}

    new = _load(new_path)
    old = _load(old_path)

    merged = new.merge(old, on="basin_id", suffixes=("_new", "_old"), how="inner")
    if len(merged) == 0:
        return {"variant": name, "status": "no_overlap", "n_compared": 0}

    diff_nse = (merged["nse_new"] - merged["nse_old"]).abs()
    diff_cal = (merged["_cal_nse_new"] - merged["_cal_nse_old"]).abs()
    n_mismatch = int((diff_nse > 1e-4).sum())

    has_p = any(c.startswith("p_") for c in new.columns)
    has_state = any(c.startswith("state_") for c in new.columns)

    return {
        "variant": name,
        "status": "ok" if n_mismatch == 0 else f"mismatch_{n_mismatch}",
        "n_new": len(new),
        "n_old": len(old),
        "n_compared": len(merged),
        "max_abs_dnse": float(diff_nse.max()),
        "median_abs_dnse": float(diff_nse.median()),
        "n_basin_mismatch_eval_nse": n_mismatch,
        "max_abs_dcal_nse": float(diff_cal.max()),
        "has_p_columns": has_p,
        "has_state_columns": has_state,
    }


def aggregate_ensemble(verbose: bool = True) -> dict:
    """Compute new ens_cal_best median from the new summary CSVs (post-rerun)."""
    dfs = {}
    for n, (subdir, _) in VARIANTS.items():
        p = NEW_BASE / subdir / "summary" / "hbv_lite_cma_local_full.csv"
        if p.exists():
            dfs[n] = _load(p)[["basin_id", "_cal_nse", "nse"]].rename(
                columns={"_cal_nse": f"c_{n}", "nse": f"e_{n}"})
    if len(dfs) < 9:
        return {"status": "incomplete", "n_variants_present": len(dfs)}

    m = dfs[list(VARIANTS.keys())[0]]
    for n in list(VARIANTS.keys())[1:]:
        m = m.merge(dfs[n], on="basin_id", how="inner")

    all_runs = list(VARIANTS.keys())
    cal_cols = [f"c_{n}" for n in all_runs]
    eval_cols = [f"e_{n}" for n in all_runs]

    m["best_cal"] = m[cal_cols].idxmax(axis=1).str.replace("c_", "")
    m["ens_cal_best"] = m.apply(lambda r: r[f"e_{r['best_cal']}"], axis=1)

    def top_k(r, k, agg):
        pairs = [(n, r[f"c_{n}"]) for n in all_runs]
        top = sorted(pairs, key=lambda x: -x[1])[:k]
        evals = [r[f"e_{n}"] for n, _ in top]
        return np.median(evals) if agg == "median" else np.mean(evals)

    m["ens_top3_median"] = m.apply(lambda r: top_k(r, 3, "median"), axis=1)
    m["oracle"] = m[eval_cols].max(axis=1)

    medians = {
        "ens_cal_best": float(m["ens_cal_best"].median()),
        "ens_top3_median": float(m["ens_top3_median"].median()),
        "oracle": float(m["oracle"].median()),
    }
    return {"status": "ok", "n_basins": len(m), "medians": medians, "df": m}


def main() -> int:
    print("=" * 72)
    print("PATCHED-RUNNER REPRODUCIBILITY VERIFICATION")
    print("=" * 72)
    print(f"Old: {OLD_BASE}")
    print(f"New: {NEW_BASE}")
    print()
    print(f"{'variant':<6} {'status':<15} {'n_new':>6} {'n_old':>6} "
          f"{'max|dNSE|':>10} {'med|dNSE|':>10} {'p?':>3} {'s?':>3}")
    print("-" * 72)

    rows = []
    for v in VARIANTS:
        r = verify_one_variant(v)
        rows.append(r)
        if r.get("n_compared", 0) > 0:
            print(f"{v:<6} {r['status']:<15} "
                  f"{r['n_new']:>6} {r['n_old']:>6} "
                  f"{r['max_abs_dnse']:>10.6f} {r['median_abs_dnse']:>10.6f} "
                  f"{'Y' if r['has_p_columns'] else 'n':>3} "
                  f"{'Y' if r['has_state_columns'] else 'n':>3}")
        else:
            print(f"{v:<6} {r['status']:<15}")

    df_rows = pd.DataFrame(rows)
    out_dir = NEW_BASE / "verification"
    out_dir.mkdir(parents=True, exist_ok=True)
    df_rows.to_csv(out_dir / "per_variant_match.csv", index=False)

    # Strict precondition: rerun is only complete when ALL 9 variants have
    # p_* AND state_* columns. Otherwise the "new" data is still the OLD
    # data (rerun overwrites summary CSV only after writing all per-basin
    # CSVs), and any "PASS" verdict on numerical match is meaningless.
    all_have_p = all(r.get("has_p_columns") for r in rows)
    all_have_state = all(r.get("has_state_columns") for r in rows)
    rerun_complete = all_have_p and all_have_state

    print()
    print("=" * 72)
    print("ENSEMBLE REPRODUCTION")
    print("=" * 72)
    if not rerun_complete:
        n_p = sum(1 for r in rows if r.get("has_p_columns"))
        n_s = sum(1 for r in rows if r.get("has_state_columns"))
        print(f"  STATUS: WAITING FOR RERUN")
        print(f"  variants with p_* columns:     {n_p}/9")
        print(f"  variants with state_* columns: {n_s}/9")
        print(f"  Rerun must finish before reproducibility can be verified.")
        print(f"  Current 0.6227 below is from the ORIGINAL data (pre-rerun),")
        print(f"  not a verification that the new run matches.")
        agg = aggregate_ensemble(verbose=False)
        if agg["status"] == "ok":
            print()
            print("  (Diagnostic: original ensemble medians)")
            for rule, val in agg["medians"].items():
                print(f"    {rule:<22} median NSE = {val:+.4f}")
        return 1

    agg = aggregate_ensemble()
    if agg["status"] == "ok":
        for rule, val in agg["medians"].items():
            print(f"  {rule:<22} median NSE = {val:+.4f}")
        print()
        target = 0.6227
        delta = agg["medians"]["ens_cal_best"] - target
        if abs(delta) < 0.0001:
            print(f"PASS: ens_cal_best median {agg['medians']['ens_cal_best']:.4f} "
                  f"matches original {target} within tolerance.")
            print(f"      Rerun reproduces original numbers + adds p_* and state_* columns.")
        else:
            print(f"FAIL: ens_cal_best median {agg['medians']['ens_cal_best']:.4f} "
                  f"differs from original {target} by {delta:+.4f}.")
            print(f"      Investigate code changes between original run and rerun.")
        agg["df"].to_csv(out_dir / "new_ensemble_per_basin.csv", index=False)
    else:
        print(f"  Incomplete: {agg.get('n_variants_present', 0)}/9 variants "
              f"have summary CSVs. Run again after all variants complete.")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
