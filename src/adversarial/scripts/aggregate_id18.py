"""Print every main.tex number from the ID18 result JSONs — single source of truth for the
rewrite. Robust to not-yet-finished experiments (prints PENDING for missing files).

Run: python src/adversarial/scripts/aggregate_id18.py | tee results/05_adversarial_robustness/id18_s100/AGGREGATE.txt
"""
from __future__ import annotations

import json
from pathlib import Path

import numpy as np

R = Path(__file__).resolve().parents[3] / "results/05_adversarial_robustness/id18_s100"


def load(name):
    p = R / f"{name}.json"
    if not p.exists():
        return None
    return json.load(open(p))


def q(x, p):
    return float(np.quantile(np.asarray(x, float), p))


def med(x):
    return float(np.median(np.asarray(x, float)))


def fmt_iqr(x):
    return f"{med(x):+.3f} [{q(x,0.25):+.3f}, {q(x,0.75):+.3f}]"


def sec(title):
    print("\n" + "=" * 70 + f"\n{title}\n" + "=" * 70)


# ---------- Exp1: attack-method comparison (531) ----------
sec("EXP1  attack-method comparison (531 basins)")
EPS = ["0.01", "0.05", "0.1", "0.2"]
e1 = {e: load(f"exp1_eps{e}") for e in EPS}
if all(e1.values()):
    n_finite = sum(np.isfinite([r["nse_clean"] for r in e1["0.1"]]))
    print(f"finite nse_clean: {n_finite}/{len(e1['0.1'])}  (drop the old N=514/17-non-finite caveat if 531/531)")
    print(f"{'eps':>5} | {'APGD med[IQR]':>26} | {'FGSM med':>9} | {'rs100 med':>10} | {'gauss100':>9} "
          f"| {'A/rs100':>7} | {'A/FGSM':>7} | {'%adv<0':>7} | {'%dNSE<-1':>8}")
    for e in EPS:
        d = e1[e]
        apgd = [r["D_APGD"] for r in d]
        fg = [r["D_FGSM"] for r in d]
        rs = [r["D_rs100"] for r in d]
        gz = [r["D_gauss100"] for r in d]
        nc = np.array([r["nse_clean"] for r in d])
        adv = nc - np.array(apgd)
        pct_b0 = 100 * np.mean(adv < 0)
        pct_bm1 = 100 * np.mean(np.array(apgd) > 1.0)  # ΔNSE < -1
        print(f"{e:>5} | {fmt_iqr([-a for a in apgd]):>26} | {-med(fg):+.3f} | {-med(rs):+.4f}  "
              f"| {-med(gz):+.4f} | {med(apgd)/med(rs):6.2f}x | {med(apgd)/med(fg):6.3f}x "
              f"| {pct_b0:6.1f}% | {pct_bm1:7.1f}%")
    # Fig 2 percentiles (eps=0.1, ΔNSE = -D_APGD)
    d = e1["0.1"]
    dn = -np.array([r["D_APGD"] for r in d])
    print(f"\nFig2 (eps0.1 ΔNSE): p10={q(dn,0.10):+.3f}  median={q(dn,0.50):+.3f}  p90={q(dn,0.90):+.3f}")
    # skill stratification (not-a-low-skill-artifact)
    nc = np.array([r["nse_clean"] for r in d]); apgd = np.array([r["D_APGD"] for r in d]); rs = np.array([r["D_rs100"] for r in d])
    print("skill bins (clean NSE): n | med ΔNSE | A/rs100 | %adv<0")
    for lo, hi, lab in [(-9, 0.3, "<0.3"), (0.3, 0.5, "0.3-0.5"), (0.5, 0.7, "0.5-0.7"), (0.7, 0.8, "0.7-0.8"), (0.8, 9, ">=0.8")]:
        m = (nc >= lo) & (nc < hi)
        if m.sum():
            print(f"  {lab:8} {int(m.sum()):4d} | {-med(apgd[m]):+.3f} | {med(apgd[m])/med(rs[m]):5.1f}x | {100*np.mean((nc-apgd)[m]<0):5.1f}%")
else:
    print("PENDING (need exp1_eps*.json)")

# ---------- Exp2: constraint ablation (107) ----------
sec("EXP2  constraint ablation (107)")
e2 = load("exp2_constraint_ablation")
if e2:
    for e in ["0.05", "0.1", "0.2"]:
        lp = [r[f"D_lp_{e}"] for r in e2]; ph = [r[f"D_physical_{e}"] for r in e2]; st = [r[f"D_statistical_{e}"] for r in e2]
        print(f"eps {e}: lp med={med(lp):.4f} mean={np.mean(lp):.4f} | phys med={med(ph):.4f} | stat med={med(st):.4f}"
              f" | %lp: lp=100 phys={100*med(ph)/med(lp):.0f} stat={100*med(st)/med(lp):.0f}")
else:
    print("PENDING")

# ---------- Exp3: targeted ΔNSE + ΔKGE (107) ----------
sec("EXP3  targeted ΔNSE + ΔKGE (107)")
e3 = load("exp3_targeted")
if e3 and "dkge_untargeted" in e3[0]:
    for t in ["untargeted", "flood", "lowflow"]:
        dn = [r[f"D_{t}"] for r in e3]; dk = [r[f"dkge_{t}"] for r in e3]
        print(f"{t:11}: ΔNSE {fmt_iqr([-x for x in dn])} | ΔKGE {fmt_iqr(dk)}")
    fl = med([r["D_flood"] for r in e3]); lo = med([r["D_lowflow"] for r in e3])
    print(f"flood/lowflow ΔNSE ratio = {fl/max(lo,1e-9):.2f}x  | median kge_clean = {med([r['kge_clean'] for r in e3]):.3f}")
elif e3:
    print("PENDING ΔKGE (exp3 present but no dkge keys — rerun run_exp3.py)")
else:
    print("PENDING")

# ---------- Exp4: causal-trigger (107) ----------
sec("EXP4  causal-trigger pre-event (107)")
e4 = load("exp4_causal")
if e4:
    ok = [r for r in e4 if "error" not in r and r.get("n_peaks", 0) > 0]
    print(f"basins with peaks: {len(ok)}  | median n_peaks = {med([r['n_peaks'] for r in ok]):.0f}")
    for w in [1, 3, 7, 14]:
        dp = [r[f"D_peak_{w}"] for r in ok]; do = [r[f"D_overall_{w}"] for r in ok]
        print(f"  {w:2}d: D_peak med={med(dp):+.4f}  | D_overall med={med(do):+.4f}")
else:
    print("PENDING")

# ---------- Exp5: C&W min-L2 (76) ----------
sec("EXP5  C&W minimum-L2 safety margin")
e5 = load("exp5_cw")
if e5:
    ok = [r for r in e5 if "error" not in r]
    broke = [r for r in ok if r.get("success")]
    print(f"evaluated {len(ok)}; broke (NSE<0) {len(broke)} ({100*len(broke)/max(len(ok),1):.1f}%)")
    if broke:
        l2 = [r["l2"] for r in broke]
        print(f"min-L2 to break: median={med(l2):.3f}  [Q25={q(l2,0.25):.3f}, Q75={q(l2,0.75):.3f}]  p10={q(l2,0.1):.3f} p90={q(l2,0.9):.3f}")
else:
    print("PENDING")

# ---------- Exp6: Yang KGE (107) ----------
sec("EXP6  Yang reconciliation KGE (107)")
e6 = load("exp6_yang_kge")
if e6:
    kc = med([r["kge_clean"] for r in e6]); dk = med([r["dkge"] for r in e6])
    print(f"median kge_clean={kc:.3f}  median ΔKGE={dk:+.3f}  relative={100*dk/kc:+.1f}%  (Yang ΔKGE=-0.105/0.833=-12.6%)")
else:
    print("PENDING")

# ---------- detect: KS detectability (107) ----------
sec("DETECT  KS detectability (107)")
ed = load("exp_detect")
if ed:
    ok = [r for r in ed if "error" not in r]
    pmin = np.array([r["ks_p_min"] for r in ok])
    dn = np.array([r["D_nse"] for r in ok])
    frac_invisible = 100 * np.mean(pmin > 0.05)
    # of high-damage basins (|ΔNSE|>0.1), how many are KS-invisible
    hi = dn > 0.1
    print(f"basins with min-feature KS p>0.05 (undetectable): {frac_invisible:.1f}%")
    if hi.sum():
        print(f"of {int(hi.sum())} basins with ΔNSE<-0.1: {100*np.mean(pmin[hi]>0.05):.1f}% have KS p>0.05 (effective AND invisible)")
else:
    print("PENDING")

# ---------- ksweep (21) ----------
sec("KSWEEP  random best-of-K scaling (21)")
ks = load("ksweep")
if ks:
    Ks = [1, 3, 10, 30, 100, 300, 1000, 2000]
    apgd = np.array([r["D_APGD"] for r in ks])
    medr = {K: med([r["D_random_K"][str(K)] for r in ks]) for K in Ks}
    Kfit = [k for k in Ks if k >= 10]
    x = np.sqrt(np.log(Kfit)); y = np.array([medr[k] for k in Kfit])
    A = np.vstack([x, np.ones_like(x)]).T
    a, b = np.linalg.lstsq(A, y, rcond=None)[0]
    pred = a * np.sqrt(np.log(1e9)) + b
    print(f"median D_APGD={med(apgd):.4f}; random best-of-K fit a*sqrt(lnK)+b: a={a:.5f} b={b:.5f}")
    print(f"extrapolated K=1e9 -> random={pred:.4f}; APGD/random(1e9) = {med(apgd)/pred:.1f}x")
else:
    print("PENDING")

print("\n" + "=" * 70 + "\nDONE\n" + "=" * 70)
