#!/usr/bin/env python3
import argparse
from pathlib import Path
import random


def read_ids(path: Path):
    with path.open("r", encoding="utf-8") as f:
        return [line.strip() for line in f if line.strip()]


def write_ids(path: Path, ids):
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as f:
        for bid in ids:
            f.write(f"{bid}\n")


def main():
    parser = argparse.ArgumentParser(description="Make train/val/test basin splits")
    parser.add_argument("--all", dest="all_path", type=str,
                        default="examples/01-Introduction/all_basins.txt",
                        help="Path to all basins list")
    parser.add_argument("--out-train", dest="out_train", type=str,
                        default="examples/01-Introduction/full_674_basins_train_basins.txt")
    parser.add_argument("--out-val", dest="out_val", type=str,
                        default="examples/01-Introduction/full_674_basins_val_basins.txt")
    parser.add_argument("--out-test", dest="out_test", type=str,
                        default="examples/01-Introduction/full_674_basins_test_basins.txt")
    parser.add_argument("--ratios", dest="ratios", type=str, default="0.8,0.1,0.1",
                        help="train,val,test ratios, sum to 1.0")
    parser.add_argument("--seed", dest="seed", type=int, default=20251007,
                        help="random seed for reproducibility")
    parser.add_argument("--subset", dest="subset_path", type=str, default=None,
                        help="Optional path to a subset list (e.g., 517-basin list); if set, split within this subset only")

    args = parser.parse_args()

    all_ids = read_ids(Path(args.all_path))

    if args.subset_path:
        subset = set(read_ids(Path(args.subset_path)))
        ids = [b for b in all_ids if b in subset]
    else:
        ids = list(all_ids)

    ratios = [float(x) for x in args.ratios.split(",")]
    if len(ratios) != 3 or abs(sum(ratios) - 1.0) > 1e-6:
        raise ValueError("ratios must be three numbers that sum to 1.0, e.g., 0.8,0.1,0.1")

    random.seed(args.seed)
    ids = list(sorted(set(ids)))
    random.shuffle(ids)

    n = len(ids)
    n_train = int(n * ratios[0])
    n_val = int(n * ratios[1])
    n_test = n - n_train - n_val

    train_ids = ids[:n_train]
    val_ids = ids[n_train:n_train + n_val]
    test_ids = ids[n_train + n_val:]

    write_ids(Path(args.out_train), train_ids)
    write_ids(Path(args.out_val), val_ids)
    write_ids(Path(args.out_test), test_ids)

    print(f"Total: {n}, train: {len(train_ids)}, val: {len(val_ids)}, test: {len(test_ids)}")
    print(f"Train -> {args.out_train}")
    print(f"Val   -> {args.out_val}")
    print(f"Test  -> {args.out_test}")


if __name__ == "__main__":
    main()

