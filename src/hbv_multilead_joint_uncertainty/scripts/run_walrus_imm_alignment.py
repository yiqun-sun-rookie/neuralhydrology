"""Cross-code alignment: this repo's MUKF/IMM vs MATLAB trackingUKF/trackingIMM.

Executes the four frozen gates of ``walrus_imm_alignment_v01`` (see
``docs/plans/2026-07-22-walrus-imm-alignment-design.md``): input consistency,
WALRUS open-loop replay, twelve single-filter runs, and the interacting
multiple-model probability trajectory, all against the submission workspace
``updated_results_params_10.mat`` (read-only, hash-verified).
"""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import sys
from pathlib import Path

import numpy as np
import scipy.io as sio

REPO_ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(REPO_ROOT / "src"))

from hbv_joint_uncertainty.imm import InteractingMultipleModel  # noqa: E402
from hbv_joint_uncertainty.sigma_filter import ModifiedUnscentedFilter  # noqa: E402
from hbv_multilead_joint_uncertainty.walrus_port import statetran  # noqa: E402
from hbv_multilead_joint_uncertainty.scripts.run_candidate_likelihood_identifiability import (  # noqa: E402
    _checksums_for_directory,
    _environment,
    _json_write,
)
from hbv_multilead_joint_uncertainty.scripts.run_three_stage_switching_validation import (  # noqa: E402
    _replace_directory_with_retries,
    _validate_output_is_disjoint_from_protected_paths,
)

UT_ALPHA = 0.6874
UT_BETA = 2.0
UT_KAPPA = -2.0
N_CANDIDATES = 12
N_STATE = 5
KEEP_PROBABILITY = 0.99


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for block in iter(lambda: handle.read(1 << 20), b""):
            digest.update(block)
    return digest.hexdigest()


def _load_workspace(mat_path: Path) -> dict:
    raw = sio.loadmat(str(mat_path), squeeze_me=False)
    data = {}
    for key in ("p", "etpot", "qobs", "noise_r_truth"):
        data[key] = np.asarray(raw[key], dtype=np.float64).reshape(-1)
    data["noise_q_truth"] = np.asarray(raw["noise_q_truth"], dtype=np.float64)
    data["state0"] = np.asarray(raw["state0"], dtype=np.float64).reshape(-1)
    data["p0"] = np.asarray(raw["p0"], dtype=np.float64)
    for key in ("cw", "cv", "cg", "cq"):
        data[key] = np.asarray(raw[key], dtype=np.float64).reshape(-1)
    for key in ("cw_truth", "cv_truth", "cg_truth", "cq_truth"):
        data[key] = np.asarray(raw[key], dtype=np.float64).reshape(-1)
    data["cd"] = float(np.asarray(raw["cd"], dtype=np.float64).reshape(-1)[0])
    data["cs"] = float(np.asarray(raw["cs"], dtype=np.float64).reshape(-1)[0])
    data["r"] = float(np.asarray(raw["r"], dtype=np.float64).reshape(-1)[0])
    data["t1_2"] = int(np.asarray(raw["t1_2"]).reshape(-1)[0])
    data["t2_3"] = int(np.asarray(raw["t2_3"]).reshape(-1)[0])
    data["states_obs"] = np.asarray(raw["states_obs"], dtype=np.float64)
    data["imm_probs"] = np.asarray(raw["imm_probs"], dtype=np.float64)
    data["states_upd_imm"] = np.asarray(raw["states_upd_imm"], dtype=np.float64)

    q_s_all_cell = raw["q_s_all"]
    data["q_s_all"] = [
        np.asarray(q_s_all_cell[0, index], dtype=np.float64) for index in range(q_s_all_cell.shape[1])
    ]
    updated_cell = raw["states_upd_filters"]
    data["states_upd_filters"] = [
        np.asarray(updated_cell[index, 0], dtype=np.float64) for index in range(updated_cell.shape[0])
    ]
    return data


def _gate0_input_consistency(data: dict, gate_config: dict) -> dict:
    checks = {}
    checks["qobs_equals_states_obs_last_column"] = bool(
        np.array_equal(data["qobs"], data["states_obs"][:, 4])
    )
    checks["t1_2"] = {"expected": gate_config["t1_2"], "actual": data["t1_2"]}
    checks["t2_3"] = {"expected": gate_config["t2_3"], "actual": data["t2_3"]}
    checks["total_length"] = {
        "expected": gate_config["total_length"],
        "actual": int(len(data["qobs"])),
    }
    truth_rows_match = True
    for name in ("cw", "cv", "cg", "cq"):
        for offset, phase in ((10, 0), (11, 1)):
            if data[name][offset] != data[f"{name}_truth"][phase]:
                truth_rows_match = False
    checks["candidate_rows_11_12_equal_truth_phase_1_2"] = truth_rows_match
    checks["r"] = {"expected": gate_config["r"], "actual": data["r"]}
    expected_p0 = np.diag((0.001 * data["state0"]) ** 2)
    checks["p0_rule"] = bool(np.allclose(data["p0"], expected_p0, rtol=0.0, atol=0.0))
    expected_q = 1e-6 * np.diag(np.array([140.0, 1000.0, 4.0, 1200.0, 0.0]))
    checks["q_s_all_rule"] = bool(
        len(data["q_s_all"]) == N_CANDIDATES
        and all(np.array_equal(matrix, expected_q) for matrix in data["q_s_all"])
    )
    theory_std = np.sqrt(np.diag(expected_q))
    empirical_std = data["noise_q_truth"].std(axis=0, ddof=1)
    nonzero = theory_std > 0.0
    checks["noise_std_consistency"] = bool(
        np.all(np.abs(empirical_std[nonzero] / theory_std[nonzero] - 1.0) <= 0.05)
        and np.all(data["noise_q_truth"][:, ~nonzero] == 0.0)
    )
    passed = (
        checks["qobs_equals_states_obs_last_column"]
        and checks["t1_2"]["actual"] == checks["t1_2"]["expected"]
        and checks["t2_3"]["actual"] == checks["t2_3"]["expected"]
        and checks["total_length"]["actual"] == checks["total_length"]["expected"]
        and truth_rows_match
        and checks["r"]["actual"] == checks["r"]["expected"]
        and checks["p0_rule"]
        and checks["q_s_all_rule"]
        and checks["noise_std_consistency"]
    )
    return {"passed": bool(passed), "checks": checks}


def _truth_phase_parameters(data: dict, one_based_step: int) -> tuple[float, float, float, float]:
    if one_based_step <= data["t1_2"]:
        phase = 0
    elif one_based_step <= data["t2_3"]:
        phase = 1
    else:
        phase = 2
    return (
        data["cw_truth"][phase],
        data["cv_truth"][phase],
        data["cg_truth"][phase],
        data["cq_truth"][phase],
    )


def _gate1_open_loop(data: dict, threshold: float) -> tuple[dict, np.ndarray]:
    total = len(data["qobs"])
    replay = np.zeros((total, N_STATE), dtype=np.float64)
    replay[0] = data["state0"]
    for index in range(1, total):
        one_based = index + 1
        cw, cv, cg, cq = _truth_phase_parameters(data, one_based)
        replay[index] = statetran(
            replay[index - 1],
            data["p"][index - 1],
            data["etpot"][index - 1],
            data["noise_q_truth"][index],
            cw=cw,
            cv=cv,
            cg=cg,
            cq=cq,
            cd=data["cd"],
            cs=data["cs"],
        )
    replay[:, 4] = replay[:, 4] + data["noise_r_truth"]
    difference = np.abs(replay - data["states_obs"])
    max_abs_diff = float(difference.max())
    exceed_positions = np.argwhere(difference > threshold)
    first_exceed_step = int(exceed_positions[0, 0]) + 1 if len(exceed_positions) else None
    result = {
        "passed": bool(max_abs_diff <= threshold),
        "max_abs_diff": max_abs_diff,
        "threshold": threshold,
        "first_exceed_step_one_based": first_exceed_step,
        "per_state_max_abs_diff": [float(value) for value in difference.max(axis=0)],
    }
    return result, difference


def _make_transition(data: dict, candidate: int, forcing_index: int):
    cw = data["cw"][candidate]
    cv = data["cv"][candidate]
    cg = data["cg"][candidate]
    cq = data["cq"][candidate]
    p_t = data["p"][forcing_index]
    etpot_t = data["etpot"][forcing_index]
    zero_noise = np.zeros(N_STATE, dtype=np.float64)

    def transition(state: np.ndarray) -> np.ndarray:
        return statetran(
            state, p_t, etpot_t, zero_noise,
            cw=cw, cv=cv, cg=cg, cq=cq, cd=data["cd"], cs=data["cs"],
        )

    return transition


def _observe(state: np.ndarray) -> np.ndarray:
    return np.array([state[4]], dtype=np.float64)


def _build_filter(data: dict, candidate: int) -> ModifiedUnscentedFilter:
    return ModifiedUnscentedFilter(
        state=data["state0"].copy(),
        covariance=data["p0"].copy(),
        transition=_make_transition(data, candidate, 0),
        observation=_observe,
        process_covariance=data["q_s_all"][candidate].copy(),
        observation_covariance=np.array([[data["r"]]], dtype=np.float64),
        alpha=UT_ALPHA,
        beta=UT_BETA,
        kappa=UT_KAPPA,
    )


def _gate2_single_filters(data: dict, tolerance_scale: float) -> tuple[dict, list[np.ndarray]]:
    total = len(data["qobs"])
    per_filter = []
    trajectories = []
    for candidate in range(N_CANDIDATES):
        sub_filter = _build_filter(data, candidate)
        updated = np.zeros((total, N_STATE), dtype=np.float64)
        updated[0] = data["state0"]
        first_exceed = None
        for index in range(1, total):
            sub_filter.transition = _make_transition(data, candidate, index - 1)
            sub_filter.predict()
            result = sub_filter.update(np.array([data["qobs"][index]]))
            updated[index] = result.posterior_state
        reference = data["states_upd_filters"][candidate]
        tolerance = tolerance_scale * np.maximum(1.0, np.abs(reference))
        exceed_mask = np.abs(updated - reference) > tolerance
        exceed_rows = np.argwhere(exceed_mask.any(axis=1)).reshape(-1)
        if len(exceed_rows):
            first_exceed = int(exceed_rows[0]) + 1
        per_filter.append(
            {
                "candidate_one_based": candidate + 1,
                "first_exceed_step_one_based": first_exceed,
                "max_abs_diff": float(np.abs(updated - reference).max()),
            }
        )
        trajectories.append(updated)
    strong_pass = all(entry["first_exceed_step_one_based"] is None for entry in per_filter)
    return {"strong_pass": bool(strong_pass), "per_filter": per_filter}, trajectories


def _anchor_metrics(probs: np.ndarray, data: dict) -> dict:
    anchors = {}
    phases = [
        ("phase1", 0, data["t1_2"], 10),
        ("phase2", data["t1_2"], data["t2_3"], 11),
    ]
    for label, start, stop, true_index in phases:
        window = probs[start:stop]
        argmax = np.argmax(window, axis=1)
        is_top = argmax == true_index
        first_top = int(np.argmax(is_top)) + 1 if bool(is_top.any()) else None
        stable_top = None
        if bool(is_top.any()):
            not_top_positions = np.argwhere(~is_top).reshape(-1)
            last_not_top = int(not_top_positions[-1]) if len(not_top_positions) else -1
            if last_not_top < len(is_top) - 1:
                stable_top = last_not_top + 2
        anchors[label] = {
            "true_filter_mean_prob": float(window[:, true_index].mean()),
            "first_top_cycle": first_top,
            "stable_top_cycle": stable_top,
        }
    return anchors


def _gate3_imm(data: dict, gate_config: dict) -> tuple[dict, np.ndarray]:
    total = len(data["qobs"])
    filters = [_build_filter(data, candidate) for candidate in range(N_CANDIDATES)]
    off_diagonal = (1.0 - KEEP_PROBABILITY) / (N_CANDIDATES - 1)
    transition_matrix = np.full((N_CANDIDATES, N_CANDIDATES), off_diagonal, dtype=np.float64)
    np.fill_diagonal(transition_matrix, KEEP_PROBABILITY)
    imm = InteractingMultipleModel(
        filters=filters,
        transition_matrix=transition_matrix,
        initial_probabilities=np.full(N_CANDIDATES, 1.0 / N_CANDIDATES, dtype=np.float64),
        parameter_groups=list(range(N_CANDIDATES)),
    )
    imm.interaction_mode = "full"
    probs = np.zeros((total, N_CANDIDATES), dtype=np.float64)
    probs[0] = imm.probabilities
    for index in range(1, total):
        for candidate, sub_filter in enumerate(imm.filters):
            sub_filter.transition = _make_transition(data, candidate, index - 1)
        step = imm.step(np.array([data["qobs"][index]]))
        probs[index] = step.posterior_probabilities

    prob_diff = np.abs(probs - data["imm_probs"])
    max_abs_prob_diff = float(prob_diff.max())
    strong_pass = max_abs_prob_diff <= gate_config["strong_pass_max_abs_prob_diff"]

    reference_anchors = _anchor_metrics(data["imm_probs"], data)
    python_anchors = _anchor_metrics(probs, data)
    tolerances = gate_config["anchor_metrics"]["anchor_pass_tolerances"]
    anchor_rows = []
    anchors_pass = True
    for label in ("phase1", "phase2"):
        for metric in ("true_filter_mean_prob", "first_top_cycle", "stable_top_cycle"):
            reference_value = reference_anchors[label][metric]
            python_value = python_anchors[label][metric]
            if metric == "true_filter_mean_prob":
                tolerance = tolerances["mean_prob"]
            else:
                tolerance = tolerances["cycles"]
            if reference_value is None or python_value is None:
                within = reference_value is None and python_value is None
            else:
                within = abs(python_value - reference_value) <= tolerance
            anchors_pass = anchors_pass and within
            anchor_rows.append(
                {
                    "phase": label,
                    "metric": metric,
                    "matlab_reference": reference_value,
                    "python": python_value,
                    "tolerance": tolerance,
                    "within_tolerance": bool(within),
                }
            )
    result = {
        "strong_pass": bool(strong_pass),
        "max_abs_prob_diff": max_abs_prob_diff,
        "anchors_pass": bool(anchors_pass),
        "anchor_rows": anchor_rows,
        "reference_anchors_vs_config": {
            "config_recorded": gate_config["anchor_metrics"],
            "recomputed_from_reference": reference_anchors,
        },
    }
    return result, probs


def _verdict(gate1: dict, gate2: dict, gate3: dict) -> str:
    if gate1["passed"] and gate2["strong_pass"] and gate3["strong_pass"]:
        return "数值一致"
    if gate1["passed"] and gate3["anchors_pass"]:
        return "结构等价"
    if gate1["passed"]:
        return "部分等价"
    return "不等价"


def run(config_path: Path, output_dir: Path) -> dict:
    started_at = dt.datetime.now(dt.timezone.utc).isoformat()
    config_bytes = config_path.read_bytes()
    config = json.loads(config_bytes.decode("utf-8"))

    mat_config = config["inputs"]["reference_mat"]
    mat_path = Path(mat_config["path"])
    actual_hash = _sha256(mat_path)
    if actual_hash != mat_config["sha256"]:
        raise RuntimeError(
            f"reference mat hash mismatch: expected {mat_config['sha256']}, got {actual_hash}"
        )

    incomplete = output_dir.with_name(output_dir.name + ".incomplete")
    if output_dir.exists() or incomplete.exists():
        raise RuntimeError(f"output already exists: {output_dir} or {incomplete}")
    _validate_output_is_disjoint_from_protected_paths(incomplete, [mat_path.parent])

    data = _load_workspace(mat_path)
    preflight = {
        "loaded_reference_bytes": int(mat_path.stat().st_size),
        "working_array_bytes_estimate": int(
            (4 * data["states_obs"].nbytes) + (N_CANDIDATES + 1) * data["imm_probs"].nbytes
        ),
        "note": "all arrays are megabyte-scale; no memory gate required",
    }

    gate0 = _gate0_input_consistency(data, config["gates"]["g0_input_consistency"])
    if not gate0["passed"]:
        raise RuntimeError(f"gate G0 failed: {json.dumps(gate0['checks'], default=str)}")

    gate1, g1_difference = _gate1_open_loop(
        data, config["gates"]["g1_walrus_open_loop"]["pass_threshold_max_abs_diff"]
    )
    if gate1["passed"]:
        gate2, _ = _gate2_single_filters(
            data, 1e-6
        )
        gate3, python_probs = _gate3_imm(data, config["gates"]["g3_imm"])
    else:
        gate2 = {"strong_pass": False, "per_filter": [], "skipped": "G1 failed"}
        gate3 = {
            "strong_pass": False,
            "anchors_pass": False,
            "anchor_rows": [],
            "skipped": "G1 failed",
        }
        python_probs = np.zeros_like(data["imm_probs"])

    verdict = _verdict(gate1, gate2, gate3)
    ended_at = dt.datetime.now(dt.timezone.utc).isoformat()
    summary = {
        "experiment": config["experiment"],
        "verdict_tier": verdict,
        "gate0": gate0,
        "gate1": gate1,
        "gate2": gate2,
        "gate3": {key: value for key, value in gate3.items() if key != "anchor_rows"},
        "started_at": started_at,
        "ended_at": ended_at,
        "reference_mat_sha256": actual_hash,
        "config_sha256": hashlib.sha256(config_bytes).hexdigest(),
    }

    incomplete.mkdir(parents=True, exist_ok=False)
    try:
        (incomplete / "config_snapshot.json").write_bytes(config_bytes)
        _json_write(incomplete / "resource_preflight.json", preflight)
        _json_write(incomplete / "gate_results.json", summary)
        np.savez_compressed(
            incomplete / "g1_replay_diff.npz",
            max_abs_diff_per_step=g1_difference.max(axis=1),
            per_state_max=g1_difference.max(axis=0),
        )
        if gate1["passed"]:
            with open(incomplete / "g2_first_exceed.csv", "w", encoding="utf-8", newline="\n") as handle:
                handle.write("candidate_one_based,first_exceed_step_one_based,max_abs_diff\n")
                for entry in gate2["per_filter"]:
                    handle.write(
                        f"{entry['candidate_one_based']},"
                        f"{entry['first_exceed_step_one_based']},"
                        f"{entry['max_abs_diff']:.12e}\n"
                    )
            np.savez_compressed(
                incomplete / "g3_prob_diff.npz",
                python_probs=python_probs,
                reference_probs=data["imm_probs"],
            )
            with open(incomplete / "g3_anchor_comparison.csv", "w", encoding="utf-8", newline="\n") as handle:
                handle.write("phase,metric,matlab_reference,python,tolerance,within_tolerance\n")
                for row in gate3["anchor_rows"]:
                    handle.write(
                        f"{row['phase']},{row['metric']},{row['matlab_reference']},"
                        f"{row['python']},{row['tolerance']},{row['within_tolerance']}\n"
                    )
        report_lines = [
            "# 跨码对齐结果：本仓 MUKF/IMM vs MATLAB trackingUKF/trackingIMM",
            "",
            f"- 判定档位（预冻结分级）：**{verdict}**",
            f"- G0 输入自洽：{'通过' if gate0['passed'] else '失败'}",
            f"- G1 WALRUS 开环最大绝对差：{gate1['max_abs_diff']:.3e}（门槛 {gate1['threshold']:.0e}，"
            f"{'通过' if gate1['passed'] else '失败'}）",
            f"- G2 单滤波器强判据：{'通过' if gate2.get('strong_pass') else '未通过'}",
            f"- G3 概率轨迹最大绝对差：{gate3.get('max_abs_prob_diff', float('nan')):.3e}；"
            f"锚点判据：{'通过' if gate3.get('anchors_pass') else '未通过'}",
            "",
            "详见 gate_results.json / g2_first_exceed.csv / g3_anchor_comparison.csv。",
        ]
        (incomplete / "alignment_report.md").write_text(
            "\n".join(report_lines) + "\n", encoding="utf-8"
        )
        _json_write(incomplete / "environment.json", _environment(REPO_ROOT, started_at))
        checksums = _checksums_for_directory(incomplete)
        _json_write(incomplete / "checksums.json", checksums)
    except BaseException:
        raise
    _replace_directory_with_retries(incomplete, output_dir)
    return summary


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--config",
        type=Path,
        default=REPO_ROOT / "src/hbv_multilead_joint_uncertainty/configs/walrus_imm_alignment_v02.json",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=REPO_ROOT / "results/23_hbv_multilead_joint_uncertainty/walrus_imm_alignment_v02",
    )
    arguments = parser.parse_args()
    summary = run(arguments.config, arguments.output)
    print(json.dumps({"verdict_tier": summary["verdict_tier"]}, ensure_ascii=False))


if __name__ == "__main__":
    main()
