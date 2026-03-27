"""Representation drift analysis for knowledge separation experiments.

Computes cosine distance, Euclidean distance, and linear CKA between
source and adapted model activations at each module boundary.
"""
import argparse
from pathlib import Path
from typing import Dict

import torch
import torch.nn.functional as F


def cosine_distance(a: torch.Tensor, b: torch.Tensor) -> float:
    """Mean pairwise cosine distance between rows of a and b.

    Parameters
    ----------
    a, b : torch.Tensor
        Shape (N, D). Same number of samples and features.

    Returns
    -------
    float
        Mean (1 - cosine_similarity) across samples.
    """
    sim = F.cosine_similarity(a, b, dim=1)
    return (1.0 - sim).mean().item()


def euclidean_distance(a: torch.Tensor, b: torch.Tensor) -> float:
    """Mean per-sample L2 distance between a and b."""
    return (a - b).norm(dim=1).mean().item()


def linear_cka(a: torch.Tensor, b: torch.Tensor) -> float:
    """Linear Centered Kernel Alignment (Kornblith et al., 2019).

    Parameters
    ----------
    a, b : torch.Tensor
        Shape (N, D1) and (N, D2). Same number of samples.

    Returns
    -------
    float
        CKA similarity in [0, 1].
    """
    a = a - a.mean(dim=0, keepdim=True)
    b = b - b.mean(dim=0, keepdim=True)

    hsic_ab = (a @ a.T * (b @ b.T)).sum()
    hsic_aa = (a @ a.T * (a @ a.T)).sum()
    hsic_bb = (b @ b.T * (b @ b.T)).sum()

    denom = torch.sqrt(hsic_aa * hsic_bb)
    if denom < 1e-12:
        return 0.0
    return (hsic_ab / denom).item()


def aggregate_drift_by_module(
    source_activations: Dict[str, torch.Tensor],
    adapted_activations: Dict[str, torch.Tensor],
) -> Dict[str, Dict[str, float]]:
    """Compute drift metrics for each module.

    Parameters
    ----------
    source_activations : dict
        Module name → (N, D) tensor from source model.
    adapted_activations : dict
        Module name → (N, D) tensor from adapted model.

    Returns
    -------
    dict
        Module name → {cosine_distance, euclidean_distance, linear_cka}.
    """
    drift = {}
    for module_name in source_activations:
        a = source_activations[module_name]
        b = adapted_activations[module_name]
        drift[module_name] = {
            "cosine_distance": cosine_distance(a, b),
            "euclidean_distance": euclidean_distance(a, b),
            "linear_cka": linear_cka(a, b),
        }
    return drift


def main():
    parser = argparse.ArgumentParser(description="Analyze representation drift between source and adapted models.")
    parser.add_argument("--source-acts", type=Path, required=True, help="Directory with source activation .pt files")
    parser.add_argument("--adapted-acts", type=Path, required=True, help="Directory with adapted activation .pt files")
    parser.add_argument("--output-dir", type=Path, default=Path("."))
    args = parser.parse_args()

    source = {}
    adapted = {}
    for pt_file in args.source_acts.glob("*.pt"):
        module_name = pt_file.stem
        source[module_name] = torch.load(pt_file, map_location="cpu", weights_only=True)
        adapted[module_name] = torch.load(args.adapted_acts / pt_file.name, map_location="cpu", weights_only=True)

    drift = aggregate_drift_by_module(source, adapted)

    args.output_dir.mkdir(parents=True, exist_ok=True)
    import json
    (args.output_dir / "drift_metrics.json").write_text(
        json.dumps(drift, indent=2), encoding="utf-8"
    )

    for module_name, metrics in drift.items():
        print(f"{module_name:20s}  cos={metrics['cosine_distance']:.4f}  "
              f"l2={metrics['euclidean_distance']:.4f}  cka={metrics['linear_cka']:.4f}")


if __name__ == "__main__":
    main()
