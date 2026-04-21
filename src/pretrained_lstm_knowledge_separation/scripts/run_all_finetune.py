"""Run all 8 finetune experiments sequentially.

Usage:
    python src/pretrained_lstm_knowledge_separation/scripts/run_all_finetune.py \
        --source-run-dir runs/ks_source_pretrain_XXXX
"""
import argparse
import json
import subprocess
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2].parent / "src"))

from pretrained_lstm_knowledge_separation.scripts.run_matrix import materialize_run_matrix


def main():
    parser = argparse.ArgumentParser(description="Run all 8 finetune experiments.")
    parser.add_argument("--source-run-dir", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, default=Path("results/pretrained_lstm_knowledge_separation"))
    parser.add_argument("--gpu", type=int, default=0)
    parser.add_argument("--dry-run", action="store_true", help="Print commands without running")
    args = parser.parse_args()

    result = materialize_run_matrix(source_run_dir=args.source_run_dir, output_dir=args.output_dir)
    manifest = json.loads(result.manifest_path.read_text(encoding="utf-8"))

    print(f"=== {len(manifest)} finetune runs to execute ===\n")

    for i, row in enumerate(manifest, 1):
        config_path = row["materialized_config_path"]
        cmd = [
            sys.executable, "-m", "neuralhydrology.nh_run", "finetune",
            "--config-file", config_path,
            "--gpu", str(args.gpu),
        ]
        print(f"[{i}/{len(manifest)}] {row['split_label']} / {row['adaptation_group']}")
        print(f"  Config: {config_path}")

        if args.dry_run:
            print(f"  Command: {' '.join(cmd)}")
            print()
            continue

        t0 = time.time()
        proc = subprocess.run(cmd, capture_output=False)
        elapsed = time.time() - t0

        if proc.returncode != 0:
            print(f"  FAILED (exit code {proc.returncode}) after {elapsed:.0f}s")
            sys.exit(1)
        else:
            print(f"  DONE in {elapsed:.0f}s\n")

    print("=== All finetune runs complete ===")


if __name__ == "__main__":
    main()
