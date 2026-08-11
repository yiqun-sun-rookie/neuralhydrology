import json
import subprocess
from pathlib import Path

import pytest


MODULE_ROOT = Path(__file__).resolve().parents[1]
POLICY_PATH = MODULE_ROOT / "protocols" / "automatic_rehearsal_v1.json"


def _initialize_repo(repo: Path) -> None:
    repo.mkdir()
    subprocess.run(["git", "init", "-q"], cwd=repo, check=True)


def test_frozen_policy_proposes_exactly_three_distinct_result_independent_candidates():
    from unified_autoresearch.workflow.automatic_rehearsal import load_and_validate_rehearsal_policy

    policy = load_and_validate_rehearsal_policy(POLICY_PATH)

    assert policy["schema_version"] == "automatic_rehearsal_policy_v1"
    assert policy["proposal_budget"] == 3
    assert policy["proposal_inputs"] == [
        "approved_candidate_catalog",
        "declared_resource_budget",
        "prediction_information_contract",
    ]
    assert policy["result_dependent_proposal_inputs"] is False
    assert policy["recommendation_rule"] == "descending_median_mean_nse_then_candidate_id_v1"
    assert len(policy["proposals"]) == 3
    assert len({proposal["candidate_id"] for proposal in policy["proposals"]}) == 3
    assert len({proposal["category"] for proposal in policy["proposals"]}) == 3
    assert all(proposal["seed"] == 29 for proposal in policy["proposals"])


@pytest.mark.parametrize(
    "mutation",
    [
        lambda value: value.update({"proposal_budget": 2}),
        lambda value: value.update({"result_dependent_proposal_inputs": True}),
        lambda value: value["candidate_pool"][1].update(
            {"category": value["candidate_pool"][0]["category"]}
        ),
        lambda value: value["candidate_pool"][1].update(
            {"candidate_id": value["candidate_pool"][0]["candidate_id"]}
        ),
    ],
)
def test_invalid_policy_is_rejected_before_an_output_parent_is_created(tmp_path, mutation):
    from unified_autoresearch.workflow.automatic_rehearsal import freeze_rehearsal_proposals

    value = json.loads(POLICY_PATH.read_text(encoding="utf-8"))
    mutation(value)
    invalid_path = tmp_path / "invalid-policy.json"
    invalid_path.write_text(json.dumps(value), encoding="utf-8")
    proposal_registry_path = tmp_path / "absent" / "PROPOSAL_REGISTRY.json"

    with pytest.raises(ValueError):
        freeze_rehearsal_proposals(invalid_path, proposal_registry_path)

    assert not proposal_registry_path.parent.exists()


def test_rehearsal_runs_three_candidates_and_recommends_one_from_development_only(
    tmp_path, monkeypatch, frozen_dependencies_for_active_environment
):
    import unified_autoresearch.workflow.automatic_rehearsal as rehearsal
    from unified_autoresearch.runtime.resources import ResourceSnapshot

    repo = tmp_path / "repo"
    _initialize_repo(repo)
    package_root = repo / "packages"
    package_root.mkdir()
    package_manifest_path = package_root / "PACKAGE_MANIFEST.json"
    package_manifest_path.write_text("{}\n", encoding="utf-8")
    output_root = repo / "runs" / "three-candidate-rehearsal"
    expected_candidate_scores = {
        "hbv-lite-calibrated-v1": 0.2,
        "reference-deep-learning-v1": 0.5,
        "reference-fusion-v1": 0.3,
    }
    calls = []

    monkeypatch.setattr(
        rehearsal,
        "_validate_package",
        lambda package_root, expected_manifest_sha256: (
            package_manifest_path,
            {
                "schema_version": "development_packages_v1",
                "basins": json.loads(
                    (MODULE_ROOT / "selection" / "development_basins_v1.json").read_text(
                        encoding="utf-8"
                    )
                )["basins"],
                "source_manifest_sha256": "source-sha256",
            },
        ),
    )

    def fake_single_candidate(*, materialize, output_root, **kwargs):
        assert (output_root.parent.parent / "PROPOSAL_REGISTRY.json").is_file()
        output_root.mkdir(parents=True)
        materialized = materialize(output_root=output_root / "candidate")
        candidate_id = materialized.descriptor.candidate_id
        category = materialized.descriptor.category
        score = expected_candidate_scores[candidate_id]
        calls.append(candidate_id)
        protocols = {}
        for protocol in ("forward", "reverse"):
            for mode in ("train", "predict"):
                run_root = output_root / "runs" / protocol / mode
                log_root = run_root / "logs"
                log_root.mkdir(parents=True)
                (log_root / "runtime-result.json").write_text(
                    json.dumps(
                        {
                            "status": "succeeded",
                            "process_exit_code": 0,
                            "normalized_exit_code": 0,
                            "denied_event_count": 0,
                            "required_outputs_complete": True,
                            "output_contract": {"valid": True, "failures": []},
                        }
                    )
                    + "\n",
                    encoding="utf-8",
                )
                (log_root / "access.jsonl").write_text("", encoding="utf-8")
            protocols[protocol] = {
                "train_run_root": f"runs/{protocol}/train",
                "predict_run_root": f"runs/{protocol}/predict",
                "train": {
                    "status": "succeeded",
                    "process_exit_code": 0,
                    "normalized_exit_code": 0,
                    "denied_event_count": 0,
                },
                "predict": {
                    "status": "succeeded",
                    "process_exit_code": 0,
                    "normalized_exit_code": 0,
                    "denied_event_count": 0,
                },
            }
        result = {
            "candidate_id": candidate_id,
            "category": category,
            "basin_count": 8,
            "protocol_count": 2,
            "registered_run_count": 4,
            "score_report_count": 2,
            "cell_count": 8,
            "protocols": protocols,
            "cells": [
                {
                    "candidate_id": candidate_id,
                    "category": category,
                    "basin": f"{index:08d}",
                    "forward_nse": score,
                    "reverse_nse": score,
                    "mean_nse": score,
                }
                for index in range(8)
            ],
        }
        (output_root / "CANDIDATE_SUMMARY.json").write_text(
            json.dumps(result, sort_keys=True) + "\n", encoding="utf-8"
        )
        return result

    monkeypatch.setattr(rehearsal, "run_single_candidate_development", fake_single_candidate)

    result = rehearsal.run_automatic_rehearsal(
        repo_root=repo,
        package_root=package_root,
        expected_package_manifest_sha256="package-sha256",
        policy_path=POLICY_PATH,
        output_root=output_root,
        resource_snapshot=ResourceSnapshot(
            available_cpu_cores=4,
            available_gpu_count=0,
            available_memory_gb=4.0,
            free_disk_gb=10.0,
        ),
        candidate_dependencies=frozen_dependencies_for_active_environment,
    )

    assert calls == [
        "hbv-lite-calibrated-v1",
        "reference-deep-learning-v1",
        "reference-fusion-v1",
    ]
    assert result["schema_version"] == "automatic_rehearsal_v1"
    assert result["candidate_count"] == 3
    assert result["registered_run_count"] == 12
    assert result["score_report_count"] == 6
    assert result["protocol_basin_metric_count"] == 48
    assert result["cell_count"] == 24
    assert result["total_denied_event_count"] == 0
    assert result["recommended_candidate_id"] == "reference-deep-learning-v1"
    assert len([row for row in result["ranking"] if row["recommended_for_64_basin_validation"]]) == 1
    assert result["sealed_final_evaluation_read_or_scored"] is False
    assert result["fair_benchmark_scoring_program_run"] is False
    assert result["formal_basin_search_run"] is False
    assert result["baseline_outperformance_claimed"] is False
    assert json.loads((output_root / "REHEARSAL_SUMMARY.json").read_text(encoding="utf-8")) == result

    with pytest.raises(FileExistsError):
        rehearsal.run_automatic_rehearsal(
            repo_root=repo,
            package_root=package_root,
            expected_package_manifest_sha256="package-sha256",
            policy_path=POLICY_PATH,
            output_root=output_root,
            resource_snapshot=ResourceSnapshot(
                available_cpu_cores=4,
                available_gpu_count=0,
                available_memory_gb=4.0,
                free_disk_gb=10.0,
            ),
            candidate_dependencies=frozen_dependencies_for_active_environment,
        )


def test_rehearsal_stops_when_a_registered_process_has_a_denial():
    from unified_autoresearch.workflow.automatic_rehearsal import validate_candidate_result

    candidate_result = {
        "basin_count": 8,
        "protocol_count": 2,
        "registered_run_count": 4,
        "score_report_count": 2,
        "cell_count": 8,
        "cells": [{"mean_nse": 0.1}] * 8,
        "protocols": {
            protocol: {
                mode: {
                    "status": "succeeded",
                    "process_exit_code": 0,
                    "normalized_exit_code": 0,
                    "denied_event_count": int(protocol == "reverse" and mode == "predict"),
                }
                for mode in ("train", "predict")
            }
            for protocol in ("forward", "reverse")
        },
    }

    with pytest.raises(RuntimeError, match="denied event"):
        validate_candidate_result(candidate_result, expected_basin_count=8)


def test_raw_runtime_evidence_rejects_an_incomplete_output_contract(tmp_path):
    from unified_autoresearch.workflow.automatic_rehearsal import validate_candidate_runtime_evidence

    protocols = {}
    for protocol in ("forward", "reverse"):
        protocols[protocol] = {}
        for mode in ("train", "predict"):
            relative = Path("runs") / protocol / mode
            protocols[protocol][f"{mode}_run_root"] = relative.as_posix()
            protocols[protocol][mode] = {"denied_event_count": 0}
            log_root = tmp_path / relative / "logs"
            log_root.mkdir(parents=True)
            complete = not (protocol == "reverse" and mode == "predict")
            (log_root / "runtime-result.json").write_text(
                json.dumps(
                    {
                        "status": "succeeded",
                        "process_exit_code": 0,
                        "normalized_exit_code": 0,
                        "denied_event_count": 0,
                        "required_outputs_complete": complete,
                        "output_contract": {"valid": complete, "failures": [] if complete else ["missing"]},
                    }
                )
                + "\n",
                encoding="utf-8",
            )
            (log_root / "access.jsonl").write_text("", encoding="utf-8")

    with pytest.raises(RuntimeError, match="output contract"):
        validate_candidate_runtime_evidence(tmp_path, {"protocols": protocols})
