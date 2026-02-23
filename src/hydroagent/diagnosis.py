import numpy as np
import pandas as pd
from typing import Any, Dict, List
from scipy.signal import find_peaks, periodogram
from scipy.stats import wasserstein_distance


class HydroDiagnostician:
    """
    Module A: 诊断评价系统
    负责接收观测与模拟流量，生成结构化的病理报告和自然语言反馈。

    集成四个维度的先进方法：
    - 传统水文评价 (NSE, KGE, Low Flow Bias)
    - 模式识别与峰值匹配 (Windowed Peak Matching, Onset Detection)
    - 谱分析 (Periodogram Energy Ratio)
    - 最优传输 (Temporal Wasserstein Distance)
    """

    def __init__(self, cfg: Dict[str, Any] = None):
        cfg = cfg or {}
        self.window_hours = cfg.get('window_hours', 12)
        self.min_prominence_factor = cfg.get('min_prominence_factor', 0.05)

    def generate_report(self, obs: pd.Series, sim: pd.Series) -> Dict[str, Any]:
        """核心入口：计算指标并生成报告。"""
        obs_arr = np.asarray(obs, dtype=float)
        sim_arr = np.asarray(sim, dtype=float)

        nse = self._calc_nse(obs_arr, sim_arr)
        kge = self._calc_kge(obs_arr, sim_arr)
        peak_info = self._windowed_peak_matching(obs_arr, sim_arr)
        low_flow_bias = self._calc_low_flow_bias(obs_arr, sim_arr)
        spectral_ratio = self._calc_spectral_ratio(obs_arr, sim_arr)
        wass_dist = self._calc_wasserstein(obs_arr, sim_arr)
        onset_lag = self._calc_onset_lag(obs_arr, sim_arr)

        metrics = {
            'NSE': round(nse, 4),
            'KGE': round(kge, 4),
            'Peak_Lag_Hours': round(peak_info['peak_lag'], 1),
            'Peak_MAPE': round(peak_info['peak_mape'], 4),
            'Low_Flow_Bias': round(low_flow_bias, 4),
            'High_Freq_Energy_Ratio': round(spectral_ratio, 4),
            'Temporal_Wasserstein_Dist': round(wass_dist, 2),
            'Onset_Lag_Hours': round(onset_lag, 1),
        }

        feedback = self._generate_feedback(metrics)
        return {'metrics': metrics, 'semantic_feedback': feedback}

    # ------------------------------------------------------------------
    # 传统水文指标
    # ------------------------------------------------------------------

    def _calc_nse(self, obs: np.ndarray, sim: np.ndarray) -> float:
        denominator = np.sum((obs - np.mean(obs)) ** 2)
        if denominator == 0:
            return 1.0 if np.allclose(obs, sim) else -np.inf
        return 1.0 - np.sum((obs - sim) ** 2) / denominator

    def _calc_kge(self, obs: np.ndarray, sim: np.ndarray) -> float:
        r = np.corrcoef(obs, sim)[0, 1] if np.std(obs) > 0 and np.std(sim) > 0 else 0.0
        alpha = np.std(sim) / np.std(obs) if np.std(obs) > 0 else 0.0
        beta = np.mean(sim) / np.mean(obs) if np.mean(obs) != 0 else 0.0
        return 1.0 - np.sqrt((r - 1) ** 2 + (alpha - 1) ** 2 + (beta - 1) ** 2)

    # ------------------------------------------------------------------
    # 模式识别：峰值匹配
    # ------------------------------------------------------------------

    def _windowed_peak_matching(self, obs: np.ndarray, sim: np.ndarray) -> Dict[str, float]:
        """基于 Prominence 的窗口贪心峰值匹配，抗双峰干扰。"""
        min_prominence = self.min_prominence_factor * (np.max(obs) - np.min(obs))
        min_prominence = max(min_prominence, 0.1)

        obs_peaks, obs_props = find_peaks(obs, prominence=min_prominence)
        sim_peaks, sim_props = find_peaks(sim, prominence=min_prominence)

        if len(obs_peaks) == 0:
            return {'peak_lag': 0.0, 'peak_mape': 0.0}

        window = self.window_hours
        lags = []
        mapes = []
        used_sim = set()

        # 按 prominence 降序排列观测峰，优先匹配主峰
        obs_order = np.argsort(-obs_props['prominences'])
        for idx in obs_order:
            o_peak = obs_peaks[idx]
            best_s = None
            best_dist = window + 1
            for j, s_peak in enumerate(sim_peaks):
                if j in used_sim:
                    continue
                dist = abs(int(s_peak) - int(o_peak))
                if dist <= window and dist < best_dist:
                    best_dist = dist
                    best_s = j
            if best_s is not None:
                used_sim.add(best_s)
                lags.append(int(sim_peaks[best_s]) - int(o_peak))
                obs_val = obs[o_peak]
                sim_val = sim[sim_peaks[best_s]]
                if obs_val > 0:
                    mapes.append(abs(sim_val - obs_val) / obs_val)

        peak_lag = float(np.mean(lags)) if lags else 0.0
        peak_mape = float(np.mean(mapes)) if mapes else 0.0
        return {'peak_lag': peak_lag, 'peak_mape': peak_mape}

    # ------------------------------------------------------------------
    # 枯水期偏差
    # ------------------------------------------------------------------

    def _calc_low_flow_bias(self, obs: np.ndarray, sim: np.ndarray) -> float:
        threshold = np.percentile(obs, 25)
        mask = obs <= threshold
        if not np.any(mask):
            return 0.0
        obs_low = obs[mask]
        sim_low = sim[mask]
        mean_obs = np.mean(obs_low)
        if mean_obs == 0:
            return 0.0
        return float((np.mean(sim_low) - mean_obs) / mean_obs)

    # ------------------------------------------------------------------
    # 谱分析：高频能量比
    # ------------------------------------------------------------------

    def _calc_spectral_ratio(self, obs: np.ndarray, sim: np.ndarray) -> float:
        """计算模拟与观测的高频段能量比 (Sim/Obs)。"""
        n = len(obs)
        if n < 4:
            return 1.0

        freqs_obs, psd_obs = periodogram(obs, fs=1.0)
        freqs_sim, psd_sim = periodogram(sim, fs=1.0)

        # 高频定义：频率 > 中位频率
        mid_freq = freqs_obs[len(freqs_obs) // 2]
        high_mask = freqs_obs > mid_freq

        obs_energy = np.sum(psd_obs[high_mask])
        sim_energy = np.sum(psd_sim[high_mask])

        if obs_energy == 0:
            return 1.0 if sim_energy == 0 else float('inf')
        return float(sim_energy / obs_energy)

    # ------------------------------------------------------------------
    # 最优传输：Wasserstein 距离
    # ------------------------------------------------------------------

    def _calc_wasserstein(self, obs: np.ndarray, sim: np.ndarray) -> float:
        """将流量视为时间轴上的概率分布，计算 Wasserstein 距离（单位：小时）。"""
        obs_pos = np.maximum(obs, 0)
        sim_pos = np.maximum(sim, 0)

        if np.sum(obs_pos) == 0 or np.sum(sim_pos) == 0:
            return 0.0

        # 归一化为概率分布
        obs_dist = obs_pos / np.sum(obs_pos)
        sim_dist = sim_pos / np.sum(sim_pos)

        indices = np.arange(len(obs), dtype=float)
        return float(wasserstein_distance(indices, indices, obs_dist, sim_dist))

    # ------------------------------------------------------------------
    # 起涨点检测
    # ------------------------------------------------------------------

    def _calc_onset_lag(self, obs: np.ndarray, sim: np.ndarray) -> float:
        """检测洪水起涨点的时间差异。"""
        threshold_factor = 0.2
        obs_range = np.max(obs) - np.min(obs)
        if obs_range < 0.5:
            return 0.0

        threshold = np.median(obs) + threshold_factor * obs_range

        obs_onsets = self._find_onsets(obs, threshold)
        sim_onsets = self._find_onsets(sim, threshold)

        if len(obs_onsets) == 0:
            return 0.0

        lags = []
        window = self.window_hours
        used = set()
        for o_onset in obs_onsets:
            best_s = None
            best_dist = window + 1
            for j, s_onset in enumerate(sim_onsets):
                if j in used:
                    continue
                dist = abs(s_onset - o_onset)
                if dist <= window and dist < best_dist:
                    best_dist = dist
                    best_s = j
            if best_s is not None:
                used.add(best_s)
                lags.append(sim_onsets[best_s] - o_onset)

        return float(np.mean(lags)) if lags else 0.0

    @staticmethod
    def _find_onsets(series: np.ndarray, threshold: float) -> List[int]:
        """找出序列中每次超过阈值的起始索引。"""
        above = series > threshold
        onsets = []
        was_below = True
        for i in range(len(series)):
            if above[i] and was_below:
                onsets.append(i)
                was_below = False
            elif not above[i]:
                was_below = True
        return onsets

    # ------------------------------------------------------------------
    # 语义反馈生成
    # ------------------------------------------------------------------

    def _generate_feedback(self, metrics: Dict[str, float]) -> List[str]:
        feedback = []

        if metrics['Peak_Lag_Hours'] > 3.0:
            feedback.append(
                "Critical: 洪峰响应显著滞后。建议移除滞后函数或减小汇流参数(k)。"
            )

        if metrics['Low_Flow_Bias'] < -0.3:
            feedback.append(
                "Warning: 枯水期流量被严重低估。建议增加并联的线性水库作为慢速地下水层。"
            )
        elif metrics['Low_Flow_Bias'] > 0.3:
            feedback.append(
                "Warning: 枯水期流量被高估。建议减小蒸发系数或检查土壤蓄水量参数。"
            )

        if metrics['High_Freq_Energy_Ratio'] < 0.6:
            feedback.append(
                "Insight [谱分析]: 模拟流量过度平滑。尝试保留高频动态响应，建议减小滞留时间常数。"
            )
        elif metrics['High_Freq_Energy_Ratio'] > 1.5:
            feedback.append(
                "Insight [谱分析]: 高频振荡过大。建议增加平滑机制或检查输入数据质量。"
            )

        if metrics['Temporal_Wasserstein_Dist'] > 5.0:
            feedback.append(
                "Insight [最优传输]: 全局时空偏移严重。即使NSE尚可，整体重心仍有偏移。"
            )

        return feedback
