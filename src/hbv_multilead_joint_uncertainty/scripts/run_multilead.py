"""Prepare frozen contracts, run them, or verify an immutable artifact."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

import pandas as pd


REPO_ROOT = Path(__file__).resolve().parents[3]
if str(REPO_ROOT / "src") not in sys.path:
    sys.path.insert(0, str(REPO_ROOT / "src"))

from hbv_multilead_joint_uncertainty.basins import freeze_formal_selection  # noqa: E402
from hbv_multilead_joint_uncertainty.contracts import load_base_config  # noqa: E402
from hbv_multilead_joint_uncertainty.experiment import (  # noqa: E402
    verify_contract_package,
    verify_result_package,
)
from hbv_multilead_joint_uncertainty.orchestrator import (  # noqa: E402
    prepare_contract_package,
    run_contract_evaluation,
    verify_run_log,
)


def _load_pilot_table(root: Path, config: dict) -> pd.DataFrame:
    table = pd.read_csv(root / config["pilot_basin_file"], dtype={"basin_id": str})
    table["basin_id"] = table["basin_id"].str.zfill(8)
    return table.rename(columns={"basin_id": "gauge_id"})


def _load_smoke_table(root: Path, config: dict, basin_id: str) -> pd.DataFrame:
    normalized = str(basin_id).strip().zfill(8)
    if len(normalized) != 8 or not normalized.isdigit():
        raise ValueError("smoke basin identifier must contain at most eight digits")
    pilot = _load_pilot_table(root, config)
    selected = pilot.loc[pilot["gauge_id"] == normalized, ["gauge_id"]].reset_index(drop=True)
    if len(selected) != 1:
        raise ValueError("smoke contract basin must be one frozen development basin")
    return selected


def _load_and_verify_formal_table(root: Path, config: dict, pilot_ids: list[str]) -> pd.DataFrame:
    frozen = pd.read_csv(root / config["formal_basin_file"], dtype={"gauge_id": str, "huc_02": str})
    frozen["gauge_id"] = frozen["gauge_id"].str.zfill(8)
    recomputed = freeze_formal_selection(root, additional_development_ids=pilot_ids)
    if frozen["gauge_id"].tolist() != recomputed["gauge_id"].tolist():
        raise ValueError("versioned formal basin file does not match independent static-rule recomputation")
    for column in ("climate_stratum", "response_stratum", "area_stratum", "huc_02"):
        expected = recomputed[column].astype(str)
        actual = frozen[column].astype(str)
        if column == "huc_02":
            expected = expected.str.zfill(2)
            actual = actual.str.zfill(2)
        if actual.tolist() != expected.tolist():
            raise ValueError(f"versioned formal basin labels differ from recomputation: {column}")
    return frozen


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo-root", type=Path, default=REPO_ROOT)
    subparsers = parser.add_subparsers(dest="command", required=True)
    prepare_smoke = subparsers.add_parser("prepare-smoke")
    prepare_smoke.add_argument("--contract-id", required=True)
    prepare_smoke.add_argument("--basin-id", required=True)
    prepare_pilot = subparsers.add_parser("prepare-pilot")
    prepare_pilot.add_argument("--contract-id", required=True)
    prepare_formal = subparsers.add_parser("prepare-formal")
    prepare_formal.add_argument("--contract-id", required=True)
    prepare_formal.add_argument("--pilot-contract", type=Path, required=True)
    run = subparsers.add_parser("run-contract")
    run.add_argument("--contract", type=Path, required=True)
    run.add_argument("--experiment-id", required=True)
    verify = subparsers.add_parser("verify-output")
    verify.add_argument("--artifact", type=Path, required=True)
    verify_log = subparsers.add_parser("verify-log")
    verify_log.add_argument("--log", type=Path, required=True)
    return parser


def main(argv=None) -> int:
    arguments = build_parser().parse_args(argv)
    root = arguments.repo_root.resolve()
    config = load_base_config(root)
    if arguments.command == "prepare-smoke":
        result = prepare_contract_package(
            root,
            arguments.contract_id,
            _load_smoke_table(root, config, arguments.basin_id),
        )
    elif arguments.command == "prepare-pilot":
        result = prepare_contract_package(
            root,
            arguments.contract_id,
            _load_pilot_table(root, config),
        )
    elif arguments.command == "prepare-formal":
        pilot_contract = arguments.pilot_contract.resolve()
        interaction = json.loads((pilot_contract / "interaction_audit.json").read_text(encoding="utf-8"))
        pilot_table = pd.read_csv(pilot_contract / "basins.csv", dtype={"gauge_id": str})
        pilot_ids = pilot_table["gauge_id"].str.zfill(8).tolist()
        formal_table = pd.read_csv(
            root / config["formal_basin_file"],
            dtype={"gauge_id": str, "huc_02": str},
        )
        formal_table["gauge_id"] = formal_table["gauge_id"].str.zfill(8)
        result = prepare_contract_package(
            root,
            arguments.contract_id,
            formal_table,
            interaction_audit=interaction,
            prerequisite_contract=pilot_contract,
            prerequisite_basin_ids=pilot_ids,
        )
    elif arguments.command == "run-contract":
        result = run_contract_evaluation(root, arguments.contract, arguments.experiment_id)
    elif arguments.command == "verify-output":
        artifact = arguments.artifact.resolve()
        if (artifact / "contract_manifest.json").is_file():
            result = verify_contract_package(artifact)
        elif (artifact / "result_manifest.json").is_file():
            result = verify_result_package(artifact)
        else:
            raise ValueError("artifact does not contain a recognized contract or result manifest")
    else:
        result = verify_run_log(arguments.log)
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
