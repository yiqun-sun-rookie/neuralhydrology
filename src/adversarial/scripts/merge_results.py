"""Merge per-chunk adversarial results into a single JSON file."""
from __future__ import annotations

import argparse
import json
from pathlib import Path


def merge_results(input_dir: Path, pattern: str = "results_*.json") -> list[dict]:
    """Merge all matching JSON files and deduplicate."""
    all_results = []
    files = sorted(input_dir.glob(pattern))
    for f in files:
        with open(f) as fh:
            chunk = json.load(fh)
        print(f"  {f.name}: {len(chunk)} records")
        all_results.extend(chunk)

    # Deduplicate by experiment identity
    seen = set()
    unique = []
    for r in all_results:
        key = (
            r["attack"],
            r["epsilon"],
            r.get("constraint", "lp"),
            r.get("target", "untargeted"),
            r["basin"],
            r["sample_idx"],
            r.get("pre_window", ""),
            r.get("freq_band", ""),
        )
        if key not in seen:
            seen.add(key)
            unique.append(r)

    n_dup = len(all_results) - len(unique)
    if n_dup > 0:
        print(f"  Removed {n_dup} duplicates")
    return unique


def main():
    parser = argparse.ArgumentParser(description="Merge adversarial result chunks")
    parser.add_argument("--input-dir", required=True, help="Directory with chunk result files")
    parser.add_argument("--pattern", default="results_*.json", help="Glob pattern for chunk files")
    parser.add_argument("--output", required=True, help="Output merged JSON path")
    args = parser.parse_args()

    input_dir = Path(args.input_dir)
    unique = merge_results(input_dir, args.pattern)

    output_path = Path(args.output)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    with open(output_path, "w") as f:
        json.dump(unique, f, indent=2)
    print(f"Merged {len(unique)} unique records -> {args.output}")


if __name__ == "__main__":
    main()
