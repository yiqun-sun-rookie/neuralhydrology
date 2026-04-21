"""Delay Map experiment v2: 300 steps, max_delay=150, depth=6."""
import sys
from pathlib import Path
from collections import deque

import numpy as np
import torch
import torch.nn as nn
from torch.utils.data import Dataset, DataLoader, random_split

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

_SRC_DIR = Path(__file__).resolve().parents[2]
if str(_SRC_DIR) not in sys.path:
    sys.path.insert(0, str(_SRC_DIR))

from spatial_routing_discovery.terrain import generate_dem, compute_d8_flow, _D8_DR, _D8_DC
from spatial_routing_discovery.simulator import WaterSimulator
from spatial_routing_discovery.dataset import generate_rainfall_event
from spatial_routing_discovery.analysis import correlation_with_drainage

N_STEPS = 300
RAIN_STEPS = 5
MAX_DELAY = 150


def compute_flow_distance(dem):
    flow_dir, _ = compute_d8_flow(dem)
    outlet_pos = np.argwhere(dem == dem.min())[0]
    nrows, ncols = dem.shape
    flow_dist = np.full((nrows, ncols), -1, dtype=np.int32)
    flow_dist[outlet_pos[0], outlet_pos[1]] = 0
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
            rain = generate_rainfall_event(
                size=dem_size, event_type=etype, seed=ei * 13 + 1, intensity=intensity
            )
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
    def __init__(self, depth=6, hidden_ch=48, n_steps=N_STEPS, max_delay=MAX_DELAY):
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
        self.kernel_width = nn.Parameter(torch.tensor(3.0))

    def forward(self, x):
        h = self.features(x)
        weight_map = torch.sigmoid(self.weight_head(h)).squeeze(1)
        delay_map = torch.sigmoid(self.delay_head(h)).squeeze(1) * self.max_delay
        rain = x[:, 1, :, :]
        contribution = weight_map * rain

        t_range = torch.arange(self.n_steps, dtype=torch.float32, device=x.device)
        delay_exp = delay_map.unsqueeze(-1)
        t_exp = t_range.view(1, 1, 1, -1)

        sigma = torch.abs(self.kernel_width) + 0.5
        kernel = torch.exp(-0.5 * ((t_exp - delay_exp) / sigma) ** 2)
        kernel = kernel / (kernel.sum(dim=-1, keepdim=True) + 1e-8)

        contrib_exp = contribution.unsqueeze(-1)
        hydrograph = (contrib_exp * kernel).sum(dim=(1, 2))
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

    print(f"Generating dataset (300 events, {N_STEPS} steps)...")
    ds = HydrographDataset(n_events=300, n_steps=N_STEPS)

    # Check hydrograph shape
    for i in range(3):
        h = ds[i][1].numpy()
        print(f"  Event {i}: peak={h.max():.4f} at t={h.argmax()}, tail={h[-1]:.6f}")

    nv = len(ds) // 5
    nt = len(ds) - nv
    tr, va = random_split(ds, [nt, nv], generator=torch.Generator().manual_seed(42))
    tl = DataLoader(tr, batch_size=16, shuffle=True)
    vl = DataLoader(va, batch_size=16)

    model = DelayMapCNN(depth=6, hidden_ch=48, n_steps=N_STEPS, max_delay=MAX_DELAY).to(device)
    opt = torch.optim.Adam(model.parameters(), lr=5e-4)
    crit = nn.MSELoss()

    print("Training (depth=6, hidden=48, 150 epochs)...")
    best_val = float("inf")
    for ep in range(150):
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
        if (ep + 1) % 30 == 0:
            print(f"  Epoch {ep+1}/150  val_loss={vl_loss:.6f}  best={best_val:.6f}")

    # ===== Analyze =====
    model.eval()
    rain_test = generate_rainfall_event(size=64, event_type="localized", seed=42)
    x_t = torch.from_numpy(np.stack([dem_norm, rain_test], axis=0)).float().unsqueeze(0).to(device)
    with torch.no_grad():
        pred_hydro, weight_map, delay_map = model(x_t)
    weight_np = weight_map[0].cpu().numpy()
    delay_np = delay_map[0].cpu().numpy()
    fd_float = flow_dist.astype(np.float32)
    fd_float[flow_dist < 0] = 0

    r_delay_fd = correlation_with_drainage(delay_np, fd_float)
    r_weight_fa = correlation_with_drainage(weight_np, flow_acc)

    # Random control
    torch.manual_seed(999)
    rm = DelayMapCNN(depth=6, hidden_ch=48, n_steps=N_STEPS, max_delay=MAX_DELAY).to(device)
    rm.eval()
    with torch.no_grad():
        _, rw, rd = rm(x_t)
    r_rand = correlation_with_drainage(rd[0].cpu().numpy(), fd_float)

    # Consistency
    rain2 = generate_rainfall_event(size=64, event_type="uniform", seed=0)
    x_t2 = torch.from_numpy(np.stack([dem_norm, rain2], axis=0)).float().unsqueeze(0).to(device)
    with torch.no_grad():
        _, _, dm2 = model(x_t2)
    r_consist = correlation_with_drainage(delay_np, dm2[0].cpu().numpy())

    print(f"\n===== RESULTS (N_STEPS={N_STEPS}, MAX_DELAY={MAX_DELAY}) =====")
    print(f"Val loss:                    {best_val:.6f}")
    print(f"Delay vs flow_distance:      r = {r_delay_fd:.3f}  (random: {r_rand:.3f})")
    print(f"Weight vs flow_acc:          r = {r_weight_fa:.3f}")
    print(f"Delay consistency:           r = {r_consist:.3f}")
    print(f"Delay range:                 {delay_np.min():.1f} - {delay_np.max():.1f}")
    print(f"Kernel width (learned):      {(torch.abs(model.kernel_width) + 0.5).item():.2f}")

    # Visualization
    fig, axes = plt.subplots(2, 4, figsize=(20, 10))
    axes[0, 0].imshow(dem, cmap="terrain")
    axes[0, 0].set_title("DEM")
    axes[0, 0].axis("off")
    axes[0, 1].imshow(fd_float, cmap="viridis")
    axes[0, 1].set_title("Flow Distance (truth)")
    axes[0, 1].axis("off")
    axes[0, 2].imshow(delay_np, cmap="viridis")
    axes[0, 2].set_title(f"Learned Delay\nr={r_delay_fd:.3f} (rand={r_rand:.3f})")
    axes[0, 2].axis("off")
    axes[0, 3].imshow(np.log1p(flow_acc.astype(np.float32)), cmap="Blues")
    axes[0, 3].set_title("Flow Acc (log)")
    axes[0, 3].axis("off")

    axes[1, 0].imshow(rain_test, cmap="YlGnBu")
    axes[1, 0].set_title("Rainfall")
    axes[1, 0].axis("off")
    axes[1, 1].imshow(weight_np, cmap="hot")
    axes[1, 1].set_title(f"Weight Map\nr={r_weight_fa:.3f}")
    axes[1, 1].axis("off")
    axes[1, 2].scatter(fd_float.flatten(), delay_np.flatten(), s=0.5, alpha=0.3)
    axes[1, 2].plot([0, max_fd := flow_dist.max()], [0, max_fd], "r--", alpha=0.5, label="1:1 line")
    axes[1, 2].set_xlabel("Flow Distance")
    axes[1, 2].set_ylabel("Learned Delay")
    axes[1, 2].set_title(f"Scatter: r={r_delay_fd:.3f}")
    axes[1, 2].legend()

    actual = ds[1][1].numpy()
    with torch.no_grad():
        x0 = ds[1][0].unsqueeze(0).to(device)
        p0, _, _ = model(x0)
    axes[1, 3].plot(actual, "b-", label="Actual", linewidth=2)
    axes[1, 3].plot(p0[0].cpu().numpy(), "r--", label="Predicted")
    axes[1, 3].set_title("Hydrograph")
    axes[1, 3].legend()
    axes[1, 3].set_xlabel("t")

    plt.suptitle(f"Delay Map v2 (steps={N_STEPS}, max_delay={MAX_DELAY}, depth=6)", fontsize=14)
    plt.tight_layout()
    plt.savefig(out_dir / "fig8_delay_v2.png", dpi=150)
    print(f"\nSaved fig8_delay_v2.png")


if __name__ == "__main__":
    main()
