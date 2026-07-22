"""Generate confirmation configs for the deterministically selected boundary cells.

Reads the sealed development curve, applies the frozen rule (per budget row:
smallest passing multiplier and largest failing multiplier), and writes one
confirmation config per boundary cell with fresh confirmation seeds. Runs
exactly once; refuses to overwrite existing configs.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[3]
if str(REPO_ROOT / "src") not in sys.path:
    sys.path.insert(0, str(REPO_ROOT / "src"))

from hbv_multilead_joint_uncertainty.g2_curve_design import (  # noqa: E402
    BUDGET_STAGE_LENGTHS,
    CONFIRMATION_BOOTSTRAP_SEED_BASE,
    confirmation_block_seeds,
    confirmation_experiment_id,
    development_experiment_id,
    grid_cells,
)

CONFIG_DIR = REPO_ROOT / "src/hbv_multilead_joint_uncertainty/configs"
CURVE_DIR = (
    REPO_ROOT / "results/23_hbv_multilead_joint_uncertainty/g2_identification_time_curve_dev_v01"
)


def _boundary_cells() -> list[dict]:
    curve = json.loads((CURVE_DIR / "curve_summary.json").read_text(encoding="utf-8"))
    selected = []
    for stage_length_key, row in curve["axis_checks"]["budget_rows"].items():
        stage_length = int(stage_length_key)
        for key in ("smallest_passing_multiplier", "largest_failing_multiplier"):
            multiplier = row["boundary_cells"][key]
            if multiplier is None:
                continue
            cell = next(
                c
                for c in grid_cells()
                if c["stage_length"] == stage_length and c["multiplier"] == float(multiplier)
            )
            selected.append({**cell, "selection_rule": key})
    return selected


def main() -> None:
    boundary = _boundary_cells()
    if not boundary:
        raise RuntimeError("no boundary cells selected")
    names = [
        confirmation_experiment_id(cell["multiplier"], cell["stage_length"]) + ".json"
        for cell in boundary
    ]
    existing = [name for name in names if (CONFIG_DIR / name).exists()]
    if existing:
        raise FileExistsError(f"refusing to overwrite existing configs: {existing}")

    development_ids = [
        development_experiment_id(cell["multiplier"], cell["stage_length"])
        for cell in grid_cells()
    ]
    extra_protected = [
        *(
            f"results/23_hbv_multilead_joint_uncertainty/{experiment_id}"
            for experiment_id in development_ids
        ),
        "results/23_hbv_multilead_joint_uncertainty/g2_identification_time_curve_dev_v01",
        *(f"src/hbv_multilead_joint_uncertainty/configs/{name}" for name in names),
    ]
    for cell in boundary:
        development_config = json.loads(
            (
                CONFIG_DIR
                / (development_experiment_id(cell["multiplier"], cell["stage_length"]) + ".json")
            ).read_text(encoding="utf-8")
        )
        config = dict(development_config)
        config["experiment_id"] = confirmation_experiment_id(
            cell["multiplier"], cell["stage_length"]
        )
        config["dataset_role"] = "confirmation"
        config["purpose"] = (
            "G2 boundary-cell confirmation (frozen rule: "
            f"{cell['selection_rule']} in the L={cell['stage_length']} row); "
            "single run on fresh confirmation seeds, final whatever the direction."
        )
        config["g2_grid"] = {
            **development_config["g2_grid"],
            "selection_rule": cell["selection_rule"],
            "confirms_development_experiment": development_experiment_id(
                cell["multiplier"], cell["stage_length"]
            ),
        }
        row_index = BUDGET_STAGE_LENGTHS.index(int(cell["stage_length"]))
        config["matched_blocks"] = confirmation_block_seeds(row_index)
        config["bootstrap"] = {
            **development_config["bootstrap"],
            "seed": CONFIRMATION_BOOTSTRAP_SEED_BASE + int(cell["cell_number"]),
        }
        config["protected_paths"] = [
            *development_config["protected_paths"],
            *extra_protected,
        ]
        target = CONFIG_DIR / (config["experiment_id"] + ".json")
        target.write_text(json.dumps(config, indent=2) + "\n", encoding="utf-8", newline="\n")
    print(f"wrote {len(boundary)} confirmation configs: {[n[:-5] for n in names]}")


if __name__ == "__main__":
    main()
