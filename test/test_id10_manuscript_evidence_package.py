import hashlib
import json
import re
import shutil
import subprocess
import sys
import tarfile
import zipfile
from pathlib import Path

import pandas as pd
import pytest
from pandas.testing import assert_frame_equal

from src.lstm_fair_531.scripts.build_manuscript_evidence_package import (
    SnapshotInputError,
    _advantage_concentration_table,
    _stale_reference_audit,
    build_external_archive,
    build_package,
    validate_external_archive,
    validate_snapshot_inputs,
)


PACKAGE = Path("draft/papers/10_18_conceptual_lstm_package")
GENERATOR = Path("src/lstm_fair_531/scripts/build_manuscript_evidence_package.py")
SNAPSHOT_POLICY = Path("src/lstm_fair_531/configs/manuscript_snapshot_policy.json")
FULL_DRAFT = PACKAGE / "manuscript_full_draft.md"
KEY_POINTS = PACKAGE / "key_points.md"


def _section(text: str, start: str, end: str) -> str:
    return text.split(start, maxsplit=1)[1].split(end, maxsplit=1)[0]


def _positive_overclaim_sentences(text: str) -> list[str]:
    direct_triggers = [
        "causal mechanism",
        "causal snowmelt",
        "learned a real",
        "learned the real",
        "learned the true",
        "physical processes faithfully",
        "predictive complement",
        "theoretical ceiling",
    ]
    negations = [
        r"\bnot\b",
        r"\bcannot\b",
        r"\bno evidence\b",
        r"\bwithout\b",
        r"\bneither\b",
        r"\bavoid(?:s|ed|ing)?\b",
        r"\boverstatement\b",
    ]
    raw_sentences = re.split(r"(?<=[.!?;])\s+|,?\s+\b(?:but|however|yet)\b\s+", text, flags=re.IGNORECASE)
    sentences = []
    for sentence in raw_sentences:
        if re.match(r"\s*(?:although|while|whereas|even though)\b", sentence, flags=re.IGNORECASE):
            clauses = sentence.split(",", maxsplit=1)
            if len(clauses) == 1:
                main_subject = re.search(
                    r"\b(?:the\s+)?(?:lstm|long short-term memory|neural (?:network|model))\b",
                    sentence,
                    flags=re.IGNORECASE,
                )
                if main_subject is not None:
                    clauses = [sentence[:main_subject.start()], sentence[main_subject.start():]]
            sentences.extend(clauses)
        elif re.search(r"\s+(?:although|while|whereas|even though)\b", sentence, flags=re.IGNORECASE):
            sentences.extend(
                re.split(r",?\s+(?=(?:although|while|whereas|even though)\b)", sentence, flags=re.IGNORECASE)
            )
        else:
            sentences.append(sentence)
    flagged = []
    for sentence in sentences:
        lower = sentence.lower()
        direct = any(trigger in lower for trigger in direct_triggers)
        process_learning = (
            re.search(r"\b(?:lstm|long short-term memory|neural (?:network|model))\b", lower) is not None
            and
            re.search(r"\b(?:learn(?:s|ed|ing)?|captur(?:e|es|ed|ing)|represent(?:s|ed|ing)?|"
                      r"reproduc(?:e|es|ed|ing)|discover(?:s|ed|ing)?)\b", lower) is not None
            and re.search(r"\b(?:snow|snowmelt|physical|physics|process(?:es)?|mechanism(?:s)?)\b", lower) is not None
        )
        if (direct or process_learning) and not any(re.search(negation, lower) for negation in negations):
            flagged.append(sentence)
    return flagged


def _load_snapshot_policy() -> dict:
    return json.loads(SNAPSHOT_POLICY.read_text(encoding="utf-8"))


def _select_csv_value(path: Path, selector: str):
    parts = dict(part.split("=", maxsplit=1) for part in selector.split(";"))
    column = parts.pop("column")
    table = pd.read_csv(path)
    selected = table
    for key, expected in parts.items():
        selected = selected[selected[key].astype(str) == expected]
    assert len(selected) == 1, (path, selector, len(selected))
    return selected.iloc[0][column]


def test_snapshot_policy_classifies_the_original_162_files_once():
    policy = _load_snapshot_policy()
    baseline = pd.DataFrame(policy["baseline_files"])

    assert len(baseline) == 162
    assert baseline["path"].nunique() == 162
    assert set(baseline["classification"]) == {
        "version_control",
        "external_archive",
        "regenerate",
        "exclude",
    }
    assert (baseline["bytes"] >= 0).all()
    assert baseline["sha256"].str.fullmatch(r"[0-9a-f]{64}").all()
    assert baseline["reason"].str.strip().ne("").all()

    actual = {
        path.relative_to(PACKAGE).as_posix()
        for path in PACKAGE.rglob("*")
        if path.is_file() and "reproducibility" not in path.relative_to(PACKAGE).parts
    }
    assert set(baseline["path"]) == actual


def test_snapshot_policy_pins_every_direct_generator_input():
    policy = _load_snapshot_policy()
    inputs = pd.DataFrame(policy["external_inputs"])

    assert len(inputs) == 19
    assert inputs["input_id"].nunique() == 19
    assert inputs["path"].nunique() == 19
    assert inputs["sha256"].str.fullmatch(r"[0-9a-f]{64}").all()
    assert inputs["role"].str.strip().ne("").all()
    assert inputs["source_command"].str.strip().ne("").all()

    for row in inputs.itertuples(index=False):
        path = Path(row.path)
        assert path.is_file(), row.path
        assert path.stat().st_size == row.bytes, row.path
        assert hashlib.sha256(path.read_bytes()).hexdigest() == row.sha256, row.path

    assert set(inputs["path"]) == {
        "results/10_global_conceptual_model_benchmark/camels_us_531_repro_v01/summary/"
        "gr4j_pdd_cma_FINAL_pt_v1_local_full.csv",
        "results/10_global_conceptual_model_benchmark/camels_us_531_repro_v01/summary/"
        "xaj_pdd_cma_FINAL_pt_v1_5k3_local_full.csv",
        "results/10_global_conceptual_model_benchmark/camels_us_531_repro_v01/summary/"
        "hbv_lite_cma_FINAL_pt_v1_warmup_local_full.csv",
        "results/10_global_conceptual_model_benchmark/camels_us_531_repro_v01/diagnostic/"
        "cross_method_per_basin_nse.csv",
        "results/18_lstm_fair_531/_reports/compare_iter1_cudalstm_s100.json",
        "results/18_lstm_fair_531/lstm_cudalstm_maurer_s100_2026_0616_1513_ep30/test/"
        "model_epoch030/test_metrics.csv",
        "results/18_lstm_fair_531/_reports/compare_iter2_cudalstm_8seed_ens.json",
        "results/18_lstm_fair_531/_reports/ensemble_cudalstm_maurer_8seed_per_basin.csv",
        "draft/papers/10_18_conceptual_lstm_package/deep_dive/"
        "D01_structure_diagnostic_20260709/tables/primary_static_spearman.csv",
        "draft/papers/10_18_conceptual_lstm_package/deep_dive/"
        "D04_full_population_seasonal_residual_20260709/tables/seasonal_attribute_link_checks.csv",
        "draft/papers/10_18_conceptual_lstm_package/deep_dive/"
        "D04_full_population_seasonal_residual_20260709/tables/flow_attribute_link_checks.csv",
        "draft/papers/10_18_conceptual_lstm_package/deep_dive/"
        "D05_lstm_advantage_decomposition_20260709/tables/season_regime_advantage_concentration.csv",
        "draft/papers/10_18_conceptual_lstm_package/deep_dive/"
        "D05_lstm_advantage_decomposition_20260709/tables/flow_regime_advantage_concentration.csv",
        "draft/papers/10_18_conceptual_lstm_package/deep_dive/"
        "D06_joint_season_flow_advantage_20260709/tables/joint_regime_advantage_concentration.csv",
        "draft/papers/10_18_conceptual_lstm_package/audit/"
        "R01_saved_parameter_replay_current_code/saved_parameter_replay_summary.csv",
        "draft/papers/10_18_conceptual_lstm_package/deep_dive/"
        "D02_seasonal_residual_20260709/tables/seasonal_delta_aggregate.csv",
        "draft/papers/10_18_conceptual_lstm_package/deep_dive/"
        "D02_seasonal_residual_20260709/tables/flow_delta_aggregate.csv",
        "draft/papers/10_18_conceptual_lstm_package/deep_dive/"
        "D03_population_seasonal_residual_20260709/tables/seasonal_delta_aggregate.csv",
        "draft/papers/10_18_conceptual_lstm_package/deep_dive/"
        "D03_population_seasonal_residual_20260709/tables/flow_delta_aggregate.csv",
    }


def test_snapshot_policy_lists_the_complete_proposed_version_control_overlay():
    policy = _load_snapshot_policy()
    overlay = policy["proposed_version_control_files"]
    code_inputs = policy["code_inputs"]

    assert len(overlay) == len(set(overlay))
    assert GENERATOR.as_posix() in overlay
    assert SNAPSHOT_POLICY.as_posix() in overlay
    assert "test/test_id10_manuscript_evidence_package.py" in overlay
    assert set(policy["top_level_outputs"]) == {
        Path(path).relative_to(PACKAGE).as_posix()
        for path in map(Path, overlay)
        if PACKAGE in path.parents and path.parent == PACKAGE
    }
    for relative in overlay:
        assert Path(relative).is_file(), relative
    assert len(code_inputs) == 5
    for item in code_inputs:
        normalized = Path(item["path"]).read_bytes().replace(b"\r\n", b"\n").replace(b"\r", b"\n")
        assert item["digest_mode"] == "text_lf"
        assert len(normalized) == item["bytes"]
        assert hashlib.sha256(normalized).hexdigest() == item["sha256"]


def test_single_external_archive_matches_the_registry_and_is_deterministic(tmp_path):
    policy = _load_snapshot_policy()
    bundle = policy["external_archive_bundle"]
    archive = Path(bundle["path"])

    assert archive.is_file()
    assert archive.stat().st_size == bundle["bytes"]
    assert hashlib.sha256(archive.read_bytes()).hexdigest() == bundle["sha256"]
    assert bundle["member_count"] == len(policy["external_inputs"]) == 19
    assert bundle["source_command"].endswith(
        "--build-external-archive results/paper_snapshot_archives/"
        "conceptual_lstm_531_external_inputs_20260713.zip"
    )

    with zipfile.ZipFile(archive) as zipped:
        assert zipped.namelist() == sorted(item["path"] for item in policy["external_inputs"])
        for item in policy["external_inputs"]:
            payload = zipped.read(item["path"])
            assert len(payload) == item["bytes"]
            assert hashlib.sha256(payload).hexdigest() == item["sha256"]

    rebuilt = tmp_path / "rebuilt.zip"
    build_external_archive(policy, rebuilt)
    assert rebuilt.read_bytes() == archive.read_bytes()


def test_external_archive_validation_rejects_missing_and_changed_bundles(tmp_path):
    archive = tmp_path / "bundle.zip"
    archive.write_bytes(b"registered archive\n")
    policy = {
        "external_archive_bundle": {
            "path": "bundle.zip",
            "bytes": archive.stat().st_size,
            "sha256": hashlib.sha256(archive.read_bytes()).hexdigest(),
            "format": "zip_stored",
            "member_count": 0,
        }
    }

    report = validate_external_archive(policy, repo_root=tmp_path)
    assert report.iloc[0]["status"] == "ok"

    archive.write_bytes(b"changed archive\n")
    with pytest.raises(SnapshotInputError, match="external archive bundle failed validation"):
        validate_external_archive(policy, repo_root=tmp_path)

    archive.unlink()
    with pytest.raises(SnapshotInputError, match="missing"):
        validate_external_archive(policy, repo_root=tmp_path)


def test_command_line_can_recreate_the_registered_external_archive(tmp_path):
    rebuilt = tmp_path / "external_inputs.zip"
    command = [
        sys.executable,
        "-X",
        "utf8",
        "-m",
        "src.lstm_fair_531.scripts.build_manuscript_evidence_package",
        "--build-external-archive",
        str(rebuilt),
    ]
    completed = subprocess.run(command, check=False, capture_output=True, text=True)

    assert completed.returncode == 0, completed.stderr
    registered = Path(_load_snapshot_policy()["external_archive_bundle"]["path"])
    assert rebuilt.read_bytes() == registered.read_bytes()


@pytest.mark.parametrize(
    "unsafe_path",
    ["/absolute.csv", "C:/absolute.csv", "../outside.csv", r"nested\file.csv", "nested/./file.csv"],
)
def test_external_archive_rejects_noncanonical_or_escaping_member_paths(tmp_path, unsafe_path):
    repo = tmp_path / "repo"
    repo.mkdir()
    archive = tmp_path / "unsafe.zip"
    policy = {"external_inputs": [{"path": unsafe_path}]}

    with pytest.raises(SnapshotInputError, match="Invalid external input path"):
        build_external_archive(policy, archive, repo_root=repo)
    assert not archive.exists()


def test_external_archive_rejects_duplicate_member_paths_before_writing(tmp_path):
    repo = tmp_path / "repo"
    repo.mkdir()
    archive = tmp_path / "duplicate.zip"
    policy = {"external_inputs": [{"path": "same.csv"}, {"path": "same.csv"}]}

    with pytest.raises(SnapshotInputError, match="Duplicate external input path"):
        build_external_archive(policy, archive, repo_root=repo)
    assert not archive.exists()


def test_external_archive_rejects_a_repository_symlink_that_resolves_outside(tmp_path):
    repo = tmp_path / "repo"
    repo.mkdir()
    outside = tmp_path / "outside.csv"
    outside.write_text("outside\n", encoding="utf-8")
    link = repo / "linked.csv"
    try:
        link.symlink_to(outside)
    except OSError as exc:
        pytest.skip(f"Symbolic links are unavailable: {exc}")
    archive = tmp_path / "symlink.zip"
    policy = {"external_inputs": [{"path": "linked.csv"}]}

    with pytest.raises(SnapshotInputError, match="resolves outside the repository"):
        build_external_archive(policy, archive, repo_root=repo)
    assert not archive.exists()


def test_snapshot_input_validation_reports_missing_and_changed_files(tmp_path):
    good = tmp_path / "good.csv"
    good.write_text("good\n", encoding="utf-8")
    changed = tmp_path / "changed.csv"
    changed.write_text("changed\n", encoding="utf-8")
    expected_changed = b"original\n"
    policy = {
        "external_inputs": [
            {
                "input_id": "I01",
                "path": "good.csv",
                "bytes": good.stat().st_size,
                "sha256": hashlib.sha256(good.read_bytes()).hexdigest(),
                "role": "valid fixture",
                "source_command": "fixture",
            },
            {
                "input_id": "I02",
                "path": "missing.csv",
                "bytes": 1,
                "sha256": hashlib.sha256(b"x").hexdigest(),
                "role": "missing fixture",
                "source_command": "fixture",
            },
            {
                "input_id": "I03",
                "path": "changed.csv",
                "bytes": len(expected_changed),
                "sha256": hashlib.sha256(expected_changed).hexdigest(),
                "role": "changed fixture",
                "source_command": "fixture",
            },
        ]
    }

    report = validate_snapshot_inputs(policy, repo_root=tmp_path, raise_on_error=False).set_index("input_id")
    assert report.loc["I01", "status"] == "ok"
    assert report.loc["I02", "status"] == "missing"
    assert report.loc["I03", "status"] == "sha256_mismatch"

    with pytest.raises(SnapshotInputError) as exc_info:
        validate_snapshot_inputs(policy, repo_root=tmp_path)
    message = str(exc_info.value)
    assert "missing.csv [missing]" in message
    assert "changed.csv [sha256_mismatch]" in message


def test_stale_reference_audit_ignores_files_outside_the_active_snapshot(tmp_path):
    active = tmp_path / "active_source.py"
    active.write_text('STALE_PATTERNS = ["xaj_pdd_local_full.csv"]\n', encoding="utf-8")
    unrelated = tmp_path / "unrelated_draft.md"
    unrelated.write_text("XAJ-PDD (ours) 0.4458\n", encoding="utf-8")

    report = _stale_reference_audit(scan_paths=[active])

    assert set(report["file"]) == {active.as_posix()}
    assert unrelated.as_posix() not in set(report["file"])


def test_compact_advantage_table_reports_three_headline_contexts():
    table = pd.read_csv(PACKAGE / "tables" / "lstm_advantage_concentration.csv")
    generated = _advantage_concentration_table(PACKAGE)

    assert_frame_equal(table, generated, check_exact=False, atol=1e-15, rtol=0)

    assert list(table.columns) == [
        "context_family",
        "hydrologic_context",
        "context_share",
        "positive_best_gap_share",
        "concentration_ratio",
        "shared_failure_rate",
        "n_contexts",
        "shared_failure_count",
    ]
    assert list(table["hydrologic_context"]) == [
        "snow-dominated / MAM",
        "snow-dominated / high-flow",
        "snow-dominated / MAM / high-flow",
    ]

    expected = [
        (0.07156308851224105, 0.18577895559435664, 2.596016458436931, 0.9407894736842105),
        (0.09553739786297925, 0.3612286095145997, 3.7810178798534744, 0.9539473684210527),
        (0.02776255707762557, 0.13615038405582494, 4.904101004642379, 0.9144736842105263),
    ]
    for row, values in zip(table.itertuples(index=False), expected):
        assert row.context_share == pytest.approx(values[0])
        assert row.positive_best_gap_share == pytest.approx(values[1])
        assert row.concentration_ratio == pytest.approx(values[2])
        assert row.shared_failure_rate == pytest.approx(values[3])

    source_specs = [
        (
            PACKAGE / "deep_dive" / "D05_lstm_advantage_decomposition_20260709" / "tables" /
            "season_regime_advantage_concentration.csv",
            {"regime": "snow-dominated", "season": "MAM"},
        ),
        (
            PACKAGE / "deep_dive" / "D05_lstm_advantage_decomposition_20260709" / "tables" /
            "flow_regime_advantage_concentration.csv",
            {"regime": "snow-dominated", "flow_group": "high"},
        ),
        (
            PACKAGE / "deep_dive" / "D06_joint_season_flow_advantage_20260709" / "tables" /
            "joint_regime_advantage_concentration.csv",
            {"regime": "snow-dominated", "season": "MAM", "flow_group": "high"},
        ),
    ]
    for compact_row, (source_path, selectors) in zip(table.itertuples(index=False), source_specs):
        source = pd.read_csv(source_path)
        for column, value in selectors.items():
            source = source[source[column] == value]
        assert len(source) == 1
        source_row = source.iloc[0]
        assert compact_row.context_share == pytest.approx(source_row["context_share"])
        assert compact_row.positive_best_gap_share == pytest.approx(source_row["positive_best_gap_share"])
        assert compact_row.concentration_ratio == pytest.approx(source_row["gap_concentration_ratio"])
        assert compact_row.shared_failure_rate == pytest.approx(source_row["shared_failure_rate"])


def test_active_evidence_package_avoids_overclaiming_phrases():
    prohibited = [
        "where the LSTM advantage comes from",
        "residual mechanisms behind",
        "process-facing",
        "shared conceptual ceiling zone",
        "advantage is not uniform in interpretation",
        "Kratzert-grade",
        "intrinsic snow physics",
        "fair enough for a manuscript claim",
        "to prove GR4J/XAJ external snow front-end effective equivalence",
    ]
    sources = [GENERATOR, *PACKAGE.rglob("*.md")]
    combined = "\n".join(path.read_text(encoding="utf-8") for path in sources)

    for phrase in prohibited:
        assert phrase not in combined


def test_active_top_level_narrative_does_not_call_the_lstm_a_ceiling():
    active_files = [
        GENERATOR,
        PACKAGE / "manuscript_skeleton.md",
        PACKAGE / "claims_limitations.md",
        PACKAGE / "manuscript_ready_claim_map.md",
        PACKAGE / "manuscript_sections.md",
        PACKAGE / "figure_table_captions.md",
        PACKAGE / "final_submission_readiness_memo.md",
        PACKAGE / "independent_audit_conclusion.md",
        FULL_DRAFT,
    ]
    combined = "\n".join(path.read_text(encoding="utf-8") for path in active_files)
    prohibited = [
        "predictive ceiling",
        "reproduced LSTM ceiling",
        "diagnostic ceiling reference",
        "LSTM ceiling",
        "LSTM-ceiling",
        "ceiling reference",
        "reference ceiling",
    ]
    for phrase in prohibited:
        assert phrase not in combined


def test_headline_numbers_and_reproducibility_boundaries_are_locked():
    main = pd.read_csv(PACKAGE / "tables" / "main_benchmark.csv").set_index("model")
    assert main.loc["LSTM_ensemble_8seed", "median_nse"] == pytest.approx(0.7592252236337574)
    assert main.loc["GR4J", "median_nse"] == pytest.approx(0.653287)
    assert main.loc["XAJ", "median_nse"] == pytest.approx(0.619564)
    assert main.loc["HBV", "median_nse"] == pytest.approx(0.617033)

    skeleton = (PACKAGE / "manuscript_skeleton.md").read_text(encoding="utf-8")
    for value in [
            "0.759225", "0.653287", "0.619564", "0.617033", "rho = 0.429", "q = 1.65e-23", "2.8%",
            "13.6%", "4.90", "0.914"
    ]:
        assert value in skeleton
    assert "not predictive competitors" in skeleton
    assert "27 static basin attributes" in skeleton

    audit = (PACKAGE / "deep_dive" / "FINAL_INNOVATION_AUDIT_20260709.md").read_text(encoding="utf-8")
    for value in ["0.027763", "0.136150", "4.904101", "0.914474"]:
        assert value in audit

    manifest = json.loads((PACKAGE / "MANIFEST.json").read_text(encoding="utf-8"))
    assert manifest["stale_reference_blockers"] == []
    assert manifest["reproducibility"] == {
        "status": "registered_snapshot_rebuildable",
        "current_worktree_artifacts_auditable": True,
        "registered_external_inputs_verified": True,
        "single_external_archive_verified": True,
        "external_archive_path": (
            "results/paper_snapshot_archives/conceptual_lstm_531_external_inputs_20260713.zip"
        ),
        "proposed_overlay_rebuild_verified": True,
        "committed_clean_checkout_rebuild_verified": True,
        "notes": "The committed snapshot rebuild is verified from a clean checkout using one content-pinned local external archive; archive publication remains unverified.",
    }
    for filename in ["final_submission_readiness_memo.md", "independent_audit_conclusion.md"]:
        text = (PACKAGE / filename).read_text(encoding="utf-8")
        assert "registered snapshot" in text
        assert "committed clean checkout" in text
        assert "Stale-reference blockers" in text


def test_full_manuscript_is_complete_traceable_and_narrowly_framed():
    text = FULL_DRAFT.read_text(encoding="utf-8")

    required_headings = [
        "# Locating Where Long Short-Term Memory Networks Win",
        "## Abstract",
        "## 1. Introduction",
        "## 2. Methods",
        "## 3. Results",
        "## 4. Discussion",
        "## 5. Limitations",
        "## 6. Conclusions",
        "## Data and Code Availability",
        "## Reference Sources Used in This Draft",
    ]
    positions = []
    for heading in required_headings:
        assert text.count(heading) == 1
        positions.append(text.index(heading))
    assert positions == sorted(positions)
    assert len(text.split()) >= 2500

    for value in [
            "0.759225", "0.653287", "0.619564", "0.617033", "0.027763", "0.136150", "4.904101",
            "0.914474"
    ]:
        assert value in text
    assert "Table 1." in text
    assert "Table 7." in text
    assert "one central contribution" in text
    assert "population-level support" in text
    assert "joint context refinement" in text
    assert "not predictive competitors" in text
    assert "post-hoc and associational" in text
    assert "registered snapshot" in text
    assert "single content-pinned local external archive" in text
    assert "committed clean checkout has been verified" in text

    for citation in ["Addor et al. (2017)", "Kratzert et al. (2019)", "Knoben et al. (2019)",
                     "Lees et al. (2021)", "Wang et al. (2026)"]:
        assert citation in text
    for placeholder in ["TODO", "TBD", "[citation needed]", "[insert"]:
        assert placeholder not in text

    manifest = json.loads((PACKAGE / "MANIFEST.json").read_text(encoding="utf-8"))
    assert manifest["outputs"]["full_manuscript"] == "manuscript_full_draft.md"


def test_full_manuscript_methods_and_wording_match_the_saved_analysis():
    text = FULL_DRAFT.read_text(encoding="utf-8")
    generator_text = GENERATOR.read_text(encoding="utf-8")

    for prohibited in ["predictive ceiling reference", "on one scale", "139 of 152"]:
        assert prohibited not in generator_text
    assert "predictive ceiling reference" not in text
    assert "on one scale" not in text

    required_method_details = [
        "arithmetic mean of the eight daily predictions",
        "10th and 90th percentiles of that basin's observed evaluation-period discharge",
        "at least 10 valid days",
        "within each context family",
        "snow fraction was at least 0.20",
        "aridity index below 1.0",
        "aridity index from 1.0 to below 1.5",
        "aridity index of at least 1.5",
        "five daily dynamic inputs",
        "sequence length of 270 days",
        "256 hidden units",
        "batch size of 256",
        "dropout of 0.4",
        "Adam optimizer",
        "Nash-Sutcliffe-efficiency loss",
        "results/18_lstm_fair_531/lstm_cudalstm_maurer_s100_2026_0616_1513_ep30/config.yml",
        "src/xaj_global_pilot/gr4j_core.py",
        "src/xaj_global_pilot/xaj_model.py",
        "src/scl_hydro/hbv_lite_numpy.py",
        "Tables 2 through 6",
    ]
    for detail in required_method_details:
        assert detail in text

    assert (
        "deep_dive/D06_joint_season_flow_advantage_20260709/tables/"
        "joint_regime_advantage_concentration.csv"
    ) in text


def test_full_manuscript_provenance_and_audit_commands_are_direct():
    ledger = pd.read_csv(PACKAGE / "provenance_ledger.csv").set_index("claim_id")
    sources = ledger.loc["C21", "source_files"]
    for source in [
            "tables/protocol.csv", "tables/parameter_accounting.csv", "tables/conceptual_diagnostics.csv",
            "tables/regime_summary.csv", "deep_dive/D01_structure_diagnostic_20260709/tables/primary_static_spearman.csv",
            "deep_dive/D04_full_population_seasonal_residual_20260709/tables/seasonal_attribute_link_checks.csv",
            "deep_dive/D05_lstm_advantage_decomposition_20260709/tables/season_regime_advantage_concentration.csv",
            "deep_dive/D06_joint_season_flow_advantage_20260709/tables/joint_regime_advantage_concentration.csv"
    ]:
        assert source in sources
    assert "provenance_ledger.csv" not in sources

    manuscript_test = "pytest test/test_id10_manuscript_evidence_package.py -q"
    for filename in ["final_submission_readiness_memo.md", "independent_audit_conclusion.md"]:
        text = (PACKAGE / filename).read_text(encoding="utf-8")
        assert manuscript_test in text


def test_key_points_form_one_traceable_three_step_argument_chain():
    text = KEY_POINTS.read_text(encoding="utf-8")
    bullets = [line[2:] for line in text.splitlines() if line.startswith("- ")]

    assert len(bullets) == 3
    assert "one contribution" in text
    assert "not three separate contributions" in text

    concentration = pd.read_csv(PACKAGE / "tables" / "lstm_advantage_concentration.csv")
    population = pd.read_csv(
        PACKAGE / "deep_dive" / "D01_structure_diagnostic_20260709" / "tables" / "primary_static_spearman.csv"
    )
    population = population[(population["target"] == "lstm_minus_best_conceptual") &
                            (population["feature"] == "clim_frac_snow")].iloc[0]

    assert bullets[0].startswith("Three conceptual structural references")
    for value in concentration.iloc[:2][["context_share", "positive_best_gap_share"]].to_numpy().ravel():
        assert f"{value:.1%}" in bullets[0]
    assert "lowest-error conceptual model in each row" in bullets[0]

    assert bullets[1].startswith("Across 531 basins")
    assert f"rho = {population['spearman_rho']:.3f}" in bullets[1]
    assert f"q = {population['q_value']:.2e}" in bullets[1]
    assert "basin-wise conceptual comparator with the highest Nash-Sutcliffe efficiency" in bullets[1]

    joint = concentration.iloc[2]
    assert bullets[2].startswith("Snow-dominated spring high flow")
    assert "retained joint context with the highest concentration ratio" in bullets[2]
    for column in ["context_share", "positive_best_gap_share", "shared_failure_rate"]:
        assert f"{joint[column]:.1%}" in bullets[2]
    assert "all three evaluated conceptual models had higher mean absolute error" in bullets[2]

    for result_section in ["Section 3.3", "Section 3.4", "Section 3.5"]:
        assert result_section in text
    for source in [
            "tables/lstm_advantage_concentration.csv",
            "deep_dive/D01_structure_diagnostic_20260709/tables/primary_static_spearman.csv",
            "deep_dive/D04_full_population_seasonal_residual_20260709/tables/seasonal_attribute_link_checks.csv",
            "deep_dive/D06_joint_season_flow_advantage_20260709/tables/joint_regime_advantage_concentration.csv",
    ]:
        assert source in text

    trace_rows = {}
    for line in text.splitlines():
        if re.match(r"^\| [123] \|", line):
            cells = [cell.strip() for cell in line.split("|")[1:-1]]
            trace_rows[cells[0]] = cells[1:]
    assert set(trace_rows) == {"1", "2", "3"}

    role, location, evidence, boundary = trace_rows["1"]
    assert role.startswith("Central contribution")
    assert location == "Section 3.3"
    assert "tables/lstm_advantage_concentration.csv" in evidence
    assert "season_regime_advantage_concentration.csv" in evidence
    assert "flow_regime_advantage_concentration.csv" in evidence
    assert "not a new predictive method" in boundary

    role, location, evidence, boundary = trace_rows["2"]
    assert role.startswith("First evidence layer")
    assert location == "Section 3.4"
    assert "primary_static_spearman.csv" in evidence
    assert "seasonal_attribute_link_checks.csv" in evidence
    assert "flow_attribute_link_checks.csv" in evidence
    assert "does not establish a snow-process mechanism" in boundary

    role, location, evidence, boundary = trace_rows["3"]
    assert role.startswith("Second evidence layer")
    assert location == "Section 3.5"
    assert "joint_regime_advantage_concentration.csv" in evidence
    assert "not event attribution or process realism" in boundary

    manifest = json.loads((PACKAGE / "MANIFEST.json").read_text(encoding="utf-8"))
    assert manifest["outputs"]["key_points"] == "key_points.md"
    ledger = pd.read_csv(PACKAGE / "provenance_ledger.csv").set_index("claim_id")
    assert ledger.loc["C22", "artifact"] == "key_points.md"
    assert "provenance_ledger.csv" not in ledger.loc["C22", "source_files"]


def test_abstract_introduction_and_conclusion_share_the_same_problem_chain():
    text = FULL_DRAFT.read_text(encoding="utf-8")
    abstract = _section(text, "## Abstract\n", "**Keywords:**")
    introduction = _section(text, "## 1. Introduction\n", "## 2. Methods")
    conclusion = _section(text, "## 6. Conclusions\n", "## Data and Code Availability")

    assert abstract.lstrip().startswith("Aggregate rainfall-runoff performance scores")
    assert introduction.lstrip().startswith("Aggregate performance summaries")
    first_intro_paragraph = introduction.strip().split("\n\n", maxsplit=1)[0]
    for model_name in ["LSTM", "GR4J", "Xinanjiang", "HBV"]:
        assert model_name not in first_intro_paragraph

    assert abstract.index("hydrological contexts") < abstract.index("long short-term memory")
    assert "Our one central contribution" not in abstract
    assert "rho = 0.429" in abstract and "q = 1.65e-23" in abstract
    assert "2.8%" in abstract and "13.6%" in abstract and "91.4%" in abstract
    assert "one central contribution" in introduction
    assert "population-level support" in introduction
    assert "joint context refinement" in introduction
    assert "aggregate ranking" in conclusion
    assert "population-level" in conclusion.lower()
    assert "2.8%" in conclusion and "13.6%" in conclusion and "91.4%" in conclusion

    abstract_steps = [
        "Aggregate rainfall-runoff performance scores",
        "We decomposed",
        "Snow-dominated spring contexts",
        "Across all 531 basins",
        "retained joint context with the highest concentration ratio",
    ]
    conclusion_steps = [
        "An aggregate ranking",
        "The diagnostic decomposition",
        "Population-level analysis",
        "retained joint context with the highest concentration ratio",
    ]
    assert [abstract.index(step) for step in abstract_steps] == sorted(abstract.index(step) for step in abstract_steps)
    assert [conclusion.index(step) for step in conclusion_steps] == sorted(
        conclusion.index(step) for step in conclusion_steps
    )
    assert len([paragraph for paragraph in conclusion.strip().split("\n\n") if paragraph]) >= 3

    skeleton = (PACKAGE / "manuscript_skeleton.md").read_text(encoding="utf-8")
    skeleton_abstract = _section(skeleton, "## Abstract skeleton\n", "## Results narrative")
    skeleton_results = _section(skeleton, "## Results narrative\n", "## Claims that are supported")
    skeleton_steps = [
        "Snow-dominated MAM contexts",
        "Across all 531 basins",
        "retained joint context with the highest concentration ratio",
    ]
    for section in [skeleton_abstract, skeleton_results]:
        section_lower = section.lower()
        positions = [section_lower.index(step.lower()) for step in skeleton_steps]
        assert positions == sorted(positions)

    abstract_evidence = "<!-- Abstract evidence:"
    assert abstract_evidence in text
    comment = text.split(abstract_evidence, maxsplit=1)[1].split("-->", maxsplit=1)[0]
    for source in [
            "tables/main_benchmark.csv",
            "tables/lstm_advantage_concentration.csv",
            "deep_dive/D01_structure_diagnostic_20260709/tables/primary_static_spearman.csv",
            "deep_dive/D06_joint_season_flow_advantage_20260709/tables/joint_regime_advantage_concentration.csv",
    ]:
        assert source in comment


def test_conceptual_comparator_terms_and_bounded_interpretation_are_precise():
    text = FULL_DRAFT.read_text(encoding="utf-8")
    abstract = _section(text, "## Abstract\n", "**Keywords:**")
    methods = _section(text, "## 2. Methods\n", "## 3. Results")
    discussion = _section(text, "## 4. Discussion\n", "## 5. Limitations")
    conclusion = _section(text, "## 6. Conclusions\n", "## Data and Code Availability")

    assert "strongest single conceptual model, GR4J" in abstract
    assert "strongest single conceptual model, GR4J" in conclusion
    assert "basin-wise conceptual comparator with the highest Nash-Sutcliffe efficiency" in methods
    assert "conceptual comparator with the lowest mean absolute error in each row" in methods
    assert "retained joint context with the highest concentration ratio" in abstract
    assert "retained joint context with the highest concentration ratio" in conclusion
    assert (
        "GR4J and Xinanjiang share the tested external snow path, whereas HBV-lite uses an intrinsic snow routine"
        in discussion
    )
    assert "do not establish a validation-selected, deployable predictive complement" in conclusion
    assert "do not support predictive complementarity" not in conclusion

    active = "\n".join([
        text,
        KEY_POINTS.read_text(encoding="utf-8"),
        (PACKAGE / "manuscript_skeleton.md").read_text(encoding="utf-8"),
        (PACKAGE / "manuscript_ready_claim_map.md").read_text(encoding="utf-8"),
        (PACKAGE / "manuscript_sections.md").read_text(encoding="utf-8"),
    ])
    for ambiguous in [
            "strongest conceptual reference",
            "best conceptual reference",
            "best-conceptual gap",
            "strongest joint context",
            "strongest observed combination",
            "strongest observed shared-failure context",
            "shared conceptual failure",
            "effectively tied",
            "clear performance ladder",
            "followed by XAJ",
    ]:
        assert ambiguous not in active

    bounded_median_wording = (
        "Do not infer XAJ superiority over HBV from their median ordering alone; "
        "no equivalence or superiority test was specified."
    )
    for artifact in [
            PACKAGE / "manuscript_skeleton.md",
            PACKAGE / "claims_limitations.md",
            PACKAGE / "manuscript_ready_claim_map.md",
    ]:
        assert bounded_median_wording in artifact.read_text(encoding="utf-8")
    sections = (PACKAGE / "manuscript_sections.md").read_text(encoding="utf-8")
    assert (
        "These descriptive medians do not establish superiority or equivalence between XAJ and HBV-lite." in sections
    )


def test_positive_overclaim_detector_catches_adversarial_mutations():
    mutations = [
        "The LSTM learned a real causal snowmelt mechanism.",
        "The LSTM learned the physical snowmelt process.",
        "The LSTM represents physical processes faithfully.",
        "The conceptual models provide a predictive complement.",
        "These models define a theoretical ceiling.",
        "This comparison is not strict, but the LSTM learned the true causal snowmelt mechanism.",
        "Although this is not a strict comparison, the LSTM learned the physical snowmelt process.",
        "Although this is not a strict comparison the LSTM learned the physical snowmelt process.",
        "The LSTM learned the physical snowmelt process, although this is not a strict comparison.",
        "The LSTM learned the physical snowmelt process although this is not a strict comparison.",
        "A noteworthy result is that the LSTM learned the physical snowmelt process.",
    ]
    for mutation in mutations:
        assert _positive_overclaim_sentences(mutation)

    active = "\n".join([
        FULL_DRAFT.read_text(encoding="utf-8"),
        KEY_POINTS.read_text(encoding="utf-8"),
        (PACKAGE / "manuscript_skeleton.md").read_text(encoding="utf-8"),
        (PACKAGE / "manuscript_ready_claim_map.md").read_text(encoding="utf-8"),
    ])
    assert _positive_overclaim_sentences(active) == []


def test_build_package_recreates_and_stably_rebuilds_argument_artifacts(tmp_path):
    out_dir = tmp_path / "package"
    required_inputs = [
        Path("deep_dive/D01_structure_diagnostic_20260709/tables/primary_static_spearman.csv"),
        Path("deep_dive/D04_full_population_seasonal_residual_20260709/tables/seasonal_attribute_link_checks.csv"),
        Path("deep_dive/D04_full_population_seasonal_residual_20260709/tables/flow_attribute_link_checks.csv"),
        Path("deep_dive/D05_lstm_advantage_decomposition_20260709/tables/season_regime_advantage_concentration.csv"),
        Path("deep_dive/D05_lstm_advantage_decomposition_20260709/tables/flow_regime_advantage_concentration.csv"),
        Path("deep_dive/D06_joint_season_flow_advantage_20260709/tables/joint_regime_advantage_concentration.csv"),
    ]
    for relative in required_inputs:
        destination = out_dir / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(PACKAGE / relative, destination)

    artifacts = [
        "key_points.md",
        "manuscript_full_draft.md",
        "provenance_ledger.csv",
        "provenance_ledger.md",
        "MANIFEST.json",
    ]
    out_dir.mkdir(parents=True, exist_ok=True)
    for artifact in artifacts:
        (out_dir / artifact).write_text("POLLUTED", encoding="utf-8")

    build_package(out_dir)
    for artifact in artifacts:
        assert "POLLUTED" not in (out_dir / artifact).read_text(encoding="utf-8")

    first_hashes = {
        artifact: hashlib.sha256((out_dir / artifact).read_bytes()).hexdigest() for artifact in artifacts
    }
    build_package(out_dir)
    second_hashes = {
        artifact: hashlib.sha256((out_dir / artifact).read_bytes()).hexdigest() for artifact in artifacts
    }
    assert second_hashes == first_hashes

    ledger = pd.read_csv(out_dir / "provenance_ledger.csv")
    c22 = ledger[ledger["claim_id"] == "C22"]
    assert len(c22) == 1
    assert c22.iloc[0]["artifact"] == "key_points.md"
    manifest = json.loads((out_dir / "MANIFEST.json").read_text(encoding="utf-8"))
    assert manifest["outputs"]["key_points"] == "key_points.md"
    assert manifest["outputs"]["full_manuscript"] == "manuscript_full_draft.md"


def test_build_package_emits_complete_snapshot_registries(tmp_path):
    out_dir = tmp_path / "package"
    for relative in [
            Path("deep_dive/D01_structure_diagnostic_20260709/tables/primary_static_spearman.csv"),
            Path("deep_dive/D04_full_population_seasonal_residual_20260709/tables/seasonal_attribute_link_checks.csv"),
            Path("deep_dive/D04_full_population_seasonal_residual_20260709/tables/flow_attribute_link_checks.csv"),
            Path("deep_dive/D05_lstm_advantage_decomposition_20260709/tables/season_regime_advantage_concentration.csv"),
            Path("deep_dive/D05_lstm_advantage_decomposition_20260709/tables/flow_regime_advantage_concentration.csv"),
            Path("deep_dive/D06_joint_season_flow_advantage_20260709/tables/joint_regime_advantage_concentration.csv"),
    ]:
        destination = out_dir / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(PACKAGE / relative, destination)

    build_package(out_dir)
    manifest = json.loads((out_dir / "MANIFEST.json").read_text(encoding="utf-8"))
    assert manifest["outputs"]["audit"] == [
        "R01_saved_parameter_replay_current_code/saved_parameter_replay_summary.csv",
        "stale_reference_audit.csv",
        "stale_reference_audit.md",
    ]
    expected_deep_dive_outputs = [
        "D01_structure_diagnostic_20260709/tables/primary_static_spearman.csv",
        "D02_seasonal_residual_20260709/tables/flow_delta_aggregate.csv",
        "D02_seasonal_residual_20260709/tables/seasonal_delta_aggregate.csv",
        "D03_population_seasonal_residual_20260709/tables/flow_delta_aggregate.csv",
        "D03_population_seasonal_residual_20260709/tables/seasonal_delta_aggregate.csv",
        "D04_full_population_seasonal_residual_20260709/tables/flow_attribute_link_checks.csv",
        "D04_full_population_seasonal_residual_20260709/tables/seasonal_attribute_link_checks.csv",
        "D05_lstm_advantage_decomposition_20260709/tables/flow_regime_advantage_concentration.csv",
        "D05_lstm_advantage_decomposition_20260709/tables/season_regime_advantage_concentration.csv",
        "D06_joint_season_flow_advantage_20260709/tables/joint_regime_advantage_concentration.csv",
    ]
    assert manifest["outputs"]["deep_dive"] == expected_deep_dive_outputs
    baseline = pd.DataFrame(_load_snapshot_policy()["baseline_files"])
    expected_classified_outputs = set(
        baseline.loc[
            (baseline["classification"] == "external_archive") & baseline["path"].str.startswith("deep_dive/"),
            "path",
        ]
    )
    assert {f"deep_dive/{path}" for path in manifest["outputs"]["deep_dive"]} == expected_classified_outputs
    repro = out_dir / "reproducibility"
    inventory = pd.read_csv(repro / "snapshot_inventory.csv")
    external = pd.read_csv(repro / "external_inputs.csv")
    archive_bundle = pd.read_csv(repro / "external_archive_bundle.csv")
    evidence = pd.read_csv(repro / "core_evidence_map.csv")
    outputs = pd.read_csv(repro / "top_level_output_hashes.csv")

    assert len(inventory) == 162
    assert inventory["path"].nunique() == 162
    assert inventory.groupby("classification").size().to_dict() == {
        "exclude": 110,
        "external_archive": 11,
        "regenerate": 27,
        "version_control": 14,
    }
    assert int(inventory["bytes"].sum()) == 356_424_245

    assert len(external) == 19
    assert set(external["status"]) == {"ok"}
    assert int(external["expected_bytes"].sum()) == 1_396_515
    assert len(archive_bundle) == 1
    assert archive_bundle.iloc[0]["status"] == "ok"
    assert int(archive_bundle.iloc[0]["member_count"]) == 19

    indexed = evidence.set_index("metric_id")
    assert float(indexed.loc["main.lstm_ensemble_8seed.median_nse", "value"]) == pytest.approx(
        0.7592252236337574
    )
    assert indexed.loc["main.lstm_ensemble_8seed.median_nse", "input_ids"] == "I07"
    assert float(indexed.loc["population.snow_fraction.quartile_median_difference", "value"]) == pytest.approx(
        0.0784895263090009
    )
    assert indexed.loc["population.snow_fraction.quartile_median_difference", "input_ids"] == "I09"
    assert float(indexed.loc["joint.snow_spring_high_flow.concentration_ratio", "value"]) == pytest.approx(
        4.904101004642379
    )
    assert indexed.loc["joint.snow_spring_high_flow.concentration_ratio", "input_ids"] == "I14"
    assert "diagnostic.xaj.median_abs_peak_bias" in indexed.index
    assert "regime.snow_dominated.median_lstm_minus_best_conceptual" in indexed.index
    assert "parameters.xaj_pdd.effective_active_parameters" in indexed.index
    assert set(evidence["output_file"]) <= {
        "tables/main_benchmark.csv",
        "tables/paired.csv",
        "tables/oracle.csv",
        "tables/lstm_advantage_concentration.csv",
        "reproducibility/population_evidence.csv",
        "tables/conceptual_diagnostics.csv",
        "tables/regime_summary.csv",
        "tables/parameter_accounting.csv",
    }
    for row in evidence.itertuples(index=False):
        actual = _select_csv_value(out_dir / row.output_file, row.output_selector)
        if isinstance(row.value, str):
            assert str(actual) == row.value
        else:
            assert float(actual) == pytest.approx(float(row.value))
    assert evidence["output_sha256"].str.fullmatch(r"[0-9a-f]{64}").all()

    assert len(outputs) == 14
    assert set(outputs["path"]) == set(_load_snapshot_policy()["top_level_outputs"])
    for row in outputs.itertuples(index=False):
        assert hashlib.sha256((out_dir / row.path).read_bytes()).hexdigest() == row.sha256
    rebuild = (repro / "REBUILD.md").read_text(encoding="utf-8")
    bundle_name = _load_snapshot_policy()["external_archive_bundle"]["path"]
    assert "one rebuild entry point" in rebuild
    assert rebuild.index("clean repository baseline") < rebuild.index("proposed_version_control_files")
    assert rebuild.index("proposed_version_control_files") < rebuild.index(bundle_name)
    assert rebuild.index(bundle_name) < rebuild.index("Expand-Archive")
    member_registry_marker = "paths listed in `external_inputs`"
    assert rebuild.index("Expand-Archive") < rebuild.index(member_registry_marker)
    assert rebuild.index(member_registry_marker) < rebuild.index("python -X utf8 -m")


def test_clean_repository_plus_registered_archive_rebuilds_the_same_14_outputs(tmp_path):
    policy = _load_snapshot_policy()
    registered_hashes = {
        relative: hashlib.sha256((PACKAGE / relative).read_bytes()).hexdigest()
        for relative in policy["top_level_outputs"]
    }
    reference = tmp_path / "reference_package"
    for item in policy["external_inputs"]:
        source = Path(item["path"])
        try:
            relative = source.relative_to(PACKAGE)
        except ValueError:
            continue
        destination = reference / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, destination)
    for name in [
            "D02_seasonal_residual_20260709",
            "D03_population_seasonal_residual_20260709",
            "DIAGNOSTIC_VERDICT.md",
            "FINAL_INNOVATION_AUDIT_20260709.md",
            "INNOVATION_VERDICT_20260709.md",
            "LITERATURE_GAP_RECHECK_20260709.md",
    ]:
        path = reference / "deep_dive" / name
        if path.suffix:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("excluded legacy working artifact\n", encoding="utf-8")
        else:
            path.mkdir(parents=True, exist_ok=True)
    build_package(reference)
    reference_hashes = {
        relative: hashlib.sha256((reference / relative).read_bytes()).hexdigest()
        for relative in policy["top_level_outputs"]
    }

    archive = tmp_path / "head.tar"
    subprocess.run(["git", "archive", "HEAD", "-o", str(archive)], check=True)
    clean_repo = tmp_path / "clean_repo"
    clean_repo.mkdir()
    with tarfile.open(archive) as tar:
        tar.extractall(clean_repo, filter="data")

    overlay = policy["proposed_version_control_files"]
    assert GENERATOR.as_posix() in overlay
    assert SNAPSHOT_POLICY.as_posix() in overlay
    assert set(policy["top_level_outputs"]) == {
        Path(path).relative_to(PACKAGE).as_posix()
        for path in map(Path, overlay)
        if PACKAGE in path.parents and path.parent == PACKAGE
    }
    for relative in overlay:
        source = Path(relative)
        destination = clean_repo / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, destination)
    bundle_source = Path(policy["external_archive_bundle"]["path"])
    bundle_destination = clean_repo / policy["external_archive_bundle"]["path"]
    bundle_destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(bundle_source, bundle_destination)
    with zipfile.ZipFile(bundle_destination) as zipped:
        zipped.extractall(clean_repo)
    replay_dir = clean_repo / PACKAGE / "audit" / "R01_saved_parameter_replay_current_code"
    assert {path.name for path in replay_dir.iterdir() if path.is_file()} == {
        "saved_parameter_replay_summary.csv"
    }

    command = [
        sys.executable,
        "-X",
        "utf8",
        "-m",
        "src.lstm_fair_531.scripts.build_manuscript_evidence_package",
        "--verify-snapshot",
    ]
    subprocess.run(command, cwd=clean_repo, check=True, capture_output=True, text=True)
    clean_package = clean_repo / PACKAGE
    first_hashes = {
        relative: hashlib.sha256((clean_package / relative).read_bytes()).hexdigest()
        for relative in policy["top_level_outputs"]
    }
    subprocess.run(command, cwd=clean_repo, check=True, capture_output=True, text=True)
    second_hashes = {
        relative: hashlib.sha256((clean_package / relative).read_bytes()).hexdigest()
        for relative in policy["top_level_outputs"]
    }

    assert first_hashes == reference_hashes
    assert first_hashes == registered_hashes
    assert second_hashes == first_hashes
