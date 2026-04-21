"""MARRMoT-inspired flux function elements for SuperflexPy.

Ported from MARRMoT v2.1 (Knoben et al., 2019, 2022) to extend the
HydroAgent component library with processes not covered by the standard
GR4J/HBV/HYMOD elements:
  - InterceptionBucket: parametric canopy interception with storage
  - ThresholdReservoir: baseflow with storage threshold
  - PercolationStore: normalized nonlinear percolation (S/Smax)
  - SaturationAreaStore: TOPMODEL-like exponential saturation area

References:
    Knoben, W. J. M., et al. (2019): MARRMoT v1.2, GMD, 12, 2463-2480.
    Knoben, W. J. M., et al. (2022): MARRMoT v2.1, GMD, 15, 6359-6369.
"""
from __future__ import annotations

import os
import sys

_HERE = os.path.dirname(os.path.abspath(__file__))
_PROJECT_ROOT = os.path.abspath(os.path.join(_HERE, '..', '..'))
_SFPY_DIR = os.path.join(_PROJECT_ROOT, 'external', 'superflexpy')
if os.path.isdir(_SFPY_DIR) and _SFPY_DIR not in sys.path:
    sys.path.insert(0, _SFPY_DIR)

import numpy as np

from superflexpy.framework.element import ODEsElement


class InterceptionBucket(ODEsElement):
    """Parametric canopy interception bucket with storage state.

    MARRMoT ref: interception_1 concept (threshold-based throughfall)
    with added evaporation from canopy storage.

    A small reservoir (Smax ~ 1-5 mm) that intercepts rainfall.
    As the bucket fills, a larger fraction of rain passes through.

    dS/dt = P - Ce*PET*S/Smax - P*S/Smax
    Fluxes:
        f0 = +P               (rainfall input)
        f1 = -Ce*PET*S/Smax   (evaporation from canopy)
        f2 = -P*S/Smax        (throughfall)

    Parameters: Smax (canopy capacity [mm]), Ce (evap coefficient [-])
    Inputs: P (rainfall [mm/d]), PET (potential ET [mm/d])
    Output: throughfall [mm/d]
    """

    def __init__(self, parameters, states, approximation, id):
        ODEsElement.__init__(self, parameters=parameters, states=states,
                             approximation=approximation, id=id)
        self._fluxes_python = [self._fluxes_function_python]
        if approximation.architecture == "python":
            self._fluxes = [self._fluxes_function_python]
        else:
            self._fluxes = [self._fluxes_function_python]

    def set_input(self, input):
        self.input = {"P": input[0], "PET": input[1]}

    def get_output(self, solve=True):
        if solve:
            self._solver_states = [self._states[self._prefix_states + "S0"]]
            self._solve_differential_equation()
            self.set_states({self._prefix_states + "S0": self.state_array[-1, 0]})

        fluxes = self._num_app.get_fluxes(
            fluxes=self._fluxes_python,
            S=self.state_array,
            S0=self._solver_states,
            dt=self._dt,
            **self.input,
            **{k[len(self._prefix_parameters):]: self._parameters[k]
               for k in self._parameters},
        )
        return [-fluxes[0][2]]

    @staticmethod
    def _fluxes_function_python(S, S0, ind, P, PET, Smax, Ce, dt):
        if ind is None:
            return (
                [
                    P,
                    -Ce * PET * S / Smax,
                    -P * S / Smax,
                ],
                0.0,
                S0 + P * dt,
            )
        else:
            return (
                [
                    P[ind],
                    -Ce[ind] * PET[ind] * S / Smax[ind],
                    -P[ind] * S / Smax[ind],
                ],
                0.0,
                S0 + P[ind] * dt[ind],
                [
                    0.0,
                    -Ce[ind] * PET[ind] / Smax[ind],
                    -P[ind] / Smax[ind],
                ],
            )


class ThresholdReservoir(ODEsElement):
    """Reservoir with threshold-based baseflow.

    MARRMoT ref: conceptually related to baseflow variants with storage
    threshold (e.g., models where groundwater only discharges when storage
    exceeds a minimum level).

    No outflow until storage exceeds threshold Sth, then linear drainage.

    dS/dt = P - k * max(0, S - Sth)
    Fluxes:
        f0 = +P                       (inflow)
        f1 = -k * max(0, S - Sth)     (threshold baseflow)

    Parameters: k (drainage rate [d-1]), Sth (threshold storage [mm])
    Inputs: P (inflow [mm/d])
    Output: baseflow [mm/d]
    """

    def __init__(self, parameters, states, approximation, id):
        ODEsElement.__init__(self, parameters=parameters, states=states,
                             approximation=approximation, id=id)
        self._fluxes_python = [self._fluxes_function_python]
        if approximation.architecture == "python":
            self._fluxes = [self._fluxes_function_python]
        else:
            self._fluxes = [self._fluxes_function_python]

    def set_input(self, input):
        self.input = {"P": input[0]}

    def get_output(self, solve=True):
        if solve:
            self._solver_states = [self._states[self._prefix_states + "S0"]]
            self._solve_differential_equation()
            self.set_states({self._prefix_states + "S0": self.state_array[-1, 0]})

        fluxes = self._num_app.get_fluxes(
            fluxes=self._fluxes_python,
            S=self.state_array,
            S0=self._solver_states,
            dt=self._dt,
            **self.input,
            **{k[len(self._prefix_parameters):]: self._parameters[k]
               for k in self._parameters},
        )
        return [-fluxes[0][1]]

    @staticmethod
    def _fluxes_function_python(S, S0, ind, P, k, Sth, dt):
        if ind is None:
            return (
                [
                    P,
                    -k * np.maximum(0.0, S - Sth),
                ],
                0.0,
                S0 + P * dt,
            )
        else:
            excess = max(0.0, S - Sth[ind])
            return (
                [
                    P[ind],
                    -k[ind] * excess,
                ],
                0.0,
                S0 + P[ind] * dt[ind],
                [
                    0.0,
                    -k[ind] if S > Sth[ind] else 0.0,
                ],
            )


class PercolationStore(ODEsElement):
    """Normalized nonlinear percolation reservoir.

    MARRMoT ref: percolation_5 / baseflow_5
        Q = Pmax * (S/Smax)^alpha

    Different from PowerReservoir (Q = k*S^alpha): uses S/Smax normalization,
    making the outflow rate relative to maximum capacity. Pmax controls the
    peak percolation rate when the store is full.

    dS/dt = P - Pmax * (S/Smax)^alpha
    Fluxes:
        f0 = +P                           (inflow)
        f1 = -Pmax * (S/Smax)^alpha       (percolation)

    Parameters: Smax (capacity [mm]), Pmax (max perc rate [mm/d]),
                alpha (exponent [-])
    Inputs: P (inflow [mm/d])
    Output: percolation [mm/d]
    """

    def __init__(self, parameters, states, approximation, id):
        ODEsElement.__init__(self, parameters=parameters, states=states,
                             approximation=approximation, id=id)
        self._fluxes_python = [self._fluxes_function_python]
        if approximation.architecture == "python":
            self._fluxes = [self._fluxes_function_python]
        else:
            self._fluxes = [self._fluxes_function_python]

    def set_input(self, input):
        self.input = {"P": input[0]}

    def get_output(self, solve=True):
        if solve:
            self._solver_states = [self._states[self._prefix_states + "S0"]]
            self._solve_differential_equation()
            self.set_states({self._prefix_states + "S0": self.state_array[-1, 0]})

        fluxes = self._num_app.get_fluxes(
            fluxes=self._fluxes_python,
            S=self.state_array,
            S0=self._solver_states,
            dt=self._dt,
            **self.input,
            **{k[len(self._prefix_parameters):]: self._parameters[k]
               for k in self._parameters},
        )
        return [-fluxes[0][1]]

    @staticmethod
    def _fluxes_function_python(S, S0, ind, P, Smax, Pmax, alpha, dt):
        if ind is None:
            return (
                [
                    P,
                    -Pmax * (np.maximum(0.0, S) / Smax) ** alpha,
                ],
                0.0,
                S0 + P * dt,
            )
        else:
            s_ratio = max(0.0, S) / Smax[ind]
            return (
                [
                    P[ind],
                    -Pmax[ind] * s_ratio ** alpha[ind],
                ],
                0.0,
                S0 + P[ind] * dt[ind],
                [
                    0.0,
                    (-Pmax[ind] * alpha[ind] / Smax[ind]
                     * s_ratio ** (alpha[ind] - 1))
                    if S > 0.0 else 0.0,
                ],
            )


class SaturationAreaStore(ODEsElement):
    """TOPMODEL-like exponential saturation area reservoir.

    MARRMoT ref: inspired by saturation_1..3 concepts, using an
    exponential saturated area fraction distinct from the Xinanjiang
    (UpperZone) and HBV (UnsaturatedReservoir) power-law formulations.

    Saturated fraction: f_sat = 1 - exp(-b * S / Smax)
    - Differs from UpperZone: 1 - (1-S/Smax)^beta (Xinanjiang curve)
    - Differs from UnsaturatedReservoir: (S/Smax)^beta (power law)

    dS/dt = P * exp(-b*S/Smax) - PET * S/Smax
    Fluxes:
        f0 = +P                              (rainfall input)
        f1 = -PET * S / Smax                 (proportional ET)
        f2 = -P * (1 - exp(-b * S / Smax))   (saturation excess runoff)

    Parameters: Smax (capacity [mm]), b (saturation shape [-])
    Inputs: P (rainfall [mm/d]), PET (potential ET [mm/d])
    Output: saturation excess runoff [mm/d]
    """

    def __init__(self, parameters, states, approximation, id):
        ODEsElement.__init__(self, parameters=parameters, states=states,
                             approximation=approximation, id=id)
        self._fluxes_python = [self._fluxes_function_python]
        if approximation.architecture == "python":
            self._fluxes = [self._fluxes_function_python]
        else:
            self._fluxes = [self._fluxes_function_python]

    def set_input(self, input):
        self.input = {"P": input[0], "PET": input[1]}

    def get_output(self, solve=True):
        if solve:
            self._solver_states = [self._states[self._prefix_states + "S0"]]
            self._solve_differential_equation()
            self.set_states({self._prefix_states + "S0": self.state_array[-1, 0]})

        fluxes = self._num_app.get_fluxes(
            fluxes=self._fluxes_python,
            S=self.state_array,
            S0=self._solver_states,
            dt=self._dt,
            **self.input,
            **{k[len(self._prefix_parameters):]: self._parameters[k]
               for k in self._parameters},
        )
        return [-fluxes[0][2]]

    @staticmethod
    def _fluxes_function_python(S, S0, ind, P, PET, Smax, b, dt):
        if ind is None:
            s_safe = np.maximum(0.0, S)
            exp_term = np.exp(-b * s_safe / Smax)
            return (
                [
                    P,
                    -PET * s_safe / Smax,
                    -P * (1.0 - exp_term),
                ],
                0.0,
                S0 + P * dt,
            )
        else:
            s_safe = max(0.0, S)
            exp_term = np.exp(-b[ind] * s_safe / Smax[ind])
            return (
                [
                    P[ind],
                    -PET[ind] * s_safe / Smax[ind],
                    -P[ind] * (1.0 - exp_term),
                ],
                0.0,
                S0 + P[ind] * dt[ind],
                [
                    0.0,
                    -PET[ind] / Smax[ind] if S > 0.0 else 0.0,
                    -P[ind] * (b[ind] / Smax[ind]) * exp_term
                    if S > 0.0 else 0.0,
                ],
            )
