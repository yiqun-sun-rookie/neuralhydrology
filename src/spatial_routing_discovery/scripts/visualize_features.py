"""Visualize CNN feature maps and compare with drainage network.

Usage:
    cd <project_root>/src
    python -m spatial_routing_discovery.scripts.visualize_features \
        --results-dir ../results/spatial_routing_discovery --depth 4
"""

import argparse
import sys
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
import torch

_SRC_DIR = Path(__file__).resolve().parents[2]
if str(_SRC_DIR) not in sys.path:
    sys.path.insert(0, str(_SRC_DIR))

from spatial_routing_discovery.models import RoutingCNN, get_feature_maps
from spatial_routing_discovery.terrain import compute_d8_flow
from spatial_routing_discovery.dataset import generate_rainfall_event


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--results-dir", type=str, required=True)
    parser.add_argument("--depth", type=int, default=4)
    parser.add_argument("--hidden-channels", type=int, default=32)
    args = parser.parse_args()

    results_dir = Path(args.results_dir)
    dem = np.load(results_dir / "dem.npy")
    flow_acc = np.load(results_dir / "flow_acc.npy")
    size = dem.shape[0]

    model = RoutingCNN(depth=args.depth, in_channels=3, hidden_channels=args.hidden_channels)
    model.load_state_dict(torch.load(results_dir / f"model_depth{args.depth}.pt",
                                     map_location="cpu", weights_only=True))
    model.eval()

    dem_norm = (dem - dem.min()) / (dem.max() - dem.min() + 1e-8)

    rain_uniform = generate_rainfall_event(size=size, event_type="uniform", seed=0)
    rain_local = generate_rainfall_event(size=size, event_type="localized", seed=42)

    def make_input(rainfall):
        x = np.stack([dem_norm, np.zeros_like(dem), rainfall], axis=0)
        return torch.from_numpy(x).float().unsqueeze(0)

    x_uniform = make_input(rain_uniform)
    x_local = make_input(rain_local)

    with torch.no_grad():
        fm_uniform = get_feature_maps(model, x_uniform)
        fm_local = get_feature_maps(model, x_local)

    log_flow_acc = np.log1p(flow_acc.astype(np.float32))
    n_layers = len(fm_uniform)

    # Figure 1: Reference — DEM + drainage
    fig, axes = plt.subplots(1, 3, figsize=(15, 4))
    axes[0].imshow(dem, cmap="terrain")
    axes[0].set_title("DEM")
    axes[1].imshow(log_flow_acc, cmap="Blues")
    axes[1].set_title("Flow Accumulation (log)")
    axes[2].imshow(rain_local, cmap="YlGnBu")
    axes[2].set_title("Localized Rainfall")
    for ax in axes:
        ax.axis("off")
    plt.tight_layout()
    plt.savefig(results_dir / f"fig1_reference_depth{args.depth}.png", dpi=150)
    plt.close()

    # Figure 2: Per-layer feature maps for two rainfall scenarios
    fig, axes = plt.subplots(3, n_layers, figsize=(4 * n_layers, 12))
    if n_layers == 1:
        axes = axes.reshape(3, 1)
    for i in range(n_layers):
        act_uniform = fm_uniform[i][0].mean(dim=0).cpu().numpy()
        act_local = fm_local[i][0].mean(dim=0).cpu().numpy()
        act_diff = np.abs(act_uniform - act_local)
        axes[0, i].imshow(act_uniform, cmap="hot")
        axes[0, i].set_title(f"Layer {i+1}\nUniform Rain")
        axes[0, i].axis("off")
        axes[1, i].imshow(act_local, cmap="hot")
        axes[1, i].set_title(f"Layer {i+1}\nLocalized Rain")
        axes[1, i].axis("off")
        axes[2, i].imshow(act_diff, cmap="magma")
        axes[2, i].set_title(f"Layer {i+1}\n|Difference|")
        axes[2, i].axis("off")
    plt.suptitle(f"Feature Maps: Uniform vs Localized Rainfall (depth={args.depth})", fontsize=14)
    plt.tight_layout()
    plt.savefig(results_dir / f"fig2_dynamic_response_depth{args.depth}.png", dpi=150)
    plt.close()

    # Figure 3: Overlay — highest activation vs drainage
    fig, axes = plt.subplots(1, n_layers, figsize=(4 * n_layers, 4))
    if n_layers == 1:
        axes = [axes]
    channel_mask = log_flow_acc > np.percentile(log_flow_acc, 80)
    for i in range(n_layers):
        act = fm_local[i][0].mean(dim=0).cpu().numpy()
        act_thresh = act > np.percentile(act, 80)
        overlay = np.zeros((*dem.shape, 3))
        overlay[channel_mask, 0] = 1.0
        overlay[act_thresh, 2] = 1.0
        axes[i].imshow(overlay)
        axes[i].set_title(f"Layer {i+1}")
        axes[i].axis("off")
    plt.suptitle(f"Red=Drainage  Blue=High Activation  Purple=Overlap (depth={args.depth})", fontsize=12)
    plt.tight_layout()
    plt.savefig(results_dir / f"fig3_overlay_depth{args.depth}.png", dpi=150)
    plt.close()
    print(f"Figures saved to {results_dir}")


if __name__ == "__main__":
    main()
