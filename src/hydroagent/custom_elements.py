"""Custom SuperflexPy elements for HydroAgent.

Extends the SuperflexPy component library with processes not covered by the
standard GR4J/HBV/HYMOD/Thur elements:
  - DeepGroundwater: slow deep aquifer with leakage loss
  - ConveyanceLoss: transmission losses for arid/semi-arid channels
"""
from __future__ import annotations

import os
import sys

_HERE = os.path.dirname(os.path.abspath(__file__))
_PROJECT_ROOT = os.path.abspath(os.path.join(_HERE, '..', '..'))
_SFPY_DIR = os.path.join(_PROJECT_ROOT, 'external', 'superflexpy')
if os.path.isdir(_SFPY_DIR) and _SFPY_DIR not in sys.path:
    sys.path.insert(0, _SFPY_DIR)

from superflexpy.framework.element import ODEsElement


class DeepGroundwater(ODEsElement):
    """Very slow groundwater reservoir with optional deep percolation loss.

    dS/dt = recharge - baseflow - leakage
    baseflow = k * S          (k << 0.01, very slow drainage)
    leakage  = f_loss * S     (fraction lost to deep aquifer, never returns)

    Parameters: k (drainage rate), f_loss (leakage fraction)
    Input: recharge from upstream element
    Output: baseflow (slow discharge to stream)
    """

    def __init__(self, parameters, states, approximation, id):
        ODEsElement.__init__(self, parameters=parameters, states=states,
                             approximation=approximation, id=id)
        self._fluxes_python = [self._fluxes_function_python]
        if approximation.architecture == "python":
            self._fluxes = [self._fluxes_function_python]
        else:
            # Fallback to python (no numba jit for simplicity)
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
        # Output = baseflow (flux index 1, negated because outflow)
        return [-fluxes[0][1]]

    @staticmethod
    def _fluxes_function_python(S, S0, ind, P, k, f_loss, dt):
        if ind is None:
            return (
                [
                    P,             # recharge in
                    -k * S,        # baseflow out
                    -f_loss * S,   # deep leakage loss
                ],
                0.0,
                S0 + P * dt,
            )
        else:
            return (
                [
                    P[ind],
                    -k[ind] * S,
                    -f_loss[ind] * S,
                ],
                0.0,
                S0 + P[ind] * dt[ind],
                [0.0, -k[ind], -f_loss[ind]],
            )


class ConveyanceLoss(ODEsElement):
    """Channel transmission loss reservoir for arid/semi-arid basins.

    Models water loss from the channel to the alluvium (ephemeral streams).
    dS/dt = inflow - outflow - loss
    outflow = k * S           (linear channel routing)
    loss    = f_loss * S      (transmission loss to alluvium)

    Parameters: k (routing rate), f_loss (transmission loss fraction)
    Input: inflow from upstream
    Output: channel outflow (reduced by losses)
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
    def _fluxes_function_python(S, S0, ind, P, k, f_loss, dt):
        if ind is None:
            return (
                [
                    P,
                    -k * S,
                    -f_loss * S,
                ],
                0.0,
                S0 + P * dt,
            )
        else:
            return (
                [
                    P[ind],
                    -k[ind] * S,
                    -f_loss[ind] * S,
                ],
                0.0,
                S0 + P[ind] * dt[ind],
                [0.0, -k[ind], -f_loss[ind]],
            )
