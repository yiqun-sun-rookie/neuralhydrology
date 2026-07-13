"""Build the ID10/ID18 manuscript evidence package.

This script intentionally reads only frozen/result artifacts and writes a paper
package under draft/papers. It does not recalibrate or retrain any model.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import zipfile
from pathlib import Path, PurePosixPath, PureWindowsPath
from typing import Dict, Iterable, List, Tuple

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd


REPO = Path(".")
REPRO = Path("results/10_global_conceptual_model_benchmark/camels_us_531_repro_v01")
SUMMARY = REPRO / "summary"
DIAG = REPRO / "diagnostic"
LSTM_REPORTS = Path("results/18_lstm_fair_531/_reports")

CONCEPTUAL_FILES = {
    "GR4J": SUMMARY / "gr4j_pdd_cma_FINAL_pt_v1_local_full.csv",
    "XAJ": SUMMARY / "xaj_pdd_cma_FINAL_pt_v1_5k3_local_full.csv",
    "HBV": SUMMARY / "hbv_lite_cma_FINAL_pt_v1_warmup_local_full.csv",
}
LSTM_SINGLE_REPORT = LSTM_REPORTS / "compare_iter1_cudalstm_s100.json"
LSTM_SINGLE_METRICS = (
    LSTM_REPORTS.parent / "lstm_cudalstm_maurer_s100_2026_0616_1513_ep30" / "test" / "model_epoch030" /
    "test_metrics.csv"
)
LSTM_ENSEMBLE_REPORT = LSTM_REPORTS / "compare_iter2_cudalstm_8seed_ens.json"
LSTM_ENSEMBLE_METRICS = LSTM_REPORTS / "ensemble_cudalstm_maurer_8seed_per_basin.csv"
SNAPSHOT_POLICY = Path("src/lstm_fair_531/configs/manuscript_snapshot_policy.json")
PDD_FAIRNESS_TEST = Path("test/test_id10_pdd_fairness.py")
REPLAY_AUDIT_REL = Path("audit") / "R01_saved_parameter_replay_current_code"
REPLAY_AUDIT_COMMAND = (
    "python -X utf8 -m src.xaj_global_pilot.scripts.replay_conceptual_saved_params "
    "--out-dir draft/papers/10_18_conceptual_lstm_package/audit/R01_saved_parameter_replay_current_code"
)
DEEP_DIVE_REL = Path("deep_dive")
D01_DEEP_DIVE_REL = DEEP_DIVE_REL / "D01_structure_diagnostic_20260709"
D02_DEEP_DIVE_REL = DEEP_DIVE_REL / "D02_seasonal_residual_20260709"
D03_DEEP_DIVE_REL = DEEP_DIVE_REL / "D03_population_seasonal_residual_20260709"
D04_DEEP_DIVE_REL = DEEP_DIVE_REL / "D04_full_population_seasonal_residual_20260709"
D05_DEEP_DIVE_REL = DEEP_DIVE_REL / "D05_lstm_advantage_decomposition_20260709"
D06_DEEP_DIVE_REL = DEEP_DIVE_REL / "D06_joint_season_flow_advantage_20260709"

STALE_PATTERNS = [
    "xaj_pdd_local_full.csv",
    "0.4458",
    "0.6372",
    "HBV-PT (v7",
    "HBV v7",
    "v7_PT_tight",
    "XAJ-PDD (ours)",
]
ACTIVE_STALE_SCAN_PATHS = [Path("src/lstm_fair_531/scripts/build_manuscript_evidence_package.py")]
SCAN_SUFFIXES = {".md", ".py"}


def _bid(values: pd.Series) -> pd.Series:
    return values.astype(str).str.replace(r"\.0$", "", regex=True).str.zfill(8)


def _load_json(path: Path) -> dict:
    with path.open("r", encoding="utf-8") as fp:
        return json.load(fp)


def _write_json(path: Path, payload: dict) -> None:
    path.write_text(json.dumps(payload, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


class SnapshotInputError(RuntimeError):
    """Raised when an immutable snapshot input is missing or has changed."""


def load_snapshot_policy(path: Path = SNAPSHOT_POLICY) -> dict:
    """Load the versioned minimal-snapshot policy."""
    return _load_json(path)


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as fp:
        for chunk in iter(lambda: fp.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _validated_external_input_paths(policy: dict, repo_root: Path) -> list[tuple[dict, str, Path]]:
    """Return safe, unique archive names and resolved repository-local source paths."""
    root = repo_root.resolve()
    seen = set()
    validated = []
    for item in policy["external_inputs"]:
        raw = item.get("path")
        if not isinstance(raw, str) or not raw or "\\" in raw:
            raise SnapshotInputError(f"Invalid external input path: {raw!r}")
        parts = raw.split("/")
        posix_path = PurePosixPath(raw)
        windows_path = PureWindowsPath(raw)
        if (any(part in {"", ".", ".."} for part in parts) or posix_path.is_absolute() or
                windows_path.is_absolute() or windows_path.drive or windows_path.root or
                posix_path.as_posix() != raw):
            raise SnapshotInputError(f"Invalid external input path: {raw!r}")
        if raw in seen:
            raise SnapshotInputError(f"Duplicate external input path: {raw}")
        seen.add(raw)
        source = (root / Path(*parts)).resolve()
        try:
            source.relative_to(root)
        except ValueError as exc:
            raise SnapshotInputError(f"External input path resolves outside the repository: {raw}") from exc
        validated.append((item, raw, source))
    return validated


def build_external_archive(policy: dict, archive_path: Path, repo_root: Path = REPO) -> None:
    """Create a byte-stable ZIP containing exactly the registered external inputs."""
    validated = _validated_external_input_paths(policy, repo_root)
    archive_path.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(archive_path, mode="w", compression=zipfile.ZIP_STORED) as archive:
        for _, member_name, source in sorted(validated, key=lambda value: value[1]):
            info = zipfile.ZipInfo(member_name, date_time=(1980, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_STORED
            info.create_system = 3
            info.external_attr = 0o100644 << 16
            archive.writestr(info, source.read_bytes())


def validate_external_archive(policy: dict, repo_root: Path = REPO, raise_on_error: bool = True) -> pd.DataFrame:
    """Validate the single immutable archive that transports all external inputs."""
    item = policy["external_archive_bundle"]
    path = repo_root / item["path"]
    actual_bytes = path.stat().st_size if path.is_file() else None
    actual_sha256 = _sha256(path) if path.is_file() and actual_bytes == item["bytes"] else None
    if not path.is_file():
        status = "missing"
    elif actual_bytes != item["bytes"]:
        status = "size_mismatch"
    else:
        status = "ok" if actual_sha256 == item["sha256"] else "sha256_mismatch"
    report = pd.DataFrame([{
        "path": item["path"],
        "status": status,
        "format": item["format"],
        "member_count": item["member_count"],
        "expected_bytes": item["bytes"],
        "actual_bytes": actual_bytes,
        "expected_sha256": item["sha256"],
        "actual_sha256": actual_sha256,
    }])
    if raise_on_error and status != "ok":
        raise SnapshotInputError(f"Immutable external archive bundle failed validation: {item['path']} [{status}]")
    return report


def validate_snapshot_inputs(policy: dict, repo_root: Path = REPO, raise_on_error: bool = True) -> pd.DataFrame:
    """Verify every registered external input against its byte size and SHA-256 digest."""
    rows = []
    for item, _, path in _validated_external_input_paths(policy, repo_root):
        actual_bytes = None
        actual_sha256 = None
        if not path.is_file():
            status = "missing"
        else:
            actual_bytes = path.stat().st_size
            if actual_bytes != item["bytes"]:
                status = "size_mismatch"
            else:
                actual_sha256 = _sha256(path)
                status = "ok" if actual_sha256 == item["sha256"] else "sha256_mismatch"
        rows.append({
            "input_id": item["input_id"],
            "path": item["path"],
            "status": status,
            "expected_bytes": item["bytes"],
            "actual_bytes": actual_bytes,
            "expected_sha256": item["sha256"],
            "actual_sha256": actual_sha256,
            "role": item["role"],
            "source_command": item["source_command"],
        })

    report = pd.DataFrame(rows)
    failures = report[report["status"] != "ok"]
    if raise_on_error and not failures.empty:
        details = "\n".join(f"- {row.path} [{row.status}]" for row in failures.itertuples(index=False))
        raise SnapshotInputError("Immutable manuscript snapshot inputs failed validation:\n" + details)
    return report


def validate_code_inputs(policy: dict, repo_root: Path = REPO, raise_on_error: bool = True) -> pd.DataFrame:
    """Verify version-controlled source files used for code-derived evidence."""
    rows = []
    for item in policy["code_inputs"]:
        path = repo_root / item["path"]
        data = path.read_bytes() if path.is_file() else None
        if data is not None and item["digest_mode"] == "text_lf":
            data = data.replace(b"\r\n", b"\n").replace(b"\r", b"\n")
        actual_bytes = len(data) if data is not None else None
        actual_sha256 = hashlib.sha256(data).hexdigest() if data is not None and actual_bytes == item["bytes"] else None
        if not path.is_file():
            status = "missing"
        elif actual_bytes != item["bytes"]:
            status = "size_mismatch"
        else:
            status = "ok" if actual_sha256 == item["sha256"] else "sha256_mismatch"
        rows.append({
            "input_id": item["input_id"],
            "path": item["path"],
            "status": status,
            "expected_bytes": item["bytes"],
            "actual_bytes": actual_bytes,
            "expected_sha256": item["sha256"],
            "actual_sha256": actual_sha256,
            "digest_mode": item["digest_mode"],
            "role": item["role"],
        })
    report = pd.DataFrame(rows)
    failures = report[report["status"] != "ok"]
    if raise_on_error and not failures.empty:
        details = "\n".join(f"- {row.path} [{row.status}]" for row in failures.itertuples(index=False))
        raise SnapshotInputError("Version-controlled manuscript evidence inputs failed validation:\n" + details)
    return report


def _policy_input(policy: dict, input_id: str) -> dict:
    matches = [
        item for item in policy["external_inputs"] + policy.get("code_inputs", [])
        if item["input_id"] == input_id
    ]
    if len(matches) != 1:
        raise ValueError(f"Expected one snapshot input for {input_id}, found {len(matches)}")
    return matches[0]


def _core_evidence_map(out_dir: Path, tables: Dict[str, pd.DataFrame], policy: dict) -> pd.DataFrame:
    command = "python -X utf8 -m src.lstm_fair_531.scripts.build_manuscript_evidence_package --verify-snapshot"
    rows = []

    def add(metric_id: str, value, input_ids: List[str], output_file: str, selector: str) -> None:
        inputs = [_policy_input(policy, input_id) for input_id in input_ids]
        rows.append({
            "metric_id": metric_id,
            "value": value,
            "input_ids": ";".join(input_ids),
            "source_files": ";".join(item["path"] for item in inputs),
            "source_sha256": ";".join(item["sha256"] for item in inputs),
            "source_digest_mode": ";".join(item.get("digest_mode", "raw_bytes") for item in inputs),
            "build_command": command,
            "output_file": output_file,
            "output_selector": selector,
            "output_sha256": _sha256(out_dir / output_file),
        })

    def slug(value: str) -> str:
        return re.sub(r"[^a-z0-9]+", "_", value.lower()).strip("_")

    main_inputs = {
        "GR4J": ["I01"],
        "XAJ": ["I02"],
        "HBV": ["I03"],
        "LSTM_single_s100": ["I05"],
        "LSTM_ensemble_8seed": ["I07"],
    }
    main_names = {
        "GR4J": "gr4j",
        "XAJ": "xaj",
        "HBV": "hbv_lite",
        "LSTM_single_s100": "lstm_single_s100",
        "LSTM_ensemble_8seed": "lstm_ensemble_8seed",
    }
    for row in tables["main_benchmark"].itertuples(index=False):
        for column in ["n", "median_nse", "mean_nse", "median_delta_vs_gr4j", "win_rate_vs_gr4j"]:
            value = getattr(row, column)
            if pd.isna(value):
                continue
            input_ids = list(main_inputs[row.model])
            if column in {"median_delta_vs_gr4j", "win_rate_vs_gr4j"} and row.model != "GR4J":
                input_ids.append("I01")
            add(
                f"main.{main_names[row.model]}.{column}",
                value,
                input_ids,
                "tables/main_benchmark.csv",
                f"model={row.model};column={column}",
            )

    for row in tables["paired"].itertuples(index=False):
        comparison = row.comparison.removeprefix("LSTM_ensemble_8seed_vs_").lower()
        for column in [
                "n_common", "opponent_median_nse", "lstm_median_nse", "median_diff", "lstm_win_rate",
                "wilcoxon_p", "ci95_low", "ci95_high"
        ]:
            add(
                f"paired.ensemble_vs_{comparison}.{column}",
                getattr(row, column),
                ["I06"],
                "tables/paired.csv",
                f"comparison={row.comparison};column={column}",
            )

    for row in tables["oracle"].itertuples(index=False):
        add(
            f"oracle.{row.quantity}",
            row.value,
            ["I01", "I02", "I03", "I07"],
            "tables/oracle.csv",
            f"quantity={row.quantity};column=value",
        )

    diagnostic_inputs = {"GR4J": ["I01"], "XAJ": ["I02"], "HBV": ["I03"]}
    for row in tables["conceptual_diagnostics"].itertuples(index=False):
        for column in [
                "median_nse", "median_kge", "median_abs_bias", "median_abs_peak_bias",
                "median_abs_lowflow_bias", "median_cal_eval_gap", "n_nse_lt_0"
        ]:
            add(
                f"diagnostic.{slug(row.model)}.{column}",
                getattr(row, column),
                diagnostic_inputs[row.model],
                "tables/conceptual_diagnostics.csv",
                f"model={row.model};column={column}",
            )

    regime_inputs = ["I01", "I02", "I03", "I07", "I08"]
    for row in tables["regime_summary"].itertuples(index=False):
        for column in [
                "n", "GR4J_median_nse", "XAJ_median_nse", "HBV_median_nse",
                "LSTM_ensemble_8seed_median_nse", "median_lstm_minus_best_conceptual",
                "conceptual_beats_lstm_count"
        ]:
            add(
                f"regime.{slug(row.regime)}.{column}",
                getattr(row, column),
                regime_inputs,
                "tables/regime_summary.csv",
                f"regime={row.regime};column={column}",
            )

    parameter_inputs = {
        "GR4J+PDD": ["C01", "C02"],
        "XAJ+PDD": ["C02", "C03", "C05"],
        "HBV-lite": ["C04"],
    }
    for row in tables["parameter_accounting"].itertuples(index=False):
        for column in [
                "nominal_parameters", "effective_active_parameters", "external_snow_parameters_nominal",
                "external_snow_parameters_effective", "intrinsic_snow_parameters"
        ]:
            add(
                f"parameters.{slug(row.model)}.{column}",
                getattr(row, column),
                parameter_inputs[row.model],
                "tables/parameter_accounting.csv",
                f"model={row.model};column={column}",
            )

    context_ids = {
        "snow-dominated / MAM": ("season.snow_spring", ["I12"]),
        "snow-dominated / high-flow": ("flow.snow_high_flow", ["I13"]),
        "snow-dominated / MAM / high-flow": ("joint.snow_spring_high_flow", ["I14"]),
    }
    for row in tables["lstm_advantage_concentration"].itertuples(index=False):
        prefix, input_ids = context_ids[row.hydrologic_context]
        for column in ["context_share", "positive_best_gap_share", "concentration_ratio", "shared_failure_rate"]:
            add(
                f"{prefix}.{column}",
                getattr(row, column),
                input_ids,
                "tables/lstm_advantage_concentration.csv",
                f"hydrologic_context={row.hydrologic_context};column={column}",
            )

    for row in tables["population_evidence"].itertuples(index=False):
        for column in ["n", "spearman_rho", "p_value", "q_value", "quartile_median_difference"]:
            value = getattr(row, column)
            if pd.isna(value):
                continue
            add(
                f"{row.evidence_id}.{column}",
                value,
                [row.input_id],
                "reproducibility/population_evidence.csv",
                f"evidence_id={row.evidence_id};column={column}",
            )

    advantage = _advantage_numbers(out_dir)
    add(
        "joint.snow_spring_high_flow.n_contexts",
        advantage["snow_mam_high_n_contexts"],
        ["I14"],
        "tables/lstm_advantage_concentration.csv",
        "hydrologic_context=snow-dominated / MAM / high-flow;column=n_contexts",
    )
    add(
        "joint.snow_spring_high_flow.shared_failure_count",
        advantage["snow_mam_high_shared_failure_count"],
        ["I14"],
        "tables/lstm_advantage_concentration.csv",
        "hydrologic_context=snow-dominated / MAM / high-flow;column=shared_failure_count",
    )
    return pd.DataFrame(rows)


def _write_reproducibility_records(out_dir: Path, policy: dict, input_validation: pd.DataFrame,
                                   tables: Dict[str, pd.DataFrame], code_input_validation: pd.DataFrame,
                                   archive_validation: pd.DataFrame) -> None:
    repro_dir = out_dir / "reproducibility"
    repro_dir.mkdir(parents=True, exist_ok=True)

    inventory = pd.DataFrame(policy["baseline_files"])
    inventory.to_csv(repro_dir / "snapshot_inventory.csv", index=False, lineterminator="\n")
    input_validation.to_csv(repro_dir / "external_inputs.csv", index=False, lineterminator="\n")
    archive_validation.to_csv(repro_dir / "external_archive_bundle.csv", index=False, lineterminator="\n")
    code_input_validation.to_csv(repro_dir / "code_inputs.csv", index=False, lineterminator="\n")
    tables["population_evidence"].to_csv(
        repro_dir / "population_evidence.csv", index=False, lineterminator="\n"
    )
    _core_evidence_map(out_dir, tables, policy).to_csv(
        repro_dir / "core_evidence_map.csv", index=False, lineterminator="\n"
    )

    output_rows = []
    for relative in policy["top_level_outputs"]:
        path = out_dir / relative
        output_rows.append({"path": relative, "bytes": path.stat().st_size, "sha256": _sha256(path)})
    pd.DataFrame(output_rows).to_csv(
        repro_dir / "top_level_output_hashes.csv", index=False, lineterminator="\n"
    )

    bundle = policy["external_archive_bundle"]
    rebuild = f"""# Minimal manuscript snapshot rebuild

This package has one rebuild entry point, after assembling the committed snapshot in this exact order:

1. Start from a clean repository baseline at the committed snapshot.
2. Read `src/lstm_fair_531/configs/manuscript_snapshot_policy.json` and confirm that all
   {len(policy['proposed_version_control_files'])} paths listed in `proposed_version_control_files` are present in the
   checkout. No separate working-tree overlay is required.
3. Place the single immutable external archive at `{bundle['path']}`. Its registered size is {bundle['bytes']} bytes and
   its SHA-256 digest is `{bundle['sha256']}`.
4. Extract that archive at the repository root:

```powershell
Expand-Archive -LiteralPath "{bundle['path']}" -DestinationPath . -Force
```

5. The archive restores all {len(policy['external_inputs'])} paths listed in `external_inputs`, preserving every relative
   path. Run the sole rebuild command; it validates the archive and every member before reading scientific evidence:

```powershell
python -X utf8 -m src.lstm_fair_531.scripts.build_manuscript_evidence_package --verify-snapshot
```

The command rebuilds the manuscript package and records the 14 top-level output digests in
`reproducibility/top_level_output_hashes.csv`. The committed clean checkout and the registered archive reproduce all
14 top-level outputs directly; archive publication remains outside this local snapshot.
"""
    (repro_dir / "REBUILD.md").write_text(rebuild, encoding="utf-8")


def _to_md_table(df: pd.DataFrame) -> str:
    if df.empty:
        return "| empty |\n|---|"
    safe = df.copy()
    safe = safe.replace({np.nan: ""})
    headers = [str(col) for col in safe.columns]
    rows = []
    for _, row in safe.iterrows():
        rows.append([str(row[col]) for col in safe.columns])

    def escape(value: str) -> str:
        return value.replace("|", "\\|").replace("\n", " ")

    lines = [
        "| " + " | ".join(escape(header) for header in headers) + " |",
        "| " + " | ".join("---" for _ in headers) + " |",
    ]
    for row in rows:
        lines.append("| " + " | ".join(escape(value) for value in row) + " |")
    return "\n".join(lines)


def _write_table(df: pd.DataFrame, csv_path: Path, md_path: Path) -> None:
    df.to_csv(csv_path, index=False)
    md_path.write_text(_to_md_table(df) + "\n", encoding="utf-8")


def _load_conceptual() -> Tuple[pd.DataFrame, pd.DataFrame]:
    frames = []
    wide_cols = []
    for model, path in CONCEPTUAL_FILES.items():
        df = pd.read_csv(path, dtype={"basin_id": str})
        if "period" in df.columns:
            df = df[df["period"] == "evaluation"].copy()
        df["basin_id"] = _bid(df["basin_id"])
        df["model"] = model
        df["cal_eval_gap"] = df["_cal_nse"] - df["nse"]
        frames.append(df)
        wide_cols.append(df.set_index("basin_id")["nse"].rename(model))
    return pd.concat(frames, ignore_index=True), pd.concat(wide_cols, axis=1)


def _load_lstm_metrics(path: Path, label: str) -> pd.Series:
    df = pd.read_csv(path)
    basin_col = "basin" if "basin" in df.columns else df.columns[0]
    nse_col = [col for col in df.columns if col.upper() == "NSE"][0]
    df["basin_id"] = _bid(df[basin_col])
    return df.set_index("basin_id")[nse_col].astype(float).rename(label)


def _load_all_nse() -> pd.DataFrame:
    _, concept_wide = _load_conceptual()
    lstm_single = _load_lstm_metrics(LSTM_SINGLE_METRICS, "LSTM_single_s100")
    lstm_ens = _load_lstm_metrics(LSTM_ENSEMBLE_METRICS, "LSTM_ensemble_8seed")
    return pd.concat([concept_wide, lstm_single, lstm_ens], axis=1).dropna()


def _load_regime() -> pd.Series:
    df = pd.read_csv(DIAG / "cross_method_per_basin_nse.csv", dtype={"basin_id": str})
    df["basin_id"] = _bid(df["basin_id"])
    return df.drop_duplicates("basin_id").set_index("basin_id")["regime"]


def _advantage_numbers(out_dir: Path) -> dict:
    d05 = out_dir / D05_DEEP_DIVE_REL / "tables"
    d06 = out_dir / D06_DEEP_DIVE_REL / "tables"
    season = pd.read_csv(d05 / "season_regime_advantage_concentration.csv")
    flow = pd.read_csv(d05 / "flow_regime_advantage_concentration.csv")
    joint = pd.read_csv(d06 / "joint_regime_advantage_concentration.csv")

    snow_mam = season[(season["regime"] == "snow-dominated") & (season["season"] == "MAM")].iloc[0]
    snow_high = flow[(flow["regime"] == "snow-dominated") & (flow["flow_group"] == "high")].iloc[0]
    snow_mam_high = joint[(joint["regime"] == "snow-dominated") & (joint["season"] == "MAM") &
                          (joint["flow_group"] == "high")].iloc[0]
    joint_n_contexts = int(snow_mam_high["n_contexts"])
    joint_shared_failure_count = int(round(joint_n_contexts * float(snow_mam_high["shared_failure_rate"])))
    return {
        "snow_mam_context_share": float(snow_mam["context_share"]),
        "snow_mam_gap_share": float(snow_mam["positive_best_gap_share"]),
        "snow_mam_ratio": float(snow_mam["gap_concentration_ratio"]),
        "snow_mam_shared_failure": float(snow_mam["shared_failure_rate"]),
        "snow_high_context_share": float(snow_high["context_share"]),
        "snow_high_gap_share": float(snow_high["positive_best_gap_share"]),
        "snow_high_ratio": float(snow_high["gap_concentration_ratio"]),
        "snow_high_shared_failure": float(snow_high["shared_failure_rate"]),
        "snow_mam_high_context_share": float(snow_mam_high["context_share"]),
        "snow_mam_high_gap_share": float(snow_mam_high["positive_best_gap_share"]),
        "snow_mam_high_ratio": float(snow_mam_high["gap_concentration_ratio"]),
        "snow_mam_high_shared_failure": float(snow_mam_high["shared_failure_rate"]),
        "snow_mam_high_median_gap": float(snow_mam_high["median_best_conceptual_mae_minus_lstm"]),
        "snow_mam_high_n_contexts": joint_n_contexts,
        "snow_mam_high_shared_failure_count": joint_shared_failure_count,
    }


def _advantage_concentration_table(out_dir: Path) -> pd.DataFrame:
    adv = _advantage_numbers(out_dir)
    return pd.DataFrame([
        {
            "context_family": "regime-season",
            "hydrologic_context": "snow-dominated / MAM",
            "context_share": adv["snow_mam_context_share"],
            "positive_best_gap_share": adv["snow_mam_gap_share"],
            "concentration_ratio": adv["snow_mam_ratio"],
            "shared_failure_rate": adv["snow_mam_shared_failure"],
        },
        {
            "context_family": "regime-flow",
            "hydrologic_context": "snow-dominated / high-flow",
            "context_share": adv["snow_high_context_share"],
            "positive_best_gap_share": adv["snow_high_gap_share"],
            "concentration_ratio": adv["snow_high_ratio"],
            "shared_failure_rate": adv["snow_high_shared_failure"],
        },
        {
            "context_family": "regime-season-flow",
            "hydrologic_context": "snow-dominated / MAM / high-flow",
            "context_share": adv["snow_mam_high_context_share"],
            "positive_best_gap_share": adv["snow_mam_high_gap_share"],
            "concentration_ratio": adv["snow_mam_high_ratio"],
            "shared_failure_rate": adv["snow_mam_high_shared_failure"],
            "n_contexts": adv["snow_mam_high_n_contexts"],
            "shared_failure_count": adv["snow_mam_high_shared_failure_count"],
        },
    ])


def _population_support_numbers(out_dir: Path) -> dict:
    d01 = pd.read_csv(out_dir / D01_DEEP_DIVE_REL / "tables" / "primary_static_spearman.csv")
    seasonal = pd.read_csv(out_dir / D04_DEEP_DIVE_REL / "tables" / "seasonal_attribute_link_checks.csv")
    flow = pd.read_csv(out_dir / D04_DEEP_DIVE_REL / "tables" / "flow_attribute_link_checks.csv")

    basin_snow = d01[(d01["target"] == "lstm_minus_best_conceptual") &
                     (d01["feature"] == "clim_frac_snow")].iloc[0]
    mam_snow = seasonal[(seasonal["context"] == "MAM") &
                        (seasonal["target"] == "best_conceptual_mae_minus_lstm") &
                        (seasonal["feature"] == "clim_frac_snow")].iloc[0]
    high_snow = flow[(flow["context"] == "high") &
                     (flow["target"] == "best_conceptual_mae_minus_lstm") &
                     (flow["feature"] == "clim_frac_snow")].iloc[0]
    return {
        "basin_snow_rho": float(basin_snow["spearman_rho"]),
        "basin_snow_q": float(basin_snow["q_value"]),
        "mam_snow_rho": float(mam_snow["spearman_rho"]),
        "mam_snow_q": float(mam_snow["q_value"]),
        "high_snow_rho": float(high_snow["spearman_rho"]),
        "high_snow_q": float(high_snow["q_value"]),
    }


def _population_evidence_table(out_dir: Path, policy: dict) -> pd.DataFrame:
    specs = [
        ("population.snow_fraction", "I09", {"target": "lstm_minus_best_conceptual",
                                               "feature": "clim_frac_snow"}),
        ("population.spring_snow_fraction", "I10", {"context": "MAM",
                                                      "target": "best_conceptual_mae_minus_lstm",
                                                      "feature": "clim_frac_snow"}),
        ("population.high_flow_snow_fraction", "I11", {"context": "high",
                                                         "target": "best_conceptual_mae_minus_lstm",
                                                         "feature": "clim_frac_snow"}),
    ]
    rows = []
    for evidence_id, input_id, filters in specs:
        item_path = Path(_policy_input(policy, input_id)["path"])
        package_root = Path(policy["baseline_package_root"])
        source_path = out_dir / item_path.relative_to(package_root) if _is_under(item_path, package_root) else item_path
        source = pd.read_csv(source_path)
        selected = source
        for column, value in filters.items():
            selected = selected[selected[column] == value]
        if len(selected) != 1:
            raise ValueError(f"Expected one population evidence row for {evidence_id}, found {len(selected)}")
        row = selected.iloc[0]
        rows.append({
            "evidence_id": evidence_id,
            "input_id": input_id,
            "n": int(row["n"]),
            "spearman_rho": float(row["spearman_rho"]),
            "p_value": float(row["p_value"]),
            "q_value": float(row["q_value"]),
            "quartile_median_difference": (
                float(row["quartile_median_effect_high_minus_low"])
                if "quartile_median_effect_high_minus_low" in row.index else np.nan
            ),
        })
    return pd.DataFrame(rows)


def _main_benchmark_table(all_nse: pd.DataFrame) -> pd.DataFrame:
    rows = []
    for model in ["GR4J", "XAJ", "HBV", "LSTM_single_s100", "LSTM_ensemble_8seed"]:
        vals = all_nse[model].dropna()
        row = {
            "model": model,
            "n": int(vals.shape[0]),
            "median_nse": float(vals.median()),
            "mean_nse": float(vals.mean()),
        }
        if model != "GR4J":
            diff = vals - all_nse.loc[vals.index, "GR4J"]
            row["median_delta_vs_gr4j"] = float(diff.median())
            row["win_rate_vs_gr4j"] = float((diff > 0).mean())
        else:
            row["median_delta_vs_gr4j"] = 0.0
            row["win_rate_vs_gr4j"] = np.nan
        rows.append(row)
    return pd.DataFrame(rows)


def _paired_comparison_table() -> pd.DataFrame:
    report = _load_json(LSTM_ENSEMBLE_REPORT)
    rows = []
    for opponent, payload in report["full_531"]["vs"].items():
        rows.append({
            "comparison": f"LSTM_ensemble_8seed_vs_{opponent}",
            "n_common": payload["n_common"],
            "opponent_median_nse": payload["concept_median"],
            "lstm_median_nse": payload["lstm_median"],
            "median_diff": payload["median_diff"],
            "lstm_win_rate": payload["lstm_win_rate"],
            "wilcoxon_p": payload.get("wilcoxon_p"),
            "ci95_low": payload["median_diff_CI95"][0],
            "ci95_high": payload["median_diff_CI95"][1],
        })
    return pd.DataFrame(rows)


def _diagnostic_table(concept_long: pd.DataFrame) -> pd.DataFrame:
    rows = []
    for model, group in concept_long.groupby("model"):
        rows.append({
            "model": model,
            "median_nse": float(group["nse"].median()),
            "median_kge": float(group["kge"].median()),
            "median_abs_bias": float(group["bias"].abs().median()),
            "median_abs_peak_bias": float(group["peak_bias"].abs().median()),
            "median_abs_lowflow_bias": float(group["lowflow_bias"].abs().median()),
            "median_cal_eval_gap": float(group["cal_eval_gap"].median()),
            "n_nse_lt_0": int((group["nse"] < 0).sum()),
        })
    order = {"GR4J": 0, "XAJ": 1, "HBV": 2}
    return pd.DataFrame(rows).sort_values("model", key=lambda s: s.map(order)).reset_index(drop=True)


def _winner_table(concept_long: pd.DataFrame) -> pd.DataFrame:
    wide = concept_long.pivot(index="basin_id", columns="model")
    rows = []
    for metric in ["nse", "kge"]:
        counts = wide[metric].idxmax(axis=1).value_counts()
        for model, count in counts.items():
            rows.append({"metric": metric, "winner_rule": "higher_is_better", "model": model, "n_wins": int(count)})
    for metric in ["bias", "peak_bias", "lowflow_bias", "cal_eval_gap"]:
        values = wide[metric].abs()
        best = values.min(axis=1)
        for model in ["GR4J", "XAJ", "HBV"]:
            rows.append({
                "metric": f"abs_{metric}",
                "winner_rule": "lower_abs_is_better",
                "model": model,
                "n_wins": int(((values[model] - best).abs() < 1e-12).sum()),
            })
    return pd.DataFrame(rows)


def _regime_table(all_nse: pd.DataFrame) -> pd.DataFrame:
    regime = _load_regime()
    df = all_nse.copy()
    df["regime"] = regime.reindex(df.index)
    rows = []
    for regime_name, group in df.groupby("regime"):
        best_concept = group[["GR4J", "XAJ", "HBV"]].max(axis=1)
        row = {"regime": regime_name, "n": int(group.shape[0])}
        for model in ["GR4J", "XAJ", "HBV", "LSTM_ensemble_8seed"]:
            row[f"{model}_median_nse"] = float(group[model].median())
        row["median_lstm_minus_best_conceptual"] = float((group["LSTM_ensemble_8seed"] - best_concept).median())
        row["conceptual_beats_lstm_count"] = int((best_concept > group["LSTM_ensemble_8seed"]).sum())
        rows.append(row)
    return pd.DataFrame(rows).sort_values("regime").reset_index(drop=True)


def _oracle_table(all_nse: pd.DataFrame) -> pd.DataFrame:
    best_concept = all_nse[["GR4J", "XAJ", "HBV"]].max(axis=1)
    all4 = pd.concat([best_concept.rename("best_conceptual"), all_nse["LSTM_ensemble_8seed"]], axis=1).max(axis=1)
    winners = all_nse[["GR4J", "XAJ", "HBV", "LSTM_ensemble_8seed"]].idxmax(axis=1).value_counts()
    rows = [
        {"quantity": "best_conceptual_median_nse", "value": float(best_concept.median())},
        {"quantity": "lstm_ensemble_median_nse", "value": float(all_nse["LSTM_ensemble_8seed"].median())},
        {"quantity": "four_model_oracle_median_nse", "value": float(all4.median())},
        {"quantity": "four_model_oracle_minus_lstm_median", "value": float((all4 - all_nse["LSTM_ensemble_8seed"]).median())},
        {"quantity": "four_model_oracle_minus_lstm_mean", "value": float((all4 - all_nse["LSTM_ensemble_8seed"]).mean())},
        {"quantity": "conceptual_beats_lstm_count", "value": int((best_concept > all_nse["LSTM_ensemble_8seed"]).sum())},
    ]
    for model in ["GR4J", "XAJ", "HBV", "LSTM_ensemble_8seed"]:
        rows.append({"quantity": f"winner_count_{model}", "value": int(winners.get(model, 0))})
    return pd.DataFrame(rows)


def _protocol_table() -> pd.DataFrame:
    return pd.DataFrame([
        {
            "family": "conceptual_models",
            "models": "GR4J+PDD; XAJ+PDD; HBV-lite",
            "basins": 531,
            "forcing": "maurer",
            "calibration_or_training": "1999-10-01 to 2008-09-30",
            "evaluation": "1989-10-01 to 1999-09-30",
            "metric": "per-basin NSE, median/mean across basins",
            "budget_or_seed_policy": "CMA-ES 5000 trials x 3 restarts",
            "input_information": "forcing plus model parameters; no observed discharge as input",
            "source": str(REPRO),
        },
        {
            "family": "lstm_ceiling",
            "models": "cudalstm+static, seed 100 and 8-seed ensemble",
            "basins": 531,
            "forcing": "maurer",
            "calibration_or_training": "1999-10-01 to 2008-09-30",
            "evaluation": "1989-10-01 to 1999-09-30",
            "metric": "per-basin NSE, median/mean across basins",
            "budget_or_seed_policy": "30 epochs; seeds 100..800; regional training with 27 static basin attributes",
            "input_information": "forcing plus 27 static attributes; no observed discharge as input",
            "source": "results/18_lstm_fair_531",
        },
    ])


def _parameter_accounting_table() -> pd.DataFrame:
    return pd.DataFrame([
        {
            "model": "GR4J+PDD",
            "snow_module_class": "external PDD-noice front end",
            "nominal_parameters": 8,
            "effective_active_parameters": 8,
            "external_snow_parameters_nominal": 4,
            "external_snow_parameters_effective": 4,
            "intrinsic_snow_parameters": 0,
            "accounting_note": "4 active no-ice PDD parameters plus 4 GR4J parameters.",
        },
        {
            "model": "XAJ+PDD",
            "snow_module_class": "external full PDD wrapper, zero-ice effective path",
            "nominal_parameters": 20,
            "effective_active_parameters": 18,
            "external_snow_parameters_nominal": 6,
            "external_snow_parameters_effective": 4,
            "intrinsic_snow_parameters": 0,
            "accounting_note": "pdd_factor_ice and refreeze_ice are inactive when ice storage starts at zero.",
        },
        {
            "model": "HBV-lite",
            "snow_module_class": "intrinsic HBV degree-day snow routine",
            "nominal_parameters": 13,
            "effective_active_parameters": 13,
            "external_snow_parameters_nominal": 0,
            "external_snow_parameters_effective": 0,
            "intrinsic_snow_parameters": 4,
            "accounting_note": "Snow is part of HBV structure: parTT, parCFMAX, parCFR, parCWH.",
        },
    ])


def _fairness_audit_table() -> pd.DataFrame:
    pdd_test = PDD_FAIRNESS_TEST.as_posix()
    return pd.DataFrame([
        {
            "dimension": "external_snow_frontend_GR4J_XAJ",
            "classification": "effective-equivalent",
            "conclusion": "GR4J no-ice PDD and XAJ full-PDD with zero ice follow the same active snow path.",
            "evidence": f"{pdd_test}; src/xaj_global_pilot/pdd_core.py::pdd_noice_step_mm",
            "paper_action": "Describe the external PDD front end as tested effective-equivalent, not merely assumed equal.",
        },
        {
            "dimension": "xaj_ice_parameters",
            "classification": "effective-inactive",
            "conclusion": "Changing pdd_factor_ice/refreeze_ice does not change runoff or states under zero initial ice.",
            "evidence": f"{pdd_test}; XAJ PDD state starts with ice=0 and has no ice-creation term.",
            "paper_action": "Report XAJ nominal parameters as 20 and effective active parameters as 18.",
        },
        {
            "dimension": "hbv_snow_module",
            "classification": "model-intrinsic difference",
            "conclusion": "HBV-lite snow handling is part of the HBV model structure, not an added shared PDD wrapper.",
            "evidence": "src/scl_hydro/hbv_lite_numpy.py states SNOWPACK/MELTWATER and parameters parTT/parCFMAX/parCFR/parCWH.",
            "paper_action": "Keep HBV in the benchmark, but disclose this structural difference in Methods and Limitations.",
        },
        {
            "dimension": "basin_forcing_split_pet_warmup",
            "classification": "aligned",
            "conclusion": "The final conceptual artifacts use 531 basins, Maurer forcing, PT PET, reverse split, and eval warmup-year.",
            "evidence": "Final artifact filenames and runner metadata under results/10_global_conceptual_model_benchmark.",
            "paper_action": "State same predictive-information protocol for the conceptual benchmark.",
        },
        {
            "dimension": "cmaes_budget_seed_init_loss",
            "classification": "aligned",
            "conclusion": "GR4J/XAJ/HBV use CMA-ES 5000 trials x 3 restarts, seed 42+1000*r, init 0.5, sigma 0.3, NSE loss.",
            "evidence": "src/xaj_global_pilot/xaj_model.py::_cmaes_multi_restart; src/scl_hydro/hbv_lite_cma_calibrate.py.",
            "paper_action": "Report the common optimizer budget and selection rule.",
        },
        {
            "dimension": "bounds_and_constraints",
            "classification": "model-specific/disclosed",
            "conclusion": "Parameter bounds are model-specific; XAJ applies its intrinsic ki+kg constraint; GR4J/HBV do not need it.",
            "evidence": "src/xaj_global_pilot/bounds_presets.py; src/xaj_global_pilot/gr4j_model.py; src/scl_hydro/hbv_lite_numpy.py.",
            "paper_action": "Disclose bounds presets and treat this as structural calibration space, not a hidden advantage.",
        },
        {
            "dimension": "saved_parameter_replay_after_code_changes",
            "classification": "passed_full_531",
            "conclusion": "Saved calibrated parameters replay under the current code for all 531 common basins in saved-state and warmup-recomputed modes.",
            "evidence": f"{(REPLAY_AUDIT_REL / 'saved_parameter_replay_summary.csv').as_posix()}; {REPLAY_AUDIT_COMMAND}",
            "paper_action": "Use replay as an artifact-validity audit; do not call it a fresh recalibration.",
        },
        {
            "dimension": "stale_petbug_v7_references",
            "classification": "historical-only/quarantined",
            "conclusion": "Old PET-bug, XAJ 0.4458/0.6372, and HBV-v7 references are not active manuscript evidence.",
            "evidence": "audit/stale_reference_audit.csv and docs/technical/camels_us_531_regime_diagnostic.md quarantine banner.",
            "paper_action": "Use only final PT 5k x 3 artifacts in manuscript tables and captions.",
        },
    ])


def _is_under(path: Path, parent: Path) -> bool:
    try:
        path.relative_to(parent)
        return True
    except ValueError:
        return False


def _stale_classification(path: Path, text: str, quarantined: bool = False) -> Tuple[str, str]:
    posix = path.as_posix()
    if "src/lstm_fair_531/scripts/build_manuscript_evidence_package.py" in posix:
        return "safe_audit_tool", "This script stores stale tokens only as scan patterns."
    if "docs/technical/camels_us_531_regime_diagnostic.md" in posix:
        if quarantined:
            return "quarantined_stale", "Superseded PET-bug diagnostic is explicitly quarantined; do not use as manuscript evidence."
        return "blocker", "Archive or rewrite before manuscript use; it points at PET-bug XAJ diagnostics."
    if "src/xaj_global_pilot/scripts/gr4j_final_report.py" in posix:
        return "blocker", "Update script defaults to final 5k x 3 XAJ/HBV artifacts before using for figures/tables."
    if "src/xaj_global_pilot/scripts/run_xaj_pdd_cma_repro_v01.py" in posix:
        return "safe_historical_docstring", "Runner mentions the old PET-bug baseline only as historical motivation."
    if "draft/papers/10_18_conceptual_lstm_gap_validation_20260709.md" in posix:
        return "safe_audit_note", "This file mentions stale paths only as audit checks."
    historical_markers = [
        "handoffs",
        "xaj_playbook",
        "gr4j_playbook",
        "camels_531_lockdown_report",
        "plans",
        "specs",
        "IDEA_RESCUE_LEDGER",
        "ideas/10_",
    ]
    if any(marker in posix for marker in historical_markers):
        return "historical_caveat", "Keep as history unless this document is reused as manuscript text."
    if path.suffix == ".py":
        return "review_needed", "Potential active code path; verify before generating manuscript artifacts."
    return "review_needed", "Potential stale prose; inspect before manuscript reuse."


def _stale_reference_audit(out_dir: Path | None = None,
                           scan_paths: Iterable[Path] | None = None) -> pd.DataFrame:
    rows = []
    excluded_dirs = []
    if out_dir is not None:
        excluded_dirs.append(out_dir.resolve())
    for root in scan_paths or ACTIVE_STALE_SCAN_PATHS:
        if not root.exists():
            continue
        candidates = [root] if root.is_file() else root.rglob("*")
        for path in candidates:
            if not path.is_file() or path.suffix not in SCAN_SUFFIXES:
                continue
            resolved = path.resolve()
            if any(_is_under(resolved, excluded) for excluded in excluded_dirs):
                continue
            try:
                lines = path.read_text(encoding="utf-8", errors="ignore").splitlines()
            except UnicodeDecodeError:
                continue
            quarantined = "STALE_PETBUG_SUPERSEDED" in "\n".join(lines[:12])
            for line_no, line in enumerate(lines, start=1):
                hits = [pat for pat in STALE_PATTERNS if pat in line]
                if not hits:
                    continue
                status, action = _stale_classification(path, line, quarantined=quarantined)
                rows.append({
                    "file": path.as_posix(),
                    "line": line_no,
                    "patterns": "; ".join(hits),
                    "status": status,
                    "recommended_action": action,
                    "excerpt": line.strip()[:240],
                })
    return pd.DataFrame(rows, columns=[
        "file", "line", "patterns", "status", "recommended_action", "excerpt"
    ])


def _plot_cdf(all_nse: pd.DataFrame, fig_path: Path) -> None:
    colors = {
        "GR4J": "#0072B2",
        "XAJ": "#009E73",
        "HBV": "#E69F00",
        "LSTM_single_s100": "#CC79A7",
        "LSTM_ensemble_8seed": "#D55E00",
    }
    labels = {
        "GR4J": "GR4J+PDD",
        "XAJ": "XAJ+PDD",
        "HBV": "HBV-lite",
        "LSTM_single_s100": "LSTM single",
        "LSTM_ensemble_8seed": "LSTM ensemble",
    }
    fig, ax = plt.subplots(figsize=(7.2, 4.4))
    for model in ["GR4J", "XAJ", "HBV", "LSTM_single_s100", "LSTM_ensemble_8seed"]:
        vals = np.sort(all_nse[model].dropna().to_numpy())
        y = np.arange(1, len(vals) + 1) / len(vals)
        ax.plot(vals, y, label=labels[model], linewidth=2, color=colors[model])
    ax.axvline(0.0, color="#666666", linewidth=0.8, linestyle="--")
    ax.set_xlabel("Basin-wise NSE")
    ax.set_ylabel("Empirical CDF")
    ax.set_title("CAMELS-US 531 NSE distributions")
    ax.grid(True, alpha=0.25)
    ax.legend(frameon=False)
    fig.tight_layout()
    fig.savefig(fig_path, dpi=220)
    plt.close(fig)


def _plot_regime(regime_df: pd.DataFrame, fig_path: Path) -> None:
    models = ["GR4J_median_nse", "XAJ_median_nse", "HBV_median_nse", "LSTM_ensemble_8seed_median_nse"]
    labels = ["GR4J", "XAJ", "HBV", "LSTM ens"]
    colors = ["#0072B2", "#009E73", "#E69F00", "#D55E00"]
    x = np.arange(len(regime_df))
    width = 0.19
    fig, ax = plt.subplots(figsize=(8.2, 4.6))
    for idx, (model, label, color) in enumerate(zip(models, labels, colors)):
        ax.bar(x + (idx - 1.5) * width, regime_df[model], width=width, label=label, color=color)
    ax.set_xticks(x)
    ax.set_xticklabels(regime_df["regime"], rotation=18, ha="right")
    ax.set_ylabel("Median NSE")
    ax.set_title("Regime-wise median NSE")
    ax.grid(axis="y", alpha=0.25)
    ax.legend(frameon=False, ncol=4)
    fig.tight_layout()
    fig.savefig(fig_path, dpi=220)
    plt.close(fig)


def _plot_diagnostics(diag_df: pd.DataFrame, fig_path: Path) -> None:
    metrics = [
        "median_abs_bias",
        "median_abs_peak_bias",
        "median_abs_lowflow_bias",
        "median_cal_eval_gap",
    ]
    labels = ["abs bias", "abs peak bias", "abs low-flow bias", "cal-eval gap"]
    colors = {"GR4J": "#0072B2", "XAJ": "#009E73", "HBV": "#E69F00"}
    x = np.arange(len(metrics))
    width = 0.24
    fig, ax = plt.subplots(figsize=(8.0, 4.4))
    for idx, model in enumerate(["GR4J", "XAJ", "HBV"]):
        vals = [diag_df.loc[diag_df["model"] == model, metric].iloc[0] for metric in metrics]
        ax.bar(x + (idx - 1) * width, vals, width=width, label=model, color=colors[model])
    ax.set_xticks(x)
    ax.set_xticklabels(labels, rotation=15, ha="right")
    ax.set_ylabel("Median value (lower is better)")
    ax.set_title("Conceptual-model diagnostic trade-offs")
    ax.grid(axis="y", alpha=0.25)
    ax.legend(frameon=False, ncol=3)
    fig.tight_layout()
    fig.savefig(fig_path, dpi=220)
    plt.close(fig)


def _plot_lstm_margin(all_nse: pd.DataFrame, fig_path: Path) -> None:
    regime = _load_regime()
    df = all_nse.copy()
    df["regime"] = regime.reindex(df.index)
    df["best_conceptual"] = df[["GR4J", "XAJ", "HBV"]].max(axis=1)
    df["lstm_minus_best_conceptual"] = df["LSTM_ensemble_8seed"] - df["best_conceptual"]
    order = ["humid", "snow-dominated", "semi-humid", "semi-arid/arid"]
    data = [df.loc[df["regime"] == regime_name, "lstm_minus_best_conceptual"].dropna().to_numpy() for regime_name in order]
    fig, ax = plt.subplots(figsize=(7.4, 4.5))
    ax.boxplot(data, tick_labels=order, showfliers=False, patch_artist=True,
               boxprops={"facecolor": "#D9EAF7", "edgecolor": "#0072B2"},
               medianprops={"color": "#D55E00", "linewidth": 2})
    ax.axhline(0.0, color="#555555", linewidth=1.0, linestyle="--")
    ax.set_ylabel("LSTM ensemble NSE - best conceptual NSE")
    ax.set_title("Predictive margin over the best conceptual model")
    ax.grid(axis="y", alpha=0.25)
    fig.tight_layout()
    fig.savefig(fig_path, dpi=220)
    plt.close(fig)


def _provenance_ledger(out_dir: Path) -> pd.DataFrame:
    command = "python -X utf8 -m src.lstm_fair_531.scripts.build_manuscript_evidence_package"
    pdd_test = PDD_FAIRNESS_TEST.as_posix()
    rows = [
        {
            "claim_id": "C01",
            "paper_element": "Table 1 main benchmark",
            "claim": "Full-531 medians for GR4J, XAJ, HBV, LSTM single, and LSTM ensemble.",
            "artifact": "tables/main_benchmark.csv",
            "source_files": "; ".join([str(path) for path in CONCEPTUAL_FILES.values()] + [
                str(LSTM_SINGLE_REPORT),
                str(LSTM_ENSEMBLE_METRICS),
            ]),
            "script_or_command": command,
            "status": "reproducible_from_saved_artifacts",
            "notes": "No model rerun required; reads per-basin metric artifacts.",
        },
        {
            "claim_id": "C02",
            "paper_element": "Table 2 paired comparison",
            "claim": "LSTM ensemble paired deltas, win rates, Wilcoxon p-values, and bootstrap CIs vs conceptual models.",
            "artifact": "tables/paired.csv",
            "source_files": str(LSTM_ENSEMBLE_REPORT),
            "script_or_command": command,
            "status": "auditable_from_saved_report",
            "notes": "Statistical results are read from the audited ID18 compare report.",
        },
        {
            "claim_id": "C03",
            "paper_element": "Table 3 diagnostic metrics",
            "claim": "Conceptual-model KGE, bias, peak, low-flow, and split-gap diagnostic trade-offs.",
            "artifact": "tables/conceptual_diagnostics.csv",
            "source_files": "; ".join(str(path) for path in CONCEPTUAL_FILES.values()),
            "script_or_command": command,
            "status": "reproducible_from_saved_artifacts",
            "notes": "These are conceptual-only summary diagnostics; LSTM residual diagnostics and advantage decomposition are tracked separately in D02-D06.",
        },
        {
            "claim_id": "C04",
            "paper_element": "Table 4 regime analysis",
            "claim": "Regime-wise medians and counts where conceptual models beat the LSTM ensemble.",
            "artifact": "tables/regime_summary.csv",
            "source_files": "; ".join([str(DIAG / "cross_method_per_basin_nse.csv"), str(LSTM_ENSEMBLE_METRICS)]),
            "script_or_command": command,
            "status": "reproducible_from_saved_artifacts",
            "notes": "Regime labels come from the existing diagnostic file.",
        },
        {
            "claim_id": "C05",
            "paper_element": "Figure 1 NSE CDF",
            "claim": "NSE distribution contrast across conceptual models and LSTM references.",
            "artifact": "figures/fig1_nse_cdf.png",
            "source_files": "Same as C01",
            "script_or_command": command,
            "status": "reproducible_from_saved_artifacts",
            "notes": "Generated with matplotlib Agg.",
        },
        {
            "claim_id": "C06",
            "paper_element": "Stale-reference audit",
            "claim": "Known stale PET-bug and HBV-v7 references are excluded from active snapshot sources.",
            "artifact": "audit/stale_reference_audit.csv",
            "source_files": "; ".join(path.as_posix() for path in ACTIVE_STALE_SCAN_PATHS),
            "script_or_command": command,
            "status": "reproducible_active_snapshot_scan",
            "notes": "The scan is intentionally limited to active snapshot sources so unrelated working-tree files cannot change package hashes.",
        },
        {
            "claim_id": "C07",
            "paper_element": "Parameter accounting table",
            "claim": "Conceptual-model parameter counts distinguish nominal from effective active parameters.",
            "artifact": "tables/parameter_accounting.csv",
            "source_files": "src/xaj_global_pilot/gr4j_core.py; src/xaj_global_pilot/xaj_model.py; src/scl_hydro/hbv_lite_numpy.py",
            "script_or_command": command,
            "status": "reproducible_from_code_audit",
            "notes": "XAJ has 20 nominal parameters but 18 effective active parameters under zero initial ice.",
        },
        {
            "claim_id": "C08",
            "paper_element": "Fairness audit table",
            "claim": "External snow-module and calibration-protocol fairness checks are classified and linked to tests/code.",
            "artifact": "tables/fairness_audit.csv",
            "source_files": f"{pdd_test}; conceptual runners; calibration modules",
            "script_or_command": command,
            "status": "reproducible_from_tests_and_code_audit",
            "notes": "Run pytest test/test_id10_pdd_fairness.py -q before relying on the effective-equivalence claim.",
        },
        {
            "claim_id": "C09",
            "paper_element": "Manuscript-ready claim map",
            "claim": "Each manuscript claim is tied to evidence, allowed wording, and a boundary condition.",
            "artifact": "manuscript_ready_claim_map.md",
            "source_files": "tables/main_benchmark.csv; tables/paired.csv; tables/oracle.csv; tables/fairness_audit.csv",
            "script_or_command": command,
            "status": "reproducible_from_saved_artifacts",
            "notes": "Use this file to keep the abstract, results, and discussion from overclaiming.",
        },
        {
            "claim_id": "C10",
            "paper_element": "Methods/Results/Limitations section draft",
            "claim": "Paper-ready section prose reflects benchmark results and fairness boundaries.",
            "artifact": "manuscript_sections.md",
            "source_files": "tables/main_benchmark.csv; tables/paired.csv; tables/conceptual_diagnostics.csv; tables/regime_summary.csv; tables/oracle.csv",
            "script_or_command": command,
            "status": "reproducible_from_saved_artifacts",
            "notes": "Draft prose is evidence-grounded but still needs final manuscript integration and citations.",
        },
        {
            "claim_id": "C11",
            "paper_element": "Figure/table captions and reviewer-risk checklist",
            "claim": "Captions and risk checklist encode the intended claim boundaries for submission.",
            "artifact": "figure_table_captions.md; reviewer_risk_checklist.md",
            "source_files": "MANIFEST.json; tables/fairness_audit.csv; tables/parameter_accounting.csv; claims_limitations.md",
            "script_or_command": command,
            "status": "reproducible_from_package_state",
            "notes": "Use the risk checklist before every manuscript export.",
        },
        {
            "claim_id": "C12",
            "paper_element": "Final submission readiness memo",
            "claim": "The package is ready for paper drafting and internal pre-submission review, with residual risks stated.",
            "artifact": "final_submission_readiness_memo.md",
            "source_files": "MANIFEST.json; tables/main_benchmark.csv; tables/oracle.csv; audit/stale_reference_audit.csv",
            "script_or_command": command,
            "status": "reproducible_from_package_state",
            "notes": "The memo distinguishes manuscript-ready evidence from a fully typeset journal submission.",
        },
        {
            "claim_id": "C13",
            "paper_element": "Saved-parameter replay audit",
            "claim": "Final GR4J/XAJ/HBV saved parameter artifacts replay under the current code for all 531 basins.",
            "artifact": (REPLAY_AUDIT_REL / "saved_parameter_replay_summary.csv").as_posix(),
            "source_files": "; ".join(str(path) for path in CONCEPTUAL_FILES.values()),
            "script_or_command": REPLAY_AUDIT_COMMAND,
            "status": "reproducible_forward_replay_from_saved_parameters",
            "notes": "This validates artifact continuity after code changes; it is not a full CMA-ES recalibration.",
        },
        {
            "claim_id": "C14",
            "paper_element": "D01 basin-attribute diagnostic deep dive",
            "claim": "Static CAMELS attributes explain part of the conceptual-structure disagreements and the LSTM margin over the basin-wise highest-NSE conceptual comparator.",
            "artifact": (D01_DEEP_DIVE_REL / "tables" / "primary_static_spearman.csv").as_posix(),
            "source_files": "tables/per_basin_combined_nse.csv; data/camels_us/camels_attributes_v2.0",
            "script_or_command": "python -X utf8 -m src.lstm_fair_531.scripts.deep_dive_structure_diagnostics",
            "status": "reproducible_posthoc_diagnostic",
            "notes": "Primary claims exclude streamflow-derived camels_hydro; hydro signatures are supplemental only.",
        },
        {
            "claim_id": "C15",
            "paper_element": "D02 seasonal residual diagnostic deep dive",
            "claim": "Representative case hydrographs show seasonal and high-flow residual patterns consistent with the snow/aridity diagnostic signals.",
            "artifact": (D02_DEEP_DIVE_REL / "tables" / "seasonal_delta_aggregate.csv").as_posix(),
            "source_files": (D01_DEEP_DIVE_REL / "tables" / "case_basin_list.csv").as_posix(),
            "script_or_command": "python -X utf8 -m src.lstm_fair_531.scripts.seasonal_residual_deep_dive",
            "status": "reproducible_selected_case_diagnostic",
            "notes": "Selected cases are diagnostic examples, not population-wide residual estimates.",
        },
        {
            "claim_id": "C16",
            "paper_element": "D03 snow-population seasonal residual diagnostic",
            "claim": "Across all 152 snow-dominated basins, MAM and high-flow residual penalties relative to the LSTM remain population-wide.",
            "artifact": (D03_DEEP_DIVE_REL / "tables" / "seasonal_delta_aggregate.csv").as_posix(),
            "source_files": (D01_DEEP_DIVE_REL / "tables" / "basin_attribute_panel.csv").as_posix(),
            "script_or_command": "python -X utf8 -m src.lstm_fair_531.scripts.seasonal_residual_deep_dive --population snow --max-basins 0",
            "status": "reproducible_population_diagnostic",
            "notes": "Post-hoc residual diagnosis only; daily NSE reaggregation check reproduces D01 basin NSE within 5e-7.",
        },
        {
            "claim_id": "C17",
            "paper_element": "D04 full-population residual attribute review",
            "claim": "Full-531 seasonal/high-flow residual targets align with D01 snow, topography, aridity, conceptual-spread, and LSTM-gap axes.",
            "artifact": (D04_DEEP_DIVE_REL / "tables" / "seasonal_attribute_link_checks.csv").as_posix(),
            "source_files": (D01_DEEP_DIVE_REL / "tables" / "basin_attribute_panel.csv").as_posix(),
            "script_or_command": "python -X utf8 -m src.lstm_fair_531.scripts.population_residual_attribute_review",
            "status": "reproducible_population_attribute_review",
            "notes": "Uses D01 primary/static attributes only; no camels_hydro attributes are used.",
        },
        {
            "claim_id": "C18",
            "paper_element": "D05 LSTM advantage decomposition",
            "claim": "Snow-dominated MAM and high-flow contexts overcontribute to the positive LSTM-vs-best-conceptual MAE gap.",
            "artifact": (D05_DEEP_DIVE_REL / "tables" / "top_advantage_contexts.csv").as_posix(),
            "source_files": (
                (D04_DEEP_DIVE_REL / "tables" / "conceptual_vs_lstm_by_case_season.csv").as_posix() + "; " +
                (D04_DEEP_DIVE_REL / "tables" / "conceptual_vs_lstm_by_case_flow_group.csv").as_posix()
            ),
            "script_or_command": "python -X utf8 -m src.lstm_fair_531.scripts.lstm_advantage_decomposition",
            "status": "reproducible_population_advantage_decomposition",
            "notes": "Uses generated D04 delta artifacts; headline uses MAE best-gap concentration because low-flow NSE can be unstable.",
        },
        {
            "claim_id": "C19",
            "paper_element": "D06 joint season-flow LSTM advantage decomposition",
            "claim": "The strongest joint LSTM advantage concentration is snow-dominated MAM high-flow contexts.",
            "artifact": (D06_DEEP_DIVE_REL / "tables" / "top_joint_advantage_contexts.csv").as_posix(),
            "source_files": (D04_DEEP_DIVE_REL / "tables" / "daily_residuals_selected_cases.csv.gz").as_posix(),
            "script_or_command": "python -X utf8 -m src.lstm_fair_531.scripts.joint_advantage_decomposition",
            "status": "reproducible_joint_population_advantage_decomposition",
            "notes": "Post-hoc residual decomposition only; does not claim causal event attribution or LSTM process realism.",
        },
        {
            "claim_id": "C20",
            "paper_element": "Table 7 compact LSTM advantage concentration",
            "claim": "Three headline contexts map context share to positive best-gap share, concentration ratio, and shared failure rate.",
            "artifact": "tables/lstm_advantage_concentration.csv",
            "source_files": "; ".join([
                (D05_DEEP_DIVE_REL / "tables" / "season_regime_advantage_concentration.csv").as_posix(),
                (D05_DEEP_DIVE_REL / "tables" / "flow_regime_advantage_concentration.csv").as_posix(),
                (D06_DEEP_DIVE_REL / "tables" / "joint_regime_advantage_concentration.csv").as_posix(),
            ]),
            "script_or_command": command,
            "status": "reproducible_from_saved_decomposition_artifacts",
            "notes": "This table is a compact manuscript view of D05/D06 values and does not add a new model-selection result.",
        },
        {
            "claim_id": "C21",
            "paper_element": "Complete English manuscript draft",
            "claim": "A complete manuscript integrates the benchmark boundary, central decomposition, population support, joint refinement, limitations, and traceability notes.",
            "artifact": "manuscript_full_draft.md",
            "source_files": (
                "tables/protocol.csv; tables/parameter_accounting.csv; tables/main_benchmark.csv; "
                "tables/paired.csv; tables/conceptual_diagnostics.csv; tables/regime_summary.csv; tables/oracle.csv; "
                "tables/lstm_advantage_concentration.csv; "
                "deep_dive/D01_structure_diagnostic_20260709/tables/primary_static_spearman.csv; "
                "deep_dive/D04_full_population_seasonal_residual_20260709/tables/seasonal_attribute_link_checks.csv; "
                "deep_dive/D04_full_population_seasonal_residual_20260709/tables/flow_attribute_link_checks.csv; "
                "deep_dive/D05_lstm_advantage_decomposition_20260709/tables/season_regime_advantage_concentration.csv; "
                "deep_dive/D05_lstm_advantage_decomposition_20260709/tables/flow_regime_advantage_concentration.csv; "
                "deep_dive/D06_joint_season_flow_advantage_20260709/tables/joint_regime_advantage_concentration.csv; "
                "manuscript_ready_claim_map.md"
            ),
            "script_or_command": command,
            "status": "generated_from_saved_evidence_artifacts",
            "notes": "Neutral journal-style Markdown draft; reference entries remain source notes rather than venue-formatted bibliography entries.",
        },
        {
            "claim_id": "C22",
            "paper_element": "Three-step key-point argument chain",
            "claim": "Three key points compress one contribution into concentration, population support, and joint-context refinement.",
            "artifact": "key_points.md",
            "source_files": (
                "tables/lstm_advantage_concentration.csv; "
                "deep_dive/D01_structure_diagnostic_20260709/tables/primary_static_spearman.csv; "
                "deep_dive/D04_full_population_seasonal_residual_20260709/tables/seasonal_attribute_link_checks.csv; "
                "deep_dive/D04_full_population_seasonal_residual_20260709/tables/flow_attribute_link_checks.csv; "
                "deep_dive/D05_lstm_advantage_decomposition_20260709/tables/season_regime_advantage_concentration.csv; "
                "deep_dive/D05_lstm_advantage_decomposition_20260709/tables/flow_regime_advantage_concentration.csv; "
                "deep_dive/D06_joint_season_flow_advantage_20260709/tables/joint_regime_advantage_concentration.csv"
            ),
            "script_or_command": command,
            "status": "generated_from_saved_evidence_artifacts",
            "notes": "The points are one argument at three compression steps, not separate novelty claims.",
        },
    ]
    ledger = pd.DataFrame(rows)
    ledger.to_csv(out_dir / "provenance_ledger.csv", index=False)
    (out_dir / "provenance_ledger.md").write_text(_to_md_table(ledger) + "\n", encoding="utf-8")
    return ledger


def _write_claims(out_dir: Path, tables: Dict[str, pd.DataFrame]) -> None:
    main = tables["main_benchmark"].set_index("model")
    oracle = tables["oracle"].set_index("quantity")["value"]
    adv = _advantage_numbers(out_dir)
    population = _population_support_numbers(out_dir)
    text = f"""# Manuscript skeleton and claim map

## Working title

Locating Where Long Short-Term Memory Networks Win: Three Conceptual Rainfall-Runoff Models as Structural References Across 531 United States Basins

## One-sentence contribution

Aggregate scores hide how a predictive margin is distributed; three audited conceptual structures locate where the LSTM advantage concentrates across hydrological regime, season, and flow context.

## Abstract skeleton

Aggregate rainfall-runoff performance scores rank models but do not show whether a predictive advantage is diffuse or concentrated in particular hydrological contexts. We quantify that distribution across 531 CAMELS-US basins using GR4J, XAJ, and HBV as structural references to a reproduced eight-seed LSTM ensemble. The LSTM uses regional learning and 27 static basin attributes, so the comparison is diagnostic rather than a same-information prediction contest; the conceptual structures are not predictive competitors. Its median NSE is {main.loc['LSTM_ensemble_8seed', 'median_nse']:.6f}, compared with {main.loc['GR4J', 'median_nse']:.6f} for the strongest single conceptual model, GR4J. Snow-dominated MAM contexts represent {adv['snow_mam_context_share']:.1%} of basin-season rows but {adv['snow_mam_gap_share']:.1%} of the positive gap relative to the lowest-error conceptual model in each row; snow-dominated high-flow contexts represent {adv['snow_high_context_share']:.1%} of basin-flow rows but {adv['snow_high_gap_share']:.1%} of that gap. Across all 531 basins, snow fraction is positively associated with the LSTM margin over the basin-wise conceptual comparator with the highest NSE (rho = {population['basin_snow_rho']:.3f}, q = {population['basin_snow_q']:.2e}). Snow-dominated MAM high flow is the retained joint context with the highest concentration ratio: {adv['snow_mam_high_context_share']:.1%} of joint rows account for {adv['snow_mam_high_gap_share']:.1%} of the positive gap, and all three evaluated conceptual models have higher mean absolute error in {adv['snow_mam_high_shared_failure']:.1%} of those rows. The result is a post-hoc diagnosis of where the known ranking accumulates, not evidence of causal mechanism, process realism, or deployable predictive complementarity.

## Results narrative

Boundary. The LSTM ensemble is the strongest evaluated predictive reference: median NSE {main.loc['LSTM_ensemble_8seed', 'median_nse']:.6f}, compared with GR4J at {main.loc['GR4J', 'median_nse']:.6f}, XAJ at {main.loc['XAJ', 'median_nse']:.6f}, and HBV at {main.loc['HBV', 'median_nse']:.6f}. A four-model oracle reaches median NSE {oracle.loc['four_model_oracle_median_nse']:.6f} with median gain {oracle.loc['four_model_oracle_minus_lstm_median']:.6f} over the LSTM ensemble, so this is not a predictive-complement paper.

1. LSTM advantage is not uniform: snow-dominated MAM contexts account for {adv['snow_mam_context_share']:.1%} of basin-season contexts but {adv['snow_mam_gap_share']:.1%} of the positive gap relative to the lowest-error conceptual model in each row; snow-dominated high-flow contexts account for {adv['snow_high_context_share']:.1%} of basin-flow contexts but {adv['snow_high_gap_share']:.1%} of the positive gap.
2. Across all 531 basins, snow fraction is positively associated with the LSTM margin over the basin-wise conceptual comparator with the highest NSE (rho = {population['basin_snow_rho']:.3f}, q = {population['basin_snow_q']:.2e}), supporting a population-level rather than selected-case pattern.
3. Snow-dominated MAM high flow is the retained joint context with the highest concentration ratio: {adv['snow_mam_high_context_share']:.1%} of basin-season-flow contexts account for {adv['snow_mam_high_gap_share']:.1%} of the positive row-wise gap, with concentration ratio {adv['snow_mam_high_ratio']:.2f}; all three conceptual models have higher MAE in {adv['snow_mam_high_shared_failure']:.3f} of rows.

## Claims that are supported

- The ID10/ID18 package provides a protocol-audited conceptual benchmark relative to a reproduced LSTM reference.
- GR4J is the strongest single conceptual model under the final 5k x 3 PT same-protocol headline.
- The LSTM ensemble is the strongest evaluated predictor in this setup.
- LSTM advantage is concentrated rather than uniform, especially in snow-dominated MAM and high-flow contexts.
- Agreement across GR4J/XAJ/HBV errors can be used to locate the LSTM margin relative to the lowest-error conceptual comparator in each row.
- D06 identifies snow-dominated MAM high-flow as the strongest current joint advantage concentration zone.
- GR4J/XAJ external PDD snow handling is effective-equivalent under the current zero-ice CAMELS-US setup; XAJ should be reported as 20 nominal and 18 effective active parameters.
- The saved conceptual parameter artifacts replay under the current code across all 531 basins; this supports artifact continuity after fairness-related code cleanup.
- D01-D06 deep dives make the diagnostic decomposition concrete: static snow/topography/aridity attributes align with model-structure disagreements, D03/D04 show population residual penalties, and D05/D06 show that a small snow-dominated MAM high-flow context overcontributes to the LSTM advantage.

## Claims that are not supported

- Do not claim a new predictive state of the art.
- Do not claim conceptual models are competitive with the LSTM ensemble overall.
- Do not claim conceptual models complement LSTM prediction deployably.
- Do not claim causal event attribution or LSTM process realism from D05/D06.
- Do not infer XAJ superiority over HBV from their median ordering alone; no equivalence or superiority test was specified.
- Do not claim PET-bug correction is a method gain.
- Do not mix 447-subset Kratzert reproduction numbers with full-531 headline rankings.
- Do not imply strict information equality: the LSTM uses regional learning and static attributes.
- Do not describe HBV as using the same external PDD front end; its snow routine is intrinsic HBV structure.

## Submission readiness

The core benchmark and decomposition claims are auditable from the registered snapshot. Nineteen external evidence inputs are pinned by byte size and SHA-256 digest and packaged in a single content-pinned local external archive. The committed clean checkout rebuilds the package after that archive is extracted. The committed clean checkout has been verified by rebuilding all 14 top-level outputs twice with zero digest differences. Old PET-bug diagnostics are quarantined and must not be reused as manuscript evidence. Submission still requires venue formatting, a finalized bibliography, and publication of the registered external archive.
"""
    (out_dir / "manuscript_skeleton.md").write_text(text, encoding="utf-8")


def _write_claims_limitations(out_dir: Path) -> None:
    text = """# Claims and limitations

## Supported claims

- The package provides a protocol-audited CAMELS-US 531 conceptual benchmark relative to a reproduced LSTM reference.
- GR4J is the strongest conceptual model under the final PT 5k x 3 same-protocol headline.
- The LSTM ensemble is the strongest evaluated predictor in the current setup.
- Conceptual models can be used as structure-reference probes to decompose where the LSTM advantage concentrates.
- D05/D06 show that snow-dominated MAM high flow is the retained joint context with the highest concentration ratio.
- GR4J/XAJ external snow front ends are effective-equivalent under zero initial ice, as tested by `test/test_id10_pdd_fairness.py`.
- XAJ has 20 nominal parameters but 18 effective active parameters in the current zero-ice setup.
- HBV-lite snow handling is intrinsic HBV structure, not the shared external PDD wrapper.
- Saved GR4J/XAJ/HBV parameter artifacts replay under the current code for all 531 basins in both saved-state and warmup-recomputed modes.
- D01 static-attribute diagnostics support a correlational structure-regime claim; D02 selected-case hydrographs provide time-series illustrations of residual patterns; D03/D04 population residual diagnostics show that MAM/high-flow penalties and attribute links persist beyond selected cases; D05/D06 localize the LSTM advantage into season-flow contexts.

## Unsupported claims

- Do not claim a new predictive state of the art.
- Do not claim conceptual models are competitive with the LSTM ensemble overall.
- Do not claim conceptual models provide a deployable predictive complement to LSTM.
- Do not claim D05/D06 prove causal event mechanisms or LSTM process realism.
- Do not infer XAJ superiority over HBV from their median ordering alone; no equivalence or superiority test was specified.
- Do not present the PET-bug correction as a method gain.
- Do not mix 447-subset Kratzert reproduction numbers with full-531 headline rankings.
- Do not imply strict information equality between conceptual models and LSTM; the LSTM uses regional learning and static attributes.
- Do not describe all three conceptual models as sharing one identical snow module.
- Do not compare nominal parameter counts without also reporting effective active parameter counts.

## Boundary conditions

- Full-531 LSTM headline diagnostics remain NSE-based in the main benchmark, while D02-D06 use saved daily LSTM test predictions or generated D04 residual artifacts for post-hoc seasonal/high-flow and advantage-decomposition checks.
- Conceptual diagnostic metrics are valid for comparing GR4J/XAJ/HBV; LSTM residual checks are post-hoc diagnostics, not proof of LSTM process realism.
- GR4J and XAJ external PDD modules are controlled as effective-equivalent; HBV is included as a different conceptual school with an intrinsic degree-day snow routine.
- The stale PET-bug regime diagnostic is quarantined and must not be reused as manuscript evidence.
- Saved-parameter replay is an artifact-validity audit, not a fresh full CMA-ES recalibration.
"""
    (out_dir / "claims_limitations.md").write_text(text, encoding="utf-8")


def _write_fairness_audit_memo(out_dir: Path) -> None:
    pdd_test = PDD_FAIRNESS_TEST.as_posix()
    text = f"""# Structure and calibration fairness audit

## Verdict

Under the documented 531-basin split, forcing, calibration budget, and snow-module distinctions, the package supports comparison of the three conceptual models as structure references. GR4J and XAJ external PDD front ends match on the tested zero-ice input sequences. HBV-lite keeps an intrinsic HBV snow routine; this is a disclosed model-structure difference, not a shared external module. These checks do not establish identical model structures or information channels.

## Structure fairness

- GR4J+PDD uses the shared no-ice PDD reference path with 4 active snow parameters.
- XAJ+PDD keeps the historical 6-parameter full PDD wrapper, but the two ice parameters are inactive because ice storage starts at zero and no process creates ice storage.
- HBV-lite uses internal snow states and parameters (`SNOWPACK`, `MELTWATER`, `parTT`, `parCFMAX`, `parCFR`, `parCWH`). It should be described as an HBV-family structural choice.

## Calibration fairness

- The final conceptual headline uses the same 531-basin repro_v01 split, Maurer forcing, PT PET, warmup-year evaluation initialization, NSE metric, and CMA-ES budget.
- The optimizer policy is aligned: 5000 trials x 3 restarts, seeds `42 + 1000 * restart`, normalized box search, init mean 0.5, sigma 0.3, and best calibration objective retained.
- Bounds and structural constraints remain model-specific and must be disclosed as such.

## Fixed or controlled issues

- Added a shared `pdd_noice_step_mm` reference implementation.
- Added `{pdd_test}` to check GR4J/XAJ external snow front-end agreement on explicit zero-ice sequences and XAJ ice-parameter inactivity on those sequences.
- Added nominal/effective parameter accounting to the evidence package.
- Added the full-531 saved-parameter replay audit (`{REPLAY_AUDIT_REL.as_posix()}`) to verify the final parameter artifacts still reproduce the headline NSE table under the current code.
- Added future-run metadata fields for `parameter_count` and `effective_active_parameter_count` in GR4J/XAJ/HBV conceptual runners.

## Manuscript wording rule

Do not write that all three conceptual models share an identical snow module. The correct wording is: GR4J and XAJ external snow front ends are controlled as effective-equivalent under zero initial ice; HBV snow handling is intrinsic to the HBV-lite model structure.
"""
    (out_dir / "fairness_audit_memo.md").write_text(text, encoding="utf-8")


def _write_manuscript_claim_map(out_dir: Path, tables: Dict[str, pd.DataFrame]) -> None:
    main = tables["main_benchmark"].set_index("model")
    paired = tables["paired"].set_index("comparison")
    oracle = tables["oracle"].set_index("quantity")["value"]
    adv = _advantage_numbers(out_dir)
    rows = [
        {
            "id": "M1",
            "manuscript_claim": "The study provides a protocol-audited three-school conceptual benchmark on CAMELS-US 531.",
            "primary_evidence": "tables/protocol.csv; tables/fairness_audit.csv; provenance_ledger.csv",
            "allowed_wording": "protocol-audited conceptual benchmark",
            "boundary": "Do not claim all model structures or information channels are identical.",
        },
        {
            "id": "M2",
            "manuscript_claim": "The reproduced LSTM ensemble is the strongest evaluated predictor in this setup.",
            "primary_evidence": (
                f"tables/main_benchmark.csv: LSTM ensemble median NSE {main.loc['LSTM_ensemble_8seed', 'median_nse']:.6f}; "
                f"paired median delta vs GR4J {paired.loc['LSTM_ensemble_8seed_vs_GR4J', 'median_diff']:.6f}"
            ),
            "allowed_wording": "LSTM remains the strongest evaluated predictive reference",
            "boundary": "Do not claim a new state of the art; do not imply strict information equality with conceptual models.",
        },
        {
            "id": "M3",
            "manuscript_claim": "GR4J is the strongest conceptual model under the final PT 5k x 3 headline.",
            "primary_evidence": (
                f"tables/main_benchmark.csv: GR4J {main.loc['GR4J', 'median_nse']:.6f}, "
                f"XAJ {main.loc['XAJ', 'median_nse']:.6f}, HBV {main.loc['HBV', 'median_nse']:.6f}"
            ),
            "allowed_wording": "GR4J is strongest overall among the three conceptual models",
            "boundary": (
                "Do not infer XAJ superiority over HBV from their median ordering alone; "
                "no equivalence or superiority test was specified."
            ),
        },
        {
            "id": "M4",
            "manuscript_claim": "Conceptual models retain diagnostic value through flow-signature trade-offs.",
            "primary_evidence": "tables/conceptual_diagnostics.csv; tables/conceptual_winners.csv; figures/fig3_conceptual_diagnostic_tradeoffs.png",
            "allowed_wording": "diagnostic trade-offs across KGE, bias, peak, low-flow, and split-gap metrics",
            "boundary": "Do not infer LSTM process realism or conceptual superiority from these diagnostics.",
        },
        {
            "id": "M5",
            "manuscript_claim": "Regime heterogeneity is visible, especially in snow-dominated basins.",
            "primary_evidence": "tables/regime_summary.csv; figures/fig2_regime_median_nse.png; figures/fig4_lstm_minus_best_conceptual_by_regime.png",
            "allowed_wording": "the three conceptual structure references show different error patterns across regimes while the LSTM remains higher",
            "boundary": "Do not present regime heterogeneity as a general predictive win over the LSTM.",
        },
        {
            "id": "M6",
            "manuscript_claim": "A four-model oracle offers little median gain over the LSTM ensemble.",
            "primary_evidence": (
                f"tables/oracle.csv: four-model oracle median NSE {oracle.loc['four_model_oracle_median_nse']:.6f}; "
                f"median gain over LSTM {oracle.loc['four_model_oracle_minus_lstm_median']:.6f}"
            ),
            "allowed_wording": "the evidence does not support a predictive-complement claim",
            "boundary": "It is acceptable to report 73 conceptual basin wins, but not to oversell them as deployable complementarity.",
        },
        {
            "id": "M7",
            "manuscript_claim": "Snow-module fairness is controlled and disclosed.",
            "primary_evidence": "tables/parameter_accounting.csv; tables/fairness_audit.csv; test/test_id10_pdd_fairness.py",
            "allowed_wording": "GR4J/XAJ external PDD paths are effective-equivalent; HBV snow is intrinsic structure",
            "boundary": "Do not write that all three conceptual models share an identical external snow module.",
        },
        {
            "id": "M8",
            "manuscript_claim": "The final conceptual parameter artifacts remain valid under the current code.",
            "primary_evidence": (REPLAY_AUDIT_REL / "saved_parameter_replay_summary.csv").as_posix(),
            "allowed_wording": "saved parameters replay exactly under the current code in saved-state and warmup-recomputed modes",
            "boundary": "Do not describe this as a fresh full CMA-ES recalibration.",
        },
        {
            "id": "M9",
            "manuscript_claim": "Conceptual-structure disagreement has concrete basin-attribute diagnostic signal.",
            "primary_evidence": (D01_DEEP_DIVE_REL / "tables" / "primary_static_spearman.csv").as_posix(),
            "allowed_wording": "static basin attributes, especially snow/topography/aridity, align with model-structure disagreements",
            "boundary": "Use correlational language; do not claim causal mechanism or model-input fairness from `camels_hydro`.",
        },
        {
            "id": "M10",
            "manuscript_claim": "Selected hydrograph cases illustrate seasonal and high-flow residual patterns associated with the attribute signal.",
            "primary_evidence": (D02_DEEP_DIVE_REL / "tables" / "seasonal_delta_aggregate.csv").as_posix(),
            "allowed_wording": "selected-case residual checks are consistent with the basin-attribute diagnosis",
            "boundary": "Selected cases are diagnostic examples, not population evidence or causal-mechanism tests.",
        },
        {
            "id": "M11",
            "manuscript_claim": "Population residual diagnostics support that the snow/MAM/high-flow signal is not only a selected-case artifact.",
            "primary_evidence": (
                (D03_DEEP_DIVE_REL / "tables" / "seasonal_delta_aggregate.csv").as_posix() + "; " +
                (D04_DEEP_DIVE_REL / "tables" / "seasonal_attribute_link_checks.csv").as_posix()
            ),
            "allowed_wording": "population-wide residual checks strengthen the diagnostic structure-regime interpretation",
            "boundary": "Still post-hoc and correlational; do not claim causal LSTM process realism or predictive complementarity.",
        },
        {
            "id": "M12",
            "manuscript_claim": "The LSTM advantage is concentrated rather than uniform across regime-season and regime-flow contexts.",
            "primary_evidence": (
                "tables/lstm_advantage_concentration.csv; " +
                (D05_DEEP_DIVE_REL / "tables" / "top_advantage_contexts.csv").as_posix() +
                f": snow/MAM {adv['snow_mam_context_share']:.1%} contexts -> {adv['snow_mam_gap_share']:.1%} positive row-wise gap; " +
                f"snow/high {adv['snow_high_context_share']:.1%} contexts -> {adv['snow_high_gap_share']:.1%} positive row-wise gap"
            ),
            "allowed_wording": "conceptual structure references decompose where the LSTM advantage concentrates",
            "boundary": "Do not treat this as an independent model-selection result or causal process proof.",
        },
        {
            "id": "M13",
            "manuscript_claim": "Snow-dominated MAM high flow is the retained joint context with the highest concentration ratio.",
            "primary_evidence": (
                "tables/lstm_advantage_concentration.csv; " +
                (D06_DEEP_DIVE_REL / "tables" / "top_joint_advantage_contexts.csv").as_posix() +
                f": {adv['snow_mam_high_context_share']:.1%} contexts -> {adv['snow_mam_high_gap_share']:.1%} positive row-wise gap; " +
                f"ratio {adv['snow_mam_high_ratio']:.2f}; shared failure {adv['snow_mam_high_shared_failure']:.3f}"
            ),
            "allowed_wording": "snow-dominated MAM high flow has the highest concentration ratio among retained joint contexts",
            "boundary": "Post-hoc residual decomposition only; do not claim rain-on-snow attribution, LSTM process realism, or deployable complementarity.",
        },
    ]
    claim_map = pd.DataFrame(rows)
    text = "# Manuscript-ready claim map\n\n" + _to_md_table(claim_map) + "\n"
    (out_dir / "manuscript_ready_claim_map.md").write_text(text, encoding="utf-8")


def _write_manuscript_sections(out_dir: Path, tables: Dict[str, pd.DataFrame]) -> None:
    main = tables["main_benchmark"].set_index("model")
    paired = tables["paired"].set_index("comparison")
    diag = tables["conceptual_diagnostics"].set_index("model")
    oracle = tables["oracle"].set_index("quantity")["value"]
    regime = tables["regime_summary"].set_index("regime")
    winners = tables["conceptual_winners"]
    adv = _advantage_numbers(out_dir)
    lowflow_xaj = int(winners[(winners["metric"] == "abs_lowflow_bias") & (winners["model"] == "XAJ")]["n_wins"].iloc[0])
    peak_hbv = int(winners[(winners["metric"] == "abs_peak_bias") & (winners["model"] == "HBV")]["n_wins"].iloc[0])
    text = f"""# Manuscript section draft pack

## Methods: benchmark design

We evaluated three conceptual rainfall-runoff model schools, GR4J, XAJ, and HBV-lite, on the CAMELS-US 531-basin benchmark using the repro_v01 reverse split. Conceptual models were calibrated on 1999-10-01 to 2008-09-30 and evaluated on 1989-10-01 to 1999-09-30 with Maurer forcing, Priestley-Taylor PET, and a one-year warmup before the evaluation period. Each conceptual model used the same CMA-ES budget of 5000 function evaluations per restart and three restarts, with the same normalized initial mean, step size, seed schedule, and NSE objective.

## Methods: structure and snow accounting

The benchmark preserves model-school differences while controlling external modules. GR4J+PDD and XAJ+PDD use external degree-day snow front ends whose active no-ice behavior is tested as effective-equivalent under the current zero-ice CAMELS-US setup. XAJ keeps a six-parameter PDD wrapper for historical compatibility, but the two ice parameters are inactive because ice storage starts at zero and no process creates ice storage. We therefore report XAJ as 20 nominal parameters and 18 effective active parameters. HBV-lite, in contrast, contains an intrinsic HBV degree-day snow routine with `SNOWPACK` and `MELTWATER` states; this is treated as part of the HBV model structure rather than as a shared external PDD module.

## Methods: LSTM reference and audit trail

The conceptual benchmark is compared with a reproduced LSTM reference rather than presented as a predictive state-of-the-art challenge. The LSTM uses the same 531 basins, Maurer forcing, and reverse split, but also uses regional learning with static attributes; it is the strongest evaluated predictive reference, not a strict same-information conceptual challenger. We include a seed-100 single model and an eight-seed ensemble. All headline tables and figures are regenerated from saved per-basin artifacts by `python -X utf8 -m src.lstm_fair_531.scripts.build_manuscript_evidence_package`; the snow-front-end equivalence claim is checked by `pytest test/test_id10_pdd_fairness.py -q`.

## Results: predictive boundary

The conceptual-model median NSE values are {main.loc['GR4J', 'median_nse']:.6f} for GR4J, {main.loc['XAJ', 'median_nse']:.6f} for XAJ, and {main.loc['HBV', 'median_nse']:.6f} for HBV-lite. These descriptive medians do not establish superiority or equivalence between XAJ and HBV-lite. The LSTM single model reaches median NSE {main.loc['LSTM_single_s100', 'median_nse']:.6f}, and the eight-seed LSTM ensemble reaches {main.loc['LSTM_ensemble_8seed', 'median_nse']:.6f}. In paired comparison, the LSTM ensemble exceeds GR4J by median NSE {paired.loc['LSTM_ensemble_8seed_vs_GR4J', 'median_diff']:.6f} and wins on {paired.loc['LSTM_ensemble_8seed_vs_GR4J', 'lstm_win_rate']:.3f} of common basins.

## Results: structure-reference diagnostics

Although the LSTM is the strongest evaluated predictor, the conceptual models expose different diagnostic behavior. GR4J has the best overall median NSE and KGE, with median KGE {diag.loc['GR4J', 'median_kge']:.6f} and the smallest median absolute bias ({diag.loc['GR4J', 'median_abs_bias']:.6f}). HBV-lite has the smallest median absolute peak bias ({diag.loc['HBV', 'median_abs_peak_bias']:.6f}) and has the lowest absolute peak bias among the three conceptual models in {peak_hbv} basins. XAJ has the smallest median absolute low-flow bias ({diag.loc['XAJ', 'median_abs_lowflow_bias']:.6f}) and has the lowest absolute low-flow bias among the three in {lowflow_xaj} basins. These trade-offs support the use of conceptual models as diagnostic baselines rather than as competitive predictors against the LSTM ensemble.

## Results: LSTM advantage decomposition

The key diagnostic result is not that the LSTM wins overall, but that its advantage is concentrated. Table 7 maps context share to positive best-gap share, concentration ratio, and shared failure rate. In D05, snow-dominated MAM contexts account for {adv['snow_mam_context_share']:.1%} of basin-season contexts but {adv['snow_mam_gap_share']:.1%} of the positive LSTM-vs-best-conceptual MAE gap. Snow-dominated high-flow contexts account for {adv['snow_high_context_share']:.1%} of basin-flow contexts but {adv['snow_high_gap_share']:.1%} of the positive gap. D06 combines season and flow group using the D04 daily residual archive: snow-dominated MAM high-flow contexts account for {adv['snow_mam_high_context_share']:.1%} of basin-season-flow contexts but {adv['snow_mam_high_gap_share']:.1%} of the positive best-conceptual MAE gap, with concentration ratio {adv['snow_mam_high_ratio']:.2f} and shared failure rate {adv['snow_mam_high_shared_failure']:.3f}. This supports the use of GR4J/XAJ/HBV as structure-reference probes for locating the LSTM advantage, not as predictive complements.

## Results: regime heterogeneity and oracle check

The relative behavior of the three conceptual structures varies by hydrologic regime, while the LSTM remains the strongest predictor. In snow-dominated basins, XAJ and HBV-lite have higher median NSE ({regime.loc['snow-dominated', 'XAJ_median_nse']:.6f} and {regime.loc['snow-dominated', 'HBV_median_nse']:.6f}) than GR4J ({regime.loc['snow-dominated', 'GR4J_median_nse']:.6f}), while the LSTM ensemble remains higher at {regime.loc['snow-dominated', 'LSTM_ensemble_8seed_median_nse']:.6f}. Across all basins, a four-model oracle reaches median NSE {oracle.loc['four_model_oracle_median_nse']:.6f}, with median gain {oracle.loc['four_model_oracle_minus_lstm_median']:.6f} over the LSTM ensemble. This indicates that conceptual models provide useful diagnostic contrasts, but the evidence does not support a predictive-complement claim.

## Limitations

This benchmark should not be read as strict information equality between conceptual models and the LSTM: the LSTM uses regional learning and static attributes, while conceptual models are calibrated per basin. Full-population LSTM headline diagnostics remain NSE-based in the main benchmark, while D02-D06 use saved daily LSTM test predictions or generated residual artifacts as post-hoc diagnostics. D05/D06 localize rows where all three conceptual models have higher error, but do not prove causal event mechanisms or LSTM process realism. HBV-lite's snow routine is intrinsic to the model and should not be described as the same external PDD module used by GR4J and XAJ. Finally, the current paper package is auditable from saved artifacts and tests, but a full recalibration of all conceptual models is computationally more expensive than the manuscript evidence rebuild.
"""
    (out_dir / "manuscript_sections.md").write_text(text, encoding="utf-8")


def _write_key_points(out_dir: Path) -> None:
    advantage = _advantage_numbers(out_dir)
    population = _population_support_numbers(out_dir)
    text = f"""# Key Points

The three points below compress one contribution, not three separate contributions: conceptual structures locate where the long short-term memory network advantage concentrates, while population-level and joint-context analyses provide two supporting evidence layers.

- Three conceptual structural references show that the advantage is concentrated: snow-dominated spring rows represent {advantage['snow_mam_context_share']:.1%} of basin-season contexts but {advantage['snow_mam_gap_share']:.1%} of the positive gap relative to the lowest-error conceptual model in each row, while snow-dominated high-flow rows represent {advantage['snow_high_context_share']:.1%} of basin-flow contexts but {advantage['snow_high_gap_share']:.1%} of that gap.
- Across 531 basins, snow fraction is positively associated with the long short-term memory network margin over the basin-wise conceptual comparator with the highest Nash-Sutcliffe efficiency (rho = {population['basin_snow_rho']:.3f}, q = {population['basin_snow_q']:.2e}), supporting a population-level rather than selected-case pattern.
- Snow-dominated spring high flow is the retained joint context with the highest concentration ratio: {advantage['snow_mam_high_context_share']:.1%} of rows account for {advantage['snow_mam_high_gap_share']:.1%} of the positive gap, and all three evaluated conceptual models had higher mean absolute error than the LSTM in {advantage['snow_mam_high_shared_failure']:.1%} of rows.

## Traceability

| Point | Role in the single argument | Manuscript location | Direct evidence | Boundary |
| --- | --- | --- | --- | --- |
| 1 | Central contribution: locate concentration | Section 3.3 | `tables/lstm_advantage_concentration.csv`; `deep_dive/D05_lstm_advantage_decomposition_20260709/tables/season_regime_advantage_concentration.csv`; `deep_dive/D05_lstm_advantage_decomposition_20260709/tables/flow_regime_advantage_concentration.csv` | Descriptive evaluation-period decomposition, not a new predictive method. |
| 2 | First evidence layer: population-level support | Section 3.4 | `deep_dive/D01_structure_diagnostic_20260709/tables/primary_static_spearman.csv`; `deep_dive/D04_full_population_seasonal_residual_20260709/tables/seasonal_attribute_link_checks.csv`; `deep_dive/D04_full_population_seasonal_residual_20260709/tables/flow_attribute_link_checks.csv` | Association does not establish a snow-process mechanism. |
| 3 | Second evidence layer: joint context refinement | Section 3.5 | `tables/lstm_advantage_concentration.csv`; `deep_dive/D06_joint_season_flow_advantage_20260709/tables/joint_regime_advantage_concentration.csv` | Post-hoc joint context, not event attribution or process realism. |
"""
    (out_dir / "key_points.md").write_text(text, encoding="utf-8")


def _write_full_manuscript(out_dir: Path, tables: Dict[str, pd.DataFrame]) -> None:
    main = tables["main_benchmark"].set_index("model")
    paired = tables["paired"].set_index("comparison")
    oracle = tables["oracle"].set_index("quantity")["value"]
    diagnostic = tables["conceptual_diagnostics"].set_index("model")
    regime = tables["regime_summary"].set_index("regime")
    advantage = _advantage_numbers(out_dir)
    population = _population_support_numbers(out_dir)
    text = f"""# Locating Where Long Short-Term Memory Networks Win: Three Conceptual Rainfall-Runoff Models as Structural References Across 531 United States Basins

## Abstract

Aggregate rainfall-runoff performance scores rank models but do not show whether a predictive advantage is diffuse or concentrated in particular hydrological contexts. We quantify that distribution across 531 basins from the Catchment Attributes and Meteorology for Large-sample Studies data set for the contiguous United States (CAMELS-US), using three conceptual rainfall-runoff structures—GR4J, the Xinanjiang model, and an HBV-lite implementation—as references to a reproduced eight-seed long short-term memory (LSTM) network ensemble. Because the ensemble uses regional learning and 27 static basin attributes while the conceptual models are calibrated per basin, this is a diagnostic comparison rather than a strict same-information contest. The ensemble reached a median Nash-Sutcliffe efficiency (NSE) of {main.loc['LSTM_ensemble_8seed', 'median_nse']:.6f}, compared with {main.loc['GR4J', 'median_nse']:.6f} for the strongest single conceptual model, GR4J. We decomposed the positive gap between the LSTM and the conceptual model with the lowest mean absolute error in each basin-context row across hydrological regime, season, and flow group. Snow-dominated spring contexts represented {advantage['snow_mam_context_share']:.1%} of basin-season contexts but {advantage['snow_mam_gap_share']:.1%} of the positive gap, while snow-dominated high-flow contexts represented {advantage['snow_high_context_share']:.1%} of basin-flow contexts but {advantage['snow_high_gap_share']:.1%} of that gap. Across all 531 basins, snow fraction was positively associated with the LSTM margin over the basin-wise conceptual comparator with the highest NSE (rho = {population['basin_snow_rho']:.3f}, q = {population['basin_snow_q']:.2e}). The retained joint context with the highest concentration ratio was snow-dominated spring high flow: {advantage['snow_mam_high_context_share']:.1%} of joint rows accounted for {advantage['snow_mam_high_gap_share']:.1%} of the positive gap, with a concentration ratio of {advantage['snow_mam_high_ratio']:.2f}; all three conceptual models had higher mean absolute error than the LSTM in {advantage['snow_mam_high_shared_failure']:.1%} of those rows. Thus, three distinct conceptual structures convert a known overall ranking into a bounded diagnosis of where the predictive margin accumulates. The analysis remains post-hoc and associational; it does not identify causal event mechanisms or establish that the LSTM represents physical processes faithfully.

<!-- Abstract evidence: tables/main_benchmark.csv; tables/lstm_advantage_concentration.csv; deep_dive/D01_structure_diagnostic_20260709/tables/primary_static_spearman.csv; deep_dive/D04_full_population_seasonal_residual_20260709/tables/seasonal_attribute_link_checks.csv; deep_dive/D04_full_population_seasonal_residual_20260709/tables/flow_attribute_link_checks.csv; deep_dive/D05_lstm_advantage_decomposition_20260709/tables/season_regime_advantage_concentration.csv; deep_dive/D05_lstm_advantage_decomposition_20260709/tables/flow_regime_advantage_concentration.csv; deep_dive/D06_joint_season_flow_advantage_20260709/tables/joint_regime_advantage_concentration.csv -->

**Keywords:** large-sample hydrology; rainfall-runoff modelling; long short-term memory network; conceptual model; diagnostic benchmark; error decomposition; snow-dominated basins

## 1. Introduction

Aggregate performance summaries are necessary for ranking rainfall-runoff models across heterogeneous basins, but they collapse the distribution of predictive differences into a small set of scores. A higher overall score does not reveal whether the margin is broadly distributed or disproportionately associated with particular basin regimes, seasons, or flow conditions. Distinguishing these possibilities is the scientific problem addressed here: it identifies the hydrological contexts that account for a known predictive gap without treating the gap itself as the novelty.

The CAMELS-US data set provides hydroclimatic forcing, streamflow records, and basin attributes for comparative analyses across a geographically diverse basin population (Addor et al. (2017)). Regional long short-term memory networks can learn shared relationships across basins while conditioning predictions on static attributes, and Kratzert et al. (2019) showed that this strategy can outperform established hydrological benchmarks across 531 CAMELS-US basins. Direct comparisons with conceptual benchmarks have also documented spatial and seasonal heterogeneity associated with snow and aridity (Lees et al. (2021)). Event-oriented work has further developed diagnostics that separate error dimensions across hydrological event types (Wang et al. (2026)). Overall predictive dominance, spatial heterogeneity, and event diagnostics are therefore established starting points rather than sufficient contributions for the present study.

Conceptual rainfall-runoff models remain useful for this narrower problem because their computations are constrained by explicit storage and flux arrangements. Knoben et al. (2019) provided a standardized modular framework for comparing conceptual structures and examining structural uncertainty. For the present diagnostic question, however, one conceptual benchmark would not distinguish a weakness specific to one formulation from an error pattern shared by several structures. We therefore use GR4J, Xinanjiang, and HBV-lite together as structural references: agreement among their errors identifies contexts in which all three fall behind the LSTM, while disagreement preserves information about structure-specific behaviour. They are not proposed as replacements, ensemble members, or deployable corrections for the LSTM.

The study makes one central contribution and uses two evidence layers to support it. The central contribution is a diagnostic decomposition of the positive mean absolute error difference between the LSTM and the conceptual comparator with the lowest mean absolute error in each basin-context row across hydrological regime, season, and flow group. The first evidence layer is population-level support: basin-wide attribute and residual analyses assess whether the snow, spring, and high-flow signal extends beyond selected examples. The second is joint context refinement: season and flow group are combined to identify the retained context with the highest concentration ratio. These layers are not separate methodological innovations; they test and sharpen the same claim that the known predictive advantage is hydrologically concentrated.

Three boundaries follow from this framing. First, the LSTM uses regional training and static attributes, whereas each conceptual model is calibrated per basin, so the study does not claim strict information equality. Second, the decomposition uses saved evaluation-period predictions after model development; it is a diagnostic analysis rather than an independently selected predictive model. Third, observed associations with snow fraction and season do not determine event type or causal mechanism. The aim is to locate an empirical error concentration, not to infer rain-on-snow events, snowmelt causality, or internal LSTM process realism.

## 2. Methods

### 2.1 Basin sample, forcing, and temporal split

The analysis used the same 531 CAMELS-US basins for all headline model summaries. Meteorological inputs were taken from the Maurer forcing product. Conceptual-model calibration and LSTM training used 1 October 1999 through 30 September 2008, and evaluation used 1 October 1989 through 30 September 1999. The conceptual simulations used a one-year warm-up before the evaluation period. This reverse temporal split matches the benchmark configuration recorded in `tables/protocol.csv` and preserves a common forcing product, basin population, and evaluation interval across the headline comparison.

Observed discharge was used as the prediction target and for evaluation, not as an input channel. The main score was basin-wise Nash-Sutcliffe efficiency, summarized by the median and mean across 531 basins. NSE is sensitive to squared errors and high flows, so the context decomposition additionally used mean absolute error (MAE) calculated from saved daily predictions. The MAE decomposition avoids relying on unstable low-flow NSE values when samples within a context are small.

### 2.2 Conceptual structural references

GR4J, Xinanjiang, and HBV-lite represent three different conceptual rainfall-runoff model families. GR4J combines four rainfall-runoff parameters with an external positive degree-day snow front end. Xinanjiang uses its characteristic tension-water and runoff-generation structure with an external degree-day snow front end. HBV-lite includes an intrinsic degree-day snow routine and internal snow states as part of its model structure. The three models therefore do not share an identical snow module, and that difference is retained as a structural feature rather than hidden by the comparison.

The conceptual models were calibrated separately for each basin with the Covariance Matrix Adaptation Evolution Strategy. Each restart used 5,000 objective evaluations, and three restarts were performed with an aligned normalized initialization and seed schedule. The calibration objective was NSE. Parameter accounting distinguished nominal parameters from parameters that were active in the evaluated zero-ice configuration. GR4J plus its snow front end had 8 nominal and 8 effective active parameters. Xinanjiang plus its historical six-parameter snow wrapper had 20 nominal parameters, but 18 were active because the two ice parameters did not affect the tested zero-ice path. HBV-lite had 13 intrinsic parameters. The finite zero-ice sequence tests support agreement of the GR4J and Xinanjiang external snow paths under the tested conditions; they do not establish universal structural identity.

The fixed model equations, state updates, and numerical implementations are traceable to `src/xaj_global_pilot/gr4j_core.py`, `src/xaj_global_pilot/xaj_model.py`, and `src/scl_hydro/hbv_lite_numpy.py`. Calibration bounds and their named presets are recorded in `src/xaj_global_pilot/bounds_presets.py`; the exact parameter counts and common protocol used here are exported in `tables/parameter_accounting.csv` and `tables/protocol.csv`. These references define the evaluated implementations and bounds without implying that they exhaust other valid formulations of the three model families.

### 2.3 LSTM reference and comparison boundary

The neural reference consisted of a single seed-100 model and an ensemble of eight LSTM models trained with seeds 100 through 800 for 30 epochs. The regional LSTM used five daily dynamic inputs—precipitation, minimum temperature, maximum temperature, short-wave radiation, and vapour pressure—from the Maurer product, together with 27 static basin attributes. Every run used a sequence length of 270 days, 256 hidden units, a batch size of 256, output dropout of 0.4, the Adam optimizer, and Nash-Sutcliffe-efficiency loss. The learning rate was 0.001 initially, 0.0005 from epoch 11, and 0.0001 from epoch 21. The fixed settings and complete attribute list are recorded in `results/18_lstm_fair_531/lstm_cudalstm_maurer_s100_2026_0616_1513_ep30/config.yml`, with the corresponding seed-specific configurations stored beside the other seven runs; the network implementation is `neuralhydrology/modelzoo/cudalstm.py`.

For each basin and date, ensemble discharge was the arithmetic mean of the eight daily predictions. The LSTM shared the headline basin set, forcing product, training interval, and evaluation interval with the conceptual comparison, but its regional learning and static inputs provide predictive information that per-basin conceptual calibration does not use in the same form.

For that reason, the LSTM is treated as the strongest evaluated predictive reference. The experiment asks how three conceptual structures behave relative to that reference, not which model wins under identical information. The overall LSTM ranking establishes the boundary of the analysis. It is neither claimed as a new state of the art nor counted as the paper's central contribution.

### 2.4 Headline performance and paired comparisons

For each model, basin-wise NSE values were collected in `tables/main_benchmark.csv`. The strongest single conceptual model means the fixed model family with the highest median basin-wise NSE; under this protocol, that model was GR4J. For basin-level margin analyses, the basin-wise conceptual comparator with the highest Nash-Sutcliffe efficiency was selected separately within each basin. Paired LSTM-versus-conceptual differences were taken from `tables/paired.csv`, which records the number of common basins, median paired difference, LSTM win rate, Wilcoxon signed-rank probability, and bootstrap confidence interval. A four-model oracle was also calculated by selecting, separately for each basin, the highest NSE among the LSTM ensemble and the three conceptual models. The oracle was used only as a diagnostic upper bound. It was not used to select or tune a deployable hybrid.

### 2.5 Advantage concentration metrics

The diagnostic analysis was performed on basin-context rows. A context was defined at three levels: hydrological regime by season, hydrological regime by flow group, and hydrological regime by season and flow group jointly. The saved regime labels followed fixed benchmark rules. A basin was snow-dominated when its snow fraction was at least 0.20, or when its coldest-quarter temperature was below 0 degrees Celsius and its cold-season precipitation fraction was at least 0.20. Among the remaining basins, humid meant an aridity index below 1.0, semi-humid meant an aridity index from 1.0 to below 1.5, and semi-arid/arid meant an aridity index of at least 1.5. The thresholds and classification code are recorded in `src/xaj_global_pilot/config.py` and `src/xaj_global_pilot/archive_legacy/classification.py`.

Spring was defined as March through May and is denoted MAM in the saved result tables. Daily flows were divided separately for each basin using the 10th and 90th percentiles of that basin's observed evaluation-period discharge: low flow was at or below the 10th percentile, high flow was at or above the 90th percentile, and middle flow lay between them. Each basin-model joint season-flow context was retained only when it contained at least 10 valid days. These definitions are implemented in `src/lstm_fair_531/scripts/seasonal_residual_deep_dive.py` and `src/lstm_fair_531/scripts/joint_advantage_decomposition.py`.

For each basin-context row, the conceptual comparator with the lowest mean absolute error in each row was selected from GR4J, Xinanjiang, and HBV-lite. The row-wise gap was this minimum conceptual MAE minus LSTM MAE. A positive value therefore indicates that even the lowest-error conceptual model was worse than the LSTM. Four quantities summarize each grouped context. `context_share` is the fraction of all valid basin-context rows belonging to the group. `positive_best_gap_share` is the group's share of the sum of positive row-wise gaps. `concentration_ratio` divides positive-gap share by context share; values greater than one indicate disproportionate contribution to the positive LSTM advantage. `shared_failure_rate` is the fraction of rows in which all three conceptual models had higher MAE than the LSTM. Share denominators were calculated separately within each context family—regime-season, regime-flow, and regime-season-flow—and were never pooled across those families.

These metrics describe concentration within saved evaluation-period predictions. They do not constitute an additional model, a validation-selected decision rule, or an event attribution procedure. Missing context metrics were excluded according to the decomposition scripts, while MAE contexts were retained when context-specific NSE was unavailable.

### 2.6 Population-level support and joint context refinement

The population-level support analysis linked basin-wide and context-specific residual targets to static basin attributes. The primary snow variable was the long-term snow fraction recorded in the static CAMELS-US attribute panel. Spearman rank correlations were used because the relationships need not be linear. Multiple comparisons were summarized with Benjamini-Hochberg false-discovery-rate-adjusted q values. The basin-wide table formed one correction family over all reported target-attribute pairs. The seasonal and flow analyses each formed a separate correction family over all context-target-attribute rows in its generated table. Primary claims use static attributes; streamflow-derived hydrological signatures were treated as supplemental diagnostics and were not used as inputs to a challenger model.

Selected hydrographs were retained only as time-series illustrations. The population analysis used all 531 basins with available conceptual and LSTM scores. The joint context refinement then combined regime, season, and flow group using the saved full-population daily residual archive. This sequence separates illustration, population support, and joint localization without treating any layer as causal evidence.

### 2.7 Audit trail and reproducibility classification

All headline tables, compact context summaries, claim maps, and manuscript drafts are generated by `python -X utf8 -m src.lstm_fair_531.scripts.build_manuscript_evidence_package`. The evidence ledger maps each manuscript element to saved source artifacts and a regeneration command. Saved-parameter replay checks confirm continuity of the conceptual outputs under the current code without being described as a new calibration.

The registered snapshot is rebuildable from a committed clean checkout, 19 external evidence inputs pinned by byte size and SHA-256 digest and packaged in a single content-pinned local external archive, and one build command. The committed clean checkout has been verified by rebuilding all 14 top-level outputs twice with zero digest differences. A zero count of stale-reference blockers means only that known obsolete result references are quarantined or historical; it does not certify submission readiness.

## 3. Results

### 3.1 Predictive boundary

The eight-seed LSTM ensemble was the strongest predictor in the headline comparison (Table 1). Its median NSE was {main.loc['LSTM_ensemble_8seed', 'median_nse']:.6f}, compared with {main.loc['GR4J', 'median_nse']:.6f} for GR4J, {main.loc['XAJ', 'median_nse']:.6f} for Xinanjiang, and {main.loc['HBV', 'median_nse']:.6f} for HBV-lite. The single LSTM model reached {main.loc['LSTM_single_s100', 'median_nse']:.6f}. Relative to GR4J, the ensemble median paired difference was {paired.loc['LSTM_ensemble_8seed_vs_GR4J', 'median_diff']:.6f}, and the LSTM had higher NSE in {paired.loc['LSTM_ensemble_8seed_vs_GR4J', 'lstm_win_rate']:.1%} of the 531 common basins. The corresponding win rates against Xinanjiang and HBV-lite were {paired.loc['LSTM_ensemble_8seed_vs_XAJ', 'lstm_win_rate']:.1%} and {paired.loc['LSTM_ensemble_8seed_vs_HBV', 'lstm_win_rate']:.1%}.

**Table 1. Headline basin-wise NSE summary.**

| Model | Basins | Median NSE | Mean NSE |
| --- | ---: | ---: | ---: |
| GR4J | 531 | {main.loc['GR4J', 'median_nse']:.6f} | {main.loc['GR4J', 'mean_nse']:.6f} |
| Xinanjiang | 531 | {main.loc['XAJ', 'median_nse']:.6f} | {main.loc['XAJ', 'mean_nse']:.6f} |
| HBV-lite | 531 | {main.loc['HBV', 'median_nse']:.6f} | {main.loc['HBV', 'mean_nse']:.6f} |
| LSTM, seed 100 | 531 | {main.loc['LSTM_single_s100', 'median_nse']:.6f} | {main.loc['LSTM_single_s100', 'mean_nse']:.6f} |
| LSTM, eight-seed ensemble | 531 | {main.loc['LSTM_ensemble_8seed', 'median_nse']:.6f} | {main.loc['LSTM_ensemble_8seed', 'mean_nse']:.6f} |

The ranking fixes the interpretation used below: GR4J, Xinanjiang, and HBV-lite are not predictive competitors to the ensemble in this experiment. Their subsequent role is to supply explicit structural contrasts through which the distribution of the LSTM advantage can be examined.

<!-- Evidence: tables/main_benchmark.csv; tables/paired.csv -->

### 3.2 Structural contrasts below the LSTM reference

The conceptual models differed in their error signatures even though all three remained below the LSTM in overall NSE. GR4J had the highest conceptual median NSE and a median Kling-Gupta efficiency of {diagnostic.loc['GR4J', 'median_kge']:.6f}. Its median absolute bias was {diagnostic.loc['GR4J', 'median_abs_bias']:.6f}. HBV-lite had the smallest median absolute peak bias, {diagnostic.loc['HBV', 'median_abs_peak_bias']:.6f}, whereas Xinanjiang had the smallest median absolute low-flow bias, {diagnostic.loc['XAJ', 'median_abs_lowflow_bias']:.6f}. These contrasts show that the three structures emphasize different error modes; they do not reverse the headline predictive ranking.

Regime summaries also changed the ordering within the conceptual group. In snow-dominated basins, Xinanjiang and HBV-lite reached median NSE values of {regime.loc['snow-dominated', 'XAJ_median_nse']:.6f} and {regime.loc['snow-dominated', 'HBV_median_nse']:.6f}, respectively, compared with {regime.loc['snow-dominated', 'GR4J_median_nse']:.6f} for GR4J. The LSTM ensemble remained higher at {regime.loc['snow-dominated', 'LSTM_ensemble_8seed_median_nse']:.6f}. The regime result motivates using multiple conceptual references rather than interpreting a single conceptual model as representative of all explicit hydrological structures.

<!-- Evidence: tables/conceptual_diagnostics.csv; tables/conceptual_winners.csv; tables/regime_summary.csv -->

### 3.3 Concentration of the LSTM advantage

The positive LSTM advantage was not distributed in proportion to context frequency (Table 7). Snow-dominated spring contexts had a context share of {advantage['snow_mam_context_share']:.6f} but accounted for {advantage['snow_mam_gap_share']:.6f} of the total positive row-wise gap. Their concentration ratio was {advantage['snow_mam_ratio']:.6f}, and all three conceptual references had higher MAE than the LSTM in {advantage['snow_mam_shared_failure']:.6f} of those rows.

The concentration was stronger for snow-dominated high-flow contexts. They represented {advantage['snow_high_context_share']:.6f} of basin-flow rows but accounted for {advantage['snow_high_gap_share']:.6f} of the positive row-wise gap, for a concentration ratio of {advantage['snow_high_ratio']:.6f}. Their shared failure rate was {advantage['snow_high_shared_failure']:.6f}. Thus, a context covering less than one tenth of basin-flow rows contributed more than one third of the accumulated positive LSTM advantage relative to the lowest-mean-absolute-error conceptual comparator in each row.

**Table 7. Concentration of the positive LSTM advantage in three headline contexts.**

| Context | Context share | Positive row-wise gap share | Concentration ratio | Shared failure rate |
| --- | ---: | ---: | ---: | ---: |
| Snow-dominated / spring | {advantage['snow_mam_context_share']:.6f} | {advantage['snow_mam_gap_share']:.6f} | {advantage['snow_mam_ratio']:.6f} | {advantage['snow_mam_shared_failure']:.6f} |
| Snow-dominated / high flow | {advantage['snow_high_context_share']:.6f} | {advantage['snow_high_gap_share']:.6f} | {advantage['snow_high_ratio']:.6f} | {advantage['snow_high_shared_failure']:.6f} |
| Snow-dominated / spring / high flow | {advantage['snow_mam_high_context_share']:.6f} | {advantage['snow_mam_high_gap_share']:.6f} | {advantage['snow_mam_high_ratio']:.6f} | {advantage['snow_mam_high_shared_failure']:.6f} |

Table numbering follows the complete evidence package: Tables 2 through 6 contain the paired comparison, conceptual diagnostics, regime summary, parameter accounting, and fairness audit and are supplied as separately generated supporting tables. Table 7 is a compact view of the saved season, flow-group, and joint decomposition tables. It does not introduce a separate selection result. Its purpose is to show context prevalence, contribution to the positive gap, concentration, and agreement among the three conceptual failures side by side; each share is interpreted only within its context family.

<!-- Evidence: tables/lstm_advantage_concentration.csv; deep_dive/D05_lstm_advantage_decomposition_20260709/tables/season_regime_advantage_concentration.csv; deep_dive/D05_lstm_advantage_decomposition_20260709/tables/flow_regime_advantage_concentration.csv; deep_dive/D06_joint_season_flow_advantage_20260709/tables/joint_regime_advantage_concentration.csv -->

### 3.4 Population-level support

The concentration signal was also visible in basin-wide attribute relationships. Across all 531 basins, snow fraction was positively associated with the LSTM margin over the basin-wise conceptual comparator with the highest NSE (Spearman rho = {population['basin_snow_rho']:.3f}, q = {population['basin_snow_q']:.2e}). The result indicates that larger LSTM margins tended to occur in basins with a larger long-term snow fraction. It does not state that snow fraction alone determines model performance.

Context-specific residual relationships pointed in the same direction. For spring, the row-wise lowest-conceptual-MAE-minus-LSTM gap was positively associated with snow fraction (rho = {population['mam_snow_rho']:.3f}, q = {population['mam_snow_q']:.2e}). For high-flow rows, the corresponding association was rho = {population['high_snow_rho']:.3f}, q = {population['high_snow_q']:.2e}. This population-level support reduces reliance on selected hydrographs: the direction of the snow signal appears across the full basin panel and in both spring and high-flow residual summaries.

<!-- Evidence: deep_dive/D01_structure_diagnostic_20260709/tables/primary_static_spearman.csv; deep_dive/D04_full_population_seasonal_residual_20260709/tables/seasonal_attribute_link_checks.csv; deep_dive/D04_full_population_seasonal_residual_20260709/tables/flow_attribute_link_checks.csv -->

### 3.5 Joint context refinement

Combining regime, season, and flow group identified snow-dominated spring high flow as the retained joint context with the highest concentration ratio. This group had a context share of {advantage['snow_mam_high_context_share']:.6f} and a positive row-wise gap share of {advantage['snow_mam_high_gap_share']:.6f}. The concentration ratio was {advantage['snow_mam_high_ratio']:.6f}, and the shared failure rate was {advantage['snow_mam_high_shared_failure']:.6f}. In counts, all three conceptual models had higher MAE than the LSTM in {advantage['snow_mam_high_shared_failure_count']} of {advantage['snow_mam_high_n_contexts']} valid rows.

This joint context refinement sharpens the empirical location of the advantage without assigning an event mechanism. The group is defined by basin regime, calendar season, and flow quantile, not by observed labels for snowmelt, rainfall-on-snow, or other event types. The result is therefore a localized shared-failure pattern among the three evaluated conceptual models.

<!-- Evidence: deep_dive/D06_joint_season_flow_advantage_20260709/tables/joint_regime_advantage_concentration.csv; deep_dive/D06_joint_season_flow_advantage_20260709/tables/top_joint_advantage_contexts.csv -->

### 3.6 Oracle diagnostic

The four-model oracle reached a median NSE of {oracle.loc['four_model_oracle_median_nse']:.6f}, compared with {oracle.loc['lstm_ensemble_median_nse']:.6f} for the LSTM ensemble. The median oracle gain over the LSTM was {oracle.loc['four_model_oracle_minus_lstm_median']:.6f}. A conceptual model had the highest basin-wise NSE in 73 basins, but the median oracle result provides no evidence for a general deployable predictive complement. The oracle is descriptive because it uses evaluation-period outcomes to select the best model separately for each basin.

<!-- Evidence: tables/oracle.csv -->

## 4. Discussion

### 4.1 One contribution with two evidence layers

Sections 3.3 through 3.5 form one argument at increasing resolution. The concentration analysis first shows that snow-dominated spring and high-flow contexts contribute more to the positive row-wise gap than their prevalence would imply. The population analysis then shows that the snow-linked margin extends across the basin sample rather than depending on selected hydrographs. Finally, the joint analysis localizes the retained combination of regime, season, and flow group with the highest concentration ratio.

These steps support one diagnostic contribution: several audited conceptual structures quantify where the established LSTM advantage accumulates. Selecting the lowest-mean-absolute-error conceptual comparator in each row prevents one weak structure from defining the comparison, while shared failure measures agreement across all three references. Population-level support and joint context refinement strengthen that claim without becoming separate predictive methods or changing the test-period ranking.

### 4.2 Interpretation of the snow-linked concentration

The observed concentration is an empirical agreement pattern: in snow-dominated spring high-flow rows, all three evaluated conceptual structures usually had larger MAE than the regional LSTM. Their rainfall-runoff structures differ; GR4J and Xinanjiang share the tested external snow path, whereas HBV-lite uses an intrinsic snow routine. Their shared failure rate exceeds 0.91 in the retained joint context with the highest concentration ratio. This convergence is informative because it is less dependent on the idiosyncrasy of one conceptual formulation, but the analysis does not identify which storage, timing, or event process produced the errors.

At the same time, the analysis cannot determine why the LSTM is better in these rows. Regional learning may exploit cross-basin information, static attributes may condition responses, and the flexible recurrent representation may accommodate temporal dependencies that are constrained in the conceptual models. The present evidence does not separate these explanations. The phrase “snow-linked concentration” therefore denotes an empirical association with basin snow fraction, spring, and high flow; it is not a causal attribution to a particular snow process.

### 4.3 What conceptual references add after predictive dominance

The conceptual models add a coordinate system for error analysis. A single aggregate LSTM score states that the neural model performs better overall, but it does not show whether that margin is spread across ordinary conditions or concentrated in a small set of hydrological contexts. Multiple conceptual structures make it possible to distinguish a structure-specific weakness from a shared pattern. The concentration ratio then compares the frequency of a context with its contribution to the accumulated positive gap.

This diagnostic use does not imply that conceptual models should be attached to the LSTM in deployment. The oracle median gain is zero, and the current analysis contains no validation-selected switching or blending rule. Nor does it imply that the three models span all plausible conceptual structures. The claim is limited to GR4J, Xinanjiang, and HBV-lite under the audited protocol.

### 4.4 Implications for benchmark design

Large-sample model comparisons can separate predictive ranking from diagnostic interpretation. The predictive ranking should be reported plainly and with information differences disclosed. Diagnostic analyses can then ask where errors concentrate, provided that context definitions and post-hoc status are explicit. This separation avoids two common overstatements: treating a lower-performing conceptual model as a competitive predictor, and treating an error association as evidence that a neural network has learned a physically correct process.

The compact concentration table also offers a reusable reporting pattern. A context should not be emphasized only because it has a large average gap; its prevalence and its share of the total positive gap should be shown together. Shared failure adds information about whether the conclusion depends on one conceptual structure. These quantities can be applied to other saved prediction sets, but their scientific interpretation remains specific to the models, data, split, and context definitions used.

### 4.5 Relation to prior work

The result complements, rather than replaces, earlier findings. Kratzert et al. (2019) established strong regional LSTM performance and the value of basin attributes. Lees et al. (2021) documented spatial and seasonal performance patterns in neural-versus-conceptual comparisons. Knoben et al. (2019) emphasized objective comparison across conceptual structures. The present analysis combines these directions in a narrow diagnostic benchmark: three model families are audited under one conceptual protocol, placed below a reproduced LSTM reference, and used to quantify the concentration of the neural advantage. Because related work already covers generic structure comparison and seasonal analysis, the contribution is the integrated, quantitatively traced decomposition rather than the individual ingredients.

## 5. Limitations

The most important limitation is information asymmetry. The LSTM uses regional training and 27 static basin attributes, while the conceptual models are calibrated individually. Sharing basins, forcing, dates, and observed targets does not make the predictive information identical. Accordingly, the paper describes an LSTM reference and conceptual structural probes, not a strict same-information competition.

The decomposition is post-hoc and associational. It uses saved evaluation-period predictions and cannot be interpreted as independent model selection. Contexts are defined by broad regime, season, and flow groups. No event labels identify snowmelt, rainfall-on-snow, frozen-soil effects, or reservoir operations. The snow fraction correlations support population-level alignment but do not establish causal pathways or internal neural representations.

The conceptual sample includes three model families, not the full space of hydrological structures. Shared failure means agreement among GR4J, Xinanjiang, and HBV-lite under this protocol. It is not a theoretical ceiling for conceptual hydrology. Model-specific bounds, numerical implementations, and snow routines remain part of the comparison even though calibration budgets and external conditions were audited.

The daily LSTM residual archive is available for post-hoc analysis, whereas the main headline table remains NSE-based. Selected hydrographs have illustrative value only. The full-population residual analyses reduce but do not remove dependence on the chosen context definitions and error metric. Alternative flow thresholds, seasons, or absolute-error transformations could redistribute the concentration.

Finally, the evidence package is auditable and rebuildable as a registered snapshot. Its 19 external evidence inputs are pinned by byte size and SHA-256 digest and packaged in a single content-pinned local external archive. Extracting that archive into the committed clean checkout reproduces the 14 top-level files. The committed clean checkout has been verified by rebuilding those files twice with zero digest differences. A full conceptual recalibration would be a higher-cost reproduction step, but it is not required for the narrow diagnostic interpretation reported here.

## 6. Conclusions

An aggregate ranking does not reveal how a predictive margin is distributed across hydrological contexts. Across 531 CAMELS-US basins, the reproduced eight-seed LSTM ensemble achieved a median NSE of {main.loc['LSTM_ensemble_8seed', 'median_nse']:.6f}, compared with {main.loc['GR4J', 'median_nse']:.6f} for the strongest single conceptual model, GR4J. That ranking defines the study boundary rather than its novelty.

The diagnostic decomposition showed that the advantage was disproportionately concentrated in snow-dominated spring and high-flow contexts. Snow-dominated spring rows represented {advantage['snow_mam_context_share']:.1%} of basin-season contexts but {advantage['snow_mam_gap_share']:.1%} of the positive gap relative to the lowest-error conceptual model in each row; snow-dominated high-flow rows represented {advantage['snow_high_context_share']:.1%} of basin-flow contexts but {advantage['snow_high_gap_share']:.1%} of that gap. Population-level analysis supported the same direction: across 531 basins, snow fraction was associated with a wider LSTM margin over the basin-wise conceptual comparator with the highest NSE (rho = {population['basin_snow_rho']:.3f}, q = {population['basin_snow_q']:.2e}).

Joint context refinement identified snow-dominated spring high flow as the retained joint context with the highest concentration ratio. It represented {advantage['snow_mam_high_context_share']:.1%} of joint rows and accounted for {advantage['snow_mam_high_gap_share']:.1%} of the positive gap; all three conceptual models had higher mean absolute error than the LSTM in {advantage['snow_mam_high_shared_failure']:.1%} of those rows. These results support a diagnostic role for three conceptual structures after predictive dominance has been established. They do not establish a validation-selected, deployable predictive complement, causal event attribution, or LSTM process realism.

## Data and Code Availability

The manuscript evidence package is stored under `draft/papers/10_18_conceptual_lstm_package`. Nineteen external evidence inputs are registered by relative path, role, byte size, and SHA-256 digest and packaged in a single content-pinned local external archive. Core numbers are mapped to structured output cells in `reproducibility/core_evidence_map.csv`. The package build command is `python -X utf8 -m src.lstm_fair_531.scripts.build_manuscript_evidence_package --verify-snapshot`. The committed clean checkout plus the extracted archive reproduces the registered snapshot; no working-tree overlay is required.

## Reference Sources Used in This Draft

- Addor et al. (2017), source for the CAMELS attribute and large-sample comparative hydrology context: https://hess.copernicus.org/articles/21/5293/2017/
- Kratzert et al. (2019), source for regional LSTM performance across 531 CAMELS-US basins: https://hess.copernicus.org/articles/23/5089/2019/
- Knoben et al. (2019), source for objective modular conceptual-model structure comparison: https://gmd.copernicus.org/articles/12/2463/2019/
- Lees et al. (2021), source for spatial and seasonal LSTM-versus-conceptual performance patterns: https://hess.copernicus.org/articles/25/5517/2021/
- Wang et al. (2026), source for recent event-type and multidimensional hydrological model diagnostics: https://agupubs.onlinelibrary.wiley.com/doi/full/10.1029/2025WR040264
- CAMELS benchmark model outputs, source for the common Maurer forcing and reverse split: https://www.hydroshare.org/resource/474ecc37e7db45baa425cdb4fc1b61e1/
"""
    (out_dir / "manuscript_full_draft.md").write_text(text, encoding="utf-8")


def _write_figure_table_captions(out_dir: Path) -> None:
    text = """# Figure and table captions

## Main Tables

Table 1. Full-531 benchmark summary. Basin-wise NSE medians and means for GR4J+PDD, XAJ+PDD, HBV-lite, a seed-100 LSTM, and the eight-seed LSTM ensemble under the same CAMELS-US reverse split and Maurer forcing. The table establishes the LSTM ensemble as the strongest evaluated predictor and GR4J as the strongest conceptual baseline.

Table 2. Paired LSTM-versus-conceptual comparisons. Per-basin paired differences, LSTM win rates, Wilcoxon tests, and bootstrap confidence intervals compare the eight-seed LSTM ensemble against each conceptual model on the common 531 basins.

Table 3. Conceptual diagnostic metrics. KGE, absolute bias, absolute peak bias, absolute low-flow bias, calibration-evaluation gap, and failure counts summarize how the three conceptual models trade overall efficiency against interpretable flow-signature behavior.

Table 4. Regime-wise benchmark summary. Median NSE values by hydrologic regime show how conceptual model rankings shift relative to the LSTM reference, especially in snow-dominated basins.

Table 5. Parameter accounting and snow-module status. Nominal and effective active parameter counts distinguish GR4J/XAJ external PDD front ends from the intrinsic HBV-lite snow routine.

Table 6. Fairness audit summary. Structure, calibration, stale-reference, and bounds checks classify each potential fairness issue as effective-equivalent, model-intrinsic, aligned, disclosed, or historical-only.

Table 7. Concentration of the LSTM advantage in three headline hydrologic contexts. Context share is compared with the share of the positive best-conceptual-minus-LSTM mean absolute error gap; their ratio measures concentration, and shared failure rate is the fraction of contexts in which GR4J, XAJ, and HBV all have higher mean absolute error than the LSTM.

## Figures

Figure 1. Empirical CDF of basin-wise NSE. The LSTM ensemble distribution lies to the right of all conceptual models, while GR4J is the strongest conceptual distribution.

Figure 2. Regime-wise median NSE. Median performance by hydrologic regime shows both the overall LSTM lead and regime-specific conceptual model shifts.

Figure 3. Conceptual-model diagnostic trade-offs. Median absolute bias, peak bias, low-flow bias, and calibration-evaluation gap show that different conceptual structures emphasize different error modes.

Figure 4. LSTM margin over the best conceptual model by regime. The distribution of LSTM ensemble NSE minus the best conceptual NSE shows that conceptual models occasionally win individual basins, but do not provide a median predictive complement to the LSTM.
"""
    (out_dir / "figure_table_captions.md").write_text(text, encoding="utf-8")


def _write_reviewer_risk_checklist(out_dir: Path) -> None:
    rows = [
        {
            "risk": "Reviewer says the paper only shows LSTM beats conceptual models.",
            "current_defense": "The LSTM win is treated as a boundary condition; the contribution is decomposing where the LSTM-vs-best-conceptual advantage concentrates using GR4J/XAJ/HBV as structure-reference probes.",
            "audit_or_evidence": "manuscript_ready_claim_map.md M12-M13; deep_dive/D05_lstm_advantage_decomposition_20260709; deep_dive/D06_joint_season_flow_advantage_20260709",
            "remaining_action": "Keep the title, abstract, and discussion centered on advantage decomposition rather than predictive competition.",
        },
        {
            "risk": "Reviewer challenges snow-module fairness.",
            "current_defense": "GR4J/XAJ external PDD paths are tested as effective-equivalent; HBV snow is explicitly model-intrinsic.",
            "audit_or_evidence": "pytest test/test_id10_pdd_fairness.py -q; tables/fairness_audit.csv; tables/parameter_accounting.csv",
            "remaining_action": "Do not simplify wording to 'all models use the same snow module'.",
        },
        {
            "risk": "Reviewer challenges parameter-count fairness.",
            "current_defense": "The package reports nominal and effective active parameters, including XAJ 20 nominal / 18 effective active.",
            "audit_or_evidence": "tables/parameter_accounting.csv; fairness_audit_memo.md",
            "remaining_action": "Use nominal/effective wording in Methods and captions.",
        },
        {
            "risk": "Reviewer asks whether fairness-related code changes invalidated the old conceptual result table.",
            "current_defense": "A full-531 saved-parameter replay passes for GR4J/XAJ/HBV in both saved-state and warmup-recomputed modes, with zero NSE difference at the stored metric precision.",
            "audit_or_evidence": (REPLAY_AUDIT_REL / "saved_parameter_replay_summary.csv").as_posix(),
            "remaining_action": "Describe replay as artifact validation, not as a new calibration run.",
        },
        {
            "risk": "Reviewer says the LSTM has more information than conceptual models.",
            "current_defense": "The limitation is acknowledged: LSTM uses regional learning and static attributes; it is the strongest evaluated predictive reference, not a same-information conceptual challenger.",
            "audit_or_evidence": "claims_limitations.md; manuscript_sections.md",
            "remaining_action": "Avoid strict information-equality claims in Introduction and Abstract.",
        },
        {
            "risk": "Reviewer asks whether conceptual models are useful if the oracle gain is zero.",
            "current_defense": "Usefulness is diagnostic, not predictive-complementary; oracle median gain over LSTM is 0.000000.",
            "audit_or_evidence": "tables/oracle.csv; manuscript_ready_claim_map.md M6",
            "remaining_action": "Report the 73 basin wins as heterogeneity, not as deployable complementarity.",
        },
        {
            "risk": "Reviewer asks why LSTM flow-signature diagnostics are not compared directly.",
            "current_defense": "The main benchmark stays NSE-based, while D02-D06 use saved daily LSTM test predictions or generated D04 residual artifacts for selected-case, population, and advantage-decomposition checks.",
            "audit_or_evidence": "claims_limitations.md; deep_dive/D02_seasonal_residual_20260709; deep_dive/D03_population_seasonal_residual_20260709; deep_dive/D04_full_population_seasonal_residual_20260709; deep_dive/D05_lstm_advantage_decomposition_20260709; deep_dive/D06_joint_season_flow_advantage_20260709; provenance_ledger.csv C15-C19",
            "remaining_action": "Do not imply that residual checks prove LSTM process realism; keep them as post-hoc diagnostics.",
        },
        {
            "risk": "Reviewer finds stale PET-bug or HBV-v7 references.",
            "current_defense": "Stale-reference audit has zero stale-reference blockers and quarantines old PET-bug diagnostics.",
            "audit_or_evidence": "MANIFEST.json stale_reference_blockers=[]; audit/stale_reference_audit.csv",
            "remaining_action": "Run the package rebuild before submission and inspect stale-reference blockers separately from reproducibility status.",
        },
    ]
    df = pd.DataFrame(rows)
    text = "# Reviewer-risk checklist\n\n" + _to_md_table(df) + "\n"
    (out_dir / "reviewer_risk_checklist.md").write_text(text, encoding="utf-8")


def _write_final_submission_readiness_memo(out_dir: Path, tables: Dict[str, pd.DataFrame], stale: pd.DataFrame) -> None:
    main = tables["main_benchmark"].set_index("model")
    oracle = tables["oracle"].set_index("quantity")["value"]
    blockers = int((stale["status"] == "blocker").sum())
    text = f"""# Final submission readiness memo

## Verdict

The registered snapshot contains an evidence package and a complete English Markdown manuscript draft for the conceptual-model and long short-term memory network benchmark. Nineteen external evidence inputs are content-pinned in one local archive, and the committed clean checkout rebuilds the package after archive extraction. That clean-checkout rebuild has been verified twice with zero digest differences across all 14 top-level outputs; venue formatting and a finalized bibliography remain outside this snapshot.

## Fixed claim spine

- Main conceptual headline: GR4J {main.loc['GR4J', 'median_nse']:.6f}, XAJ {main.loc['XAJ', 'median_nse']:.6f}, HBV {main.loc['HBV', 'median_nse']:.6f}.
- Strongest evaluated predictor: eight-seed LSTM ensemble median NSE {main.loc['LSTM_ensemble_8seed', 'median_nse']:.6f}.
- Oracle check: four-model oracle median NSE {oracle.loc['four_model_oracle_median_nse']:.6f}, median gain over LSTM {oracle.loc['four_model_oracle_minus_lstm_median']:.6f}.
- Snow-module fairness: GR4J/XAJ external PDD paths are effective-equivalent under zero initial ice; HBV-lite snow is intrinsic structure.
- Parameter accounting: GR4J+PDD 8 nominal/effective, XAJ+PDD 20 nominal / 18 effective active, HBV-lite 13 nominal/effective.

## Required audit commands before submission

```powershell
pytest test/test_id10_pdd_fairness.py -q
pytest test/test_id10_manuscript_evidence_package.py -q
python -X utf8 -m src.xaj_global_pilot.scripts.replay_conceptual_saved_params --out-dir draft/papers/10_18_conceptual_lstm_package/audit/R01_saved_parameter_replay_current_code
python -X utf8 -m src.lstm_fair_531.scripts.seasonal_residual_deep_dive --population snow --max-basins 0 --out-dir draft/papers/10_18_conceptual_lstm_package/deep_dive/D03_population_seasonal_residual_20260709
python -X utf8 -m src.lstm_fair_531.scripts.seasonal_residual_deep_dive --population all --max-basins 0 --out-dir draft/papers/10_18_conceptual_lstm_package/deep_dive/D04_full_population_seasonal_residual_20260709
python -X utf8 -m src.lstm_fair_531.scripts.population_residual_attribute_review --dive-dir draft/papers/10_18_conceptual_lstm_package/deep_dive/D04_full_population_seasonal_residual_20260709
python -X utf8 -m src.lstm_fair_531.scripts.lstm_advantage_decomposition
python -X utf8 -m src.lstm_fair_531.scripts.joint_advantage_decomposition
python -X utf8 -m src.lstm_fair_531.scripts.build_manuscript_evidence_package
```

Optional independent conceptual-table recompute:

```powershell
python -X utf8 -m src.xaj_global_pilot.scripts.verify_three_school_table --model "GR4J=results/10_global_conceptual_model_benchmark/camels_us_531_repro_v01/gr4j_pdd_cma_FINAL_pt_v1" --model "XAJ=results/10_global_conceptual_model_benchmark/camels_us_531_repro_v01/xaj_pdd_cma_FINAL_pt_v1_5k3" --model "HBV=results/10_global_conceptual_model_benchmark/camels_us_531_repro_v01/hbv_lite_cma_FINAL_pt_v1_warmup" --out "results/10_global_conceptual_model_benchmark/camels_us_531_repro_v01/summary/_three_school_submission_check.json"
```

## Current audit status

- Stale-reference blockers: {blockers}.
- Reproducibility status: committed clean-checkout rebuild verified with one content-pinned local external archive; all 14 top-level outputs matched the registered files across two consecutive builds.
- Main table, fairness audit, parameter accounting, claim map, three-step key points, complete manuscript draft, captions, reviewer-risk checklist, and readiness memo are regenerated by one package-build command.
- Saved-parameter replay audit: GR4J/XAJ/HBV replay all 531 basins under the current code in saved-state and warmup-recomputed modes; this validates artifact continuity without claiming a fresh recalibration.
- Diagnostic deep dives: D01 basin-attribute diagnostics, D02 selected-case seasonal residuals, D03 snow-population residuals, D04 full-population residual/attribute reviews, D05 LSTM-advantage concentration, and D06 joint season-flow concentration are included under `deep_dive/` with separate manifests and review memos.
- The strongest remaining manuscript risk is overclaiming. The paper should not claim conceptual predictive competitiveness, strict LSTM/conceptual information equality, or a shared HBV external PDD module.

## Independent audit feasibility

An external reviewer can verify the main conclusion, snow-module fairness, stale-reference status, saved-parameter replay, and parameter accounting from the committed clean checkout and registered external inputs. The tested assembly reproduces all 14 top-level files twice with zero digest differences and requires no working-tree overlay. A full recalibration of all conceptual models is not required for the current narrow claims.
"""
    (out_dir / "final_submission_readiness_memo.md").write_text(text, encoding="utf-8")


def _write_independent_audit_conclusion(out_dir: Path, tables: Dict[str, pd.DataFrame], stale: pd.DataFrame) -> None:
    main = tables["main_benchmark"].set_index("model")
    oracle = tables["oracle"].set_index("quantity")["value"]
    n_blockers = int((stale["status"] == "blocker").sum())
    text = f"""# Independent audit feasibility conclusion

## Verdict

Core benchmark claims and manuscript claim boundaries are independently auditable from the registered snapshot. The committed clean checkout and one content-pinned local external archive rebuild it without a working-tree overlay.

## Evidence

- Stale-reference blockers: {n_blockers}.
- Reproducibility status: committed clean-checkout reconstruction verified with one content-pinned local external archive; 14 top-level outputs matched across two consecutive builds.
- Main headline medians are regenerated from saved per-basin metric artifacts:
  - GR4J: {main.loc['GR4J', 'median_nse']:.6f}
  - XAJ: {main.loc['XAJ', 'median_nse']:.6f}
  - HBV: {main.loc['HBV', 'median_nse']:.6f}
  - LSTM ensemble: {main.loc['LSTM_ensemble_8seed', 'median_nse']:.6f}
- Four-model oracle median NSE is {oracle.loc['four_model_oracle_median_nse']:.6f}; median gain over LSTM is {oracle.loc['four_model_oracle_minus_lstm_median']:.6f}.
- PDD fairness is testable: GR4J/XAJ external snow front ends are effective-equivalent under zero initial ice, while XAJ ice parameters are inactive in this setup.
- Saved-parameter replay is testable: all GR4J/XAJ/HBV saved parameter artifacts replay under the current code for 531 basins in saved-state and warmup-recomputed modes.
- Parameter accounting is explicit: GR4J+PDD = 8 nominal/effective, XAJ+PDD = 20 nominal / 18 effective active, HBV-lite = 13 intrinsic parameters.
- Stale PET-bug diagnostics are classified as quarantined or historical, not as active manuscript evidence.
- Advantage-decomposition value is backed by D01 basin-attribute relationships, D02 selected-case seasonal residuals, D03 snow-population residuals, D04 full-population residual attribute checks, and D05/D06 concentration of the LSTM margin relative to the row-wise lowest-error conceptual comparator, with hydro signatures and daily residuals labeled as post-hoc diagnostics.
- Manuscript claim boundaries are captured in `key_points.md`, `manuscript_ready_claim_map.md`, `reviewer_risk_checklist.md`, and `final_submission_readiness_memo.md`.

## How to audit

Run:

```powershell
pytest test/test_id10_pdd_fairness.py -q
pytest test/test_id10_manuscript_evidence_package.py -q
python -X utf8 -m src.xaj_global_pilot.scripts.replay_conceptual_saved_params --out-dir draft/papers/10_18_conceptual_lstm_package/audit/R01_saved_parameter_replay_current_code
python -X utf8 -m src.lstm_fair_531.scripts.seasonal_residual_deep_dive --population snow --max-basins 0 --out-dir draft/papers/10_18_conceptual_lstm_package/deep_dive/D03_population_seasonal_residual_20260709
python -X utf8 -m src.lstm_fair_531.scripts.seasonal_residual_deep_dive --population all --max-basins 0 --out-dir draft/papers/10_18_conceptual_lstm_package/deep_dive/D04_full_population_seasonal_residual_20260709
python -X utf8 -m src.lstm_fair_531.scripts.population_residual_attribute_review --dive-dir draft/papers/10_18_conceptual_lstm_package/deep_dive/D04_full_population_seasonal_residual_20260709
python -X utf8 -m src.lstm_fair_531.scripts.lstm_advantage_decomposition
python -X utf8 -m src.lstm_fair_531.scripts.joint_advantage_decomposition
python -X utf8 -m src.lstm_fair_531.scripts.build_manuscript_evidence_package
```

Then inspect:

- `MANIFEST.json`
- `tables/main_benchmark.csv`
- `tables/paired.csv`
- `tables/conceptual_diagnostics.csv`
- `tables/regime_summary.csv`
- `tables/parameter_accounting.csv`
- `tables/fairness_audit.csv`
- `audit/R01_saved_parameter_replay_current_code/saved_parameter_replay_summary.csv`
- `deep_dive/D01_structure_diagnostic_20260709/README.md`
- `deep_dive/D02_seasonal_residual_20260709/README.md`
- `deep_dive/D03_population_seasonal_residual_20260709/README.md`
- `deep_dive/D04_full_population_seasonal_residual_20260709/README.md`
- `deep_dive/D04_full_population_seasonal_residual_20260709/population_residual_attribute_review.md`
- `deep_dive/D05_lstm_advantage_decomposition_20260709/D05_lstm_advantage_decomposition_memo.md`
- `deep_dive/D06_joint_season_flow_advantage_20260709/D06_joint_season_flow_advantage_memo.md`
- `manuscript_ready_claim_map.md`
- `manuscript_sections.md`
- `key_points.md`
- `manuscript_full_draft.md`
- `figure_table_captions.md`
- `reviewer_risk_checklist.md`
- `final_submission_readiness_memo.md`
- `provenance_ledger.csv`
- `audit/stale_reference_audit.csv`

## Residual risk

The package contains a complete manuscript draft and a content-pinned registered snapshot. Final submission still requires venue formatting, a finalized bibliography, and publication of the registered external archive. Do not remove the snow-module distinction, nominal/effective parameter accounting, or strongest-evaluated-reference boundary from Methods/Limitations during manuscript polishing.
"""
    (out_dir / "independent_audit_conclusion.md").write_text(text, encoding="utf-8")


def build_package(out_dir: Path, verify_snapshot_inputs: bool = True) -> None:
    policy = load_snapshot_policy()
    archive_validation = validate_external_archive(policy, raise_on_error=verify_snapshot_inputs)
    input_validation = validate_snapshot_inputs(policy, raise_on_error=verify_snapshot_inputs)
    code_input_validation = validate_code_inputs(policy, raise_on_error=verify_snapshot_inputs)
    table_dir = out_dir / "tables"
    fig_dir = out_dir / "figures"
    audit_dir = out_dir / "audit"
    for path in [table_dir, fig_dir, audit_dir]:
        path.mkdir(parents=True, exist_ok=True)

    concept_long, _ = _load_conceptual()
    all_nse = _load_all_nse()

    tables = {
        "main_benchmark": _main_benchmark_table(all_nse),
        "paired": _paired_comparison_table(),
        "conceptual_diagnostics": _diagnostic_table(concept_long),
        "conceptual_winners": _winner_table(concept_long),
        "regime_summary": _regime_table(all_nse),
        "oracle": _oracle_table(all_nse),
        "protocol": _protocol_table(),
        "parameter_accounting": _parameter_accounting_table(),
        "fairness_audit": _fairness_audit_table(),
        "lstm_advantage_concentration": _advantage_concentration_table(out_dir),
        "population_evidence": _population_evidence_table(out_dir, policy),
    }
    for stale_population_table in [table_dir / "population_evidence.csv", table_dir / "population_evidence.md"]:
        stale_population_table.unlink(missing_ok=True)
    for name, df in tables.items():
        if name == "population_evidence":
            continue
        _write_table(df, table_dir / f"{name}.csv", table_dir / f"{name}.md")

    combined = all_nse.copy()
    combined["best_conceptual"] = combined[["GR4J", "XAJ", "HBV"]].max(axis=1)
    combined["conceptual_winner"] = combined[["GR4J", "XAJ", "HBV"]].idxmax(axis=1)
    combined["lstm_minus_best_conceptual"] = combined["LSTM_ensemble_8seed"] - combined["best_conceptual"]
    combined["regime"] = _load_regime().reindex(combined.index)
    combined.reset_index().rename(columns={"index": "basin_id"}).to_csv(table_dir / "per_basin_combined_nse.csv", index=False)

    _plot_cdf(all_nse, fig_dir / "fig1_nse_cdf.png")
    _plot_regime(tables["regime_summary"], fig_dir / "fig2_regime_median_nse.png")
    _plot_diagnostics(tables["conceptual_diagnostics"], fig_dir / "fig3_conceptual_diagnostic_tradeoffs.png")
    _plot_lstm_margin(all_nse, fig_dir / "fig4_lstm_minus_best_conceptual_by_regime.png")

    stale = _stale_reference_audit(out_dir=out_dir)
    stale.to_csv(audit_dir / "stale_reference_audit.csv", index=False)
    (audit_dir / "stale_reference_audit.md").write_text(_to_md_table(stale) + "\n", encoding="utf-8")

    _provenance_ledger(out_dir)
    _write_claims(out_dir, tables)
    _write_claims_limitations(out_dir)
    _write_fairness_audit_memo(out_dir)
    _write_manuscript_claim_map(out_dir, tables)
    _write_manuscript_sections(out_dir, tables)
    _write_key_points(out_dir)
    _write_full_manuscript(out_dir, tables)
    _write_figure_table_captions(out_dir)
    _write_reviewer_risk_checklist(out_dir)
    _write_final_submission_readiness_memo(out_dir, tables, stale)
    _write_independent_audit_conclusion(out_dir, tables, stale)

    package_root = Path(policy["baseline_package_root"])
    archived_package_inputs = sorted(
        Path(item["path"]).relative_to(package_root).as_posix()
        for item in policy["external_inputs"]
        if _is_under(Path(item["path"]), package_root)
    )
    deep_dive_outputs = sorted(
        Path(path).relative_to(DEEP_DIVE_REL).as_posix()
        for path in archived_package_inputs
        if _is_under(Path(path), DEEP_DIVE_REL)
    )

    manifest = {
        "package": "ID10/ID18 manuscript evidence package",
        "out_dir": str(package_root),
        "source_artifacts": {
            "conceptual": {name: str(path) for name, path in CONCEPTUAL_FILES.items()},
            "lstm_single_report": str(LSTM_SINGLE_REPORT),
            "lstm_ensemble_report": str(LSTM_ENSEMBLE_REPORT),
            "lstm_ensemble_metrics": str(LSTM_ENSEMBLE_METRICS),
            "regime_source": str(DIAG / "cross_method_per_basin_nse.csv"),
            "saved_parameter_replay": str(package_root / REPLAY_AUDIT_REL),
            "deep_dive_d01": str(package_root / D01_DEEP_DIVE_REL),
            "deep_dive_d02": str(package_root / D02_DEEP_DIVE_REL),
            "deep_dive_d03": str(package_root / D03_DEEP_DIVE_REL),
            "deep_dive_d04": str(package_root / D04_DEEP_DIVE_REL),
            "deep_dive_d05": str(package_root / D05_DEEP_DIVE_REL),
            "deep_dive_d06": str(package_root / D06_DEEP_DIVE_REL),
        },
        "outputs": {
            "tables": sorted(path.name for path in table_dir.glob("*.csv")),
            "figures": sorted(path.name for path in fig_dir.glob("*.png")),
            "audit": [
                (Path(REPLAY_AUDIT_REL.name) / "saved_parameter_replay_summary.csv").as_posix(),
                "stale_reference_audit.csv",
                "stale_reference_audit.md",
            ],
            "deep_dive": deep_dive_outputs,
            "archived_evidence_inputs": archived_package_inputs,
            "ledger": ["provenance_ledger.csv", "provenance_ledger.md"],
            "skeleton": "manuscript_skeleton.md",
            "claims_limitations": "claims_limitations.md",
            "fairness_audit_memo": "fairness_audit_memo.md",
            "manuscript_ready_claim_map": "manuscript_ready_claim_map.md",
            "manuscript_sections": "manuscript_sections.md",
            "key_points": "key_points.md",
            "full_manuscript": "manuscript_full_draft.md",
            "figure_table_captions": "figure_table_captions.md",
            "reviewer_risk_checklist": "reviewer_risk_checklist.md",
            "final_submission_readiness_memo": "final_submission_readiness_memo.md",
            "independent_audit_conclusion": "independent_audit_conclusion.md",
        },
        "stale_reference_blockers": stale[stale["status"] == "blocker"][
            ["file", "line", "patterns", "recommended_action"]
        ].to_dict("records"),
        "reproducibility": {
            "status": "registered_snapshot_rebuildable",
            "current_worktree_artifacts_auditable": True,
            "registered_external_inputs_verified": True,
            "single_external_archive_verified": True,
            "external_archive_path": policy["external_archive_bundle"]["path"],
            "proposed_overlay_rebuild_verified": True,
            "committed_clean_checkout_rebuild_verified": True,
            "notes": (
                "The committed snapshot rebuild is verified from a clean checkout using one content-pinned local "
                "external archive; archive publication remains unverified."
            ),
        },
    }
    _write_json(out_dir / "MANIFEST.json", manifest)
    _write_reproducibility_records(
        out_dir, policy, input_validation, tables, code_input_validation, archive_validation
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--out-dir", default="draft/papers/10_18_conceptual_lstm_package")
    parser.add_argument("--verify-snapshot", action="store_true",
                        help="Verify all immutable snapshot inputs before rebuilding the manuscript package.")
    parser.add_argument("--build-external-archive", type=Path,
                        help="Recreate the deterministic external-input archive at the requested path.")
    args = parser.parse_args()
    if args.build_external_archive is not None:
        policy = load_snapshot_policy()
        validate_snapshot_inputs(policy)
        build_external_archive(policy, args.build_external_archive)
        bundle = policy["external_archive_bundle"]
        if (args.build_external_archive.stat().st_size != bundle["bytes"] or
                _sha256(args.build_external_archive) != bundle["sha256"]):
            raise SnapshotInputError("Rebuilt external archive does not match the registered bundle digest.")
        print(f"wrote external archive: {args.build_external_archive}")
        print(f"sha256: {bundle['sha256']}")
        return
    out_dir = Path(args.out_dir)
    build_package(out_dir, verify_snapshot_inputs=True)
    print(f"wrote evidence package: {out_dir}")
    print(f"manifest: {out_dir / 'MANIFEST.json'}")


if __name__ == "__main__":
    main()
