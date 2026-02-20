from __future__ import annotations

from typing import Dict, Tuple, Any, Optional
import pandas as pd
import numpy as np

try:
    import networkx as nx  # type: ignore
except Exception:
    # Keep HydroAgent importable even when networkx backends are misconfigured.
    nx = None

class SuperflexEnv:
    """
    Module B: 自动化建模环境
    负责将 JSON 结构转化为可运行的 SuperflexPy 模型，并自动寻找最优参数。
    """
    
    def __init__(self):
        self.structure_json: Dict[str, Any] = {}
        self.elements: Dict[str, Dict[str, Any]] = {}

    def run(self, structure_json: Dict[str, Any], forcing_data: pd.DataFrame, obs_data: pd.Series) -> Tuple[pd.Series, float]:
        """
        环境运行入口。
        
        Args:
            structure_json: 符合协议的结构描述
            forcing_data: 气象驱动
            obs_data: 用于率定的观测数据
            
        Returns:
            sim_flow: 模拟流量序列
            best_nse: 优化后的 NSE 分数
        """
        self.parse_structure(structure_json)
        result = self.auto_calibrate(forcing_data, obs_data)
        return result["qsim"], float(result["nse"])

    def parse_structure(self, structure_json: Dict[str, Any]) -> None:
        """Parse and store a light-weight structure definition."""
        layers = structure_json.get("layers", [])
        if not isinstance(layers, list):
            raise ValueError("`layers` must be a list in structure_json.")
        self.structure_json = structure_json
        self.elements = {}
        for layer in layers:
            layer_id = layer.get("id")
            if layer_id:
                self.elements[str(layer_id)] = layer

    @staticmethod
    def _pick_forcing_columns(forcing_data: pd.DataFrame) -> Tuple[pd.Series, pd.Series]:
        prcp_col = "prcp" if "prcp" in forcing_data.columns else forcing_data.columns[0]
        ep_col: Optional[str] = None
        for candidate in ["ep", "pet", "evap", "evaporation"]:
            if candidate in forcing_data.columns:
                ep_col = candidate
                break
        prcp = forcing_data[prcp_col].astype(float).fillna(0.0)
        if ep_col is None:
            ep = pd.Series(0.0, index=forcing_data.index)
        else:
            ep = forcing_data[ep_col].astype(float).fillna(0.0)
        return prcp, ep

    def run_simulation(self, forcing_data: pd.DataFrame, params: Optional[Dict[str, float]] = None) -> pd.Series:
        """Run a simple conceptual rainfall-runoff baseline."""
        if not self.structure_json:
            raise ValueError("Structure has not been parsed. Call parse_structure() first.")
        if forcing_data.empty:
            raise ValueError("forcing_data is empty.")

        params = params or {}
        alpha = float(params.get("alpha", 0.65))  # storage memory
        beta = float(params.get("beta", 0.25))    # PET penalty
        scale = float(params.get("scale", 1.0))   # runoff scale
        alpha = min(max(alpha, 0.0), 0.999)
        beta = min(max(beta, 0.0), 2.0)
        scale = max(scale, 0.0)

        prcp, ep = self._pick_forcing_columns(forcing_data)
        storage = 0.0
        qsim = np.zeros(len(forcing_data), dtype=float)
        for i, (p, e) in enumerate(zip(prcp.values, ep.values)):
            effective = max(p - beta * e, 0.0)
            storage = alpha * storage + effective
            qsim[i] = max((1.0 - alpha) * storage * scale, 0.0)

        return pd.Series(qsim, index=forcing_data.index, name="qsim")

    @staticmethod
    def _nse(obs: pd.Series, sim: pd.Series) -> float:
        common_idx = obs.index.intersection(sim.index)
        if len(common_idx) == 0:
            return float("-inf")
        o = obs.loc[common_idx].astype(float).replace([np.inf, -np.inf], np.nan).dropna()
        s = sim.loc[o.index].astype(float).replace([np.inf, -np.inf], np.nan).dropna()
        common_idx = o.index.intersection(s.index)
        if len(common_idx) == 0:
            return float("-inf")
        o = o.loc[common_idx]
        s = s.loc[common_idx]
        denom = float(((o - o.mean()) ** 2).sum())
        if denom <= 1e-12:
            return float("-inf")
        num = float(((o - s) ** 2).sum())
        return 1.0 - num / denom

    def auto_calibrate(self, forcing_data: pd.DataFrame, obs_data: pd.Series) -> Dict[str, Any]:
        """Calibrate a small parameter grid and return the best simulation."""
        if obs_data.empty:
            raise ValueError("obs_data is empty.")
        best_nse = float("-inf")
        best_params: Dict[str, float] = {"alpha": 0.65, "beta": 0.25, "scale": 1.0}
        best_qsim = self.run_simulation(forcing_data, best_params)

        alpha_grid = [0.45, 0.55, 0.65, 0.75, 0.85]
        beta_grid = [0.0, 0.1, 0.2, 0.3, 0.4]
        for alpha in alpha_grid:
            for beta in beta_grid:
                params = {"alpha": alpha, "beta": beta, "scale": 1.0}
                qsim = self.run_simulation(forcing_data, params)
                nse = self._nse(obs_data, qsim)
                if nse > best_nse:
                    best_nse = nse
                    best_params = params
                    best_qsim = qsim

        return {"nse": float(best_nse), "optimized_params": best_params, "qsim": best_qsim}

    def _build_model(self, json_config):
        """解析 JSON 构建物理模型图"""
        self.parse_structure(json_config)
        return self

    def _auto_calibrate(self, model, forcing, obs):
        """调用 L-BFGS-B 进行参数寻优"""
        return self.auto_calibrate(forcing, obs).get("optimized_params", {})

