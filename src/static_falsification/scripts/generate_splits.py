"""Generate 5-fold PUB splits and per-fold derangement mappings."""
import json
import random
from pathlib import Path
from typing import Dict, List


def generate_fold_splits(basins: List[str], n_folds: int = 5, seed: int = 42) -> List[List[str]]:
    """Partition basins into n_folds non-overlapping groups."""
    rng = random.Random(seed)
    shuffled = list(basins)
    rng.shuffle(shuffled)
    fold_size = len(shuffled) // n_folds
    folds = []
    for i in range(n_folds):
        start = i * fold_size
        end = start + fold_size if i < n_folds - 1 else len(shuffled)
        folds.append(sorted(shuffled[start:end]))
    return folds


def generate_derangement(items: List[str], seed: int = 42) -> Dict[str, str]:
    """Generate a fixed-point-free permutation (derangement) of items."""
    rng = random.Random(seed)
    n = len(items)
    if n < 2:
        raise ValueError("Need at least 2 items for a derangement")
    shuffled = list(items)
    for _ in range(1000):
        rng.shuffle(shuffled)
        if all(shuffled[i] != items[i] for i in range(n)):
            return dict(zip(items, shuffled))
    # Fallback: Sattolo's algorithm (always produces a derangement for n >= 2)
    shuffled = list(items)
    for i in range(n - 1, 0, -1):
        j = rng.randint(0, i - 1)
        shuffled[i], shuffled[j] = shuffled[j], shuffled[i]
    return dict(zip(items, shuffled))


def main():
    """Generate and save splits + derangements for the experiment."""
    basin_file = Path("src/full_531_basins/data/531_basin_list.txt")
    if not basin_file.exists():
        basin_file = Path("data/CAMELS_US/basin_list.txt")
    basins = [line.strip() for line in basin_file.read_text().splitlines() if line.strip()]

    out_dir = Path("src/static_falsification/data")
    out_dir.mkdir(parents=True, exist_ok=True)

    folds = generate_fold_splits(basins, n_folds=5, seed=42)

    derangements = {}
    for fold_idx in range(5):
        derangements[str(fold_idx)] = generate_derangement(basins, seed=100 + fold_idx)

    fold_data = {}
    for fold_idx, test_basins in enumerate(folds):
        train_basins = sorted([b for i, f in enumerate(folds) for b in f if i != fold_idx])
        rng = random.Random(42 + fold_idx)
        val_size = max(1, len(train_basins) // 10)
        val_basins = sorted(rng.sample(train_basins, val_size))
        actual_train = sorted([b for b in train_basins if b not in val_basins])
        fold_data[str(fold_idx)] = {
            "train": actual_train,
            "validation": val_basins,
            "test": test_basins,
        }

    with open(out_dir / "fold_splits.json", "w") as f:
        json.dump(fold_data, f, indent=2)

    with open(out_dir / "shuffle_maps.json", "w") as f:
        json.dump(derangements, f, indent=2)

    for fold_idx, splits in fold_data.items():
        for split_name, basin_list in splits.items():
            fname = out_dir / f"fold{fold_idx}_{split_name}.txt"
            fname.write_text("\n".join(basin_list) + "\n")

    print(f"Generated 5-fold splits: {[len(f) for f in folds]} basins per fold")
    print(f"Generated {len(derangements)} derangement mappings")
    print(f"Output: {out_dir}")


if __name__ == "__main__":
    main()
