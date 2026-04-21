"""Experiment: Can a CNN learn a delay map that aligns with flow distance?

Usage:
    cd <project_root>/src
    python -m spatial_routing_discovery.scripts.run_delay_experiment
"""
import sys
from pathlib import Path
from collections import deque

import numpy as np
import torch
import torch.nn as nn
from torch.utils.data import Dataset, DataLoader, random_split

_SRC_DIR = Path(__file__).resolve().parents[2]
if str(_SRC_DIR) not in sys.path:
    sys.path.insert(0, str(_SRC_DIR))

from spatial_routing_discovery.terrain import generate_dem, compute_d8_flow, _D8_DR, _D8_DC
from spatial_routing_discovery.simulator import WaterSimulator
from spatial_routing_discovery.dataset import generate_rainfall_event
from spatial_routing_discovery.analysis import correlation_with_drainage

N_STEPS = 50
RAIN_STEPS = 5


def compute_flow_distance(dem):
    """Compute flow distance (in D8 steps) from each cell to the outlet."""
    flow_dir, _ = compute_d8_flow(dem)
    outlet_pos = np.argwhere(dem == dem.min())[0]
    nrows, ncols = dem.shape
    flow_dist = np.full((nrows, ncols), -1, dtype=np.int32)
    flow_dist[outlet_pos[0], outlet_pos[1]] = 0

    # Build reverse graph
    reverse_graph = {}
    for r in range(nrows):
        for c in range(ncols):
            d = flow_dir[r, c]
            if d >= 0:
                nr, nc = r + _D8_DR[d], c + _D8_DC[d]
                reverse_graph.setdefault((nr, nc), []).append((r, c))

    queue = deque([(outlet_pos[0], outlet_pos[1])])
    while queue:
        r, c = queue.popleft()
        for (ur, uc) in reverse_graph.get((r, c), []):
            if flow_dist[ur, uc] == -1:
                flow_dist[ur, uc] = flow_dist[r, c] + 1
                queue.append((ur, uc))
    return flow_dist


class HydrographDataset(Dataset):
    def __init__(self, dem_size=64, dem_seed=42, n_events=300, n_steps=N_STEPS):
        self.dem = generate_dem(size=dem_size, seed=dem_seed)
        self.dem_norm = (self.dem - self.dem.min()) / (self.dem.max() - self.dem.min() + 1e-8)
        et = ["uniform", "localized", "moving"]
        self.samples = []
        for ei in range(n_events):
            etype = et[ei % 3]
            intensity = 0.005 + 0.03 * (ei % 7) / 6
            rain = generate_rainfall_event(size=dem_size, event_type=etype, seed=ei * 13 + 1, intensity=intensity)
            sim = WaterSimulator(self.dem, flow_fraction=0.5)
            hydro = np.zeros(n_steps, dtype=np.float32)
            for t in range(n_steps):
                if t < RAIN_STEPS:
                    sim.add_rainfall(rain)
                prev = sim.outlet_loss
                sim.step()
                hydro[t] = sim.outlet_loss - prev
            self.samples.append((rain, hydro))

    def __len__(self):
        return len(self.samples)

    def __getitem__(self, i):
        rain, hydro = self.samples[i]
        x = np.stack([self.dem_norm, rain], axis=0)
        return torch.from_numpy(x).float(), torch.from_numpy(hydro).float()


class DelayMapCNN(nn.Module):
    """CNN outputs weight_map + delay_map per pixel.

    Q(t) = sum_{i,j} weight(i,j) * rain(i,j) * gaussian(t - delay(i,j), sigma)
    """

    def __init__(self, depth=4, hidden_ch=32, n_steps=N_STEPS, max_delay=40):
        super().__init__()
        layers = []
        for i in range(depth):
            ic = 2 if i == 0 else hidden_ch
            layers.append(nn.Conv2d(ic, hidden_ch, kernel_size=3, padding=1))
            layers.append(nn.ReLU(inplace=True))
        self.features = nn.Sequential(*layers)
        self.weight_head = nn.Conv2d(hidden_ch, 1, kernel_size=1)
        self.delay_head = nn.Conv2d(hidden_ch, 1, kernel_size=1)
        self.n_steps = n_steps
        self.max_delay = max_delay
        self.kernel_width = nn.Parameter(torch.tensor(2.0))

    def forward(self, x):
        h = self.features(x)
        weight_map = torch.sigmoid(self.weight_head(h)).squeeze(1)  # (B, H, W)
        delay_map = torch.sigmoid(self.delay_head(h)).squeeze(1) * self.max_delay  # (B, H, W)
        rain = x[:, 1, :, :]  # (B, H, W)

        contribution = weight_map * rain  # (B, H, W)
        t_range = torch.arange(self.n_steps, dtype=torch.float32, device=x.device)
        delay_exp = delay_map.unsqueeze(-1)  # (B, H, W, 1)
        t_exp = t_range.view(1, 1, 1, -1)  # (1, 1, 1, T)

        sigma = torch.abs(self.kernel_width) + 0.5
        kernel = torch.exp(-0.5 * ((t_exp - delay_exp) / sigma) ** 2)
        kernel = kernel / (kernel.sum(dim=-1, keepdim=True) + 1e-8)

        contrib_exp = contribution.unsqueeze(-1)  # (B, H, W, 1)
        hydrograph = (contrib_exp * kernel).sum(dim=(1, 2))  # (B, T)
        return hydrograph, weight_map, delay_map


def main():
    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    print(f"Device: {device}")

    dem = generate_dem(size=64, seed=42)
    _, flow_acc = compute_d8_flow(dem)
    flow_dist = compute_flow_distance(dem)
    dem_norm = (dem - dem.min()) / (dem.max() - dem.min() + 1e-8)
    print(f"Flow distance range: {flow_dist[flow_dist >= 0].min()} - {flow_dist.max()}")

    out_dir = Path(__file__).resolve().parents[3] / "results" / "spatial_routing_discovery"
    out_dir.mkdir(parents=True, exist_ok=True)

    print("Generating dataset (300 events)...")
    ds = HydrographDataset(n_events=300)
    nv = len(ds) // 5
    nt = len(ds) - nv
    tr, va = random_split(ds, [nt, nv], generator=torch.Generator().manual_seed(42))
    tl = DataLoader(tr, batch_size=32, shuffle=True)
    vl = DataLoader(va, batch_size=32)

    model = DelayMapCNN(depth=4, hidden_ch=32, n_steps=N_STEPS).to(device)
    opt = torch.optim.Adam(model.parameters(), lr=1e-3)
    crit = nn.MSELoss()

    print("Training...")
    best_val = float("inf")
    for ep in range(100):
        model.train()
        for x, y in tl:
            x, y = x.to(device), y.to(device)
            pred, _, _ = model(x)
            loss = crit(pred, y)
            opt.zero_grad()
            loss.backward()
            opt.step()
        model.eval()
        vl_loss = 0
        with torch.no_grad():
            for x, y in vl:
                x, y = x.to(device), y.to(device)
                pred, _, _ = model(x)
                vl_loss += crit(pred, y).item() * x.size(0)
        vl_loss /= len(vl.dataset)
        best_val = min(best_val, vl_loss)
        if (ep + 1) % 20 == 0:
            print(f"  Epoch {ep+1}/100  val_loss={vl_loss:.6f}  best={best_val:.6f}")

    # ===== Analyze =====
    model.eval()
    rain_test = generate_rainfall_event(size=64, event_type="localized", seed=42)
    x_test = np.stack([dem_norm, rain_test], axis=0)
    x_t = torch.from_numpy(x_test).float().unsqueeze(0).to(device)

    with torch.no_grad():
        pred_hydro, weight_map, delay_map = model(x_t)

    weight_np = weight_map[0].cpu().numpy()
    delay_np = delay_map[0].cpu().numpy()

    # Correlations with ground truth
    fd_float = flow_dist.astype(np.float32)
    fd_float[flow_dist < 0] = 0
    r_delay_fd = correlation_with_drainage(delay_np, fd_float)
    r_delay_fa = correlation_with_drainage(delay_np, flow_acc)
    r_weight_fa = correlation_with_drainage(weight_np, flow_acc)

    print(f"\n===== RESULTS =====")
    print(f"Val loss: {best_val:.6f}")
    print(f"Delay map vs flow_distance: r = {r_delay_fd:.3f}")
    print(f"Delay map vs flow_acc:      r = {r_delay_fa:.3f}")
    print(f"Weight map vs flow_acc:     r = {r_weight_fa:.3f}")
    print(f"Delay range: {delay_np.min():.1f} - {delay_np.max():.1f}")
    print(f"Weight range: {weight_np.min():.4f} - {weight_np.max():.4f}")

    # Control: random model
    torch.manual_seed(999)
    rand_model = DelayMapCNN(depth=4, hidden_ch=32, n_steps=N_STEPS).to(device)
    rand_model.eval()
    with torch.no_grad():
        _, rw, rd = rand_model(x_t)
    r_rand_delay = correlation_with_drainage(rd[0].cpu().numpy(), fd_float)
    r_rand_weight = correlation_with_drainage(rw[0].cpu().numpy(), flow_acc)
    print(f"\nRandom model controls:")
    print(f"  Random delay vs flow_dist:  r = {r_rand_delay:.3f}")
    print(f"  Random weight vs flow_acc:  r = {r_rand_weight:.3f}")

    # Delay map consistency across different rainfall
    rain_test2 = generate_rainfall_event(size=64, event_type="uniform", seed=0)
    x_t2 = torch.from_numpy(np.stack([dem_norm, rain_test2], axis=0)).float().unsqueeze(0).to(device)
    with torch.no_grad():
        _, _, delay_map2 = model(x_t2)
    delay_consistency = correlation_with_drainage(delay_np, delay_map2[0].cpu().numpy())
    print(f"\nDelay map consistency (localized vs uniform rain): r = {delay_consistency:.3f}")

    # Save
    np.save(out_dir / "delay_map.npy", delay_np)
    np.save(out_dir / "weight_map.npy", weight_np)
    np.save(out_dir / "flow_dist.npy", flow_dist)
    torch.save(model.state_dict(), out_dir / "model_delay_depth4.pt")

    # Visualize
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    fig, axes = plt.subplots(2, 4, figsize=(20, 10))

    axes[0, 0].imshow(dem, cmap="terrain")
    axes[0, 0].set_title("DEM")
    axes[0, 1].imshow(fd_float, cmap="viridis")
    axes[0, 1].set_title(f"Flow Distance\n(ground truth)")
    axes[0, 2].imshow(delay_np, cmap="viridis")
    axes[0, 2].set_title(f"Learned Delay Map\nr={r_delay_fd:.3f} vs flow_dist")
    axes[0, 3].imshow(np.log1p(flow_acc.astype(np.float32)), cmap="Blues")
    axes[0, 3].set_title("Flow Accumulation (log)")

    axes[1, 0].imshow(rain_test, cmap="YlGnBu")
    axes[1, 0].set_title("Rainfall Input")
    axes[1, 1].imshow(weight_np, cmap="hot")
    axes[1, 1].set_title(f"Learned Weight Map\nr={r_weight_fa:.3f} vs flow_acc")
    axes[1, 2].scatter(fd_float.flatten(), delay_np.flatten(), s=0.5, alpha=0.3)
    axes[1, 2].set_xlabel("Flow Distance (ground truth)")
    axes[1, 2].set_ylabel("Learned Delay")
    axes[1, 2].set_title(f"Scatter: r={r_delay_fd:.3f}")

    # Plot actual vs predicted hydrograph
    actual_hydro = ds[0][1].numpy()
    with torch.no_grad():
        x0 = ds[0][0].unsqueeze(0).to(device)
        pred0, _, _ = model(x0)
    axes[1, 3].plot(actual_hydro, "b-", label="Actual")
    axes[1, 3].plot(pred0[0].cpu().numpy(), "r--", label="Predicted")
    axes[1, 3].set_title("Hydrograph: Actual vs Predicted")
    axes[1, 3].legend()
    axes[1, 3].set_xlabel("Time step")

    for ax in axes[0, :]:
        ax.axis("off")
    axes[1, 0].axis("off")
    axes[1, 1].axis("off")

    plt.suptitle("Delay Map CNN: Can the network learn flow distance?", fontsize=14)
    plt.tight_layout()
    plt.savefig(out_dir / "fig6_delay_map_results.png", dpi=150)
    print(f"\nFigure saved to {out_dir / 'fig6_delay_map_results.png'}")


if __name__ == "__main__":
    main()
