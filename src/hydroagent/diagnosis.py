import warnings

import numpy as np
import pandas as pd
from typing import Any, Dict, List, Optional, Tuple
from scipy.signal import find_peaks, periodogram, hilbert
from scipy.stats import wasserstein_distance


METRIC_GROUPS = {
    'hydro_basic':  ['NSE', 'KGE', 'KGE_r', 'KGE_alpha', 'KGE_beta'],
    'peak_timing':  ['Peak_Lag_Hours', 'Peak_MAPE', 'Onset_Lag_Hours'],
    'flow_regime':  ['Low_Flow_Bias', 'High_Freq_Energy_Ratio', 'Temporal_Wasserstein_Dist',
                     'Recession_K_Ratio', 'FDC_Slope_Error'],
    'seasonal':     ['Winter_Bias', 'Snow_Season_NSE', 'Seasonal_Amplitude_Ratio'],
    'cross_domain': ['Hjorth_Activity_Ratio', 'Hjorth_Mobility_Ratio', 'Hjorth_Complexity_Ratio',
                     'SSIM_1D', 'ITAE_Ratio', 'TF_Envelope_Misfit', 'TF_Phase_Misfit',
                     'Perkins_Skill_Score'],
}

_METRIC_TO_GROUP = {m: g for g, ms in METRIC_GROUPS.items() for m in ms}


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

    def __init__(self, cfg: Dict[str, Any] = None, enabled_groups=None):
        cfg = cfg or {}
        self.window_hours = cfg.get('window_hours', 12)
        self.min_prominence_factor = cfg.get('min_prominence_factor', 0.05)
        self.enabled_groups = frozenset(enabled_groups) if enabled_groups is not None else None

    def generate_report(self, obs: pd.Series, sim: pd.Series) -> Dict[str, Any]:
        """核心入口：计算指标并生成报告。"""
        obs_arr, sim_arr, dt_index = self._sanitize_inputs(obs, sim)

        if len(obs_arr) < 2:
            return {'metrics': self._empty_metrics(), 'semantic_feedback': ["Error: 有效数据不足，无法计算诊断指标。"]}

        nse = self._calc_nse(obs_arr, sim_arr)
        kge_val, kge_r, kge_alpha, kge_beta = self._calc_kge(obs_arr, sim_arr)
        peak_info = self._windowed_peak_matching(obs_arr, sim_arr)
        low_flow_bias = self._calc_low_flow_bias(obs_arr, sim_arr)
        spectral_ratio = self._calc_spectral_ratio(obs_arr, sim_arr)
        wass_dist = self._calc_wasserstein(obs_arr, sim_arr)
        onset_lag = self._calc_onset_lag(obs_arr, sim_arr)
        recession_k_ratio = self._calc_recession_error(obs_arr, sim_arr)
        fdc_slope_err = self._calc_fdc_slope_error(obs_arr, sim_arr)

        # 季节性指标
        winter_bias = self._calc_winter_bias(obs_arr, sim_arr, dt_index)
        snow_nse = self._calc_snow_season_nse(obs_arr, sim_arr, dt_index)
        seasonal_amp = self._calc_seasonal_amplitude_ratio(obs_arr, sim_arr, dt_index)

        # 跨领域指标
        hjorth_act, hjorth_mob, hjorth_comp = self._calc_hjorth_ratios(obs_arr, sim_arr)
        ssim_1d = self._calc_ssim_1d(obs_arr, sim_arr)
        itae_ratio = self._calc_itae_ratio(obs_arr, sim_arr)
        tf_env, tf_phase = self._calc_tf_misfit(obs_arr, sim_arr)
        perkins_ss = self._calc_perkins_ss(obs_arr, sim_arr)

        metrics = {
            'NSE': round(nse, 4),
            'KGE': round(kge_val, 4),
            'KGE_r': round(kge_r, 4),
            'KGE_alpha': round(kge_alpha, 4),
            'KGE_beta': round(kge_beta, 4),
            'Peak_Lag_Hours': round(peak_info['peak_lag'], 1),
            'Peak_MAPE': round(peak_info['peak_mape'], 4),
            'Low_Flow_Bias': round(low_flow_bias, 4),
            'High_Freq_Energy_Ratio': round(spectral_ratio, 4),
            'Temporal_Wasserstein_Dist': round(wass_dist, 2),
            'Onset_Lag_Hours': round(onset_lag, 1),
            'Recession_K_Ratio': round(recession_k_ratio, 4),
            'FDC_Slope_Error': round(fdc_slope_err, 4),
            # 季节性指标
            'Winter_Bias': round(winter_bias, 4),
            'Snow_Season_NSE': round(snow_nse, 4) if not np.isnan(snow_nse) else float('nan'),
            'Seasonal_Amplitude_Ratio': round(seasonal_amp, 4),
            # 跨领域指标
            'Hjorth_Activity_Ratio': round(hjorth_act, 4),
            'Hjorth_Mobility_Ratio': round(hjorth_mob, 4),
            'Hjorth_Complexity_Ratio': round(hjorth_comp, 4),
            'SSIM_1D': round(ssim_1d, 4),
            'ITAE_Ratio': round(itae_ratio, 4),
            'TF_Envelope_Misfit': round(tf_env, 4),
            'TF_Phase_Misfit': round(tf_phase, 4),
            'Perkins_Skill_Score': round(perkins_ss, 4),
        }

        # --- Ablation: filter metrics by enabled groups ---
        if self.enabled_groups is not None:
            metrics = {k: v for k, v in metrics.items()
                       if _METRIC_TO_GROUP.get(k, 'hydro_basic') in self.enabled_groups}

        feedback = self._generate_feedback(metrics)
        return {'metrics': metrics, 'semantic_feedback': feedback}

    # ------------------------------------------------------------------
    # 输入清洗与防护
    # ------------------------------------------------------------------

    @staticmethod
    def _sanitize_inputs(obs, sim) -> Tuple[np.ndarray, np.ndarray, Optional[pd.DatetimeIndex]]:
        """清洗 NaN/Inf，截断长度不一致，返回干净的配对数组和可选的时间索引。"""
        # 提取 DatetimeIndex（若存在）
        dt_index = None
        if isinstance(getattr(obs, 'index', None), pd.DatetimeIndex):
            dt_index = obs.index

        obs_arr = np.asarray(obs, dtype=float).ravel()
        sim_arr = np.asarray(sim, dtype=float).ravel()

        # 长度对齐：取最短
        n = min(len(obs_arr), len(sim_arr))
        if len(obs_arr) != len(sim_arr):
            warnings.warn(f"HydroDiagnostician: obs({len(obs_arr)}) 与 sim({len(sim_arr)}) 长度不一致，截断至 {n}。")
        obs_arr = obs_arr[:n]
        sim_arr = sim_arr[:n]
        if dt_index is not None:
            dt_index = dt_index[:n]

        # 去除 NaN / Inf
        valid = np.isfinite(obs_arr) & np.isfinite(sim_arr)
        n_dropped = n - np.sum(valid)
        if n_dropped > 0:
            drop_pct = n_dropped / n * 100
            warnings.warn(f"HydroDiagnostician: 丢弃 {n_dropped} 个无效值 ({drop_pct:.1f}%)。")
            if drop_pct > 50:
                warnings.warn("HydroDiagnostician: 超过 50% 数据无效，诊断结果可能不可靠。")
            obs_arr = obs_arr[valid]
            sim_arr = sim_arr[valid]
            if dt_index is not None:
                dt_index = dt_index[valid]

        return obs_arr, sim_arr, dt_index

    @staticmethod
    def _empty_metrics() -> Dict[str, float]:
        return {
            'NSE': float('nan'), 'KGE': float('nan'),
            'KGE_r': float('nan'), 'KGE_alpha': float('nan'), 'KGE_beta': float('nan'),
            'Peak_Lag_Hours': 0.0, 'Peak_MAPE': 0.0,
            'Low_Flow_Bias': 0.0, 'High_Freq_Energy_Ratio': 1.0,
            'Temporal_Wasserstein_Dist': 0.0, 'Onset_Lag_Hours': 0.0,
            'Recession_K_Ratio': 1.0, 'FDC_Slope_Error': 0.0,
            # 季节性指标
            'Winter_Bias': 0.0, 'Snow_Season_NSE': float('nan'), 'Seasonal_Amplitude_Ratio': 1.0,
            # 跨领域指标
            'Hjorth_Activity_Ratio': 1.0, 'Hjorth_Mobility_Ratio': 1.0,
            'Hjorth_Complexity_Ratio': 1.0, 'SSIM_1D': 1.0,
            'ITAE_Ratio': 1.0, 'TF_Envelope_Misfit': 0.0,
            'TF_Phase_Misfit': 0.0, 'Perkins_Skill_Score': 1.0,
        }

    # ------------------------------------------------------------------
    # 传统水文指标
    # ------------------------------------------------------------------

    def _calc_nse(self, obs: np.ndarray, sim: np.ndarray) -> float:
        denominator = np.sum((obs - np.mean(obs)) ** 2)
        if denominator == 0:
            return 1.0 if np.allclose(obs, sim) else -np.inf
        return 1.0 - np.sum((obs - sim) ** 2) / denominator

    def _calc_kge(self, obs: np.ndarray, sim: np.ndarray) -> Tuple[float, float, float, float]:
        r = float(np.corrcoef(obs, sim)[0, 1]) if np.std(obs) > 0 and np.std(sim) > 0 else 0.0
        alpha = float(np.std(sim) / np.std(obs)) if np.std(obs) > 0 else 0.0
        beta = float(np.mean(sim) / np.mean(obs)) if np.mean(obs) != 0 else 0.0
        kge = 1.0 - np.sqrt((r - 1) ** 2 + (alpha - 1) ** 2 + (beta - 1) ** 2)
        return float(kge), r, alpha, beta

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
    # 退水分析 (Recession Analysis)
    # ------------------------------------------------------------------

    def _calc_recession_error(self, obs: np.ndarray, sim: np.ndarray) -> float:
        """比较观测与模拟的退水常数，返回 Recession_K_Ratio = mean(sim_k) / mean(obs_k)。

        退水常数 k 来自 Q(t) = Q0 * exp(-k*t) 拟合。
        Ratio > 1.3 → 退水过快（缺慢速蓄水）; Ratio < 0.7 → 退水过慢。
        """
        obs_ks = self._extract_recession_constants(obs)
        sim_ks = self._extract_recession_constants(sim)

        if not obs_ks or not sim_ks:
            return 1.0

        mean_obs_k = float(np.mean(obs_ks))
        mean_sim_k = float(np.mean(sim_ks))

        if mean_obs_k == 0:
            return 1.0
        return mean_sim_k / mean_obs_k

    def _extract_recession_constants(self, series: np.ndarray) -> List[float]:
        """从序列中提取所有退水段的退水常数 k。

        退水段定义：峰值后连续下降至少 5 步的片段。
        使用 log-linear 回归拟合 ln(Q) = ln(Q0) - k*t。
        """
        min_prominence = self.min_prominence_factor * (np.max(series) - np.min(series))
        min_prominence = max(min_prominence, 0.1)
        peaks, _ = find_peaks(series, prominence=min_prominence)

        if len(peaks) == 0:
            return []

        min_recession_len = 5
        ks = []

        for peak_idx in peaks:
            # 从峰值开始向后找连续下降段
            start = peak_idx
            end = start + 1
            while end < len(series) and series[end] <= series[end - 1]:
                end += 1

            recession_len = end - start
            if recession_len < min_recession_len:
                continue

            q_segment = series[start:end]
            # 过滤掉 <= 0 的值（无法取对数）
            valid = q_segment > 0
            if np.sum(valid) < min_recession_len:
                continue

            t = np.arange(recession_len, dtype=float)[valid]
            ln_q = np.log(q_segment[valid])

            # log-linear 回归: ln(Q) = a - k*t
            if len(t) < 2:
                continue
            coeffs = np.polyfit(t, ln_q, 1)
            k = -coeffs[0]  # 斜率的负数即为退水常数
            if k > 0:
                ks.append(float(k))

        return ks

    # ------------------------------------------------------------------
    # 流量历时曲线 (Flow Duration Curve Signature)
    # ------------------------------------------------------------------

    def _calc_fdc_slope_error(self, obs: np.ndarray, sim: np.ndarray) -> float:
        """计算 FDC 中段斜率的相对误差 (Yilmaz et al., 2008)。

        FDC 中段 (33%-66% exceedance) 的斜率反映流量变异性。
        返回相对误差 = (sim_slope - obs_slope) / |obs_slope|。
        正值 → 模拟变异性过大; 负值 → 模拟过于平坦。
        """
        obs_slope = self._fdc_mid_slope(obs)
        sim_slope = self._fdc_mid_slope(sim)

        if obs_slope is None or sim_slope is None:
            return 0.0

        if abs(obs_slope) < 1e-10:
            return 0.0

        return float((sim_slope - obs_slope) / abs(obs_slope))

    @staticmethod
    def _fdc_mid_slope(series: np.ndarray) -> float:
        """计算 FDC 中段斜率 (33%-66% exceedance probability)。

        对 log(Q) 在中段的超越概率区间做线性拟合。
        """
        n = len(series)
        if n < 10:
            return None

        sorted_q = np.sort(series)[::-1]  # 降序
        exceedance = np.arange(1, n + 1) / (n + 1)

        # 中段: 33% - 66% exceedance
        mask = (exceedance >= 0.33) & (exceedance <= 0.66)
        if np.sum(mask) < 3:
            return None

        q_mid = sorted_q[mask]
        exc_mid = exceedance[mask]

        # 过滤 <= 0 的流量
        valid = q_mid > 0
        if np.sum(valid) < 3:
            return None

        log_q = np.log(q_mid[valid])
        exc_valid = exc_mid[valid]

        coeffs = np.polyfit(exc_valid, log_q, 1)
        return float(coeffs[0])  # 斜率

    # ------------------------------------------------------------------
    # 季节性指标 (驱动 SnowReservoir 选择)
    # ------------------------------------------------------------------

    @staticmethod
    def _calc_winter_bias(obs: np.ndarray, sim: np.ndarray,
                          dt_index: Optional[pd.DatetimeIndex]) -> float:
        """冬季偏差: (mean(sim) - mean(obs)) / mean(obs)，仅 Dec-Feb。"""
        if dt_index is None or len(dt_index) != len(obs):
            return 0.0
        winter_mask = dt_index.month.isin([12, 1, 2])
        if winter_mask.sum() < 30:
            return 0.0
        obs_w = obs[winter_mask]
        sim_w = sim[winter_mask]
        mean_obs = np.mean(obs_w)
        if abs(mean_obs) < 1e-10:
            return 0.0
        return float((np.mean(sim_w) - mean_obs) / mean_obs)

    @staticmethod
    def _calc_snow_season_nse(obs: np.ndarray, sim: np.ndarray,
                              dt_index: Optional[pd.DatetimeIndex]) -> float:
        """仅冬季 (Dec-Feb) 的 NSE。"""
        if dt_index is None or len(dt_index) != len(obs):
            return float('nan')
        winter_mask = dt_index.month.isin([12, 1, 2])
        if winter_mask.sum() < 30:
            return float('nan')
        obs_w = obs[winter_mask]
        sim_w = sim[winter_mask]
        denom = np.sum((obs_w - np.mean(obs_w)) ** 2)
        if denom == 0:
            return 1.0 if np.allclose(obs_w, sim_w) else -np.inf
        return float(1.0 - np.sum((obs_w - sim_w) ** 2) / denom)

    @staticmethod
    def _calc_seasonal_amplitude_ratio(obs: np.ndarray, sim: np.ndarray,
                                       dt_index: Optional[pd.DatetimeIndex]) -> float:
        """季节振幅比: sim 月均值振幅 / obs 月均值振幅。"""
        if dt_index is None or len(dt_index) != len(obs):
            return 1.0
        obs_s = pd.Series(obs, index=dt_index)
        sim_s = pd.Series(sim, index=dt_index)
        obs_monthly = obs_s.groupby(obs_s.index.month).mean()
        sim_monthly = sim_s.groupby(sim_s.index.month).mean()
        if len(obs_monthly) < 4:
            return 1.0
        obs_amp = obs_monthly.max() - obs_monthly.min()
        sim_amp = sim_monthly.max() - sim_monthly.min()
        if abs(obs_amp) < 1e-10:
            return 1.0
        return float(sim_amp / obs_amp)

    # ------------------------------------------------------------------
    # 跨领域指标 1: Hjorth Parameters (脑电信号分析)
    # ------------------------------------------------------------------

    def _calc_hjorth_ratios(self, obs: np.ndarray, sim: np.ndarray) -> Tuple[float, float, float]:
        """Hjorth 三参数的 sim/obs 比值。

        - Activity = var(x) → 流量变异性
        - Mobility = std(dx)/std(x) → 过程线闪急性（涨退水速度）
        - Complexity = Mobility(dx)/Mobility(x) → 信号带宽/复杂度

        返回 (activity_ratio, mobility_ratio, complexity_ratio)，理想值均为 1.0。
        """
        def _hjorth(x):
            act = np.var(x)
            if act < 1e-12:
                return 0.0, 0.0, 0.0
            dx = np.diff(x)
            act_dx = np.var(dx)
            mob = np.sqrt(act_dx / act)
            if mob < 1e-12:
                return act, mob, 0.0
            ddx = np.diff(dx)
            mob_dx = np.sqrt(np.var(ddx) / act_dx) if act_dx > 1e-12 else 0.0
            comp = mob_dx / mob if mob > 1e-12 else 0.0
            return act, mob, comp

        o_act, o_mob, o_comp = _hjorth(obs)
        s_act, s_mob, s_comp = _hjorth(sim)

        act_r = s_act / o_act if o_act > 1e-12 else 1.0
        mob_r = s_mob / o_mob if o_mob > 1e-12 else 1.0
        comp_r = s_comp / o_comp if o_comp > 1e-12 else 1.0
        return float(act_r), float(mob_r), float(comp_r)

    # ------------------------------------------------------------------
    # 跨领域指标 2: 1D-SSIM (图像质量评估)
    # ------------------------------------------------------------------

    def _calc_ssim_1d(self, obs: np.ndarray, sim: np.ndarray) -> float:
        """一维结构相似度 (Wang et al. 2004 → 时序改编)。

        在滑动窗口内计算三个分量：
        - Luminance（均值相似） ≈ 偏差
        - Contrast（方差相似） ≈ 变异性
        - Structure（相关相似） ≈ 形状

        返回 [−1, 1]，1.0 为完美匹配。
        """
        n = len(obs)
        win = min(self.window_hours, n)
        if win < 3:
            return 1.0 if np.allclose(obs, sim) else 0.0

        data_range = float(np.max(obs) - np.min(obs))
        if data_range < 1e-10:
            data_range = 1.0
        C1 = (0.01 * data_range) ** 2
        C2 = (0.03 * data_range) ** 2

        step = max(1, win // 2)
        ssim_vals = []
        for i in range(0, n - win + 1, step):
            o_w = obs[i:i + win]
            s_w = sim[i:i + win]

            mu_o, mu_s = np.mean(o_w), np.mean(s_w)
            sig_o, sig_s = np.std(o_w), np.std(s_w)
            sig_os = np.mean((o_w - mu_o) * (s_w - mu_s))

            lum = (2.0 * mu_o * mu_s + C1) / (mu_o ** 2 + mu_s ** 2 + C1)
            con = (2.0 * sig_o * sig_s + C2) / (sig_o ** 2 + sig_s ** 2 + C2)
            stru = (sig_os + C2 / 2.0) / (sig_o * sig_s + C2 / 2.0)

            ssim_vals.append(lum * con * stru)

        return float(np.mean(ssim_vals)) if ssim_vals else 1.0

    # ------------------------------------------------------------------
    # 跨领域指标 3: ITAE (控制工程)
    # ------------------------------------------------------------------

    def _calc_itae_ratio(self, obs: np.ndarray, sim: np.ndarray) -> float:
        """ITAE / IAE 归一化比值，衡量误差是否集中在后期。

        ITAE = Σ t·|e(t)|，IAE = Σ |e(t)|。
        比值 = (ITAE/IAE) / (n/2)。
        - > 1.0 → 误差集中在后半段（退水漂移）
        - < 1.0 → 误差集中在前半段（启动偏差）
        - = 1.0 → 误差均匀分布
        """
        n = len(obs)
        if n < 2:
            return 1.0
        t = np.arange(n, dtype=float)
        abs_err = np.abs(obs - sim)
        iae = np.sum(abs_err)
        if iae < 1e-10:
            return 1.0
        itae = np.sum(t * abs_err)
        mean_error_time = itae / iae
        return float(mean_error_time / (n / 2.0))

    # ------------------------------------------------------------------
    # 跨领域指标 4: TF Misfit (地震学, Kristekova 简化版)
    # ------------------------------------------------------------------

    def _calc_tf_misfit(self, obs: np.ndarray, sim: np.ndarray) -> Tuple[float, float]:
        """分离包络误差（振幅偏大/偏小）与相位误差（时间偏早/偏晚）。

        使用 Hilbert 变换提取瞬时振幅（包络）和瞬时相位。
        - Envelope Misfit: NRMSE of envelopes → 振幅/流量大小误差
        - Phase Misfit: 平均圆周相位差 → 时间偏移误差
        均归一化到 [0, 1]，0 = 完美。

        注: 这是 Kristekova et al. (2006) 的简化版，用 Hilbert 代替 CWT。
        完整版需 ObsPy 的 tf_misfit 模块。
        """
        n = len(obs)
        if n < 8:
            return 0.0, 0.0

        analytic_o = hilbert(obs)
        analytic_s = hilbert(sim)

        env_o = np.abs(analytic_o)
        env_s = np.abs(analytic_s)

        # Envelope misfit: NRMSE
        env_range = np.max(env_o) - np.min(env_o)
        if env_range < 1e-10:
            env_misfit = 0.0
        else:
            env_misfit = float(np.sqrt(np.mean((env_o - env_s) ** 2)) / env_range)
        env_misfit = min(env_misfit, 1.0)

        # Phase misfit: mean absolute circular phase difference
        phase_o = np.angle(analytic_o)
        phase_s = np.angle(analytic_s)
        phase_diff = np.angle(np.exp(1j * (phase_s - phase_o)))
        phase_misfit = float(np.mean(np.abs(phase_diff)) / np.pi)

        return env_misfit, phase_misfit

    # ------------------------------------------------------------------
    # 跨领域指标 5: Perkins Skill Score (气候科学)
    # ------------------------------------------------------------------

    def _calc_perkins_ss(self, obs: np.ndarray, sim: np.ndarray) -> float:
        """Perkins Skill Score: 观测与模拟流量PDF的重叠面积。

        PSS = Σ min(f_obs, f_sim) * bin_width
        1.0 = 完美重叠，0.0 = 完全不同的分布。

        Ref: Perkins et al. (2007) J. Climate.
        """
        n_bins = min(50, max(10, len(obs) // 10))
        lo = min(np.min(obs), np.min(sim))
        hi = max(np.max(obs), np.max(sim))
        if hi - lo < 1e-10:
            return 1.0

        bins = np.linspace(lo, hi, n_bins + 1)
        bin_width = bins[1] - bins[0]

        obs_hist, _ = np.histogram(obs, bins=bins, density=True)
        sim_hist, _ = np.histogram(sim, bins=bins, density=True)

        overlap = float(np.sum(np.minimum(obs_hist, sim_hist)) * bin_width)
        return min(overlap, 1.0)

    # ------------------------------------------------------------------
    # 语义反馈生成
    # ------------------------------------------------------------------

    def _generate_feedback(self, metrics: Dict[str, float]) -> List[str]:
        feedback = []

        # --- 整体性能 ---
        nse = metrics.get('NSE', 0)
        if not np.isnan(nse) and nse < 0:
            feedback.append(
                "Critical: NSE < 0，模型预测能力低于均值基准。建议重新审视模型结构。"
            )

        # --- KGE 分量诊断 ---
        kge_r = metrics.get('KGE_r', 1.0)
        kge_alpha = metrics.get('KGE_alpha', 1.0)
        kge_beta = metrics.get('KGE_beta', 1.0)
        if not np.isnan(kge_r) and kge_r < 0.6:
            feedback.append(
                "Warning [KGE]: 相关性不足(r={:.2f})。模拟与观测的时序动态不匹配。".format(kge_r)
            )
        if not np.isnan(kge_alpha) and (kge_alpha < 0.5 or kge_alpha > 2.0):
            direction = "偏小" if kge_alpha < 1.0 else "偏大"
            feedback.append(
                "Warning [KGE]: 变异性比(alpha={:.2f}){}。模拟流量变幅与观测差异过大。".format(kge_alpha, direction)
            )

        # --- 洪峰时间 ---
        peak_lag = metrics.get('Peak_Lag_Hours', 0)
        if peak_lag > 3.0:
            feedback.append(
                "Critical: 洪峰响应显著滞后。建议移除滞后函数或减小汇流参数(k)。"
            )
        elif peak_lag < -3.0:
            feedback.append(
                "Warning: 洪峰响应提前(Lag={:.1f}h)。建议增加汇流滞后或检查土壤蓄水容量。".format(peak_lag)
            )

        # --- 洪峰量级 ---
        peak_mape = metrics.get('Peak_MAPE', 0)
        if peak_mape > 0.3:
            feedback.append(
                "Warning: 洪峰量级偏差较大(MAPE={:.0f}%)。建议检查非线性产流参数(beta)或蓄水容量(Smax)。".format(
                    peak_mape * 100)
            )

        # --- 枯水期 ---
        low_bias = metrics.get('Low_Flow_Bias', 0)
        if low_bias < -0.3:
            feedback.append(
                "Warning: 枯水期流量被严重低估。建议增加并联的线性水库作为慢速地下水层。"
            )
        elif low_bias > 0.3:
            feedback.append(
                "Warning: 枯水期流量被高估。建议减小蒸发系数或检查土壤蓄水量参数。"
            )

        # --- 谱分析 ---
        energy_ratio = metrics.get('High_Freq_Energy_Ratio', 1.0)
        if energy_ratio < 0.6:
            feedback.append(
                "Insight [谱分析]: 模拟流量过度平滑。尝试保留高频动态响应，建议减小滞留时间常数。"
            )
        elif energy_ratio > 1.5:
            feedback.append(
                "Insight [谱分析]: 高频振荡过大。建议增加平滑机制或检查输入数据质量。"
            )

        # --- 最优传输 ---
        wass = metrics.get('Temporal_Wasserstein_Dist', 0)
        if wass > 5.0:
            feedback.append(
                "Insight [最优传输]: 全局时空偏移严重。即使NSE尚可，整体重心仍有偏移。"
            )

        # --- 起涨点 ---
        onset_lag = metrics.get('Onset_Lag_Hours', 0)
        if onset_lag > 3.0:
            feedback.append(
                "Warning [起涨点]: 洪水起涨显著延迟({:.1f}h)。产流阈值可能过高或初始土壤含水量偏低。".format(onset_lag)
            )

        # --- 退水分析 ---
        rec_ratio = metrics.get('Recession_K_Ratio', 1.0)
        if rec_ratio > 1.3:
            feedback.append(
                "Insight [退水]: 退水过快(K_ratio={:.2f})。缺少慢速蓄水组件，建议增加线性水库。".format(rec_ratio)
            )
        elif rec_ratio < 0.7:
            feedback.append(
                "Insight [退水]: 退水过慢(K_ratio={:.2f})。蓄水组件响应过迟缓，建议减小水库时间常数。".format(rec_ratio)
            )

        # --- 季节性指标 ---
        winter_bias = metrics.get('Winter_Bias', 0.0)
        if winter_bias > 0.3:
            feedback.append(
                "Critical [季节]: 冬季流量严重高估(Winter_Bias={:.2f})。添加 SnowReservoir 将降水存为积雪，减少冬季直接径流(需温度数据)。".format(
                    winter_bias)
            )
        elif winter_bias > 0.15:
            feedback.append(
                "Warning [季节]: 冬季流量偏高(Winter_Bias={:.2f})，可能缺少积雪过程。".format(winter_bias)
            )
        elif winter_bias < -0.3:
            feedback.append(
                "Warning [季节]: 冬季流量严重低估(Winter_Bias={:.2f})。".format(winter_bias)
            )

        snow_nse = metrics.get('Snow_Season_NSE', float('nan'))
        if not np.isnan(snow_nse) and snow_nse < 0:
            feedback.append(
                "Critical [季节]: 冬季NSE<0(Snow_Season_NSE={:.2f})，冬季模型结构不适用。".format(snow_nse)
            )

        seasonal_amp = metrics.get('Seasonal_Amplitude_Ratio', 1.0)
        if seasonal_amp < 0.5:
            feedback.append(
                "Insight [季节]: 季节性振幅被压缩(Ratio={:.2f})。模拟未捕捉到季节变化。".format(seasonal_amp)
            )
        elif seasonal_amp > 2.0:
            feedback.append(
                "Insight [季节]: 季节性振幅被放大(Ratio={:.2f})。模拟过度响应季节变化。".format(seasonal_amp)
            )

        # --- FDC 特征 ---
        fdc_err = metrics.get('FDC_Slope_Error', 0)
        if fdc_err > 0.5:
            feedback.append(
                "Insight [FDC]: 流量变异性被高估(斜率误差{:+.0f}%)。中等流量区间模拟偏差较大。".format(fdc_err * 100)
            )
        elif fdc_err < -0.5:
            feedback.append(
                "Insight [FDC]: 流量变异性被低估(斜率误差{:+.0f}%)。模拟过于平坦，缺少动态响应。".format(fdc_err * 100)
            )

        # --- Hjorth: 变异性/闪急性/复杂度 ---
        hjorth_act = metrics.get('Hjorth_Activity_Ratio', 1.0)
        hjorth_mob = metrics.get('Hjorth_Mobility_Ratio', 1.0)
        if hjorth_act < 0.5 or hjorth_act > 2.0:
            direction = "不足" if hjorth_act < 1.0 else "过大"
            feedback.append(
                "Insight [Hjorth]: 流量变异性{}(Activity比={:.2f})。模拟信号的整体波动幅度与观测不匹配。".format(
                    direction, hjorth_act)
            )
        if hjorth_mob < 0.6 or hjorth_mob > 1.5:
            direction = "过于迟缓" if hjorth_mob < 1.0 else "过于剧烈"
            feedback.append(
                "Insight [Hjorth]: 过程线涨退水速度{}(Mobility比={:.2f})。建议调整快速响应组件参数。".format(
                    direction, hjorth_mob)
            )

        # --- 1D-SSIM: 局部结构 ---
        ssim = metrics.get('SSIM_1D', 1.0)
        if ssim < 0.7:
            feedback.append(
                "Warning [SSIM]: 局部结构相似度低(SSIM={:.2f})。事件尺度的过程线形状与观测偏差较大。".format(ssim)
            )

        # --- ITAE: 误差时间分布 ---
        itae_r = metrics.get('ITAE_Ratio', 1.0)
        if itae_r > 1.3:
            feedback.append(
                "Insight [ITAE]: 误差集中在模拟后期(ITAE比={:.2f})。退水段或基流段存在持续偏差。".format(itae_r)
            )
        elif itae_r < 0.7:
            feedback.append(
                "Insight [ITAE]: 误差集中在模拟前期(ITAE比={:.2f})。模型启动/预热阶段偏差较大。".format(itae_r)
            )

        # --- TF Misfit: 振幅 vs 时间误差 ---
        tf_env = metrics.get('TF_Envelope_Misfit', 0.0)
        tf_phase = metrics.get('TF_Phase_Misfit', 0.0)
        if tf_env > 0.3 and tf_phase <= 0.3:
            feedback.append(
                "Insight [TF]: 误差以振幅偏差为主(包络={:.2f}, 相位={:.2f})。流量大小不对，但时间对齐尚可。".format(
                    tf_env, tf_phase)
            )
        elif tf_phase > 0.3 and tf_env <= 0.3:
            feedback.append(
                "Insight [TF]: 误差以时间偏移为主(包络={:.2f}, 相位={:.2f})。流量大小基本对，但时间偏移明显。".format(
                    tf_env, tf_phase)
            )
        elif tf_env > 0.3 and tf_phase > 0.3:
            feedback.append(
                "Critical [TF]: 振幅和时间均有显著误差(包络={:.2f}, 相位={:.2f})。模型结构需全面调整。".format(
                    tf_env, tf_phase)
            )

        # --- Perkins SS: 流量分布 ---
        pss = metrics.get('Perkins_Skill_Score', 1.0)
        if pss < 0.7:
            feedback.append(
                "Warning [分布]: 流量分布重叠度低(PSS={:.2f})。模拟产生的流量值频率与观测差异较大。".format(pss)
            )

        return feedback
