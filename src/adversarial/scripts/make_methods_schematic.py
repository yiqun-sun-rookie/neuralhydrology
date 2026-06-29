"""Generate the Methods conceptual schematic for the adversarial paper.

Shows where perturbations live (red) and where loss is computed (blue) for
each of the six attack methods used in the study, against a synthetic
streamflow background with two flood peaks.

Run:
    python src/adversarial/scripts/make_methods_schematic.py
"""
from __future__ import annotations

from pathlib import Path

import matplotlib.patches as mpatches
import matplotlib.pyplot as plt
import numpy as np

OUT_DIR = (
    Path(__file__).resolve().parents[3]
    / "draft/papers/05_adversarial_latex/figures"
)

# ----------------------------------------------------------- synthetic hydrograph
T = 100
days = np.arange(T)
peaks = [30, 70]
peak_widths = [6, 6]
peak_amps = [5.0, 4.5]
baseline = 1.0
hydrograph = baseline * np.ones(T)
for p, w, a in zip(peaks, peak_widths, peak_amps):
    hydrograph += a * np.exp(-((days - p) / w) ** 2)
rng = np.random.default_rng(42)
hydrograph += 0.08 * rng.standard_normal(T)
hydrograph = np.maximum(hydrograph, 0.3)

# ----------------------------------------------------------- methods table
methods = [
    {
        "name": "Gaussian noise",
        "p_mask": "full", "t_mask": "full",
        "n_iter": "N = 0",
        "note": "random sample; no gradient",
    },
    {
        "name": "FGSM",
        "p_mask": "full", "t_mask": "full",
        "n_iter": "N = 1",
        "note": r"single step $\varepsilon \cdot \mathrm{sign}(\nabla\mathcal{L})$",
    },
    {
        "name": "Auto-PGD",
        "p_mask": "full", "t_mask": "full",
        "n_iter": "N = 50",
        "note": "iterative gradient + projection",
    },
    {
        "name": "Targeted (flood)",
        "p_mask": "full", "t_mask": "flood-top10",
        "n_iter": "N = 50",
        "note": "loss only on top-10% flow days",
    },
    {
        "name": "Causal Trigger",
        "p_mask": "pre-event", "t_mask": "post-event",
        "n_iter": "N = 100",
        "note": "pre / post temporally separated",
    },
    {
        "name": "C&W",
        "p_mask": "full", "t_mask": "cw",
        "n_iter": "N = 200",
        "note": r"min $\|\boldsymbol{\delta}\|_2$ s.t. NSE $< 0$",
    },
]

PRE_WINDOW = 14
POST_WINDOW = 7

# ----------------------------------------------------------- mask builders
def build_p_mask(spec):
    m = np.zeros(T)
    if spec == "full":
        m[:] = 1.0
    elif spec == "pre-event":
        for p in peaks:
            m[max(0, p - PRE_WINDOW):p] = 1.0
    return m


def build_t_mask(spec):
    if spec == "full":
        return np.ones(T)
    if spec == "flood-top10":
        # Binary hard mask: timesteps with observed flow >= 90th percentile.
        # Mirrors the actual `targeted_flood_loss` implementation in losses.py.
        threshold = np.quantile(hydrograph, 0.90)
        m = (hydrograph >= threshold).astype(float)
        return m
    if spec == "post-event":
        m = np.zeros(T)
        for p in peaks:
            m[p:min(T, p + POST_WINDOW)] = 1.0
        return m
    if spec == "cw":
        return None
    return np.ones(T)


# ----------------------------------------------------------- plot
fig, axes = plt.subplots(
    7, 1, figsize=(11.5, 8.5),
    gridspec_kw={"height_ratios": [1.5] + [1.0] * 6, "hspace": 0.25},
)

PERTURB_COLOR = "#d62728"
LOSS_COLOR = "#1f77b4"

# Top axis: hydrograph background
ax_top = axes[0]
ax_top.fill_between(days, 0, hydrograph, color="#cccccc", alpha=0.7)
ax_top.plot(days, hydrograph, color="#444", linewidth=1.0)
for p in peaks:
    ax_top.axvline(p, color="black", linestyle=":", linewidth=0.7, alpha=0.5)
    ax_top.annotate(
        "flood peak",
        xy=(p, hydrograph[p]),
        xytext=(p, hydrograph[p] + 1.4),
        ha="center", fontsize=8,
        arrowprops=dict(arrowstyle="-", color="black", lw=0.5),
    )
ax_top.set_xlim(-1, T)
ax_top.set_ylim(0, hydrograph.max() * 1.55)
ax_top.set_xticks([])
ax_top.set_yticks([])
ax_top.set_ylabel(
    r"$Q_{\mathrm{obs}}$",
    rotation=0, ha="right", va="center", fontsize=11,
)
for sp in ["top", "right", "left", "bottom"]:
    ax_top.spines[sp].set_visible(False)

# Method rows
for i, m in enumerate(methods):
    ax = axes[i + 1]
    ax.set_xlim(-1, T)
    ax.set_ylim(0, 1.0)

    p_mask = build_p_mask(m["p_mask"])
    t_mask = build_t_mask(m["t_mask"])

    # Perturbation row (top stripe). C&W gets a hatched fill to signal that
    # the perturbation magnitude is itself the optimization target rather than
    # being fixed at a budget epsilon.
    if m["name"] == "C&W":
        for d in range(T):
            if p_mask[d] > 0:
                ax.add_patch(mpatches.Rectangle(
                    (d - 0.5, 0.55), 1.0, 0.4,
                    facecolor=PERTURB_COLOR, alpha=0.35,
                    edgecolor=PERTURB_COLOR, linewidth=0.0,
                    hatch="//",
                ))
    else:
        for d in range(T):
            if p_mask[d] > 0:
                ax.add_patch(mpatches.Rectangle(
                    (d - 0.5, 0.55), 1.0, 0.4,
                    facecolor=PERTURB_COLOR, alpha=0.75,
                    edgecolor="none",
                ))

    # Loss row (bottom stripe)
    if t_mask is None:
        ax.text(
            T / 2, 0.25, m["note"],
            ha="center", va="center",
            fontsize=10, style="italic", color=LOSS_COLOR,
        )
    elif isinstance(t_mask, np.ndarray):
        for d in range(T):
            if t_mask[d] > 0:
                ax.add_patch(mpatches.Rectangle(
                    (d - 0.5, 0.05), 1.0, 0.4,
                    facecolor=LOSS_COLOR, alpha=0.85,
                    edgecolor="none",
                ))

    # Method name (left of axis)
    ax.text(
        -3, 0.5, m["name"],
        ha="right", va="center",
        fontsize=11.5, fontweight="bold",
    )

    # Sub-bar legends (just inside axis on the left)
    ax.text(-1.2, 0.75, r"$\delta$", ha="right", va="center", fontsize=11, color=PERTURB_COLOR)
    ax.text(-1.2, 0.25, r"$\mathcal{L}$", ha="right", va="center", fontsize=11, color=LOSS_COLOR)

    # Right column: iteration + note
    ax.text(
        T + 1.5, 0.75, m["n_iter"],
        ha="left", va="center",
        fontsize=9, fontweight="bold",
    )
    if t_mask is not None:
        ax.text(
            T + 1.5, 0.25, m["note"],
            ha="left", va="center",
            fontsize=8, style="italic", color="#444",
        )

    # Peak markers
    for p in peaks:
        ax.axvline(p, color="black", linestyle=":", linewidth=0.4, alpha=0.25)

    # Causal Trigger: draw a curved arrow showing LSTM state propagation
    # from the pre-event perturbation window into the post-event loss window.
    if m["name"] == "Causal Trigger":
        for p in peaks:
            x_from = p - 1            # last day of pre window
            x_to = p + 1              # first full day of post window
            ax.annotate(
                "",
                xy=(x_to, 0.30), xytext=(x_from, 0.70),
                arrowprops=dict(
                    arrowstyle="->",
                    color="#444",
                    lw=1.0,
                    connectionstyle="arc3,rad=-0.55",
                ),
            )
        # Annotate the first arrow with a hidden-state label
        ax.text(
            peaks[0] + 0.5, 0.5, r"$h_t$",
            ha="left", va="center",
            fontsize=9, color="#444",
        )

    ax.set_xticks([])
    ax.set_yticks([])
    for sp in ax.spines.values():
        sp.set_visible(False)

# Bottom row gets a time axis
ax_last = axes[-1]
ax_last.set_xticks([0, peaks[0], peaks[1], T - 1])
ax_last.set_xticklabels(
    ["0", rf"$t_1\!=\!{peaks[0]}$", rf"$t_2\!=\!{peaks[1]}$", rf"$T\!=\!{T - 1}$"],
    fontsize=8,
)
ax_last.spines["bottom"].set_visible(True)
ax_last.tick_params(axis="x", length=3)
ax_last.set_xlabel("Day index in test sequence", fontsize=9)

# Title and legend
fig.suptitle(
    r"Where perturbations live ($\delta$, red) and where loss is evaluated ($\mathcal{L}$, blue)",
    fontsize=12, y=0.985,
)

legend_handles = [
    mpatches.Patch(color=PERTURB_COLOR, alpha=0.75, label=r"$\delta$: perturbation allowed"),
    mpatches.Patch(color=LOSS_COLOR, alpha=0.75, label=r"$\mathcal{L}$: loss evaluated"),
]
fig.legend(
    handles=legend_handles,
    loc="upper right", frameon=False, fontsize=9,
    bbox_to_anchor=(0.985, 0.965),
)

OUT_DIR.mkdir(parents=True, exist_ok=True)
out_pdf = OUT_DIR / "fig_methods_schematic.pdf"
out_png = OUT_DIR / "fig_methods_schematic.png"
# Save PNG first (cheaper); fall back gracefully if PDF target is locked.
fig.savefig(out_png, dpi=150, bbox_inches="tight")
print(f"Saved: {out_png}")
try:
    fig.savefig(out_pdf, dpi=200, bbox_inches="tight")
    print(f"Saved: {out_pdf}")
except PermissionError:
    print(f"SKIP {out_pdf} (locked); PNG updated, rerun after closing viewer.")
plt.close(fig)
