# HydroAgent v11 Improvements Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Three targeted improvements to HydroAgent: LLM-chosen initial structure with basin metadata, data-driven convergence control, and correct N-way parallel split parameters.

**Architecture:** Changes span three files — `agent.py` (new initialization agent + convergence logic), `environment.py` (split parameter fix), and `data_loading.py` (basin metadata loader). Each change is independent and testable in isolation.

**Tech Stack:** Python, SuperflexPy, Optuna, pandas, CAMELS-US attributes

---

## File Structure

| File | Action | Responsibility |
|------|--------|---------------|
| `src/hydroagent/data_loading.py` | Modify | Add `load_basin_metadata()` returning climate/topo/vege attributes |
| `src/hydroagent/agent.py` | Modify | Add initialization agent, remove target_nse convergence, add floor protection |
| `src/hydroagent/environment.py` | Modify | Fix N-way split to use N-1 independent Optuna parameters |
| `src/hydroagent/tests/test_env.py` | Modify | Add test for 3-way parallel split |
| `src/hydroagent/tests/test_agent_init.py` | Create | Test initialization agent + convergence changes |

---

## Chunk 1: N-way Parallel Split Fix (environment.py)

### Task 1: Fix `_collect_calib_params` for N-way splits

**Files:**
- Modify: `src/hydroagent/environment.py:440-460` (`_collect_calib_params`)
- Modify: `src/hydroagent/environment.py:402-413` (`_run_sfpy` split logic)
- Test: `src/hydroagent/tests/test_env.py`

- [ ] **Step 1: Write the failing test for 3-way split parameter collection**

Add to `src/hydroagent/tests/test_env.py`:

```python
def test_three_way_split_params(self):
    """3 consumers of one source should produce 2 independent split params."""
    env = SuperflexEnv()
    structure = {
        'model_name': 'test_3way',
        'layers': [
            {'id': 'soil', 'type': 'UnsaturatedReservoir',
             'parameters': ['Smax', 'beta'], 'inputs': ['prcp', 'ep']},
            {'id': 'fast', 'type': 'PowerReservoir',
             'parameters': ['k', 'alpha'], 'inputs': ['soil.runoff']},
            {'id': 'inter', 'type': 'LinearReservoir',
             'parameters': ['k'], 'inputs': ['soil.runoff']},
            {'id': 'slow', 'type': 'LinearReservoir',
             'parameters': ['k'], 'inputs': ['soil.runoff']},
        ],
        'lag_functions': [],
        'system_output': ['fast', 'inter', 'slow'],
    }
    env.parse_structure(structure)
    pinfo = env._collect_calib_params()
    split_params = [name for name, _, _ in pinfo if name.startswith('__split_')]
    # N=3 consumers → N-1=2 independent split params
    self.assertEqual(len(split_params), 2)
    self.assertIn('__split_soil_0', split_params)
    self.assertIn('__split_soil_1', split_params)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd G:/github/pycharm/projects/neuralhydrology && python -m pytest src/hydroagent/tests/test_env.py::TestSuperflexEnv::test_three_way_split_params -v`
Expected: FAIL — currently produces 1 split param `__split_soil`, not 2.

- [ ] **Step 3: Fix `_collect_calib_params` to generate N-1 split params**

In `src/hydroagent/environment.py`, replace the split parameter collection (lines ~450-452):

```python
# OLD:
for src, consumers in self._topo['fan_out'].items():
    if len(consumers) >= 2:
        pinfo.append((f'__split_{src}', 0.1, 0.9))

# NEW:
for src, consumers in self._topo['fan_out'].items():
    n = len(consumers)
    if n >= 2:
        for i in range(n - 1):
            pinfo.append((f'__split_{src}_{i}', 0.01, 0.99))
```

- [ ] **Step 4: Fix `_run_sfpy` to use N-1 split params with softmax normalization**

In `src/hydroagent/environment.py`, replace the split consumption logic (lines ~406-411):

```python
# OLD:
consumers = fan_out.get(src, [lid])
if len(consumers) >= 2:
    idx = consumers.index(lid)
    s = float(params.get(f'__split_{src}', 0.5))
    frac = s if idx == 0 else (1.0 - s) / max(len(consumers) - 1, 1)
    el.set_input([src_q * frac])

# NEW:
consumers = fan_out.get(src, [lid])
if len(consumers) >= 2:
    idx = consumers.index(lid)
    n = len(consumers)
    # Collect raw split values, compute fractions via softmax-like normalization
    raw = [float(params.get(f'__split_{src}_{i}', 0.5)) for i in range(n - 1)]
    # Last fraction is 1 - sum(others), clamped to [0, 1]
    raw_sum = sum(raw)
    if raw_sum > 0.99:
        # Normalize to prevent negative remainder
        scale = 0.99 / raw_sum
        fracs = [r * scale for r in raw] + [0.01]
    else:
        fracs = raw + [1.0 - raw_sum]
    el.set_input([src_q * fracs[idx]])
```

- [ ] **Step 5: Run test to verify it passes**

Run: `cd G:/github/pycharm/projects/neuralhydrology && python -m pytest src/hydroagent/tests/test_env.py -v`
Expected: ALL PASS including new `test_three_way_split_params`.

- [ ] **Step 6: Write integration test — 3-way split calibration produces valid output**

Add to `src/hydroagent/tests/test_env.py`:

```python
def test_three_way_split_calibration(self):
    """3-way parallel structure should calibrate without error."""
    env = SuperflexEnv()
    structure = {
        'model_name': 'test_3way_calib',
        'layers': [
            {'id': 'soil', 'type': 'UnsaturatedReservoir',
             'parameters': ['Smax', 'beta'], 'inputs': ['prcp', 'ep']},
            {'id': 'fast', 'type': 'PowerReservoir',
             'parameters': ['k', 'alpha'], 'inputs': ['soil.runoff']},
            {'id': 'inter', 'type': 'LinearReservoir',
             'parameters': ['k'], 'inputs': ['soil.runoff']},
            {'id': 'slow', 'type': 'LinearReservoir',
             'parameters': ['k'], 'inputs': ['soil.runoff']},
        ],
        'lag_functions': [],
        'system_output': ['fast', 'inter', 'slow'],
    }
    env.parse_structure(structure)
    result = env.auto_calibrate(self.forcing, self.obs)
    self.assertTrue(result['nse'] > -999.0)
    # Verify all 3 split-related params are in the result
    split_params = [k for k in result['optimized_params'] if '__split_' in k]
    self.assertEqual(len(split_params), 2)
```

- [ ] **Step 7: Run full test suite and verify**

Run: `cd G:/github/pycharm/projects/neuralhydrology && python -m pytest src/hydroagent/tests/test_env.py -v`
Expected: ALL PASS.

- [ ] **Step 8: Commit**

```bash
git add src/hydroagent/environment.py src/hydroagent/tests/test_env.py
git commit -m "fix(hydroagent): N-way parallel split uses N-1 independent Optuna params

Previously, 3+ consumers shared (1-s) equally. Now each gets its own
optimizable fraction, enabling Optuna to find the best split ratios."
```

---

## Chunk 2: Basin Metadata Loading (data_loading.py)

### Task 2: Add `load_basin_metadata()` function

**Files:**
- Modify: `src/hydroagent/data_loading.py`
- Test: `src/hydroagent/tests/test_agent_init.py` (created in Task 3)

- [ ] **Step 1: Write the failing test**

Create `src/hydroagent/tests/test_agent_init.py`:

```python
import unittest
import sys
import os

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '../..')))

from hydroagent.data_loading import load_basin_metadata


class TestBasinMetadata(unittest.TestCase):
    def test_load_metadata_returns_expected_keys(self):
        """load_basin_metadata should return a dict with key basin properties."""
        meta = load_basin_metadata('01022500')
        expected_keys = {
            'area_km2', 'elev_mean', 'slope_mean',
            'p_mean', 'pet_mean', 'aridity', 'frac_snow', 'p_seasonality',
            'frac_forest', 'dom_land_cover',
        }
        self.assertTrue(expected_keys.issubset(set(meta.keys())),
                        f"Missing keys: {expected_keys - set(meta.keys())}")
        # Sanity: area should be positive
        self.assertGreater(meta['area_km2'], 0)
        # Sanity: aridity should be non-negative
        self.assertGreaterEqual(meta['aridity'], 0)

    def test_load_metadata_unknown_basin_raises(self):
        """Unknown basin ID should raise ValueError."""
        with self.assertRaises(ValueError):
            load_basin_metadata('99999999')
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd G:/github/pycharm/projects/neuralhydrology && python -m pytest src/hydroagent/tests/test_agent_init.py::TestBasinMetadata -v`
Expected: FAIL — `load_basin_metadata` does not exist yet.

- [ ] **Step 3: Implement `load_basin_metadata`**

Add to `src/hydroagent/data_loading.py`:

```python
def load_basin_metadata(
    basin_id: str,
    data_root: Union[str, Path, None] = None,
) -> dict:
    """Load CAMELS-US basin attributes for LLM context.

    Returns a flat dict with key physical/climatic properties that help
    an LLM choose an appropriate initial model structure.
    """
    data_root = str(data_root or _DEFAULT_DATA_ROOT)
    attr_dir = os.path.join(data_root, 'camels_attributes_v2.0')

    def _read_attr(filename, columns):
        df = pd.read_csv(os.path.join(attr_dir, filename), sep=';')
        df['gauge_id'] = df['gauge_id'].astype(str).str.zfill(8)
        row = df[df['gauge_id'] == basin_id]
        if row.empty:
            raise ValueError(f"Basin {basin_id} not found in {filename}")
        return {col: row.iloc[0][col] for col in columns if col in row.columns}

    meta = {}
    meta.update(_read_attr('camels_topo.txt', ['elev_mean', 'slope_mean', 'area_gages2']))
    meta.update(_read_attr('camels_clim.txt', ['p_mean', 'pet_mean', 'aridity', 'frac_snow', 'p_seasonality']))
    meta.update(_read_attr('camels_vege.txt', ['frac_forest', 'dom_land_cover']))

    # Rename for clarity
    if 'area_gages2' in meta:
        meta['area_km2'] = meta.pop('area_gages2')

    return meta
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd G:/github/pycharm/projects/neuralhydrology && python -m pytest src/hydroagent/tests/test_agent_init.py::TestBasinMetadata -v`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/hydroagent/data_loading.py src/hydroagent/tests/test_agent_init.py
git commit -m "feat(hydroagent): add load_basin_metadata for LLM context"
```

---

## Chunk 3: LLM-Chosen Initial Structure (agent.py)

### Task 3: Add Initialization Agent to `agent.py`

**Files:**
- Modify: `src/hydroagent/agent.py` (add prompt constant + `_choose_initial_structure` method)
- Modify: `src/hydroagent/agent.py:801-819` (`solve()` method)
- Test: `src/hydroagent/tests/test_agent_init.py`

- [ ] **Step 1: Write the failing test**

Add to `src/hydroagent/tests/test_agent_init.py`:

```python
from hydroagent.agent import (
    HydroAgent, MockLLMClient, build_init_prompt,
    INIT_PROMPT, AVAILABLE_COMPONENTS, DEFAULT_INITIAL_STRUCTURE,
)


class TestInitializationAgent(unittest.TestCase):
    def test_build_init_prompt_contains_metadata(self):
        """Init prompt should include basin metadata."""
        meta = {'area_km2': 574.0, 'aridity': 0.59, 'frac_snow': 0.25,
                'elev_mean': 200.0, 'frac_forest': 0.8, 'p_mean': 3.5,
                'dom_land_cover': 'Mixed Forests'}
        prompt = build_init_prompt(meta)
        self.assertIn('574.0', prompt)
        self.assertIn('0.25', prompt)       # frac_snow
        self.assertIn('Mixed Forests', prompt)
        self.assertIn('Available SuperflexPy', prompt)  # component library

    def test_solve_with_basin_meta_uses_init_agent(self):
        """When basin_meta is provided, solve should call _choose_initial_structure
        instead of using DEFAULT_INITIAL_STRUCTURE. MockLLMClient falls back to default."""
        import pandas as pd
        import numpy as np

        dates = pd.date_range('2000-01-01', periods=100, freq='D')
        forcing = pd.DataFrame({'prcp': np.random.uniform(0, 10, 100),
                                'ep': np.random.uniform(0, 3, 100)}, index=dates)
        obs = pd.Series(np.random.uniform(0, 5, 100), index=dates)

        agent = HydroAgent(MockLLMClient(), max_iterations=1)
        meta = {'area_km2': 574.0, 'aridity': 0.59, 'frac_snow': 0.25}
        result = agent.solve(forcing, obs, basin_meta=meta)
        # Should complete without error
        self.assertIn('best_nse', result)

    def test_solve_without_meta_uses_default(self):
        """When no basin_meta, solve should use DEFAULT_INITIAL_STRUCTURE as before."""
        import pandas as pd
        import numpy as np

        dates = pd.date_range('2000-01-01', periods=100, freq='D')
        forcing = pd.DataFrame({'prcp': np.random.uniform(0, 10, 100),
                                'ep': np.random.uniform(0, 3, 100)}, index=dates)
        obs = pd.Series(np.random.uniform(0, 5, 100), index=dates)

        agent = HydroAgent(MockLLMClient(), max_iterations=1)
        result = agent.solve(forcing, obs)
        self.assertIn('best_nse', result)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd G:/github/pycharm/projects/neuralhydrology && python -m pytest src/hydroagent/tests/test_agent_init.py::TestInitializationAgent -v`
Expected: FAIL — `build_init_prompt` and `INIT_PROMPT` do not exist.

- [ ] **Step 3: Add `INIT_PROMPT` constant and `build_init_prompt` function**

Add to `src/hydroagent/agent.py` after the existing prompt constants (~line 165):

```python
INIT_PROMPT = """You are a senior hydrologist. Given a basin's physical and climatic characteristics,
choose an appropriate INITIAL model structure for a conceptual rainfall-runoff model.

Rules:
1. Start simple: 2-3 layers maximum. The structure will be iteratively refined later.
2. Match the basin: snow-dominated basins need SnowReservoir, arid basins may need ConveyanceLoss,
   forested basins may benefit from InterceptionFilter.
3. Every structure MUST include at least one runoff generation layer and one routing layer.

You MUST respond with ONLY a valid JSON object. No explanations.
The JSON must have keys: "model_name", "layers", "lag_functions", "system_output"."""
```

Add `build_init_prompt` function after existing prompt builders:

```python
def build_init_prompt(basin_meta: dict) -> str:
    """Build the prompt for the initialization agent (step 0: choose starting structure)."""
    meta_lines = '\n'.join(f"  - {k}: {v}" for k, v in basin_meta.items())
    return f"""## Basin Characteristics
{meta_lines}

## Available Components
{AVAILABLE_COMPONENTS}

## Task
Based on the basin characteristics above, propose an initial model structure.
Return ONLY the JSON object."""
```

- [ ] **Step 4: Add `_choose_initial_structure` method to HydroAgent**

Add to class `HydroAgent` (after `__init__`, before `solve`):

```python
def _choose_initial_structure(self, basin_meta: dict) -> dict:
    """Use LLM to select an initial structure based on basin characteristics.

    Falls back to DEFAULT_INITIAL_STRUCTURE if LLM call fails or client is MockLLMClient.
    """
    if isinstance(self.llm, MockLLMClient):
        return deepcopy(DEFAULT_INITIAL_STRUCTURE)

    try:
        prompt = build_init_prompt(basin_meta)
        response_text = self.llm.chat(INIT_PROMPT, prompt)
        structure = extract_json_from_response(response_text)

        if not isinstance(structure, dict) or 'layers' not in structure:
            print("  [WARN] Init agent returned invalid structure, using default.")
            return deepcopy(DEFAULT_INITIAL_STRUCTURE)

        structure.setdefault('model_name', 'init_from_meta')
        structure.setdefault('lag_functions', [])
        structure.setdefault('system_output',
                             [structure['layers'][-1]['id']] if structure['layers'] else ['fast'])

        print(f"  [Init Agent] Chose: {structure.get('model_name')} "
              f"({len(structure['layers'])} layers)")

        if self.logger:
            self.logger.log_llm_response(0, prompt[:300], response_text, True)

        return structure
    except Exception as e:
        print(f"  [WARN] Init agent failed: {e}, using default.")
        return deepcopy(DEFAULT_INITIAL_STRUCTURE)
```

- [ ] **Step 5: Modify `solve()` to accept `basin_meta` and use init agent**

In `src/hydroagent/agent.py`, modify the `solve` method signature and initial structure selection:

```python
# OLD (line 801-819):
def solve(
    self,
    forcing: pd.DataFrame,
    obs: pd.Series,
    target_nse: float = 0.6,
    initial_structure: Optional[dict] = None,
) -> Dict[str, Any]:
    ...
    structure = deepcopy(initial_structure or DEFAULT_INITIAL_STRUCTURE)

# NEW:
def solve(
    self,
    forcing: pd.DataFrame,
    obs: pd.Series,
    target_nse: float = 0.6,
    initial_structure: Optional[dict] = None,
    basin_meta: Optional[dict] = None,
) -> Dict[str, Any]:
    ...
    if initial_structure is not None:
        structure = deepcopy(initial_structure)
    elif basin_meta is not None:
        structure = self._choose_initial_structure(basin_meta)
    else:
        structure = deepcopy(DEFAULT_INITIAL_STRUCTURE)
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `cd G:/github/pycharm/projects/neuralhydrology && python -m pytest src/hydroagent/tests/test_agent_init.py -v`
Expected: ALL PASS.

- [ ] **Step 7: Wire basin_meta through `run_batch.py`**

In `src/hydroagent/scripts/run_batch.py`, modify `run_single_experiment` to accept and pass basin metadata:

Add `basin_meta: Optional[dict] = None` parameter to `run_single_experiment()` signature (line 133).

Inside the try block (line ~207), pass it to solve:

```python
# OLD:
result = agent.solve(forcing, obs, target_nse=target_nse)

# NEW:
result = agent.solve(forcing, obs, target_nse=target_nse, basin_meta=basin_meta)
```

In `main()`, load metadata after loading basin data (line ~380):

```python
# After loading forcing/obs, also load metadata
from hydroagent.data_loading import load_basin_metadata
...
# Inside the basin loop, after load_camels_basin:
try:
    meta = load_basin_metadata(basin_id, data_root=args.data_root)
except Exception:
    meta = None
```

Pass `meta` into `basin_data` tuple and through to `run_single_experiment`.

- [ ] **Step 8: Commit**

```bash
git add src/hydroagent/agent.py src/hydroagent/data_loading.py \
        src/hydroagent/scripts/run_batch.py src/hydroagent/tests/test_agent_init.py
git commit -m "feat(hydroagent): LLM-chosen initial structure based on basin metadata

Add Initialization Agent (step 0): before the iterative loop, the LLM
sees basin characteristics (area, aridity, frac_snow, elevation, etc.)
and chooses an appropriate starting structure. Falls back to default
for MockLLMClient or on failure."
```

---

## Chunk 4: Convergence Control (agent.py)

### Task 4: Remove target_nse early stopping, add floor protection

**Files:**
- Modify: `src/hydroagent/agent.py:893-900` (convergence check in `solve()`)
- Modify: `src/hydroagent/agent.py:913-914` (logger finalize)
- Test: `src/hydroagent/tests/test_agent_init.py`

- [ ] **Step 1: Write the failing test — floor protection stops hopeless basins**

Add to `src/hydroagent/tests/test_agent_init.py`:

```python
class TestConvergenceControl(unittest.TestCase):
    def test_floor_protection_stops_early(self):
        """If best_nse < 0 after floor_patience iterations, solve should stop early."""
        import pandas as pd
        import numpy as np

        # Create adversarial data where NSE will always be negative
        dates = pd.date_range('2000-01-01', periods=100, freq='D')
        forcing = pd.DataFrame({'prcp': np.zeros(100), 'ep': np.zeros(100)}, index=dates)
        obs = pd.Series(np.ones(100) * 100, index=dates)  # constant 100, model will produce ~0

        agent = HydroAgent(MockLLMClient(), max_iterations=4)
        result = agent.solve(forcing, obs)

        # Should stop after 2 iterations (floor_patience), not run all 4
        self.assertLessEqual(len(agent.history), 2)

    def test_no_target_nse_early_stop(self):
        """solve() should NOT stop early when NSE exceeds old threshold of 0.6.
        It should always run max_iterations (unless floor protection triggers)."""
        import pandas as pd
        import numpy as np

        # Create easy data where NSE > 0.6 is trivially reached
        dates = pd.date_range('2000-01-01', periods=365, freq='D')
        prcp = np.random.uniform(0, 10, 365)
        forcing = pd.DataFrame({'prcp': prcp, 'ep': prcp * 0.3}, index=dates)
        obs = pd.Series(prcp * 0.4 + np.random.normal(0, 0.5, 365).clip(0), index=dates)

        agent = HydroAgent(MockLLMClient(), max_iterations=4)
        result = agent.solve(forcing, obs)

        # Should run all 4 iterations, NOT stop at target_nse
        self.assertEqual(len(agent.history), 4)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd G:/github/pycharm/projects/neuralhydrology && python -m pytest src/hydroagent/tests/test_agent_init.py::TestConvergenceControl -v`
Expected: FAIL — current code still has `target_nse` early stop.

- [ ] **Step 3: Modify `solve()` — remove target_nse stop, add floor protection**

In `src/hydroagent/agent.py`, modify `solve()`:

1. Remove `target_nse` from the signature (keep as internal variable for backward compat but don't use for early stop):

```python
# Change signature: keep target_nse param for backward compat but deprecate its stopping role
def solve(
    self,
    forcing: pd.DataFrame,
    obs: pd.Series,
    target_nse: float = 0.6,
    initial_structure: Optional[dict] = None,
    basin_meta: Optional[dict] = None,
    floor_nse: float = 0.0,
    floor_patience: int = 2,
) -> Dict[str, Any]:
```

2. Replace the convergence check block (lines ~893-900):

```python
# OLD:
# 5. Check convergence
if best_nse >= target_nse:
    print(f"\n  Target NSE ({target_nse}) reached at iteration {iteration}!")
    break

if iteration >= self.max_iterations:
    print(f"\n  Max iterations ({self.max_iterations}) reached.")
    break

# NEW:
# 5. Check termination
if iteration >= floor_patience and best_nse < floor_nse:
    print(f"\n  Floor protection: best NSE ({best_nse:.4f}) < {floor_nse} "
          f"after {iteration} iterations. Stopping.")
    break

if iteration >= self.max_iterations:
    print(f"\n  Max iterations ({self.max_iterations}) reached.")
    break
```

3. Update logger finalize call (line ~913-914):

```python
# OLD:
if self.logger:
    self.logger.finalize(best_nse, iteration, best_nse >= target_nse)

# NEW:
if self.logger:
    self.logger.finalize(best_nse, iteration, best_nse >= target_nse)  # keep for logging
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd G:/github/pycharm/projects/neuralhydrology && python -m pytest src/hydroagent/tests/test_agent_init.py::TestConvergenceControl -v`
Expected: PASS.

- [ ] **Step 5: Run all existing tests to ensure no regression**

Run: `cd G:/github/pycharm/projects/neuralhydrology && python -m pytest src/hydroagent/tests/ -v --timeout=120`
Expected: ALL PASS (existing tests should not depend on target_nse stopping behavior).

- [ ] **Step 6: Commit**

```bash
git add src/hydroagent/agent.py src/hydroagent/tests/test_agent_init.py
git commit -m "feat(hydroagent): replace target_nse early stop with floor protection

Remove fixed NSE=0.6 convergence threshold — always run max_iterations.
Add floor protection: if best_nse < 0 after 2 iterations, stop early
to avoid wasting compute on hopeless basins."
```

---

## Chunk 5: Experiment Design (no code)

### Task 5: v10-A vs v10-C experiment design

This task produces no code — it documents the experiment to validate whether feeding de-prescriptioned diagnostic rules to the Diagnostician Agent helps.

**Experiment: v10-A (current) vs v10-C (rules as reference)**

| Variant | Diagnostician Input | Description |
|---------|-------------------|-------------|
| v10-A (control) | 24 raw metrics only | Current v10 behavior |
| v10-C (treatment) | 24 raw metrics + de-prescriptioned rules | Rules with problem descriptions only, no component names |

**De-prescriptioned rules example:**
- Original: "退水过快。缺少慢速蓄水组件，建议增加线性水库。"
- De-prescriptioned: "退水过快。缺少慢速蓄水过程。"

**Implementation (when ready):**
1. Add a `diagnostic_hints: Optional[List[str]]` parameter to `build_diagnostician_prompt()`
2. If provided, append hints section after the metrics
3. Create a helper function `get_deprescriptioned_feedback(metrics)` that runs the 22 rules but strips component names
4. Add `--diag-hints` flag to `run_batch.py`

**Evaluation:**
- Same 18 basins, same DeepSeek backend, same calib/eval split
- Compare: mean eval NSE, convergence rate, component diversity
- Run command (future): `python run_batch.py --basins paper --backends deepseek --diag-hints`

---

## Execution Order

1. **Chunk 1** (environment.py split fix) — independent, no dependencies
2. **Chunk 2** (data_loading.py metadata) — independent
3. **Chunk 3** (agent.py init agent) — depends on Chunk 2
4. **Chunk 4** (agent.py convergence) — independent of Chunks 1-3
5. **Chunk 5** (experiment design) — documentation only

Chunks 1, 2, and 4 can be implemented in parallel.
Chunk 3 must wait for Chunk 2 (needs `load_basin_metadata`).
