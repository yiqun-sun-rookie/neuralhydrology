"""Independent recompute of the three-school (GR4J / XAJ / HBV) comparison table.

Reads each model's per-basin CSVs directly (NOT the summary files), restricts to
the COMMON basin set actually present for every model, and recomputes the
eval-period median NSE, pairwise median Δ, win-rates and ties. This is the S6
verification artifact: a dependency-light, standalone recompute that an
independent reviewer (or agent) can re-run to confirm the headline numbers are
faithful to the raw per-basin results.

Usage::

    python -X utf8 -m src.xaj_global_pilot.scripts.verify_three_school_table \
        --model "GR4J=results/10_global_conceptual_model_benchmark/camels_us_531_repro_v01/gr4j_pdd_cma_FINAL_pt_v1" \
        --model "XAJ=results/10_global_conceptual_model_benchmark/camels_us_531_repro_v01/xaj_pdd_cma_PT_v1_warmup" \
        --model "HBV=results/10_global_conceptual_model_benchmark/camels_us_531_repro_v01/hbv_lite_cma_FINAL_pt_v1_warmup" \
        --out results/10_global_conceptual_model_benchmark/camels_us_531_repro_v01/summary/_three_school_table.json

The ``--model`` flag is repeatable; order is the report order. The FIRST model
is treated as the reference for the pairwise Δ rows (Δ = ref − other).
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

_HERE = Path(__file__).resolve()
_REPO_ROOT = _HERE.parents[3]
if str(_REPO_ROOT / "src") not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT / "src"))
if str(_REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT))

import numpy as np  # noqa: E402
import pandas as pd  # noqa: E402

PERIOD = "evaluation"


def _load_model(path: Path) -> dict:
    """Return {basin_id(8-digit str): nse(float)} for eval-period successes."""
    files = sorted(path.glob("*.csv"))
    if not files:
        raise FileNotFoundError(f"No per-basin CSVs under {path}")
    out: dict[str, float] = {}
    n_rows = n_fail = 0
    for f in files:
        df = pd.read_csv(f, dtype={"basin_id": str}, keep_default_na=False)
        for _, row in df.iterrows():
            n_rows += 1
            if str(row.get("period", "")) != PERIOD:
                continue
            if str(row.get("run_status", "")) != "success":
                n_fail += 1
                continue
            try:
                nse = float(row["nse"])
            except (TypeError, ValueError):
                n_fail += 1
                continue
            if not np.isfinite(nse):
                n_fail += 1
                continue
            bid = str(row["basin_id"]).zfill(8)
            out[bid] = nse
    return {"nse": out, "n_files": len(files), "n_rows": n_rows, "n_fail": n_fail}


def _pair_stats(ref_nse: dict, oth_nse: dict, common: list[str]) -> dict:
    d = np.array([ref_nse[b] - oth_nse[b] for b in common], dtype=np.float64)
    wins = int((d > 0).sum())
    losses = int((d < 0).sum())
    ties = int((d == 0).sum())
    n = len(common)
    return {
        "n": n,
        "median_delta": float(np.median(d)),
        "mean_delta": float(np.mean(d)),
        "ref_win": wins,
        "ref_win_rate": round(wins / n, 4) if n else None,
        "other_win": losses,
        "ties": ties,
    }


def main(argv=None) -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--model", action="append", required=True,
                   help="LABEL=PER_BASIN_DIR (repeatable; first is the pairwise reference)")
    p.add_argument("--out", default=None, help="optional JSON output path")
    args = p.parse_args(argv)

    models: list[tuple[str, Path]] = []
    for spec in args.model:
        if "=" not in spec:
            print(f"FAIL: --model must be LABEL=PATH, got {spec!r}")
            return 1
        label, path = spec.split("=", 1)
        models.append((label.strip(), Path(path.strip())))

    loaded = {}
    for label, path in models:
        loaded[label] = _load_model(path)

    basin_sets = [set(loaded[label]["nse"]) for label, _ in models]
    common = sorted(set.intersection(*basin_sets)) if basin_sets else []
    n_common = len(common)

    print(f"# Three-school comparison recompute (period={PERIOD})")
    print(f"common basins across all {len(models)} models: {n_common}")
    print()
    print("| model | n_total | n_common | median NSE (common) | mean NSE (common) | failures |")
    print("|---|---|---|---|---|---|")
    per_model = {}
    for label, _ in models:
        nse = loaded[label]["nse"]
        arr = np.array([nse[b] for b in common], dtype=np.float64)
        med = float(np.median(arr)) if n_common else None
        mean = float(np.mean(arr)) if n_common else None
        per_model[label] = {
            "n_total": len(nse), "n_common": n_common,
            "median_nse": med, "mean_nse": mean,
            "n_fail": loaded[label]["n_fail"],
        }
        print(f"| {label} | {len(nse)} | {n_common} | "
              f"{med:.6f} | {mean:.6f} | {loaded[label]['n_fail']} |")

    ref_label = models[0][0]
    ref_nse = loaded[ref_label]["nse"]
    print()
    print(f"## Pairwise vs reference = {ref_label} (Δ = {ref_label} − other), on common {n_common}")
    print("| pair | median Δ | mean Δ | ref win | ref win-rate | other win | ties |")
    print("|---|---|---|---|---|---|---|")
    pairs = {}
    for label, _ in models[1:]:
        st = _pair_stats(ref_nse, loaded[label]["nse"], common)
        pairs[f"{ref_label}_vs_{label}"] = st
        print(f"| {ref_label} vs {label} | {st['median_delta']:+.4f} | {st['mean_delta']:+.4f} | "
              f"{st['ref_win']} | {st['ref_win_rate']:.3f} | {st['other_win']} | {st['ties']} |")

    result = {
        "period": PERIOD,
        "n_common": n_common,
        "models": [{"label": l, "dir": str(pth)} for l, pth in models],
        "per_model": per_model,
        "pairwise_vs_reference": {"reference": ref_label, "pairs": pairs},
    }
    if args.out:
        out_path = Path(args.out)
        out_path.parent.mkdir(parents=True, exist_ok=True)
        out_path.write_text(json.dumps(result, indent=2), encoding="utf-8")
        print(f"\nJSON written: {out_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
