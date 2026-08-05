"""Lead-time attribution tables, candidate diagnostics, and publication-ready plots."""

from __future__ import annotations

from pathlib import Path

import numpy as np
import pandas as pd


COMPARISON_PAIRS = (
    ("fixed_filter_vs_open_loop", "fixed_filter", "open_loop"),
    ("parameter_only_vs_fixed_filter", "parameter_only", "fixed_filter"),
    ("noise_only_vs_fixed_filter", "noise_only", "fixed_filter"),
    ("joint_vs_fixed_filter", "joint", "fixed_filter"),
    ("joint_vs_parameter_only", "joint", "parameter_only"),
    ("joint_vs_noise_only", "joint", "noise_only"),
)


def paired_method_comparisons(metrics: pd.DataFrame) -> pd.DataFrame:
    required = {"basin_id", "method", "lead_days", "rmse", "mae", "nse"}
    if not required.issubset(metrics.columns):
        raise ValueError(f"metrics are missing columns: {sorted(required - set(metrics.columns))}")
    if metrics.duplicated(["basin_id", "method", "lead_days"]).any():
        raise ValueError("metrics contain duplicate basin-method-lead rows")
    rows = []
    for comparison_id, challenger, reference in COMPARISON_PAIRS:
        for lead in sorted(metrics["lead_days"].unique()):
            challenger_rows = metrics.loc[
                (metrics["method"] == challenger) & (metrics["lead_days"] == lead),
                ["basin_id", "rmse", "mae", "nse"],
            ].set_index("basin_id")
            reference_rows = metrics.loc[
                (metrics["method"] == reference) & (metrics["lead_days"] == lead),
                ["basin_id", "rmse", "mae", "nse"],
            ].set_index("basin_id")
            if set(challenger_rows.index) != set(reference_rows.index) or challenger_rows.empty:
                raise ValueError(f"comparison {comparison_id} lead {lead} is not basin-paired")
            challenger_rows = challenger_rows.sort_index()
            reference_rows = reference_rows.loc[challenger_rows.index]
            if np.any(reference_rows["rmse"].to_numpy() <= 0.0):
                raise ValueError("root mean square error reference must be positive")
            rmse_difference = challenger_rows["rmse"] - reference_rows["rmse"]
            mae_difference = challenger_rows["mae"] - reference_rows["mae"]
            nse_difference = challenger_rows["nse"] - reference_rows["nse"]
            rmse_percent = 100.0 * rmse_difference / reference_rows["rmse"]
            rows.append(
                {
                    "comparison_id": comparison_id,
                    "challenger_method": challenger,
                    "reference_method": reference,
                    "lead_days": int(lead),
                    "basin_count": int(len(challenger_rows)),
                    "median_rmse_difference": float(rmse_difference.median()),
                    "median_rmse_change_percent": float(rmse_percent.median()),
                    "rmse_win_count": int((rmse_difference < 0.0).sum()),
                    "rmse_tie_count": int((rmse_difference == 0.0).sum()),
                    "median_mae_difference": float(mae_difference.median()),
                    "mae_win_count": int((mae_difference < 0.0).sum()),
                    "median_nse_difference": float(nse_difference.median()),
                    "nse_win_count": int((nse_difference > 0.0).sum()),
                }
            )
    return pd.DataFrame(rows)


def _candidate_probability_tables(result_directory: Path, basin_ids: list[str]):
    candidate_rows = []
    factor_rows = []
    for basin_id in basin_ids:
        with np.load(result_directory / "basins" / f"{basin_id}.npz") as arrays:
            leads = arrays["lead_days"]
            for method in ("open_loop", "fixed_filter", "parameter_only", "noise_only", "joint"):
                candidate_ids = tuple(str(value) for value in arrays[f"{method}__candidate_ids"].tolist())
                probabilities = arrays[f"{method}__probabilities"]
                for lead_index, lead in enumerate(leads):
                    lead_probabilities = probabilities[:, lead_index, :]
                    dominant = np.argmax(lead_probabilities, axis=1)
                    entropy = np.zeros(len(lead_probabilities), dtype=np.float64)
                    if len(candidate_ids) > 1:
                        positive = np.where(lead_probabilities > 0.0, lead_probabilities, 1.0)
                        entropy = -np.sum(
                            np.where(lead_probabilities > 0.0, lead_probabilities * np.log(positive), 0.0),
                            axis=1,
                        ) / np.log(len(candidate_ids))
                    for candidate_index, candidate_id in enumerate(candidate_ids):
                        candidate_rows.append(
                            {
                                "basin_id": basin_id,
                                "method": method,
                                "lead_days": int(lead),
                                "candidate_id": candidate_id,
                                "mean_probability": float(np.mean(lead_probabilities[:, candidate_index])),
                                "median_probability": float(np.median(lead_probabilities[:, candidate_index])),
                                "dominant_origin_count": int(np.sum(dominant == candidate_index)),
                                "origin_count": int(len(dominant)),
                                "mean_normalized_entropy": float(np.mean(entropy)),
                            }
                        )
                    if method == "joint":
                        parameter_ids = tuple(dict.fromkeys(value.split("__", 1)[0] for value in candidate_ids))
                        process_ids = tuple(dict.fromkeys(value.split("__", 1)[1] for value in candidate_ids))
                        for factor_type, identifiers, position in (
                            ("parameter", parameter_ids, 0),
                            ("process_noise", process_ids, 1),
                        ):
                            for identifier in identifiers:
                                indices = [
                                    index
                                    for index, candidate_id in enumerate(candidate_ids)
                                    if candidate_id.split("__", 1)[position] == identifier
                                ]
                                marginal = np.sum(lead_probabilities[:, indices], axis=1)
                                factor_rows.append(
                                    {
                                        "basin_id": basin_id,
                                        "lead_days": int(lead),
                                        "factor_type": factor_type,
                                        "factor_id": identifier,
                                        "mean_marginal_probability": float(np.mean(marginal)),
                                        "median_marginal_probability": float(np.median(marginal)),
                                    }
                                )
    return pd.DataFrame(candidate_rows), pd.DataFrame(factor_rows)


def _lead_time_plot(comparisons: pd.DataFrame, output: Path) -> None:
    import matplotlib

    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    colors = {
        "parameter_only_vs_fixed_filter": "#E69F00",
        "noise_only_vs_fixed_filter": "#56B4E9",
        "joint_vs_fixed_filter": "#009E73",
    }
    labels = {
        "parameter_only_vs_fixed_filter": "Three fixed parameter candidates",
        "noise_only_vs_fixed_filter": "Three fixed process-noise candidates",
        "joint_vs_fixed_filter": "Fixed parameter-process candidate grid",
    }
    figure, axes = plt.subplots(1, 2, figsize=(10.5, 4.2), constrained_layout=True)
    for comparison_id in colors:
        rows = comparisons.loc[comparisons["comparison_id"] == comparison_id].sort_values("lead_days")
        axes[0].plot(
            rows["lead_days"],
            rows["median_rmse_change_percent"],
            marker="o",
            linewidth=2.0,
            color=colors[comparison_id],
            label=labels[comparison_id],
        )
        axes[1].plot(
            rows["lead_days"],
            rows["median_nse_difference"],
            marker="o",
            linewidth=2.0,
            color=colors[comparison_id],
            label=labels[comparison_id],
        )
    for axis in axes:
        axis.axhline(0.0, color="#000000", linewidth=1.0, linestyle="--")
        axis.set_xticks([1, 3, 7])
        axis.set_xlabel("Lead time (days)")
        axis.grid(alpha=0.25)
    axes[0].set_ylabel("Median root mean square error change (%)")
    axes[1].set_ylabel("Median Nash-Sutcliffe efficiency change")
    axes[0].legend(frameon=False, fontsize=8)
    figure.savefig(output, dpi=220)
    plt.close(figure)


def build_study_report(
    comparisons: pd.DataFrame,
    cross_basin_summary: pd.DataFrame,
    metrics: pd.DataFrame,
) -> str:
    joint = comparisons.loc[comparisons["comparison_id"] == "joint_vs_fixed_filter"].sort_values(
        "lead_days"
    )
    effect_lines = [
        (
            f"- {int(row.lead_days)}天：均方根误差中位变化{row.median_rmse_change_percent:.3f}%，"
            f"{int(row.rmse_win_count)}/{int(row.basin_count)}个流域更低；"
            f"纳什—萨特克利夫效率系数中位变化{row.median_nse_difference:.6f}。"
        )
        for row in joint.itertuples()
    ]
    report = [
        "# 日尺度多预见期联合参数与过程噪声结果报告",
        "",
        "## 结论性数值",
        "",
        *effect_lines,
        "",
        "这些数值是严格成对的流域中位数；负的均方根误差变化表示误差降低。",
        "",
        "## 时间与输入边界",
        "",
        "起报日先用当日气象推进模型，再用当日实测流量更新状态；一天、三天和七天预测只读取起报日之后的实测气象，不读取未来流量。未来气象来自历史实测资料，因此这是诊断回报，不是业务预报。",
        "",
        "## 可核查文件",
        "",
        "- `paired_method_comparisons.csv`：每个预见期的成对方法差值与胜出流域数。",
        "- `candidate_probability_summary.csv`：每个候选的平均权重、中位权重和成为最高权重候选的次数。",
        "- `joint_factor_probability_summary.csv`：联合方法中参数因素和过程噪声因素的边际权重。",
        "- `contract_tables/parameter_vectors.csv`：每个流域三个完整参数向量的十三个数值。",
        "- `contract_tables/process_noise_covariances.csv`：每个流域三个过程噪声协方差的十五个对角元素。",
        "- `contract_tables/observation_noise.csv`：观测噪声标准差和方差。",
        "- `contract_tables/input_variables.csv`：输入字段、单位、变换、来源和日期范围。",
        "",
        "## 限制",
        "",
        "中心参数由1999年至2008年资料率定，评价窗口为1989年10月1日至1990年9月30日；结果不能解释气象预报误差，也不能外推为实时预报能力。",
        "",
        f"跨流域汇总包含{len(cross_basin_summary)}行，逐流域指标包含{len(metrics)}行。",
    ]
    return "\n".join(report) + "\n"


def write_result_diagnostics(
    result_directory: Path,
    metrics: pd.DataFrame,
    cross_basin_summary: pd.DataFrame,
    basin_ids: list[str],
) -> None:
    directory = Path(result_directory)
    comparisons = paired_method_comparisons(metrics)
    comparisons.to_csv(directory / "paired_method_comparisons.csv", index=False)
    candidate_probabilities, joint_factors = _candidate_probability_tables(directory, basin_ids)
    candidate_probabilities.to_csv(directory / "candidate_probability_summary.csv", index=False)
    joint_factors.to_csv(directory / "joint_factor_probability_summary.csv", index=False)
    _lead_time_plot(comparisons, directory / "lead_time_effects.png")

    (directory / "study_report.md").write_text(
        build_study_report(comparisons, cross_basin_summary, metrics),
        encoding="utf-8",
    )
