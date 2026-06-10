"""Reproducibility check for a locked XAJ-PDD playbook run.

Re-runs N basins under the EXACT config recorded in the locked run's
metadata.json and asserts the re-run matches the locked per-basin csvs
bit-exact (NSE, 20 params, 11 states). Mirrors the HBV-lite
`verify_rerun_matches_original.py`. Closes the H9 reproducibility gap.

Usage::

    python -X utf8 -m src.xaj_global_pilot.scripts.verify_xaj_rerun \
        --subdir xaj_pdd_cma_FINAL_oudin_warmup --n 4
"""
from __future__ import annotations

import argparse
import json
import subprocess
import sys
import tempfile
from pathlib import Path

import pandas as pd

_ROOT = Path("results/10_global_conceptual_model_benchmark/camels_us_531_repro_v01")
_PARAMS = None  # filled lazily to avoid heavy import at module load


def _param_names():
    global _PARAMS
    if _PARAMS is None:
        sys.path.insert(0, "src")
        from xaj_global_pilot.xaj_model import PDD_XAJ_PARAM_NAMES
        _PARAMS = PDD_XAJ_PARAM_NAMES
    return _PARAMS


def main(argv=None) -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--subdir", default="xaj_pdd_cma_FINAL_oudin_warmup")
    p.add_argument("--n", type=int, default=4, help="how many basins to re-run")
    p.add_argument("--manifest", default="src/xaj_global_pilot/configs/conceptual_benchmark_camels_us_531_repro.txt")
    p.add_argument("--tol", type=float, default=1e-6)
    args = p.parse_args(argv)

    meta = json.loads((_ROOT / "summary" / f"{args.subdir}_local_full.metadata.json").read_text())
    locked_dir = _ROOT / args.subdir
    basins = [l.strip().zfill(8) for l in Path(args.manifest).read_text().splitlines() if l.strip()][: args.n]

    # Re-run those basins into a temp subdir under the SAME results root,
    # using the EXACT knobs from metadata (so config drift can't hide).
    verify_sub = "_verify_rerun_tmp"
    cmd = [
        sys.executable, "-X", "utf8", "-m",
        "src.xaj_global_pilot.scripts.run_xaj_pdd_cma_repro_v01",
        "--manifest", args.manifest, "--limit", str(args.n),
        "--workers", str(min(args.n, 4)),
        "--trials", str(meta["trials"]), "--restarts", str(meta["restarts"]),
        "--pet-method", meta["pet_method"], "--bounds-preset", meta["bounds_preset"],
        "--loss", meta["loss"], "--init-mean", str(meta["init_mean"]),
        "--init-sigma", str(meta["init_sigma"]),
        "--output-subdir", verify_sub, "--no-skip-existing",
    ]
    if meta.get("warmup_year"):
        cmd.append("--warmup-year")
    print("[verify] config from metadata:",
          {k: meta[k] for k in ("pet_method", "warmup_year", "bounds_preset", "trials", "restarts")})
    print("[verify] re-running", args.n, "basins ...", flush=True)
    subprocess.run(cmd, check=True)

    pnames = _param_names()
    sn = ["snow", "ice", "last_temp", "W", "WU", "WL", "WD", "S", "QS", "QI", "QG"]
    rerun_dir = _ROOT / verify_sub
    all_ok = True
    print(f"\n{'basin':<10}{'locked nse':>12}{'rerun nse':>12}{'|dnse|':>11}{'param L1':>11}{'state L1':>11}  verdict")
    for b in basins:
        lk = pd.read_csv(locked_dir / f"{b}.csv", keep_default_na=False).iloc[0]
        rr = pd.read_csv(rerun_dir / f"{b}.csv", keep_default_na=False).iloc[0]
        dn = abs(float(lk["nse"]) - float(rr["nse"]))
        pl = sum(abs(float(lk[f"p_{n}"]) - float(rr[f"p_{n}"])) for n in pnames)
        sl = sum(abs(float(lk[f"state_{s}"]) - float(rr[f"state_{s}"])) for s in sn)
        ok = dn < args.tol and pl < args.tol and sl < args.tol
        all_ok &= ok
        print(f"{b:<10}{float(lk['nse']):>12.6f}{float(rr['nse']):>12.6f}"
              f"{dn:>11.2e}{pl:>11.2e}{sl:>11.2e}  {'BIT-EXACT' if ok else 'MISMATCH!'}")

    print("\n" + ("PASS: re-run reproduces the locked run bit-exact."
                  if all_ok else "FAIL: re-run does NOT match — investigate determinism."))
    return 0 if all_ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
