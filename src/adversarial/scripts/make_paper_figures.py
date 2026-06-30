"""Regenerate the five main.tex figures from the ID18 result JSONs.
Run: python src/adversarial/scripts/make_paper_figures.py
"""
from __future__ import annotations

import json
from pathlib import Path

import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

ROOT = Path(__file__).resolve().parents[3]
R = ROOT / "results/05_adversarial_robustness/id18_s100"
FIG = ROOT / "draft/papers/05_adversarial_latex/figures"
FIG.mkdir(parents=True, exist_ok=True)
EPS = [0.01, 0.05, 0.1, 0.2]
plt.rcParams.update({"font.size": 10, "axes.grid": True, "grid.alpha": 0.3, "savefig.bbox": "tight"})


def load(n):
    return json.load(open(R / f"{n}.json"))


def _save(fig, name):
    for ext in ("pdf", "png"):
        fig.savefig(FIG / f"{name}.{ext}", dpi=200)
    plt.close(fig)
    print("wrote", name)


def fig1_epsilon_curve():
    e = {ep: load(f"exp1_eps{ep}") for ep in EPS}
    def med_iqr(key):
        m = [np.median([-r[key] for r in e[ep]]) for ep in EPS]
        lo = [np.quantile([-r[key] for r in e[ep]], 0.25) for ep in EPS]
        hi = [np.quantile([-r[key] for r in e[ep]], 0.75) for ep in EPS]
        return np.array(m), np.array(lo), np.array(hi)
    fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(9, 3.6))
    for key, lab, c in [("D_APGD", "Scheduled-step PGD", "#d62728"), ("D_FGSM", "FGSM", "#ff7f0e")]:
        m, lo, hi = med_iqr(key)
        ax1.plot(EPS, m, "o-", color=c, label=lab)
        ax1.fill_between(EPS, lo, hi, color=c, alpha=0.15)
    ax1.set(title="(a) Gradient attacks", xlabel=r"$\varepsilon$", ylabel=r"Median $\Delta$NSE")
    ax1.legend(); ax1.invert_yaxis()
    for key, lab, c in [("D_rs100", "Random sign", "#1f77b4"), ("D_gauss100", "Gaussian", "#2ca02c")]:
        m, lo, hi = med_iqr(key)
        ax2.plot(EPS, m, "s-", color=c, label=lab)
        ax2.fill_between(EPS, lo, hi, color=c, alpha=0.15)
    ax2.set(title="(b) Random baselines", xlabel=r"$\varepsilon$", ylabel=r"Median $\Delta$NSE")
    ax2.legend(); ax2.invert_yaxis()
    _save(fig, "fig1_epsilon_curve")


def fig2_basin_vulnerability():
    d = load("exp1_eps0.1")
    dn = np.array([-r["D_APGD"] for r in d])
    p10, p50, p90 = np.quantile(dn, [0.10, 0.50, 0.90])
    fig, ax = plt.subplots(figsize=(6.5, 3.8))
    ax.hist(dn, bins=50, color="#8c8c8c", edgecolor="white")
    for v, lab, c in [(p10, f"p10 {p10:.2f}", "#d62728"), (p50, f"median {p50:.2f}", "k"), (p90, f"p90 {p90:.2f}", "#1f77b4")]:
        ax.axvline(v, ls="--", color=c, label=lab)
    ax.set(xlabel=r"$\Delta$NSE under scheduled-step PGD ($\varepsilon=0.1$)", ylabel="Basins (N=531)")
    ax.legend()
    _save(fig, "fig2_basin_vulnerability")


def fig3_causal_window():
    d = [r for r in load("exp4_causal") if "error" not in r and r.get("n_peaks", 0) > 0]
    wins = [1, 3, 7, 14]
    peak = [[-r[f"D_peak_{w}"] for r in d] for w in wins]
    overall = [[-r[f"D_overall_{w}"] for r in d] for w in wins]
    fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(9, 3.6), sharex=True)
    for ax, data, title in [(ax1, peak, r"(a) $\Delta$NSE$_{\rm peak}$"), (ax2, overall, r"(b) $\Delta$NSE$_{\rm overall}$")]:
        bp = ax.boxplot(data, positions=range(len(wins)), widths=0.6, showfliers=False, patch_artist=True)
        for box in bp["boxes"]:
            box.set(facecolor="#aec7e8", alpha=0.7)
        for i, dd in enumerate(data):
            ax.annotate(f"{np.median(dd):.3f}", (i, np.median(dd)), ha="center", va="bottom", fontsize=8)
        ax.set(title=title, xlabel="Pre-event window (days)", ylabel=r"$\Delta$NSE")
        ax.set_xticks(range(len(wins))); ax.set_xticklabels(wins); ax.invert_yaxis()
    _save(fig, "fig3_causal_window")


def fig4_cw_perturbation():
    d = [r for r in load("exp5_cw") if "error" not in r]
    broke = [r["l2"] for r in d if r.get("success")]
    nfail = sum(1 for r in d if not r.get("success"))
    fig, ax = plt.subplots(figsize=(6, 3.8))
    ax.hist(broke, bins=20, color="#9467bd", edgecolor="white")
    ax.axvline(np.median(broke), ls="--", color="k", label=f"median {np.median(broke):.2f}")
    ax.set(xlabel=r"Minimum $L_2$ perturbation to reach NSE $<0$ (standardized)",
           ylabel=f"Basins ({len(broke)} of {len(d)} broken)")
    ax.annotate(f"{nfail} basins not broken\nwithin search budget", (0.97, 0.95),
                xycoords="axes fraction", ha="right", va="top", fontsize=8)
    ax.legend()
    _save(fig, "fig4_cw_perturbation")


def fig5_detectability():
    d = [r for r in load("exp_detect") if "error" not in r]
    absd = np.array([abs(r["D_nse"]) for r in d])
    pmin = np.array([max(r["ks_p_min"], 1e-300) for r in d])
    fig, ax = plt.subplots(figsize=(6.5, 3.8))
    ax.scatter(pmin, absd, s=20, color="#d62728", alpha=0.6)
    ax.axvline(0.05, ls="--", color="k", label=r"$p=0.05$")
    ax.set_xscale("log")
    ax.set(xlabel="Smallest-feature KS $p$-value (log scale)", ylabel=r"$|\Delta$NSE$|$ (magnitude-constrained PGD)")
    ax.annotate("all basins detectable\n(p far below 0.05)", (0.03, 0.95),
                xycoords="axes fraction", ha="left", va="top", fontsize=8)
    ax.legend(loc="lower right")
    _save(fig, "fig5_detectability")


if __name__ == "__main__":
    fig1_epsilon_curve()
    fig2_basin_vulnerability()
    fig3_causal_window()
    fig4_cw_perturbation()
    fig5_detectability()
    print("ALL FIGURES REGENERATED ->", FIG)
