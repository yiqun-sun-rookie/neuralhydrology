import warnings

import numpy as np
import pandas as pd
from typing import Any, Dict, List, Tuple
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
        obs_arr, sim_arr = self._sanitize_inputs(obs, sim)

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
        }

        feedback = self._generate_feedback(metrics)
        return {'metrics': metrics, 'semantic_feedback': feedback}

    # ------------------------------------------------------------------
    # 输入清洗与防护
    # ------------------------------------------------------------------

    @staticmethod
    def _sanitize_inputs(obs, sim) -> Tuple[np.ndarray, np.ndarray]:
        """清洗 NaN/Inf，截断长度不一致，返回干净的配对数组。"""
        obs_arr = np.asarray(obs, dtype=float).ravel()
        sim_arr = np.asarray(sim, dtype=float).ravel()

        # 长度对齐：取最短
        n = min(len(obs_arr), len(sim_arr))
        if len(obs_arr) != len(sim_arr):
            warnings.warn(f"HydroDiagnostician: obs({len(obs_arr)}) 与 sim({len(sim_arr)}) 长度不一致，截断至 {n}。")
        obs_arr = obs_arr[:n]
        sim_arr = sim_arr[:n]

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

        return obs_arr, sim_arr

    @staticmethod
    def _empty_metrics() -> Dict[str, float]:
        return {
            'NSE': float('nan'), 'KGE': float('nan'),
            'KGE_r': float('nan'), 'KGE_alpha': float('nan'), 'KGE_beta': float('nan'),
            'Peak_Lag_Hours': 0.0, 'Peak_MAPE': 0.0,
            'Low_Flow_Bias': 0.0, 'High_Freq_Energy_Ratio': 1.0,
            'Temporal_Wasserstein_Dist': 0.0, 'Onset_Lag_Hours': 0.0,
            'Recession_K_Ratio': 1.0, 'FDC_Slope_Error': 0.0,
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

        return feedback
