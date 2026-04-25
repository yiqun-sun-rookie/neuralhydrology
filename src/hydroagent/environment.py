from __future__ import annotations

import os
import sys
from typing import Dict, Tuple, Any, Optional

import pandas as pd
import numpy as np
import cma

# ---------------------------------------------------------------------------
# Dynamically add external/superflexpy to sys.path so the vendored copy works
# even when superflexpy is not pip-installed.
# ---------------------------------------------------------------------------
_HERE = os.path.dirname(os.path.abspath(__file__))
_PROJECT_ROOT = os.path.abspath(os.path.join(_HERE, '..', '..'))
_SFPY_DIR = os.path.join(_PROJECT_ROOT, 'external', 'superflexpy')
if os.path.isdir(_SFPY_DIR) and _SFPY_DIR not in sys.path:
    sys.path.insert(0, _SFPY_DIR)

from superflexpy.implementation.root_finders.pegasus import PegasusPython
from superflexpy.implementation.numerical_approximators.implicit_euler import ImplicitEulerPython
from superflexpy.implementation.elements.hbv import PowerReservoir, UnsaturatedReservoir
from superflexpy.implementation.elements.hymod import LinearReservoir, UpperZone
from superflexpy.implementation.elements.thur_model_hess import SnowReservoir, HalfTriangularLag
from superflexpy.implementation.elements.gr4j import (
    InterceptionFilter, ProductionStore, RoutingStore, UnitHydrograph1, UnitHydrograph2,
)
from .custom_elements import DeepGroundwater, ConveyanceLoss
from .marrmot_elements import InterceptionBucket, ThresholdReservoir, PercolationStore, SaturationAreaStore

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
_FORCING_NAMES = frozenset({
    'prcp', 'ep', 'pet', 'evap', 'evaporation', 'precipitation', 'rainfall',
    'temp', 'temperature', 'tmax', 'tmin', 'tmean', 'tavg',
})

# ---------------------------------------------------------------------------
# Component registry
# ---------------------------------------------------------------------------
_REGISTRY: Dict[str, Dict[str, Any]] = {
    'UnsaturatedReservoir': {
        'cls': UnsaturatedReservoir,
        'params': {'Smax': 200.0, 'Ce': 1.0, 'm': 0.01, 'beta': 2.0},
        'bounds': {
            'Smax': (50.0, 500.0),
            'Ce': (0.3, 1.5),
            'm': (0.001, 0.1),
            'beta': (0.5, 5.0),
        },
        'states': {'S0': 50.0, 'PET': None},
        'input_map': 'P_PET',
    },
    'UpperZone': {
        'cls': UpperZone,
        'params': {'Smax': 200.0, 'm': 0.01, 'beta': 2.0},
        'bounds': {
            'Smax': (50.0, 500.0),
            'm': (0.001, 0.1),
            'beta': (0.5, 5.0),
        },
        'states': {'S0': 50.0},
        'input_map': 'P_PET',
    },
    'PowerReservoir': {
        'cls': PowerReservoir,
        'params': {'k': 0.1, 'alpha': 1.5},
        'bounds': {'k': (0.001, 0.5), 'alpha': (1.0, 3.0)},
        'states': {'S0': 5.0},
        'input_map': 'P',
    },
    'LinearReservoir': {
        'cls': LinearReservoir,
        'params': {'k': 0.02},
        'bounds': {'k': (0.001, 0.1)},
        'states': {'S0': 5.0},
        'input_map': 'P',
    },
    'SnowReservoir': {
        'cls': SnowReservoir,
        'params': {'t0': 0.0, 'k': 2.0, 'm': 2.0},
        'bounds': {'t0': (-3.0, 3.0), 'k': (0.5, 5.0), 'm': (0.5, 5.0)},
        'states': {'S0': 0.0},
        'input_map': 'P_T',
    },
    'ProductionStore': {
        'cls': ProductionStore,
        'params': {'x1': 350.0, 'alpha': 2.0, 'beta': 5.0, 'ni': 4.0 / 9.0},
        'bounds': {'x1': (100.0, 1500.0), 'alpha': (1.5, 2.5), 'beta': (3.0, 7.0), 'ni': (0.1, 0.9)},
        'states': {'S0': 100.0},
        'input_map': 'PET_P',
    },
    'RoutingStore': {
        'cls': RoutingStore,
        'params': {'x2': -1.0, 'x3': 100.0, 'gamma': 5.0, 'omega': 3.5},
        'bounds': {'x2': (-5.0, 3.0), 'x3': (20.0, 500.0), 'gamma': (3.0, 7.0), 'omega': (2.0, 5.0)},
        'states': {'S0': 50.0},
        'input_map': 'P',
    },
    'DeepGroundwater': {
        'cls': DeepGroundwater,
        'params': {'k': 0.002, 'f_loss': 0.01},
        'bounds': {'k': (0.0001, 0.02), 'f_loss': (0.0, 0.3)},
        'states': {'S0': 20.0},
        'input_map': 'P',
    },
    'ConveyanceLoss': {
        'cls': ConveyanceLoss,
        'params': {'k': 0.1, 'f_loss': 0.05},
        'bounds': {'k': (0.01, 0.5), 'f_loss': (0.0, 0.5)},
        'states': {'S0': 5.0},
        'input_map': 'P',
    },
    'InterceptionBucket': {
        'cls': InterceptionBucket,
        'params': {'Smax': 3.0, 'Ce': 1.0},
        'bounds': {'Smax': (0.5, 10.0), 'Ce': (0.3, 1.5)},
        'states': {'S0': 0.0},
        'input_map': 'P_PET',
    },
    'ThresholdReservoir': {
        'cls': ThresholdReservoir,
        'params': {'k': 0.05, 'Sth': 20.0},
        'bounds': {'k': (0.001, 0.3), 'Sth': (0.0, 100.0)},
        'states': {'S0': 10.0},
        'input_map': 'P',
    },
    'PercolationStore': {
        'cls': PercolationStore,
        'params': {'Smax': 100.0, 'Pmax': 5.0, 'alpha': 2.0},
        'bounds': {'Smax': (20.0, 500.0), 'Pmax': (0.5, 20.0), 'alpha': (1.0, 4.0)},
        'states': {'S0': 30.0},
        'input_map': 'P',
    },
    'SaturationAreaStore': {
        'cls': SaturationAreaStore,
        'params': {'Smax': 200.0, 'b': 3.0},
        'bounds': {'Smax': (50.0, 500.0), 'b': (0.5, 10.0)},
        'states': {'S0': 50.0},
        'input_map': 'P_PET',
    },
}


# Elements without ODE solver (BaseElement subclasses)
_BASEELEM_REGISTRY: Dict[str, Dict[str, Any]] = {
    'InterceptionFilter': {
        'cls': InterceptionFilter,
        'params': {},
        'bounds': {},
        'states': {},
        'input_map': 'PET_P',
        'output_index': 1,  # net_P (throughfall), index 0 is net_PET
    },
}

_LAG_REGISTRY: Dict[str, Dict[str, Any]] = {
    'HalfTriangularLag': {'cls': HalfTriangularLag, 'default': 2.0, 'bounds': (1.0, 10.0)},
    'UnitHydrograph1':   {'cls': UnitHydrograph1,   'default': 2.0, 'bounds': (1.0, 10.0)},
    'UnitHydrograph2':   {'cls': UnitHydrograph2,   'default': 2.0, 'bounds': (1.0, 10.0)},
}
_DEFAULT_LAG_TYPE = 'HalfTriangularLag'


def _make_lag_element(type_name: str, eid: str, lag_time=None):
    """Create a SuperflexPy lag element (discrete convolution, no ODE solver)."""
    reg = _LAG_REGISTRY[type_name]
    safe = eid.replace('_', '')
    t = lag_time if lag_time is not None else reg['default']
    return reg['cls'](parameters={'lag-time': float(t)}, states={'lag': None}, id=safe)


def _make_element(type_name: str, eid: str):
    """Create a SuperflexPy element with defaults and a fresh ODE solver."""
    safe = eid.replace('_', '')  # SuperflexPy ids must not contain '_'

    # BaseElement (no solver) — e.g. InterceptionFilter
    if type_name in _BASEELEM_REGISTRY:
        reg = _BASEELEM_REGISTRY[type_name]
        return reg['cls'](id=safe)

    reg = _REGISTRY[type_name]
    solver = ImplicitEulerPython(root_finder=PegasusPython())
    return reg['cls'](
        parameters=dict(reg['params']),
        states=dict(reg['states']),
        approximation=solver,
        id=safe,
    )


# ===================================================================
# SuperflexEnv
# ===================================================================

class SuperflexEnv:
    """
    Module B: 自动化建模环境
    负责将 JSON 结构转化为可运行的 SuperflexPy 模型，并自动寻找最优参数。
    不同的结构 JSON 会产生不同的模拟流量。
    """

    def __init__(self):
        self.structure_json: Dict[str, Any] = {}
        self.elements: Dict[str, Dict[str, Any]] = {}
        self._sfpy_els: Optional[Dict[str, Any]] = None
        self._topo: Optional[Dict[str, Any]] = None

    # ------------------------------------------------------------------
    # Public API
    # ------------------------------------------------------------------

    def run(
        self,
        structure_json: Dict[str, Any],
        forcing_data: pd.DataFrame,
        obs_data: pd.Series,
    ) -> Tuple[pd.Series, float]:
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
        return result['qsim'], float(result['nse'])

    def parse_structure(self, structure_json: Dict[str, Any]) -> None:
        """Parse structure JSON and build the SuperflexPy model graph."""
        layers = structure_json.get('layers', [])
        if not isinstance(layers, list):
            raise ValueError('`layers` must be a list in structure_json.')

        self.structure_json = structure_json
        self.elements = {}
        for layer in layers:
            layer_id = layer.get('id')
            if layer_id:
                self.elements[str(layer_id)] = layer

        self._sfpy_els = None
        self._topo = None
        if layers:
            self._build_topology(layers, structure_json)

    def run_simulation(
        self,
        forcing_data: pd.DataFrame,
        params: Optional[Dict[str, float]] = None,
    ) -> pd.Series:
        """Run the parsed model with given parameters."""
        if not self.structure_json:
            raise ValueError('Structure has not been parsed. Call parse_structure() first.')
        if forcing_data.empty:
            raise ValueError('forcing_data is empty.')
        return self._run_sfpy(forcing_data, params)

    def auto_calibrate(
        self,
        forcing_data: pd.DataFrame,
        obs_data: pd.Series,
        n_trials: int = 2000,
        n_restarts: int = 1,
    ) -> Dict[str, Any]:
        """Calibrate the model against observations."""
        if obs_data.empty:
            raise ValueError('obs_data is empty.')
        return self._calibrate_sfpy(forcing_data, obs_data, n_trials=n_trials, n_restarts=n_restarts)

    # ------------------------------------------------------------------
    # Topology builder
    # ------------------------------------------------------------------

    def _build_topology(self, layers, structure_json):
        """Analyse JSON layers -> build SuperflexPy elements + dependency graph."""
        all_ids = {lyr['id'] for lyr in layers}
        els: Dict[str, Any] = {}
        types: Dict[str, str] = {}
        deps: Dict[str, Dict[str, Any]] = {}
        raw_inputs: Dict[str, list] = {}

        for lyr in layers:
            lid, ltype = lyr['id'], lyr['type']
            if ltype not in _REGISTRY and ltype not in _BASEELEM_REGISTRY:
                raise ValueError(f'Unknown component: {ltype}')

            els[lid] = _make_element(ltype, lid)
            types[lid] = ltype

            inputs = lyr.get('inputs', [])
            raw_inputs[lid] = inputs
            is_root = any(inp.lower() in _FORCING_NAMES for inp in inputs)
            sources = [
                inp.split('.')[0]
                for inp in inputs
                if '.' in inp and inp.split('.')[0] in all_ids
            ]
            is_hybrid = is_root and len(sources) > 0
            deps[lid] = {'root': is_root, 'sources': sources, 'hybrid': is_hybrid}

        pure_roots = [lid for lid, d in deps.items() if d['root'] and not d['hybrid']]
        hybrid_roots = [lid for lid, d in deps.items() if d['hybrid']]
        downstream = [lid for lid, d in deps.items() if not d['root'] and d['sources']]

        fan_out: Dict[str, list] = {}
        for lid in hybrid_roots + downstream:
            for src in deps[lid]['sources']:
                fan_out.setdefault(src, []).append(lid)

        sys_out = structure_json.get('system_output', [layers[-1]['id']])
        id_map = {lid: lid.replace('_', '') for lid in els}

        # --- Parse lag_functions ---
        lag_els: Dict[str, Any] = {}
        lag_types: Dict[str, str] = {}
        for lag_cfg in structure_json.get('lag_functions', []):
            target = lag_cfg.get('target')
            if not target or target not in all_ids:
                continue
            ltype = lag_cfg.get('type', _DEFAULT_LAG_TYPE)
            if ltype not in _LAG_REGISTRY:
                raise ValueError(f'Unknown lag type: {ltype}')
            lag_time = lag_cfg.get('lag_steps', None)
            lag_id = f'lag_{target}'
            lag_els[target] = _make_lag_element(ltype, lag_id, lag_time)
            lag_types[target] = ltype

        self._sfpy_els = els
        self._topo = {
            'roots': pure_roots,
            'order': pure_roots + hybrid_roots + downstream,
            'deps': deps,
            'types': types,
            'fan_out': fan_out,
            'sys_out': sys_out,
            'id_map': id_map,
            'lag_els': lag_els,
            'lag_types': lag_types,
            'raw_inputs': raw_inputs,
        }

    # ------------------------------------------------------------------
    # SuperflexPy simulation
    # ------------------------------------------------------------------

    def _run_sfpy(self, forcing_data, params=None):
        """Execute the SuperflexPy element graph in topological order."""
        prcp, ep, temp = self._pick_forcing_columns(forcing_data)
        p_arr = prcp.values.astype(np.float64)
        e_arr = ep.values.astype(np.float64)
        t_arr = temp.values.astype(np.float64) if temp is not None else None
        params = params or {}

        lag_els = self._topo.get('lag_els', {})

        for el in self._sfpy_els.values():
            if hasattr(el, 'reset_states'):
                el.reset_states()
            if hasattr(el, 'set_timestep'):
                el.set_timestep(1.0)
        for lag_el in lag_els.values():
            lag_el.reset_states()

        for lid in self._topo['order']:
            el = self._sfpy_els[lid]
            if hasattr(el, 'get_parameters_name'):
                el_p = {k: v for k, v in params.items() if k in el.get_parameters_name()}
                if el_p:
                    el.set_parameters(el_p)
        for lag_el in lag_els.values():
            lag_p = {k: v for k, v in params.items() if k in lag_el.get_parameters_name()}
            if lag_p:
                lag_el.set_parameters(lag_p)

        outputs: Dict[str, np.ndarray] = {}
        fan_out = self._topo['fan_out']

        for lid in self._topo['order']:
            el = self._sfpy_els[lid]
            dep = self._topo['deps'][lid]
            ltype = self._topo['types'][lid]

            if dep.get('hybrid'):
                inp_arrays = []
                for inp in self._topo['raw_inputs'][lid]:
                    if '.' in inp and inp.split('.')[0] in outputs:
                        inp_arrays.append(outputs[inp.split('.')[0]])
                    else:
                        inp_arrays.append(self._resolve_forcing(inp.lower(), p_arr, e_arr, t_arr))
                el.set_input(inp_arrays)
            elif dep['root']:
                reg = _REGISTRY.get(ltype) or _BASEELEM_REGISTRY.get(ltype, {})
                input_map = reg.get('input_map', 'P')
                el.set_input(self._build_root_input(input_map, p_arr, e_arr, t_arr))
            else:
                src = dep['sources'][0]
                src_q = outputs[src]

                consumers = fan_out.get(src, [lid])
                if len(consumers) >= 2:
                    idx = consumers.index(lid)
                    n = len(consumers)
                    # Collect N-1 raw split values; last fraction = 1 - sum(others)
                    raw = [float(params.get(f'__split_{src}_{i}', 0.5))
                           for i in range(n - 1)]
                    raw_sum = sum(raw)
                    if raw_sum > 0.99:
                        # Normalize to prevent negative remainder
                        scale = 0.99 / raw_sum
                        fracs = [r * scale for r in raw] + [0.01]
                    else:
                        fracs = raw + [1.0 - raw_sum]
                    el.set_input([src_q * fracs[idx]])
                else:
                    el.set_input([src_q])

            try:
                out = el.get_output(solve=True)
                # BaseElement (e.g. InterceptionFilter) may use a specific output index
                base_reg = _BASEELEM_REGISTRY.get(ltype)
                out_idx = base_reg['output_index'] if base_reg else 0
                raw = out[out_idx]
            except RuntimeError:
                raw = np.full_like(p_arr, np.nan)

            if lid in lag_els:
                lag_els[lid].set_input([raw])
                try:
                    raw = lag_els[lid].get_output(solve=True)[0]
                except RuntimeError:
                    raw = np.full_like(p_arr, np.nan)

            outputs[lid] = raw

        qsim = np.sum([outputs[o] for o in self._topo['sys_out']], axis=0)
        return pd.Series(np.maximum(qsim, 0.0), index=forcing_data.index, name='qsim')

    # ------------------------------------------------------------------
    # Calibration (differential_evolution)
    # ------------------------------------------------------------------

    def _collect_calib_params(self):
        """Return [(param_name, lo, hi), ...] for all calibratable parameters."""
        pinfo = []
        for lid in self._topo['order']:
            ltype = self._topo['types'][lid]
            reg = _REGISTRY.get(ltype) or _BASEELEM_REGISTRY.get(ltype, {})
            safe = self._topo['id_map'][lid]
            for pn, (lo, hi) in reg.get('bounds', {}).items():
                pinfo.append((f'{safe}_{pn}', lo, hi))

        for src, consumers in self._topo['fan_out'].items():
            n = len(consumers)
            if n >= 2:
                for i in range(n - 1):
                    pinfo.append((f'__split_{src}_{i}', 0.01, 0.99))

        for target, lag_el in self._topo.get('lag_els', {}).items():
            ltype = self._topo['lag_types'][target]
            lo, hi = _LAG_REGISTRY[ltype]['bounds']
            for pn in lag_el.get_parameters_name():
                pinfo.append((pn, lo, hi))

        return pinfo

    def _calibrate_sfpy(self, forcing_data, obs_data, n_trials=2000, n_restarts=1):
        """Global optimisation via CMA-ES with optional multi-restart.

        Restart i uses seed `42 + i * 1000`, matching the convention in
        src/xaj_global_pilot/xaj_model.py::_cmaes_multi_restart so XAJ and
        Superflex calibration share a comparable restart schedule. The
        best NSE across restarts is returned.
        """
        if n_restarts < 1:
            raise ValueError(f'n_restarts must be >= 1, got {n_restarts}')

        pinfo = self._collect_calib_params()
        names = [n for n, _, _ in pinfo]
        lo = np.array([l for _, l, _ in pinfo])
        hi = np.array([h for _, _, h in pinfo])

        ndim = len(names)
        if ndim == 0:
            q = self._run_sfpy(forcing_data, {})
            nse_val = self._nse(obs_data, q)
            return {'nse': float(nse_val), 'optimized_params': {}, 'qsim': q}

        # Work in normalised [0, 1] space so CMA-ES treats all dimensions equally.
        def objective(x_norm):
            x = lo + np.clip(x_norm, 0.0, 1.0) * (hi - lo)
            p = dict(zip(names, x.tolist()))
            try:
                q = self._run_sfpy(forcing_data, p)
                nse = self._nse(obs_data, q)
                return 1.0 - nse if np.isfinite(nse) else 2.0
            except Exception:
                return 2.0

        x0 = [0.5] * ndim
        best_overall: Optional[Dict[str, Any]] = None
        for restart in range(n_restarts):
            seed = 42 + restart * 1000
            es = cma.CMAEvolutionStrategy(x0, 0.3, {
                'bounds': [[0.0] * ndim, [1.0] * ndim],
                'maxfevals': n_trials,
                'seed': seed,
                'verbose': -9,
            })
            es.optimize(objective)

            best_x = lo + np.clip(es.result.xbest, 0.0, 1.0) * (hi - lo)
            best_p = dict(zip(names, best_x.tolist()))
            try:
                best_q = self._run_sfpy(forcing_data, best_p)
                best_nse = self._nse(obs_data, best_q)
            except Exception:
                best_q = pd.Series(np.zeros(len(obs_data)), index=obs_data.index, name='qsim')
                best_nse = -999.0

            candidate = {'nse': float(best_nse), 'optimized_params': best_p, 'qsim': best_q}
            if best_overall is None or candidate['nse'] > best_overall['nse']:
                best_overall = candidate

        return best_overall

    # ------------------------------------------------------------------
    # Utilities
    # ------------------------------------------------------------------

    @staticmethod
    def _pick_forcing_columns(
        forcing_data: pd.DataFrame,
    ) -> Tuple[pd.Series, pd.Series, Optional[pd.Series]]:
        """Return (prcp, ep, temp).  temp is None when no temperature column exists."""
        prcp_col = 'prcp' if 'prcp' in forcing_data.columns else forcing_data.columns[0]
        ep_col: Optional[str] = None
        for c in ('ep', 'pet', 'evap', 'evaporation'):
            if c in forcing_data.columns:
                ep_col = c
                break
        prcp = forcing_data[prcp_col].astype(float).fillna(0.0)
        if ep_col is None:
            ep = pd.Series(0.0, index=forcing_data.index)
        else:
            ep = forcing_data[ep_col].astype(float).fillna(0.0)

        # Temperature: tmean > tavg > temp > temperature > synthesise from tmax+tmin
        temp: Optional[pd.Series] = None
        for c in ('tmean', 'tavg', 'temp', 'temperature'):
            if c in forcing_data.columns:
                temp = forcing_data[c].astype(float).fillna(0.0)
                break
        if temp is None and 'tmax' in forcing_data.columns and 'tmin' in forcing_data.columns:
            temp = ((forcing_data['tmax'] + forcing_data['tmin']) / 2.0).astype(float).fillna(0.0)

        return prcp, ep, temp

    @staticmethod
    def _build_root_input(input_map: str, p_arr, e_arr, t_arr) -> list:
        """Build the input list for a root element based on its input_map spec."""
        if input_map == 'P':
            return [p_arr]
        if input_map == 'P_PET':
            return [p_arr, e_arr]
        if input_map == 'PET_P':
            return [e_arr, p_arr]
        if input_map == 'P_T':
            if t_arr is None:
                raise ValueError('SnowReservoir requires temperature data but none found in forcing.')
            return [p_arr, t_arr]
        raise ValueError(f'Unknown input_map: {input_map}')

    @staticmethod
    def _resolve_forcing(name, p_arr, e_arr, t_arr):
        """Map a single forcing input name to its numpy array."""
        if name in ('prcp', 'precipitation', 'rainfall', 'p'):
            return p_arr
        if name in ('ep', 'pet', 'evap', 'evaporation'):
            return e_arr
        if name in ('temp', 'temperature', 'tmean', 'tavg'):
            if t_arr is None:
                raise ValueError(f'Forcing "{name}" required but no temperature column found.')
            return t_arr
        raise ValueError(f'Unknown forcing name: {name}')

    @staticmethod
    def _nse(obs: pd.Series, sim: pd.Series) -> float:
        common_idx = obs.index.intersection(sim.index)
        if len(common_idx) == 0:
            return float('-inf')
        o = obs.loc[common_idx].astype(float).replace([np.inf, -np.inf], np.nan).dropna()
        s = sim.loc[o.index].astype(float).replace([np.inf, -np.inf], np.nan).dropna()
        common_idx = o.index.intersection(s.index)
        if len(common_idx) == 0:
            return float('-inf')
        o = o.loc[common_idx]
        s = s.loc[common_idx]
        denom = float(((o - o.mean()) ** 2).sum())
        if denom <= 1e-12:
            return float('-inf')
        num = float(((o - s) ** 2).sum())
        return 1.0 - num / denom

    def _build_model(self, json_config):
        self.parse_structure(json_config)
        return self

    def _auto_calibrate(self, model, forcing, obs):
        return self.auto_calibrate(forcing, obs).get('optimized_params', {})
