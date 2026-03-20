"""End-to-end experiment: generate data, train CNNs at different depths, analyze.

Usage:
    cd <project_root>/src
    python -m spatial_routing_discovery.scripts.run_experiment [--dem-size 64] [--epochs 50]
"""

import argparse
import json
import sys
from pathlib import Path

import numpy as np
import torch
import torch.nn as nn
from torch.utils.data import DataLoader, random_split

_SRC_DIR = Path(__file__).resolve().parents[2]
if str(_SRC_DIR) not in sys.path:
    sys.path.insert(0, str(_SRC_DIR))

from spatial_routing_discovery.dataset import RoutingDataset
from spatial_routing_discovery.models import RoutingCNN
from spatial_routing_discovery.terrain import generate_dem, compute_d8_flow
from spatial_routing_discovery.analysis import dynamic_response_score, depth_routing_scores


def train_model(model, train_loader, val_loader, epochs, device, lr=1e-3):
    optimizer = torch.optim.Adam(model.parameters(), lr=lr)
    criterion = nn.MSELoss()
    best_val_loss = float("inf")
    for epoch in range(epochs):
        model.train()
        train_loss = 0.0
        for x, y in train_loader:
            x, y = x.to(device), y.to(device)
            pred = model(x)
            loss = criterion(pred, y)
            optimizer.zero_grad()
            loss.backward()
            optimizer.step()
            train_loss += loss.item() * x.size(0)
        train_loss /= len(train_loader.dataset)
        model.eval()
        val_loss = 0.0
        with torch.no_grad():
            for x, y in val_loader:
                x, y = x.to(device), y.to(device)
                pred = model(x)
                val_loss += criterion(pred, y).item() * x.size(0)
        val_loss /= len(val_loader.dataset)
        if val_loss < best_val_loss:
            best_val_loss = val_loss
        if (epoch + 1) % 10 == 0:
            print(f"  Epoch {epoch+1}/{epochs}  train_loss={train_loss:.6f}  val_loss={val_loss:.6f}")
    return best_val_loss


def analyze_model(model, dataset, dem, flow_acc, device):
    model.eval()
    x_sample, _ = dataset[0]
    x_sample = x_sample.unsqueeze(0).to(device)
    layer_scores = depth_routing_scores(model, x_sample, flow_acc)
    dem_norm = (dem - dem.min()) / (dem.max() - dem.min() + 1e-8)
    dem_t = torch.from_numpy(dem_norm).float().unsqueeze(0).unsqueeze(0).to(device)
    rain_a = torch.ones(1, 1, dem.shape[0], dem.shape[1]).to(device) * 0.02
    rain_b = torch.zeros(1, 1, dem.shape[0], dem.shape[1]).to(device)
    rain_b[0, 0, dem.shape[0] // 4, dem.shape[1] // 4] = 0.5
    dyn_score = dynamic_response_score(model, dem_t, rain_a, rain_b)
    return {"layer_drainage_correlations": layer_scores, "dynamic_response_score": dyn_score}


def main():
    parser = argparse.ArgumentParser(description="Spatial routing discovery experiment")
    parser.add_argument("--dem-size", type=int, default=64)
    parser.add_argument("--epochs", type=int, default=50)
    parser.add_argument("--n-events", type=int, default=60)
    parser.add_argument("--steps-per-event", type=int, default=20)
    parser.add_argument("--hidden-channels", type=int, default=32)
    parser.add_argument("--batch-size", type=int, default=32)
    parser.add_argument("--output-dir", type=str, default=None)
    args = parser.parse_args()

    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    print(f"Device: {device}")

    if args.output_dir:
        out_dir = Path(args.output_dir)
    else:
        out_dir = Path(__file__).resolve().parents[3] / "results" / "spatial_routing_discovery"
    out_dir.mkdir(parents=True, exist_ok=True)

    print("Generating DEM and computing D8 flow...")
    dem = generate_dem(size=args.dem_size, seed=42)
    _, flow_acc = compute_d8_flow(dem)
    np.save(out_dir / "dem.npy", dem)
    np.save(out_dir / "flow_acc.npy", flow_acc)

    print(f"Generating dataset: {args.n_events} events x {args.steps_per_event} steps...")
    dataset = RoutingDataset(dem_size=args.dem_size, dem_seed=42,
                             n_events=args.n_events, steps_per_event=args.steps_per_event)

    n_val = len(dataset) // 5
    n_train = len(dataset) - n_val
    train_set, val_set = random_split(dataset, [n_train, n_val],
                                      generator=torch.Generator().manual_seed(42))
    train_loader = DataLoader(train_set, batch_size=args.batch_size, shuffle=True)
    val_loader = DataLoader(val_set, batch_size=args.batch_size)

    results = {}
    for depth in [2, 4, 8]:
        print(f"\n{'='*60}")
        print(f"Training CNN depth={depth}")
        print(f"{'='*60}")
        model = RoutingCNN(depth=depth, in_channels=3, hidden_channels=args.hidden_channels).to(device)
        n_params = sum(p.numel() for p in model.parameters())
        print(f"  Parameters: {n_params:,}")
        best_val = train_model(model, train_loader, val_loader, args.epochs, device)
        print(f"  Best val loss: {best_val:.6f}")
        torch.save(model.state_dict(), out_dir / f"model_depth{depth}.pt")
        analysis = analyze_model(model, dataset, dem, flow_acc, device)
        analysis["best_val_loss"] = best_val
        analysis["n_params"] = n_params
        results[f"depth_{depth}"] = analysis
        print(f"  Layer drainage correlations: {analysis['layer_drainage_correlations']}")
        print(f"  Dynamic response score: {analysis['dynamic_response_score']:.4f}")

    def to_serializable(obj):
        if isinstance(obj, (np.floating, np.integer)):
            return float(obj)
        if isinstance(obj, np.ndarray):
            return obj.tolist()
        if isinstance(obj, list):
            return [to_serializable(i) for i in obj]
        if isinstance(obj, dict):
            return {k: to_serializable(v) for k, v in obj.items()}
        return obj

    with open(out_dir / "results.json", "w") as f:
        json.dump(to_serializable(results), f, indent=2)

    print(f"\nResults saved to {out_dir}")
    print(f"\n{'Depth':<8} {'Val Loss':<12} {'Dynamic':<12} {'Layer Correlations'}")
    print("-" * 70)
    for depth in [2, 4, 8]:
        r = results[f"depth_{depth}"]
        corrs = ", ".join(f"{c:.3f}" for c in r["layer_drainage_correlations"])
        print(f"{depth:<8} {r['best_val_loss']:<12.6f} {r['dynamic_response_score']:<12.4f} [{corrs}]")


if __name__ == "__main__":
    main()
