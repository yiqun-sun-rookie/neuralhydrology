import argparse

from src.hbv_camels_us_531.batch import load_basin_ids, run_basin_file, write_results
from src.hbv_camels_us_531.runner import run_single_basin


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Run fixed-structure HBV baseline on CAMELS-US basins.")
    parser.add_argument("--basin-id", type=str, default=None, help="Single CAMELS-US basin id.")
    parser.add_argument("--basin-file", type=str, default=None, help="File with one basin id per line.")
    parser.add_argument("--data-root", type=str, default=None, help="Override CAMELS-US data root.")
    parser.add_argument("--output-dir", type=str, default="results/08_hbv_camels_us_531", help="Output directory.")
    parser.add_argument("--workers", type=int, default=1, help="Parallel workers (default 1, use 2 to save memory).")
    parser.add_argument("--chunk-index", type=int, default=None, help="Chunk index for array jobs (0-based).")
    parser.add_argument("--n-chunks", type=int, default=11, help="Total number of chunks.")
    return parser


def run_from_args(args):
    if args.basin_id:
        result = run_single_basin(args.basin_id, data_root=args.data_root)
        write_results([result], args.output_dir)
        return result
    if args.basin_file:
        if args.chunk_index is not None:
            all_ids = load_basin_ids(args.basin_file)
            chunk_size = (len(all_ids) + args.n_chunks - 1) // args.n_chunks
            start = args.chunk_index * chunk_size
            end = min(start + chunk_size, len(all_ids))
            chunk_ids = all_ids[start:end]
            print(f"[INFO] Chunk {args.chunk_index}/{args.n_chunks}: basins {start}-{end-1} ({len(chunk_ids)} basins)")
            results = [run_single_basin(bid, data_root=args.data_root) for bid in chunk_ids]
            chunk_dir = f"{args.output_dir}/chunk_{args.chunk_index:02d}"
            write_results(results, chunk_dir)
            return results
        return run_basin_file(
            args.basin_file, data_root=args.data_root, output_dir=args.output_dir, workers=args.workers,
        )
    raise ValueError("Either --basin-id or --basin-file must be provided.")


def main() -> None:
    parser = build_parser()
    args = parser.parse_args()
    run_from_args(args)


if __name__ == "__main__":
    main()
