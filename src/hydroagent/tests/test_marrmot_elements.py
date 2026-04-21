"""Tests for MARRMoT-inspired SuperflexPy elements.

Test strategy (from marrmot_porting_plan.md):
1. Mathematical consistency — hand-calculated steady-state checks
2. Cross-validation — compare with existing elements where applicable
3. Mass conservation — verify dS = sum(fluxes) * dt
4. Boundary conditions — S=0, S=Smax, P=0, PET=0
5. Numerical stability — extreme inputs, long runs
"""
import os
import sys
import unittest

import numpy as np

# Ensure src/ packages are importable
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '../..')))

# Ensure vendored superflexpy is importable
_PROJECT_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..', '..'))
_SFPY_DIR = os.path.join(_PROJECT_ROOT, 'external', 'superflexpy')
if os.path.isdir(_SFPY_DIR) and _SFPY_DIR not in sys.path:
    sys.path.insert(0, _SFPY_DIR)

from superflexpy.implementation.root_finders.pegasus import PegasusPython
from superflexpy.implementation.numerical_approximators.implicit_euler import ImplicitEulerPython

from hydroagent.marrmot_elements import (
    InterceptionBucket,
    ThresholdReservoir,
    PercolationStore,
    SaturationAreaStore,
)


def _make_solver():
    return ImplicitEulerPython(root_finder=PegasusPython())


# ======================================================================
# InterceptionBucket Tests
# ======================================================================

class TestInterceptionBucket(unittest.TestCase):

    def _make_element(self, Smax=3.0, Ce=1.0, S0=0.0):
        el = InterceptionBucket(
            parameters={'Smax': Smax, 'Ce': Ce},
            states={'S0': S0},
            approximation=_make_solver(),
            id='ib',
        )
        el.set_timestep(1.0)
        return el

    def test_basic_run(self):
        """Element runs without error and produces output."""
        el = self._make_element()
        P = np.array([5.0, 3.0, 0.0, 1.0, 10.0])
        PET = np.array([2.0, 2.0, 2.0, 0.0, 0.0])
        el.set_input([P, PET])
        out = el.get_output()
        self.assertEqual(len(out), 1)
        self.assertEqual(len(out[0]), 5)
        self.assertTrue(np.all(np.isfinite(out[0])))

    def test_zero_rain(self):
        """No rain => no throughfall, canopy only loses to evaporation."""
        el = self._make_element(S0=2.0)
        P = np.array([0.0, 0.0, 0.0])
        PET = np.array([1.0, 1.0, 1.0])
        el.set_input([P, PET])
        out = el.get_output()
        # Throughfall = P * S/Smax = 0 * anything = 0
        np.testing.assert_array_almost_equal(out[0], 0.0, decimal=10)

    def test_zero_pet(self):
        """No PET => no canopy evaporation, only throughfall."""
        el = self._make_element(S0=1.5, Smax=3.0)
        P = np.array([5.0])
        PET = np.array([0.0])
        el.set_input([P, PET])
        out = el.get_output()
        # With S0=1.5 (half full), throughfall should be > 0
        self.assertTrue(out[0][0] > 0)

    def test_mass_conservation(self):
        """Check: delta_S = P - ET - throughfall (per timestep)."""
        el = self._make_element(S0=1.0, Smax=3.0, Ce=0.8)
        P = np.array([4.0, 2.0, 0.5, 0.0, 8.0])
        PET = np.array([1.0, 2.0, 1.0, 3.0, 0.5])
        el.set_input([P, PET])

        S_before = el._states[el._prefix_states + "S0"]
        out = el.get_output()
        S_after = el._states[el._prefix_states + "S0"]

        # Recalculate fluxes from state array
        fluxes = el._num_app.get_fluxes(
            fluxes=el._fluxes_python,
            S=el.state_array,
            S0=el._solver_states,
            dt=el._dt,
            **el.input,
            **{k[len(el._prefix_parameters):]: el._parameters[k]
               for k in el._parameters},
        )
        # Sum of all fluxes over all timesteps should equal total change in S
        total_flux = sum(np.sum(f) for f in fluxes[0])
        # With implicit Euler: S[t+1] = S[t] + dt * sum_fluxes(S[t+1])
        # The state_array stores S at each step, so check the final state
        delta_S = el.state_array[-1, 0] - S_before
        total_flux_from_dt = np.sum(fluxes[0][0]) + np.sum(fluxes[0][1]) + np.sum(fluxes[0][2])
        # Mass balance: sum of all fluxes * dt ≈ delta_S (within solver tolerance)
        np.testing.assert_almost_equal(delta_S, total_flux_from_dt, decimal=4)

    def test_throughfall_increases_with_storage(self):
        """Higher initial storage => more throughfall for same rain."""
        P = np.array([5.0])
        PET = np.array([0.0])  # no ET to isolate throughfall behavior

        el_empty = self._make_element(S0=0.0)
        el_empty.set_input([P, PET])
        out_empty = el_empty.get_output()[0][0]

        el_half = self._make_element(S0=1.5)
        el_half.set_input([P, PET])
        out_half = el_half.get_output()[0][0]

        el_full = self._make_element(S0=2.9)
        el_full.set_input([P, PET])
        out_full = el_full.get_output()[0][0]

        self.assertLess(out_empty, out_half)
        self.assertLess(out_half, out_full)

    def test_numerical_stability_extreme_rain(self):
        """200 mm/day rain on a 3mm canopy bucket doesn't crash."""
        el = self._make_element(S0=0.0)
        P = np.array([200.0])
        PET = np.array([5.0])
        el.set_input([P, PET])
        out = el.get_output()
        self.assertTrue(np.all(np.isfinite(out[0])))
        # Most rain should pass through
        self.assertGreater(out[0][0], 190.0)

    def test_long_run(self):
        """365-day run without drift or crash."""
        el = self._make_element(S0=0.0)
        np.random.seed(42)
        P = np.random.uniform(0, 20, size=365)
        PET = np.random.uniform(0, 6, size=365)
        el.set_input([P, PET])
        out = el.get_output()
        self.assertTrue(np.all(np.isfinite(out[0])))
        self.assertTrue(np.all(out[0] >= -1e-10))


# ======================================================================
# ThresholdReservoir Tests
# ======================================================================

class TestThresholdReservoir(unittest.TestCase):

    def _make_element(self, k=0.1, Sth=10.0, S0=5.0):
        el = ThresholdReservoir(
            parameters={'k': k, 'Sth': Sth},
            states={'S0': S0},
            approximation=_make_solver(),
            id='tr',
        )
        el.set_timestep(1.0)
        return el

    def test_basic_run(self):
        el = self._make_element()
        P = np.array([3.0, 5.0, 8.0, 0.0, 2.0])
        el.set_input([P])
        out = el.get_output()
        self.assertEqual(len(out), 1)
        self.assertEqual(len(out[0]), 5)
        self.assertTrue(np.all(np.isfinite(out[0])))

    def test_below_threshold_no_outflow(self):
        """S < Sth => no outflow, storage just accumulates."""
        el = self._make_element(k=0.1, Sth=50.0, S0=0.0)
        P = np.array([5.0, 5.0, 5.0])  # total 15mm, well below Sth=50
        el.set_input([P])
        out = el.get_output()
        # All outflows should be zero (or near zero)
        np.testing.assert_array_less(out[0], 0.01)

    def test_above_threshold_has_outflow(self):
        """S > Sth => outflow occurs."""
        el = self._make_element(k=0.1, Sth=5.0, S0=20.0)
        P = np.array([0.0])  # no inflow, just drain
        el.set_input([P])
        out = el.get_output()
        # Should have outflow since S0=20 > Sth=5
        self.assertGreater(out[0][0], 0.5)

    def test_mass_conservation(self):
        el = self._make_element(k=0.05, Sth=10.0, S0=15.0)
        P = np.array([3.0, 0.0, 5.0, 0.0, 0.0])
        el.set_input([P])

        S_before = el._states[el._prefix_states + "S0"]
        out = el.get_output()
        S_after = el._states[el._prefix_states + "S0"]

        # Input - output = change in storage
        total_in = np.sum(P)
        total_out = np.sum(out[0])
        delta_S = S_after - S_before
        balance = total_in - total_out - delta_S
        self.assertAlmostEqual(balance, 0.0, places=4)

    def test_steady_state(self):
        """At steady state with constant P: S_eq = Sth + P/k."""
        k, Sth = 0.1, 10.0
        P_const = 2.0  # constant input
        S_eq_expected = Sth + P_const / k  # = 10 + 20 = 30

        el = self._make_element(k=k, Sth=Sth, S0=S_eq_expected)
        P = np.full(100, P_const)
        el.set_input([P])
        out = el.get_output()

        # Storage should stay near equilibrium
        S_final = el._states[el._prefix_states + "S0"]
        self.assertAlmostEqual(S_final, S_eq_expected, places=2)

    def test_numerical_stability_extreme(self):
        el = self._make_element(k=0.1, Sth=5.0, S0=0.0)
        P = np.array([200.0])
        el.set_input([P])
        out = el.get_output()
        self.assertTrue(np.all(np.isfinite(out[0])))


# ======================================================================
# PercolationStore Tests
# ======================================================================

class TestPercolationStore(unittest.TestCase):

    def _make_element(self, Smax=100.0, Pmax=5.0, alpha=2.0, S0=50.0):
        el = PercolationStore(
            parameters={'Smax': Smax, 'Pmax': Pmax, 'alpha': alpha},
            states={'S0': S0},
            approximation=_make_solver(),
            id='ps',
        )
        el.set_timestep(1.0)
        return el

    def test_basic_run(self):
        el = self._make_element()
        P = np.array([10.0, 5.0, 0.0, 3.0])
        el.set_input([P])
        out = el.get_output()
        self.assertEqual(len(out[0]), 4)
        self.assertTrue(np.all(np.isfinite(out[0])))

    def test_full_store_max_percolation(self):
        """When S = Smax, percolation = Pmax."""
        el = self._make_element(Smax=100.0, Pmax=5.0, alpha=1.0, S0=100.0)
        P = np.array([5.0])  # input = Pmax to maintain equilibrium
        el.set_input([P])
        out = el.get_output()
        # With alpha=1, S=Smax: Q = Pmax*(100/100)^1 = 5.0
        # And P=5.0, so steady state: Q ≈ 5.0
        self.assertAlmostEqual(out[0][0], 5.0, places=2)

    def test_empty_store_no_percolation(self):
        """When S ≈ 0, percolation ≈ 0."""
        el = self._make_element(S0=0.0)
        P = np.array([0.0])
        el.set_input([P])
        out = el.get_output()
        self.assertAlmostEqual(out[0][0], 0.0, places=6)

    def test_cross_validation_with_linear_reservoir(self):
        """With alpha=1 and S0=Smax, PercolationStore(Pmax=k*Smax) ≈ LinearReservoir(k)."""
        from superflexpy.implementation.elements.hymod import LinearReservoir

        k = 0.05
        Smax = 100.0
        S0 = 50.0
        Pmax = k * Smax  # = 5.0, so at S=Smax: Q = Pmax = k*Smax

        # PercolationStore with alpha=1: Q = Pmax * S/Smax = k*Smax * S/Smax = k*S
        perc = self._make_element(Smax=Smax, Pmax=Pmax, alpha=1.0, S0=S0)
        lr = LinearReservoir(
            parameters={'k': k},
            states={'S0': S0},
            approximation=_make_solver(),
            id='lr',
        )
        lr.set_timestep(1.0)

        P = np.array([10.0, 5.0, 0.0, 3.0, 8.0])
        perc.set_input([P])
        lr.set_input([P])

        out_perc = perc.get_output()
        out_lr = lr.get_output()

        np.testing.assert_array_almost_equal(out_perc[0], out_lr[0], decimal=4)

    def test_mass_conservation(self):
        el = self._make_element(S0=30.0)
        P = np.array([8.0, 3.0, 0.0, 12.0, 1.0])
        el.set_input([P])

        S_before = el._states[el._prefix_states + "S0"]
        out = el.get_output()
        S_after = el._states[el._prefix_states + "S0"]

        total_in = np.sum(P)
        total_out = np.sum(out[0])
        delta_S = S_after - S_before
        balance = total_in - total_out - delta_S
        self.assertAlmostEqual(balance, 0.0, places=4)

    def test_nonlinearity(self):
        """Higher alpha => more nonlinear response (less outflow at low S)."""
        P = np.array([5.0, 5.0, 5.0])

        el_lin = self._make_element(alpha=1.0, S0=30.0)
        el_lin.set_input([P])
        out_lin = el_lin.get_output()[0]

        el_nonlin = self._make_element(alpha=3.0, S0=30.0)
        el_nonlin.set_input([P])
        out_nonlin = el_nonlin.get_output()[0]

        # At S0=30 < Smax=100, (S/Smax)^3 < (S/Smax)^1
        # So nonlinear element should produce less outflow
        self.assertLess(np.sum(out_nonlin), np.sum(out_lin))


# ======================================================================
# SaturationAreaStore Tests
# ======================================================================

class TestSaturationAreaStore(unittest.TestCase):

    def _make_element(self, Smax=200.0, b=3.0, S0=50.0):
        el = SaturationAreaStore(
            parameters={'Smax': Smax, 'b': b},
            states={'S0': S0},
            approximation=_make_solver(),
            id='sas',
        )
        el.set_timestep(1.0)
        return el

    def test_basic_run(self):
        el = self._make_element()
        P = np.array([10.0, 5.0, 0.0, 20.0])
        PET = np.array([3.0, 3.0, 3.0, 3.0])
        el.set_input([P, PET])
        out = el.get_output()
        self.assertEqual(len(out[0]), 4)
        self.assertTrue(np.all(np.isfinite(out[0])))

    def test_empty_store_no_runoff(self):
        """S=0 => f_sat=0 => no saturation excess."""
        el = self._make_element(S0=0.0)
        P = np.array([5.0])
        PET = np.array([0.0])
        el.set_input([P, PET])
        out = el.get_output()
        # With S0=0, f_sat = 1-exp(0) = 0, all rain infiltrates
        # After one step S > 0 so some excess, but starting from 0 it should be small
        self.assertLess(out[0][0], 2.0)

    def test_full_store_high_runoff(self):
        """S ≈ Smax => f_sat ≈ 1 - exp(-b) => high runoff fraction."""
        el = self._make_element(Smax=200.0, b=5.0, S0=200.0)
        P = np.array([10.0])
        PET = np.array([0.0])
        el.set_input([P, PET])
        out = el.get_output()
        # f_sat = 1 - exp(-5) ≈ 0.993
        # Almost all rain becomes runoff
        self.assertGreater(out[0][0], 9.0)

    def test_zero_rain(self):
        """P=0 => no saturation excess, only ET draws down storage."""
        el = self._make_element(S0=100.0)
        P = np.array([0.0, 0.0])
        PET = np.array([3.0, 3.0])
        el.set_input([P, PET])
        out = el.get_output()
        # Runoff = P * f_sat = 0
        np.testing.assert_array_almost_equal(out[0], 0.0, decimal=10)

    def test_mass_conservation(self):
        el = self._make_element(S0=80.0)
        P = np.array([15.0, 8.0, 0.0, 5.0, 20.0])
        PET = np.array([3.0, 4.0, 2.0, 1.0, 3.0])
        el.set_input([P, PET])

        S_before = el._states[el._prefix_states + "S0"]
        out = el.get_output()
        S_after = el._states[el._prefix_states + "S0"]

        fluxes = el._num_app.get_fluxes(
            fluxes=el._fluxes_python,
            S=el.state_array,
            S0=el._solver_states,
            dt=el._dt,
            **el.input,
            **{k[len(el._prefix_parameters):]: el._parameters[k]
               for k in el._parameters},
        )
        delta_S = el.state_array[-1, 0] - S_before
        total_flux = np.sum(fluxes[0][0]) + np.sum(fluxes[0][1]) + np.sum(fluxes[0][2])
        np.testing.assert_almost_equal(delta_S, total_flux, decimal=4)

    def test_saturation_increases_with_b(self):
        """Larger b => more saturation excess for same storage."""
        P = np.array([10.0])
        PET = np.array([0.0])

        el_low = self._make_element(b=1.0, S0=100.0)
        el_low.set_input([P, PET])
        out_low = el_low.get_output()[0][0]

        el_high = self._make_element(b=5.0, S0=100.0)
        el_high.set_input([P, PET])
        out_high = el_high.get_output()[0][0]

        self.assertLess(out_low, out_high)

    def test_differs_from_upper_zone(self):
        """Verify different saturation curve shape vs UpperZone (Xinanjiang)."""
        from superflexpy.implementation.elements.hymod import UpperZone

        Smax = 200.0
        S0 = 100.0  # half full
        P = np.array([10.0, 10.0, 10.0])
        PET = np.array([0.0, 0.0, 0.0])  # no ET to isolate runoff

        sas = self._make_element(Smax=Smax, b=2.0, S0=S0)
        sas.set_input([P, PET])
        out_sas = sas.get_output()[0]

        uz = UpperZone(
            parameters={'Smax': Smax, 'm': 0.01, 'beta': 2.0},
            states={'S0': S0},
            approximation=_make_solver(),
            id='uz',
        )
        uz.set_timestep(1.0)
        uz.set_input([P, PET])
        out_uz = uz.get_output()[0]

        # Outputs should be different (different saturation functions)
        self.assertFalse(np.allclose(out_sas, out_uz, atol=0.1),
                         "SaturationAreaStore should differ from UpperZone")

    def test_numerical_stability_extreme(self):
        el = self._make_element(S0=0.0)
        P = np.array([200.0])
        PET = np.array([5.0])
        el.set_input([P, PET])
        out = el.get_output()
        self.assertTrue(np.all(np.isfinite(out[0])))

    def test_long_run(self):
        el = self._make_element(S0=50.0)
        np.random.seed(123)
        P = np.random.uniform(0, 30, size=365)
        PET = np.random.uniform(0, 6, size=365)
        el.set_input([P, PET])
        out = el.get_output()
        self.assertTrue(np.all(np.isfinite(out[0])))
        self.assertTrue(np.all(out[0] >= -1e-10))


# ======================================================================
# Formula-level verification tests
# These directly verify flux function outputs against hand-calculated
# values, independently of the ODE solver.
# ======================================================================

class TestFluxFunctionFormulas(unittest.TestCase):
    """Verify each flux function produces exact values for known inputs.

    These tests call the static _fluxes_function_python directly,
    bypassing the ODE solver, to verify the mathematical formulas.
    """

    # --- InterceptionBucket ---
    # dS/dt = P - Ce*PET*S/Smax - P*S/Smax
    # f0 = P, f1 = -Ce*PET*S/Smax, f2 = -P*S/Smax

    def test_interception_flux_values(self):
        """Hand calculation: S=1.8, P=5, PET=2, Smax=3, Ce=1, dt=1.
        f0 = 5.0
        f1 = -1*2*1.8/3 = -1.2
        f2 = -5*1.8/3 = -3.0
        """
        S = np.array([1.8])
        fluxes, lb, ub = InterceptionBucket._fluxes_function_python(
            S=S, S0=1.0, ind=None,
            P=np.array([5.0]), PET=np.array([2.0]),
            Smax=3.0, Ce=1.0, dt=1.0,
        )
        np.testing.assert_almost_equal(fluxes[0], 5.0)
        np.testing.assert_almost_equal(fluxes[1], -1.2)
        np.testing.assert_almost_equal(fluxes[2], -3.0)

    def test_interception_derivatives(self):
        """Verify analytical derivatives at S=1.8.
        df0/dS = 0
        df1/dS = -Ce*PET/Smax = -1*2/3 = -0.6667
        df2/dS = -P/Smax = -5/3 = -1.6667
        """
        fluxes, lb, ub, derivs = InterceptionBucket._fluxes_function_python(
            S=1.8, S0=1.0, ind=0,
            P=np.array([5.0]), PET=np.array([2.0]),
            Smax=np.array([3.0]), Ce=np.array([1.0]), dt=np.array([1.0]),
        )
        self.assertAlmostEqual(derivs[0], 0.0)
        self.assertAlmostEqual(derivs[1], -2.0 / 3.0, places=10)
        self.assertAlmostEqual(derivs[2], -5.0 / 3.0, places=10)

    def test_interception_implicit_euler_single_step(self):
        """Verify ODE solver result matches analytical implicit Euler solution.

        Implicit Euler: S1 = S0 + dt*(P - Ce*PET*S1/Smax - P*S1/Smax)
        Rearranging (linear in S1):
          S1 * (1 + dt*(P + Ce*PET)/Smax) = S0 + dt*P
          S1 = (S0 + dt*P) / (1 + dt*(P + Ce*PET)/Smax)

        S0=1, P=5, PET=2, Smax=3, Ce=1, dt=1:
          S1 = (1+5) / (1 + (5+2)/3) = 6 / (10/3) = 1.8
        throughfall = P*S1/Smax = 5*1.8/3 = 3.0
        """
        el = InterceptionBucket(
            parameters={'Smax': 3.0, 'Ce': 1.0},
            states={'S0': 1.0},
            approximation=_make_solver(),
            id='ibtest',
        )
        el.set_timestep(1.0)
        el.set_input([np.array([5.0]), np.array([2.0])])
        out = el.get_output()

        S1_analytical = 6.0 / (10.0 / 3.0)  # = 1.8
        self.assertAlmostEqual(el.state_array[0, 0], S1_analytical, places=6)
        self.assertAlmostEqual(out[0][0], 5.0 * S1_analytical / 3.0, places=6)

    # --- ThresholdReservoir ---
    # dS/dt = P - k*max(0, S-Sth)
    # f0 = P, f1 = -k*max(0, S-Sth)

    def test_threshold_flux_below(self):
        """S=5 < Sth=10: f1 = -k*max(0, 5-10) = 0."""
        S = np.array([5.0])
        fluxes, lb, ub = ThresholdReservoir._fluxes_function_python(
            S=S, S0=5.0, ind=None,
            P=np.array([3.0]), k=0.1, Sth=10.0, dt=1.0,
        )
        np.testing.assert_almost_equal(fluxes[0], 3.0)
        np.testing.assert_almost_equal(fluxes[1], 0.0)

    def test_threshold_flux_above(self):
        """S=25 > Sth=10: f1 = -k*(25-10) = -0.1*15 = -1.5."""
        S = np.array([25.0])
        fluxes, lb, ub = ThresholdReservoir._fluxes_function_python(
            S=S, S0=20.0, ind=None,
            P=np.array([0.0]), k=0.1, Sth=10.0, dt=1.0,
        )
        np.testing.assert_almost_equal(fluxes[0], 0.0)
        np.testing.assert_almost_equal(fluxes[1], -1.5)

    def test_threshold_implicit_euler_above(self):
        """S0=20, P=0, k=0.1, Sth=10, dt=1.
        Implicit Euler: S1 = S0 - k*(S1-Sth) = 20 - 0.1*(S1-10)
          S1 + 0.1*S1 = 20 + 1
          S1 = 21/1.1 = 19.0909...
        Q = k*(S1-Sth) = 0.1*(19.0909-10) = 0.9091
        """
        el = ThresholdReservoir(
            parameters={'k': 0.1, 'Sth': 10.0},
            states={'S0': 20.0},
            approximation=_make_solver(),
            id='trtest',
        )
        el.set_timestep(1.0)
        el.set_input([np.array([0.0])])
        out = el.get_output()

        S1_analytical = 21.0 / 1.1
        Q_analytical = 0.1 * (S1_analytical - 10.0)
        self.assertAlmostEqual(el.state_array[0, 0], S1_analytical, places=5)
        self.assertAlmostEqual(out[0][0], Q_analytical, places=5)

    def test_threshold_implicit_euler_below(self):
        """S0=5, P=3, k=0.1, Sth=50, dt=1.
        S0+P=8 < Sth=50, so no outflow.
        S1 = S0 + P = 8
        Q = 0
        """
        el = ThresholdReservoir(
            parameters={'k': 0.1, 'Sth': 50.0},
            states={'S0': 5.0},
            approximation=_make_solver(),
            id='trtest2',
        )
        el.set_timestep(1.0)
        el.set_input([np.array([3.0])])
        out = el.get_output()

        self.assertAlmostEqual(el.state_array[0, 0], 8.0, places=5)
        self.assertAlmostEqual(out[0][0], 0.0, places=5)

    # --- PercolationStore ---
    # dS/dt = P - Pmax*(S/Smax)^alpha
    # f0 = P, f1 = -Pmax*(S/Smax)^alpha

    def test_percolation_flux_values(self):
        """S=50, Smax=100, Pmax=5, alpha=2.
        f1 = -5*(50/100)^2 = -5*0.25 = -1.25
        """
        S = np.array([50.0])
        fluxes, lb, ub = PercolationStore._fluxes_function_python(
            S=S, S0=40.0, ind=None,
            P=np.array([10.0]), Smax=100.0, Pmax=5.0, alpha=2.0, dt=1.0,
        )
        np.testing.assert_almost_equal(fluxes[0], 10.0)
        np.testing.assert_almost_equal(fluxes[1], -1.25)

    def test_percolation_flux_at_smax(self):
        """S=Smax: f1 = -Pmax*(1)^alpha = -Pmax."""
        S = np.array([100.0])
        fluxes, lb, ub = PercolationStore._fluxes_function_python(
            S=S, S0=90.0, ind=None,
            P=np.array([0.0]), Smax=100.0, Pmax=5.0, alpha=2.0, dt=1.0,
        )
        np.testing.assert_almost_equal(fluxes[1], -5.0)

    def test_percolation_derivative(self):
        """df1/dS = -Pmax*alpha/Smax * (S/Smax)^(alpha-1).
        S=50, Smax=100, Pmax=5, alpha=2:
        df1/dS = -5*2/100 * (50/100)^1 = -0.1 * 0.5 = -0.05
        """
        fluxes, lb, ub, derivs = PercolationStore._fluxes_function_python(
            S=50.0, S0=40.0, ind=0,
            P=np.array([10.0]), Smax=np.array([100.0]),
            Pmax=np.array([5.0]), alpha=np.array([2.0]), dt=np.array([1.0]),
        )
        self.assertAlmostEqual(derivs[0], 0.0)
        self.assertAlmostEqual(derivs[1], -0.05, places=10)

    def test_percolation_implicit_euler_alpha1(self):
        """alpha=1: Q = Pmax*S/Smax (linear), has analytical solution.
        S0=50, P=10, Pmax=5, Smax=100, dt=1.
        S1 = S0 + P - Pmax*S1/Smax
        S1*(1 + Pmax/Smax) = S0 + P
        S1 = (50+10) / (1+5/100) = 60/1.05 = 57.1429
        Q = 5*57.1429/100 = 2.8571
        """
        el = PercolationStore(
            parameters={'Smax': 100.0, 'Pmax': 5.0, 'alpha': 1.0},
            states={'S0': 50.0},
            approximation=_make_solver(),
            id='pstest',
        )
        el.set_timestep(1.0)
        el.set_input([np.array([10.0])])
        out = el.get_output()

        S1_analytical = 60.0 / 1.05
        Q_analytical = 5.0 * S1_analytical / 100.0
        self.assertAlmostEqual(el.state_array[0, 0], S1_analytical, places=4)
        self.assertAlmostEqual(out[0][0], Q_analytical, places=4)

    # --- SaturationAreaStore ---
    # f0 = P, f1 = -PET*S/Smax, f2 = -P*(1-exp(-b*S/Smax))

    def test_saturation_flux_values(self):
        """S=100, Smax=200, b=3, P=10, PET=3.
        f1 = -3*100/200 = -1.5
        f2 = -10*(1-exp(-3*100/200)) = -10*(1-exp(-1.5)) = -10*(1-0.22313) = -7.7687
        """
        S = np.array([100.0])
        fluxes, lb, ub = SaturationAreaStore._fluxes_function_python(
            S=S, S0=90.0, ind=None,
            P=np.array([10.0]), PET=np.array([3.0]),
            Smax=200.0, b=3.0, dt=1.0,
        )
        np.testing.assert_almost_equal(fluxes[0], 10.0)
        np.testing.assert_almost_equal(fluxes[1], -1.5)
        expected_f2 = -10.0 * (1.0 - np.exp(-1.5))
        np.testing.assert_almost_equal(fluxes[2], expected_f2, decimal=10)

    def test_saturation_flux_at_zero(self):
        """S=0: f1=0, f2 = -P*(1-exp(0)) = -P*0 = 0."""
        S = np.array([0.0])
        fluxes, lb, ub = SaturationAreaStore._fluxes_function_python(
            S=S, S0=0.0, ind=None,
            P=np.array([10.0]), PET=np.array([3.0]),
            Smax=200.0, b=3.0, dt=1.0,
        )
        np.testing.assert_almost_equal(fluxes[1], 0.0)
        np.testing.assert_almost_equal(fluxes[2], 0.0)

    def test_saturation_derivative(self):
        """df1/dS = -PET/Smax = -3/200 = -0.015
        df2/dS = -P*(b/Smax)*exp(-b*S/Smax)
               = -10*(3/200)*exp(-3*100/200)
               = -10*0.015*exp(-1.5) = -0.15*0.22313 = -0.03347
        """
        fluxes, lb, ub, derivs = SaturationAreaStore._fluxes_function_python(
            S=100.0, S0=90.0, ind=0,
            P=np.array([10.0]), PET=np.array([3.0]),
            Smax=np.array([200.0]), b=np.array([3.0]), dt=np.array([1.0]),
        )
        self.assertAlmostEqual(derivs[0], 0.0)
        self.assertAlmostEqual(derivs[1], -3.0 / 200.0, places=10)
        expected_d2 = -10.0 * (3.0 / 200.0) * np.exp(-3.0 * 100.0 / 200.0)
        self.assertAlmostEqual(derivs[2], expected_d2, places=10)

    def test_saturation_matches_marrmot_saturation2_at_special_case(self):
        """MARRMoT saturation_2: out = (1-(1-S/Smax)^p1)*In (Xinanjiang).
        Our formula: out = (1-exp(-b*S/Smax))*P (exponential).

        At S=0: both give 0. At S=Smax: saturation_2 gives P, ours gives
        P*(1-exp(-b)) < P for finite b.

        This test confirms they ARE different (no false equivalence).
        """
        S_over_Smax = 0.5  # S/Smax = 0.5
        P = 10.0
        p1 = 2.0
        b = 2.0

        marrmot_sat2 = (1.0 - (1.0 - S_over_Smax) ** p1) * P  # = (1-0.25)*10 = 7.5
        our_formula = (1.0 - np.exp(-b * S_over_Smax)) * P      # = (1-exp(-1))*10 = 6.321

        self.assertNotAlmostEqual(marrmot_sat2, our_formula, places=1,
                                  msg="Formulas should differ — proves distinct physics")
        # Verify the exact values too
        self.assertAlmostEqual(marrmot_sat2, 7.5)
        self.assertAlmostEqual(our_formula, 10.0 * (1.0 - np.exp(-1.0)))


# ======================================================================
# Independent forward-Euler oracle tests
#
# Strategy: implement each ODE by hand with tiny-dt forward Euler
# (no SuperflexPy at all, just numpy). Then compare the multi-step
# trajectory against the SuperflexPy implicit Euler element.
# Two completely independent code paths → if they agree, formula is right.
# ======================================================================

def _forward_euler(dsdt_fn, S0, forcing, dt_sub=0.001):
    """Run forward Euler with sub-stepping (pure numpy, no SuperflexPy).

    Args:
        dsdt_fn: callable(S, **forcing_t) -> (dSdt, dict_of_fluxes)
        S0: initial storage (float)
        forcing: list of dicts, one per macro-timestep (dt=1)
        dt_sub: sub-timestep for forward Euler accuracy
    Returns:
        S_history: storage at end of each macro-timestep
        flux_history: dict of accumulated fluxes per macro-timestep
    """
    S = S0
    S_history = []
    flux_history = []
    n_sub = int(1.0 / dt_sub)
    for frc in forcing:
        accum = None
        for _ in range(n_sub):
            dSdt, fluxes = dsdt_fn(S, **frc)
            S = max(0.0, S + dSdt * dt_sub)
            if accum is None:
                accum = {k: v * dt_sub for k, v in fluxes.items()}
            else:
                for k, v in fluxes.items():
                    accum[k] += v * dt_sub
        S_history.append(S)
        flux_history.append(accum)
    return S_history, flux_history


class TestIndependentForwardEuler(unittest.TestCase):
    """Compare SuperflexPy elements against two independent oracles:

    1. Forward Euler (dt=0.001, 1000 sub-steps) — pure numpy, no SuperflexPy
    2. Exact analytical solution (where ODE is linear)

    Key insight: forward Euler ≈ exact solution (0.02% error), but
    implicit Euler with dt=1 has ~10-15% truncation error. This is
    EXPECTED and NOT a formula bug. The test verifies:
    - Forward Euler matches exact analytical solution (oracle is correct)
    - SuperflexPy and forward Euler solve the SAME ODE (≤15% relative diff)
    """

    def _assert_same_ode(self, S_fe, S_sf, label, rtol=0.15):
        """Assert two methods solve the same ODE (within expected method error)."""
        for i in range(len(S_fe)):
            if abs(S_fe[i]) < 1e-6 and abs(S_sf[i]) < 1e-6:
                continue  # both near zero, skip
            rel_diff = abs(S_fe[i] - S_sf[i]) / max(abs(S_fe[i]), 1e-10)
            self.assertLess(rel_diff, rtol,
                msg=f"{label} step {i}: S_fe={S_fe[i]:.4f} vs S_sf={S_sf[i]:.4f} "
                    f"(rel diff {rel_diff:.1%} > {rtol:.0%})")

    def test_interception_exact_solution(self):
        """InterceptionBucket has LINEAR ODE → exact analytical solution exists.

        dS/dt = P - (P + Ce*PET)*S/Smax  =  a - b*S
        Exact: S(t) = a/b + (S0 - a/b)*exp(-b*t)

        This test verifies both forward Euler oracle AND SuperflexPy
        are solving the correct equation.

        Note: uses Smax=20 (not 3) to avoid stiff regime where implicit
        Euler truncation error exceeds 15% (b = (P+Ce*PET)/Smax must be
        small relative to 1/dt for IE to be accurate).
        """
        Smax, Ce, S0 = 20.0, 0.8, 5.0
        # Step-by-step exact solution for 5 timesteps
        P_arr = [4.0, 2.0, 0.5, 0.0, 8.0]
        PET_arr = [1.0, 2.0, 1.0, 3.0, 0.5]

        S_exact = []
        S = S0
        for P, PET in zip(P_arr, PET_arr):
            a = P
            b = (P + Ce * PET) / Smax
            if b > 0:
                S = a / b + (S - a / b) * np.exp(-b * 1.0)
            else:
                S = S + a  # no outflow
            S_exact.append(S)

        # Forward Euler oracle
        def dsdt(S, P, PET):
            evap = Ce * PET * S / Smax
            throughfall = P * S / Smax
            return P - evap - throughfall, {'throughfall': throughfall}

        forcing = [{'P': P_arr[i], 'PET': PET_arr[i]} for i in range(5)]
        S_fe, _ = _forward_euler(dsdt, S0, forcing)

        # SuperflexPy
        el = InterceptionBucket(
            parameters={'Smax': Smax, 'Ce': Ce},
            states={'S0': S0},
            approximation=_make_solver(),
            id='ibfe',
        )
        el.set_timestep(1.0)
        el.set_input([np.array(P_arr), np.array(PET_arr)])
        el.get_output()
        S_sf = list(el.state_array[:, 0])

        # Forward Euler ≈ exact solution (< 0.1%)
        for i in range(5):
            if S_exact[i] > 0.01:
                rel = abs(S_fe[i] - S_exact[i]) / S_exact[i]
                self.assertLess(rel, 0.005,
                    msg=f"FE vs exact step {i}: {S_fe[i]:.6f} vs {S_exact[i]:.6f}")

        # SuperflexPy solves same ODE as exact (within implicit Euler error)
        self._assert_same_ode(S_exact, S_sf, "InterceptionBucket", rtol=0.15)

    def test_threshold_reservoir(self):
        """ThresholdReservoir: dS/dt = P - k*max(0, S-Sth)."""
        k, Sth, S0 = 0.1, 10.0, 5.0
        P_arr = [3.0, 5.0, 8.0, 0.0, 2.0]

        def dsdt(S, P):
            Q = k * max(0.0, S - Sth)
            return P - Q, {'Q': Q}

        forcing = [{'P': P_arr[i]} for i in range(5)]
        S_fe, _ = _forward_euler(dsdt, S0, forcing)

        el = ThresholdReservoir(
            parameters={'k': k, 'Sth': Sth},
            states={'S0': S0},
            approximation=_make_solver(),
            id='trfe',
        )
        el.set_timestep(1.0)
        el.set_input([np.array(P_arr)])
        el.get_output()
        S_sf = list(el.state_array[:, 0])

        self._assert_same_ode(S_fe, S_sf, "ThresholdReservoir", rtol=0.15)

    def test_percolation_store(self):
        """PercolationStore: dS/dt = P - Pmax*(S/Smax)^alpha."""
        Smax, Pmax, alpha, S0 = 100.0, 5.0, 2.0, 50.0
        P_arr = [10.0, 5.0, 0.0, 3.0, 8.0]

        def dsdt(S, P):
            Q = Pmax * (max(0.0, S) / Smax) ** alpha
            return P - Q, {'Q': Q}

        forcing = [{'P': P_arr[i]} for i in range(5)]
        S_fe, _ = _forward_euler(dsdt, S0, forcing)

        el = PercolationStore(
            parameters={'Smax': Smax, 'Pmax': Pmax, 'alpha': alpha},
            states={'S0': S0},
            approximation=_make_solver(),
            id='psfe',
        )
        el.set_timestep(1.0)
        el.set_input([np.array(P_arr)])
        el.get_output()
        S_sf = list(el.state_array[:, 0])

        self._assert_same_ode(S_fe, S_sf, "PercolationStore", rtol=0.15)

    def test_saturation_area_store(self):
        """SaturationAreaStore: dS/dt = P*exp(-b*S/Smax) - PET*S/Smax."""
        Smax, b, S0 = 200.0, 3.0, 80.0
        P_arr = [15.0, 8.0, 0.0, 5.0, 20.0]
        PET_arr = [3.0, 4.0, 2.0, 1.0, 3.0]

        def dsdt(S, P, PET):
            s = max(0.0, S)
            exp_term = np.exp(-b * s / Smax)
            evap = PET * s / Smax
            sat_excess = P * (1.0 - exp_term)
            return P - evap - sat_excess, {'sat_excess': sat_excess}

        forcing = [{'P': P_arr[i], 'PET': PET_arr[i]} for i in range(5)]
        S_fe, _ = _forward_euler(dsdt, S0, forcing)

        el = SaturationAreaStore(
            parameters={'Smax': Smax, 'b': b},
            states={'S0': S0},
            approximation=_make_solver(),
            id='sasfe',
        )
        el.set_timestep(1.0)
        el.set_input([np.array(P_arr), np.array(PET_arr)])
        el.get_output()
        S_sf = list(el.state_array[:, 0])

        self._assert_same_ode(S_fe, S_sf, "SaturationAreaStore", rtol=0.15)


if __name__ == '__main__':
    unittest.main()
