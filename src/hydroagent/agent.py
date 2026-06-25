"""
Module C: HydroAgent — LLM-driven hydrological structure discovery.

Implements the reasoning loop: Perceive → Hypothesize → Execute → Diagnose → Refine.
Supports multiple LLM backends (OpenAI, DeepSeek, Claude, Ollama) and a deterministic
MockLLMClient for testing without API access.
"""
from __future__ import annotations

import json
import os
import re
import time
from abc import ABC, abstractmethod
from copy import deepcopy
from typing import Any, Dict, List, Optional

import numpy as np
import pandas as pd

from .diagnosis import HydroDiagnostician
from .environment import SuperflexEnv

# ---------------------------------------------------------------------------
# Step 1: Constants, prompts, and helper functions
# ---------------------------------------------------------------------------

AVAILABLE_COMPONENTS = """
Available SuperflexPy Components (14 types):

== Preprocessing ==
1. InterceptionFilter (GR4J-style)
   - Role: Canopy interception — removes min(PET, P) from precipitation before it reaches soil
   - Parameters: NONE (zero-parameter filter)
   - Inputs: ep, prcp (PET first, then precipitation)
   - Output: net precipitation (throughfall) after interception loss
   - Best for: Forested basins where canopy intercepts significant rainfall

2. InterceptionBucket (MARRMoT-style)
   - Role: Parametric canopy interception with storage state
   - Parameters: Smax (canopy capacity 0.5-10 mm), Ce (evap coefficient 0.3-1.5)
   - Inputs: prcp, ep (precipitation + PET)
   - Output: throughfall (increases as canopy fills)
   - Best for: Forested basins needing tunable interception; replaces InterceptionFilter when calibration matters

== Runoff Generation ==
3. UnsaturatedReservoir (HBV-style)
   - Role: Soil moisture accounting (partitions precipitation into runoff vs storage)
   - Parameters: Smax (max storage, mm), Ce, m, beta (nonlinearity)
   - Inputs: prcp, ep (precipitation + potential evapotranspiration)
   - Best for: General-purpose soil moisture partitioning

4. UpperZone (Hymod-style)
   - Role: Alternative soil moisture reservoir with different ET smoothing
   - Parameters: Smax (max storage, mm), m (ET smoothing), beta (runoff exponent)
   - Inputs: prcp, ep (precipitation + potential evapotranspiration)
   - Best for: Basins where UnsaturatedReservoir underperforms; 3 params vs 4 (simpler)

5. ProductionStore (GR4J-style)
   - Role: Alternative runoff generation with different saturation curve
   - Parameters: x1 (max capacity, mm), alpha, beta, ni
   - Inputs: ep, prcp (NOTE: PET first, then precipitation — reversed order)
   - Best for: Basins where UnsaturatedReservoir underperforms; provides structural diversity

6. SaturationAreaStore (TOPMODEL-style)
   - Role: Saturation excess runoff using exponential saturated area fraction
   - Parameters: Smax (capacity, mm), b (saturation shape 0.5-10)
   - Inputs: prcp, ep (precipitation + PET)
   - Output: saturation excess runoff (fraction of rain that runs off increases exponentially with wetness)
   - Best for: Basins with variable source area runoff; different curve shape from UpperZone (Xinanjiang) and UnsaturatedReservoir (HBV)

7. SnowReservoir (Thur-model)
   - Role: Snow accumulation and melt driven by temperature threshold
   - Parameters: t0 (melt threshold, °C), k (melt rate), m
   - Inputs: prcp, temperature (requires temp data in forcing)
   - Best for: Snow-dominated or cold-region basins with seasonal snowpack

== Flow Routing ==
8. PowerReservoir (HBV-style)
   - Role: Fast/nonlinear flow routing (surface runoff, interflow)
   - Parameters: k (residence time), alpha (nonlinearity exponent)
   - Inputs: inflow from upstream element
   - Best for: Quick-response flow paths

9. LinearReservoir (Hymod-style)
   - Role: Slow/linear flow routing (baseflow, groundwater)
   - Parameters: k (residence time)
   - Inputs: inflow from upstream element
   - Best for: Baseflow, slow groundwater discharge

10. RoutingStore (GR4J-style)
    - Role: Nonlinear routing with groundwater exchange term
    - Parameters: x2 (exchange coeff), x3 (capacity, mm), gamma, omega
    - Inputs: inflow from upstream element
    - Best for: Complex routing with gaining/losing stream interactions

11. ThresholdReservoir (MARRMoT-style)
    - Role: Groundwater with threshold — no outflow until storage exceeds minimum level
    - Parameters: k (drainage rate 0.001-0.3), Sth (threshold storage 0-100 mm)
    - Inputs: inflow from upstream element
    - Best for: Basins with delayed baseflow onset; storage must build up before discharge starts

12. PercolationStore (MARRMoT-style)
    - Role: Normalized nonlinear percolation using S/Smax ratio
    - Parameters: Smax (capacity 20-500 mm), Pmax (max perc rate 0.5-20 mm/d), alpha (exponent 1-4)
    - Inputs: inflow from upstream element
    - Best for: Gravity drainage between soil layers; percolation rate depends on relative fullness

13. DeepGroundwater (custom)
    - Role: Very slow deep aquifer with leakage loss to deep percolation
    - Parameters: k (very slow drainage, 0.0001-0.02), f_loss (deep leakage fraction, 0-0.3)
    - Inputs: inflow from upstream element (recharge)
    - Best for: Basins with significant deep baseflow, long recession tails, or losing streams

14. ConveyanceLoss (custom)
    - Role: Channel routing with transmission losses to alluvium
    - Parameters: k (routing rate), f_loss (transmission loss fraction, water lost to ground)
    - Inputs: inflow from upstream element
    - Best for: Arid/semi-arid basins with ephemeral streams and channel transmission losses

Connection Rules:
- Layers are connected sequentially; each layer's input references upstream outputs.
- Parallel pathways can be defined by having multiple layers receive the same upstream output.
- system_output lists which layer outputs are summed as total discharge.
- lag_functions (optional): list of {"target": "<layer_id>", "lag_steps": N} for channel routing delay.
- SnowReservoir MUST be a root layer (receives forcing directly) and needs temperature data.
- InterceptionFilter/InterceptionBucket MUST be root layers (receive forcing directly); output is net precipitation.
- ProductionStore input order is [ep, prcp], NOT [prcp, ep].
"""

DIAGNOSTICIAN_PROMPT = """You are a senior hydrologist specializing in model diagnostics.

Your task: Analyze the diagnostic metrics of a conceptual rainfall-runoff model and produce
a concise diagnosis. Identify what hydrological processes are missing or poorly represented.

Rules:
- Describe PROBLEMS, not solutions. Do NOT name specific components or suggest specific fixes.
- Consider interactions between metrics (e.g., fast recession + low baseflow = same root cause).
- Consider the iteration history — if a previous fix didn't help, the diagnosis should reflect that.
- Be concise: 2-4 sentences maximum.

Respond with ONLY the diagnosis text, no JSON, no markdown."""

STRUCTURE_PROMPT = """You are a senior hydrologist with deep expertise in conceptual rainfall-runoff modeling.

Your task: Given a diagnostic analysis of a hydrological model, propose a structural improvement.

Rules:
1. PARSIMONY FIRST: Prefer 2-4 layers. Only add a component when the diagnosis clearly indicates
   a missing process. Removing an unhelpful component is a valid improvement.
2. Make ONE structural change per iteration.
3. If previous attempts failed, try a DIFFERENT component type.
4. TOPOLOGY IS A DEGREE OF FREEDOM: do not restrict yourself to a single soil->(fast+slow) parallel
   template. Series/cascade arrangements (one store percolating into another), alternative production
   or routing stores, and rerouting existing connections are all valid single changes worth exploring.

You MUST respond with ONLY a valid JSON object representing the improved structure.
No explanations, no markdown formatting — just the raw JSON.

The JSON must have these keys:
- "model_name": string (descriptive name for this version)
- "layers": list of layer objects, each with "id", "type", "parameters", "inputs"
- "lag_functions": list (can be empty)
- "system_output": list of layer IDs whose outputs are summed
"""

INIT_PROMPT = """You are a senior hydrologist. Given a basin's physical and climatic characteristics,
choose an appropriate INITIAL model structure for a conceptual rainfall-runoff model.

Rules:
1. Start simple: 2-3 layers maximum. The structure will be iteratively refined later.
2. Match the basin: snow-dominated basins need SnowReservoir, arid basins may need ConveyanceLoss,
   forested basins may benefit from InterceptionFilter. Pick the minimal skeleton genuinely justified
   by THIS basin; the refinement stage will explore alternative components and topologies, so do not
   default to a single canonical template.
3. Every structure MUST include at least one runoff generation layer and one routing layer.

You MUST respond with ONLY a valid JSON object. No explanations.
The JSON must have keys: "model_name", "layers", "lag_functions", "system_output"."""

# Keep SYSTEM_PROMPT as alias for backward compatibility (used by MockLLMClient)
SYSTEM_PROMPT = STRUCTURE_PROMPT

DEFAULT_INITIAL_STRUCTURE = {
    "model_name": "initial_v0",
    "layers": [
        {
            "id": "soil",
            "type": "UnsaturatedReservoir",
            "parameters": ["Smax", "beta"],
            "inputs": ["prcp", "ep"]
        },
        {
            "id": "fast",
            "type": "PowerReservoir",
            "parameters": ["k", "alpha"],
            "inputs": ["soil.runoff"]
        },
    ],
    "lag_functions": [],
    "system_output": ["fast"],
}


def extract_json_from_response(text: str) -> dict:
    """Robustly extract a JSON object from LLM response text.

    Handles three scenarios:
    1. Pure JSON string
    2. JSON inside markdown code blocks (```json ... ``` or ``` ... ```)
    3. JSON embedded in surrounding prose
    """
    text = text.strip()

    # Try direct parse first
    try:
        return json.loads(text)
    except json.JSONDecodeError:
        pass

    # Try extracting from markdown code blocks
    code_block_pattern = r'```(?:json)?\s*\n?(.*?)\n?\s*```'
    matches = re.findall(code_block_pattern, text, re.DOTALL)
    for match in matches:
        try:
            return json.loads(match.strip())
        except json.JSONDecodeError:
            continue

    # Try finding JSON object in surrounding text
    brace_start = text.find('{')
    if brace_start != -1:
        depth = 0
        for i in range(brace_start, len(text)):
            if text[i] == '{':
                depth += 1
            elif text[i] == '}':
                depth -= 1
                if depth == 0:
                    candidate = text[brace_start:i + 1]
                    try:
                        return json.loads(candidate)
                    except json.JSONDecodeError:
                        break

    raise ValueError("Could not extract valid JSON from LLM response.")


ALL_COMPONENT_TYPES = {
    'InterceptionFilter', 'InterceptionBucket',
    'UnsaturatedReservoir', 'UpperZone', 'ProductionStore', 'SaturationAreaStore',
    'SnowReservoir',
    'PowerReservoir', 'LinearReservoir', 'RoutingStore',
    'ThresholdReservoir', 'PercolationStore',
    'DeepGroundwater', 'ConveyanceLoss',
}

# Default parameters per component type (used to fill missing 'parameters' field)
_DEFAULT_PARAMS = {
    'InterceptionFilter': [],
    'InterceptionBucket': ['Smax', 'Ce'],
    'UnsaturatedReservoir': ['Smax', 'beta'],
    'UpperZone': ['Smax', 'm', 'beta'],
    'ProductionStore': ['x1', 'alpha', 'beta', 'ni'],
    'SaturationAreaStore': ['Smax', 'b'],
    'SnowReservoir': ['t0', 'k', 'm'],
    'PowerReservoir': ['k', 'alpha'],
    'LinearReservoir': ['k'],
    'RoutingStore': ['x2', 'x3', 'gamma', 'omega'],
    'ThresholdReservoir': ['k', 'Sth'],
    'PercolationStore': ['Smax', 'Pmax', 'alpha'],
    'DeepGroundwater': ['k', 'f_loss'],
    'ConveyanceLoss': ['k', 'f_loss'],
}

# Default root inputs per component type
_DEFAULT_ROOT_INPUTS = {
    'InterceptionFilter': ['ep', 'prcp'],
    'InterceptionBucket': ['prcp', 'ep'],
    'UnsaturatedReservoir': ['prcp', 'ep'],
    'UpperZone': ['prcp', 'ep'],
    'ProductionStore': ['ep', 'prcp'],
    'SaturationAreaStore': ['prcp', 'ep'],
    'SnowReservoir': ['prcp', 'temperature'],
}

# Forcing names that indicate a root layer
_FORCING_NAMES_SET = frozenset({
    'prcp', 'ep', 'pet', 'evap', 'evaporation', 'precipitation', 'rainfall',
    'temp', 'temperature', 'tmax', 'tmin', 'tmean', 'tavg',
})


def sanitize_structure(structure: dict) -> dict:
    """Fix common LLM output issues in a structure JSON.

    Fixes:
    - Missing 'parameters' field → filled from _DEFAULT_PARAMS
    - Invalid 'inputs' on root layers → replaced with correct forcing names
    - Invalid 'inputs' on downstream layers → rewired to upstream_id.runoff
    - Extra fields (description, upstream, etc.) → stripped
    - Unknown component types → structure rejected (returns None)
    """
    layers = structure.get('layers', [])
    if not layers:
        return structure

    # Check all types are valid
    for layer in layers:
        if layer.get('type') not in ALL_COMPONENT_TYPES:
            raise ValueError(f"Unknown component type: {layer.get('type')}")

    all_ids = {layer['id'] for layer in layers}
    sanitized_layers = []

    for i, layer in enumerate(layers):
        ltype = layer['type']
        lid = layer['id']

        clean = {
            'id': lid,
            'type': ltype,
            'parameters': layer.get('parameters') or _DEFAULT_PARAMS.get(ltype, []),
            'inputs': layer.get('inputs', []),
        }

        # Determine if this should be a root layer (receives forcing)
        is_root_type = ltype in _DEFAULT_ROOT_INPUTS

        # Check if inputs reference any valid upstream layer
        has_valid_upstream = any(
            inp.split('.')[0] in all_ids for inp in clean['inputs'] if '.' in inp
        )
        has_forcing_input = any(inp.lower() in _FORCING_NAMES_SET for inp in clean['inputs'])

        # Fix inputs
        if is_root_type and not has_valid_upstream:
            # Root layer: ensure correct forcing inputs
            clean['inputs'] = _DEFAULT_ROOT_INPUTS[ltype]
        elif not is_root_type and not has_valid_upstream:
            # Downstream layer with broken inputs: find a plausible upstream
            # Look for the first root/soil-type layer before this one
            upstream_id = None
            for prev in sanitized_layers:
                if prev['type'] in _DEFAULT_ROOT_INPUTS:
                    upstream_id = prev['id']
            if upstream_id:
                clean['inputs'] = [f'{upstream_id}.runoff']
            else:
                # Fallback: first layer
                clean['inputs'] = [f'{sanitized_layers[0]["id"]}.runoff'] if sanitized_layers else ['prcp']

        sanitized_layers.append(clean)

    structure['layers'] = sanitized_layers

    # Ensure system_output references valid layer IDs
    sys_out = structure.get('system_output', [])
    sys_out = [oid for oid in sys_out if oid in {l['id'] for l in sanitized_layers}]
    if not sys_out:
        # Default: all non-root layers that aren't feeding another layer
        downstream_ids = [l['id'] for l in sanitized_layers if l['type'] not in _DEFAULT_ROOT_INPUTS]
        structure['system_output'] = downstream_ids if downstream_ids else [sanitized_layers[-1]['id']]
    else:
        structure['system_output'] = sys_out

    return structure


def build_diagnostician_prompt(structure: dict, report: dict, iteration: int, target_nse: float,
                               failed_attempts: Optional[List[Dict[str, Any]]] = None,
                               basin_meta: Optional[dict] = None) -> str:
    """Build the prompt for the diagnostician agent (step 1: what's wrong?)."""
    metrics = report.get('metrics', {})
    metrics_str = '\n'.join(f"  - {k}: {v}" for k, v in metrics.items())

    failed_str = ""
    if failed_attempts:
        lines = []
        for fa in failed_attempts:
            types_str = f" (components: {', '.join(fa['types'])})" if fa.get('types') else ""
            lines.append(f"  - {fa['model_name']} → NSE={fa['nse']}{types_str}")
        failed_str = f"""

### Previous Attempts (these did NOT help)
{chr(10).join(lines)}"""

    basin_str = _format_basin_meta_section(basin_meta) if basin_meta else ""

    return f"""## Iteration {iteration} — Model Diagnostic Analysis

### Current Structure
```json
{json.dumps(structure, indent=2)}
```

### Diagnostic Metrics (24 indicators)
{metrics_str}{failed_str}{basin_str}

### Target
NSE >= {target_nse:.2f}. Current NSE = {metrics.get('NSE', -999):.4f}.

### Task
Analyze the metrics and identify what hydrological processes are missing or poorly represented.
Describe the PROBLEMS only — do not suggest specific components or fixes."""


def build_structure_prompt(structure: dict, diagnosis: str, report: dict, iteration: int,
                           target_nse: float,
                           failed_attempts: Optional[List[Dict[str, Any]]] = None,
                           tried_types: Optional[set] = None,
                           steps_since_improve: int = 0,
                           basin_meta: Optional[dict] = None) -> str:
    """Build the prompt for the structure agent (step 2: how to fix it?)."""
    metrics = report.get('metrics', {})

    failed_str = ""
    if failed_attempts:
        lines = []
        for fa in failed_attempts:
            types_str = f" (components: {', '.join(fa['types'])})" if fa.get('types') else ""
            lines.append(f"  - {fa['model_name']} → NSE={fa['nse']}{types_str}")
        failed_str = f"""

### Failed Attempts (do NOT repeat these)
{chr(10).join(lines)}"""

    diversity_str = ""
    if tried_types is not None and iteration >= 2:
        untried = sorted(ALL_COMPONENT_TYPES - tried_types)
        if untried:
            diversity_str = f"""

### Structural exploration (you have many iterations — spend some exploring, not just tuning)
  Component families already tried: {', '.join(sorted(tried_types))}
  NOT yet tried: {', '.join(untried)}
  This search has so far stayed within one topology. For THIS iteration, deliberately TRIAL a
  structurally different option — either an untried component family above, OR a non-parallel
  topology (cascade/series, percolation from one store into another, an explicit routing or
  production store). The best structure so far is always kept, so exploring a worse one is safe."""

    basin_str = _format_basin_meta_section(basin_meta) if basin_meta else ""

    return f"""## Iteration {iteration} — Structure Improvement

### Current Structure
```json
{json.dumps(structure, indent=2)}
```

### Diagnostic Analysis (from hydrologist)
{diagnosis}{basin_str}

### Current NSE = {metrics.get('NSE', -999):.4f}. Target >= {target_nse:.2f}.{failed_str}{diversity_str}

### Available Components
{AVAILABLE_COMPONENTS}

### Instructions
Based on the diagnostic analysis above, return an improved structure JSON.
Make ONE structural change. Return ONLY the JSON object — no explanation."""


def build_refinement_prompt(structure: dict, report: dict, iteration: int, target_nse: float,
                            failed_attempts: Optional[List[Dict[str, Any]]] = None,
                            tried_types: Optional[set] = None,
                            steps_since_improve: int = 0) -> str:
    """Legacy single-prompt builder. Used by MockLLMClient."""
    metrics = report.get('metrics', {})
    feedback = report.get('semantic_feedback', [])

    metrics_str = '\n'.join(f"  - {k}: {v}" for k, v in metrics.items())
    feedback_str = '\n'.join(f"  - {fb}" for fb in feedback) if feedback else "  (No specific issues detected)"

    failed_str = ""
    if failed_attempts:
        lines = []
        for fa in failed_attempts:
            types_str = f" (components: {', '.join(fa['types'])})" if fa.get('types') else ""
            lines.append(f"  - {fa['model_name']} → NSE={fa['nse']}{types_str}")
        failed_str = f"""

### Failed Attempts (do NOT repeat these)
{chr(10).join(lines)}"""

    diversity_str = ""
    if tried_types is not None and steps_since_improve >= 2:
        untried = sorted(ALL_COMPONENT_TYPES - tried_types)
        if untried and metrics.get('NSE', 0) < target_nse:
            diversity_str = f"""

### Untried Components (consider using these for structural diversity)
  Already tried: {', '.join(sorted(tried_types))}
  NOT yet tried: {', '.join(untried)}
  Hint: Replacing or adding an untried component type often breaks out of local optima."""

    return f"""## Iteration {iteration} — Current Model Performance

### Current Structure
```json
{json.dumps(structure, indent=2)}
```

### Diagnostic Metrics (24 indicators)
{metrics_str}

### Semantic Feedback from Diagnostician
{feedback_str}{failed_str}

### Target
Improve NSE to >= {target_nse:.2f}. Current NSE = {metrics.get('NSE', -999):.4f}.{diversity_str}

### Available Components
{AVAILABLE_COMPONENTS}

### Instructions
Analyze the diagnostic feedback and return an improved structure JSON.
Focus on the most critical issue first. Make ONE structural change per iteration.
If previous attempts with the same component types failed, try a DIFFERENT component type.
Return ONLY the JSON object — no explanation."""


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


def _format_basin_meta_section(basin_meta: dict) -> str:
    """Format basin metadata as a prompt section for LLM context."""
    meta_lines = '\n'.join(f"  - {k}: {v}" for k, v in basin_meta.items())
    return f"""
### Basin Physical/Climatic Characteristics
{meta_lines}"""


# ---------------------------------------------------------------------------
# Step 2: LLM Client base class + MockLLMClient
# ---------------------------------------------------------------------------

class BaseLLMClient(ABC):
    """Abstract base class for LLM clients."""

    @abstractmethod
    def chat(self, system_prompt: str, user_message: str) -> str:
        """Send a message to the LLM and return the response text."""


class MockLLMClient(BaseLLMClient):
    """Deterministic rule-based engine for testing without LLM API access.

    Parses diagnostic metrics from the prompt and applies rule-chain improvements.
    """

    def chat(self, system_prompt: str, user_message: str) -> str:
        structure = self._extract_structure(user_message)
        metrics = self._extract_metrics(user_message)

        nse = metrics.get('NSE', 0.0)
        peak_lag = metrics.get('Peak_Lag_Hours', 0.0)
        low_flow_bias = metrics.get('Low_Flow_Bias', 0.0)
        recession_k = metrics.get('Recession_K_Ratio', 1.0)
        energy_ratio = metrics.get('High_Freq_Energy_Ratio', 1.0)
        winter_bias = metrics.get('Winter_Bias', 0.0)

        new_structure = deepcopy(structure)
        layer_ids = {layer['id'] for layer in new_structure.get('layers', [])}
        layer_types = {layer['type'] for layer in new_structure.get('layers', [])}

        # Find first root layer id for upstream reference
        root_id = next(
            (l['id'] for l in new_structure.get('layers', [])
             if any(inp.lower() in ('prcp', 'ep', 'pet', 'precipitation') for inp in l.get('inputs', []))),
            'soil',
        )

        # Rule chain (priority order)
        if nse < 0.3 and 'baseflow' not in layer_ids:
            new_structure['layers'].append({
                "id": "baseflow",
                "type": "RoutingStore",
                "parameters": ["x2", "x3", "gamma", "omega"],
                "inputs": [f"{root_id}.runoff"],
            })
            if 'baseflow' not in new_structure.get('system_output', []):
                new_structure.setdefault('system_output', []).append('baseflow')
            new_structure['model_name'] = self._next_name(structure, 'add_baseflow')

        elif peak_lag > 3.0 and new_structure.get('lag_functions'):
            new_structure['lag_functions'] = []
            new_structure['model_name'] = self._next_name(structure, 'remove_lag')

        elif winter_bias >= 0.3 and 'SnowReservoir' not in layer_types:
            # Insert SnowReservoir as root layer (index 0) and rewire soil input
            new_structure['layers'].insert(0, {
                "id": "snow",
                "type": "SnowReservoir",
                "parameters": ["t0", "k", "m"],
                "inputs": ["prcp", "temperature"],
            })
            # Rewire soil layer: replace 'prcp' with 'snow.outflow'
            for layer in new_structure['layers']:
                if layer['type'] == 'UnsaturatedReservoir' and 'prcp' in layer.get('inputs', []):
                    layer['inputs'] = ['snow.outflow' if inp == 'prcp' else inp for inp in layer['inputs']]
                    break
            new_structure['model_name'] = self._next_name(structure, 'add_snow')

        elif low_flow_bias < -0.3 and 'slow_gw' not in layer_ids:
            new_structure['layers'].append({
                "id": "slow_gw",
                "type": "LinearReservoir",
                "parameters": ["k"],
                "inputs": [f"{root_id}.runoff"],
            })
            if 'slow_gw' not in new_structure.get('system_output', []):
                new_structure.setdefault('system_output', []).append('slow_gw')
            new_structure['model_name'] = self._next_name(structure, 'add_slow_gw')

        elif recession_k > 1.3 and 'slow_reservoir' not in layer_ids:
            new_structure['layers'].append({
                "id": "slow_reservoir",
                "type": "LinearReservoir",
                "parameters": ["k"],
                "inputs": [f"{root_id}.runoff"],
            })
            if 'slow_reservoir' not in new_structure.get('system_output', []):
                new_structure.setdefault('system_output', []).append('slow_reservoir')
            new_structure['model_name'] = self._next_name(structure, 'add_slow_res')

        elif energy_ratio < 0.6:
            # Replace LinearReservoir with PowerReservoir
            replaced = False
            for layer in new_structure['layers']:
                if layer['type'] == 'LinearReservoir':
                    layer['type'] = 'PowerReservoir'
                    layer['parameters'] = ['k', 'alpha']
                    replaced = True
                    break
            if replaced:
                new_structure['model_name'] = self._next_name(structure, 'linear_to_power')
            else:
                new_structure['model_name'] = self._next_name(structure, 'no_change')

        elif nse < 0.5 and 'UnsaturatedReservoir' in layer_types and 'ProductionStore' not in layer_types:
            # Try replacing UnsaturatedReservoir with ProductionStore for structural diversity
            for layer in new_structure['layers']:
                if layer['type'] == 'UnsaturatedReservoir':
                    layer['type'] = 'ProductionStore'
                    layer['parameters'] = ['x1', 'alpha', 'beta', 'ni']
                    layer['inputs'] = ['ep', 'prcp']
                    break
            new_structure['model_name'] = self._next_name(structure, 'try_production_store')

        else:
            # No actionable diagnostic signal — converged or no change needed
            new_structure['model_name'] = self._next_name(structure, 'no_change')

        return json.dumps(new_structure)

    @staticmethod
    def _next_name(structure: dict, suffix: str) -> str:
        current = structure.get('model_name', 'v0')
        # Extract version number
        match = re.search(r'v(\d+)', current)
        version = int(match.group(1)) + 1 if match else 1
        return f"{suffix}_v{version}"

    @staticmethod
    def _extract_structure(prompt: str) -> dict:
        """Extract the current structure JSON from the prompt text."""
        try:
            code_block = re.search(r'```json\s*\n(.*?)\n\s*```', prompt, re.DOTALL)
            if code_block:
                return json.loads(code_block.group(1))
        except (json.JSONDecodeError, AttributeError):
            pass
        return deepcopy(DEFAULT_INITIAL_STRUCTURE)

    @staticmethod
    def _extract_metrics(prompt: str) -> dict:
        """Extract metric values from the prompt text using regex."""
        metrics = {}
        patterns = {
            'NSE': r'NSE:\s*([-\d.]+)',
            'Peak_Lag_Hours': r'Peak_Lag_Hours:\s*([-\d.]+)',
            'Low_Flow_Bias': r'Low_Flow_Bias:\s*([-\d.]+)',
            'Recession_K_Ratio': r'Recession_K_Ratio:\s*([-\d.]+)',
            'High_Freq_Energy_Ratio': r'High_Freq_Energy_Ratio:\s*([-\d.]+)',
            'Winter_Bias': r'Winter_Bias:\s*([-\d.]+)',
        }
        for key, pattern in patterns.items():
            match = re.search(pattern, prompt)
            if match:
                try:
                    metrics[key] = float(match.group(1))
                except ValueError:
                    pass
        return metrics


# ---------------------------------------------------------------------------
# Step 3: Real LLM Clients
# ---------------------------------------------------------------------------

class OpenAIClient(BaseLLMClient):
    """LLM client using the OpenAI API (GPT-4o-mini, GPT-4o, etc.)."""

    def __init__(self, api_key: Optional[str] = None, model: str = 'gpt-4o-mini'):
        try:
            import openai  # noqa: F401
        except ImportError:
            raise ImportError(
                "OpenAI SDK not installed. Install with: pip install openai"
            )
        self.api_key = api_key or os.environ.get('OPENAI_API_KEY', '')
        if not self.api_key:
            raise ValueError("OpenAI API key required. Pass api_key= or set OPENAI_API_KEY env var.")
        self.model = model
        self._openai = openai

    def chat(self, system_prompt: str, user_message: str) -> str:
        client = self._openai.OpenAI(api_key=self.api_key)
        response = client.chat.completions.create(
            model=self.model,
            messages=[
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": user_message},
            ],
            temperature=0.3,
        )
        return response.choices[0].message.content


class DeepSeekClient(BaseLLMClient):
    """LLM client using DeepSeek API (OpenAI-compatible endpoint)."""

    def __init__(self, api_key: Optional[str] = None, model: str = 'deepseek-chat'):
        try:
            import openai  # noqa: F401
        except ImportError:
            raise ImportError(
                "OpenAI SDK not installed (used for DeepSeek). Install with: pip install openai"
            )
        self.api_key = api_key or os.environ.get('DEEPSEEK_API_KEY', '')
        if not self.api_key:
            raise ValueError("DeepSeek API key required. Pass api_key= or set DEEPSEEK_API_KEY env var.")
        self.model = model
        self._openai = openai

    def chat(self, system_prompt: str, user_message: str) -> str:
        client = self._openai.OpenAI(api_key=self.api_key, base_url="https://api.deepseek.com")
        response = client.chat.completions.create(
            model=self.model,
            messages=[
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": user_message},
            ],
            temperature=0.3,
        )
        return response.choices[0].message.content


_STRUCTURE_SCHEMA = {
    "type": "json_schema",
    "schema": {
        "type": "object",
        "properties": {
            "model_name": {"type": "string"},
            "layers": {
                "type": "array",
                "items": {
                    "type": "object",
                    "properties": {
                        "id": {"type": "string"},
                        "type": {"type": "string"},
                        "parameters": {"type": "array", "items": {"type": "string"}},
                        "inputs": {"type": "array", "items": {"type": "string"}},
                    },
                    "required": ["id", "type", "parameters", "inputs"],
                    "additionalProperties": False,
                }
            },
            "lag_functions": {
                "type": "array",
                "items": {
                    "type": "object",
                    "properties": {
                        "type": {"type": "string"},
                        "target": {"type": "string"},
                        "lag_steps": {"type": "integer"},
                    },
                    "required": ["type", "target", "lag_steps"],
                    "additionalProperties": False,
                }
            },
            "system_output": {"type": "array", "items": {"type": "string"}},
        },
        "required": ["model_name", "layers", "lag_functions", "system_output"],
        "additionalProperties": False,
    }
}


class ClaudeClient(BaseLLMClient):
    """LLM client using the Anthropic Claude API with adaptive thinking and structured outputs."""

    def __init__(self, api_key: Optional[str] = None, model: str = 'claude-opus-4-8'):
        try:
            import anthropic  # noqa: F401
        except ImportError:
            raise ImportError(
                "Anthropic SDK not installed. Install with: pip install anthropic"
            )
        self.api_key = api_key or os.environ.get('ANTHROPIC_API_KEY', '')
        if not self.api_key:
            raise ValueError("Anthropic API key required. Pass api_key= or set ANTHROPIC_API_KEY env var.")
        self.model = model
        self._anthropic = anthropic

    def chat(self, system_prompt: str, user_message: str) -> str:
        client = self._anthropic.Anthropic(api_key=self.api_key)
        with client.messages.stream(
            model=self.model,
            max_tokens=16000,
            thinking={"type": "adaptive"},
            temperature=1.0,
            system=system_prompt,
            output_config={"format": _STRUCTURE_SCHEMA},
            messages=[{"role": "user", "content": user_message}],
        ) as stream:
            response = stream.get_final_message()
        return response.content[-1].text


class OllamaClient(BaseLLMClient):
    """LLM client using a local Ollama instance (REST API)."""

    def __init__(self, model: str = 'llama3.2', host: Optional[str] = None):
        try:
            import requests  # noqa: F401
        except ImportError:
            raise ImportError(
                "requests library not installed. Install with: pip install requests"
            )
        self.model = model
        self.host = host or os.environ.get('OLLAMA_HOST', 'http://localhost:11434')
        self._requests = requests

    def chat(self, system_prompt: str, user_message: str) -> str:
        url = f"{self.host.rstrip('/')}/api/chat"
        payload = {
            "model": self.model,
            "messages": [
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": user_message},
            ],
            "stream": False,
        }
        response = self._requests.post(url, json=payload, timeout=120)
        response.raise_for_status()
        data = response.json()
        return data.get("message", {}).get("content", "")


class RandomLLMClient(BaseLLMClient):
    """Ablation lower bound: random structure mutations, ignores diagnostics."""

    def __init__(self, seed=42):
        self._rng = np.random.RandomState(seed)

    def chat(self, system_prompt: str, user_message: str) -> str:
        structure = MockLLMClient._extract_structure(user_message)
        new_structure = deepcopy(structure)
        layer_ids = [l['id'] for l in new_structure.get('layers', [])]
        root_id = layer_ids[0] if layer_ids else 'soil'

        mutations = ['add_linear', 'add_power', 'remove_layer', 'swap_soil']
        choice = mutations[self._rng.randint(0, len(mutations))]

        if choice == 'add_linear':
            new_id = f'rand_lin_{self._rng.randint(0, 100)}'
            new_structure['layers'].append({
                'id': new_id,
                'type': 'LinearReservoir',
                'parameters': ['k'],
                'inputs': [f'{root_id}.runoff'],
            })
            new_structure.setdefault('system_output', []).append(new_id)

        elif choice == 'add_power':
            new_id = f'rand_pow_{self._rng.randint(0, 100)}'
            new_structure['layers'].append({
                'id': new_id,
                'type': 'PowerReservoir',
                'parameters': ['k', 'alpha'],
                'inputs': [f'{root_id}.runoff'],
            })
            new_structure.setdefault('system_output', []).append(new_id)

        elif choice == 'remove_layer' and len(new_structure.get('layers', [])) > 2:
            # Remove a random non-root layer
            removable = [i for i, l in enumerate(new_structure['layers'])
                         if i > 0]
            if removable:
                idx = removable[self._rng.randint(0, len(removable))]
                removed = new_structure['layers'].pop(idx)
                sys_out = new_structure.get('system_output', [])
                if removed['id'] in sys_out:
                    sys_out.remove(removed['id'])
                if not sys_out and new_structure['layers']:
                    sys_out.append(new_structure['layers'][-1]['id'])

        elif choice == 'swap_soil':
            for layer in new_structure['layers']:
                if layer['type'] == 'UnsaturatedReservoir':
                    layer['type'] = 'ProductionStore'
                    layer['parameters'] = ['x1', 'alpha', 'beta', 'ni']
                    layer['inputs'] = ['ep', 'prcp']
                    break
                elif layer['type'] == 'ProductionStore':
                    layer['type'] = 'UnsaturatedReservoir'
                    layer['parameters'] = ['Smax', 'beta']
                    layer['inputs'] = ['prcp', 'ep']
                    break

        new_structure['model_name'] = f'random_{choice}_v{self._rng.randint(1, 99)}'
        return json.dumps(new_structure)


# ---------------------------------------------------------------------------
# Step 4: HydroAgent main class
# ---------------------------------------------------------------------------

class HydroAgent:
    """
    Module C: 数字水文学家 (The Brain)
    LLM-driven reasoning loop for hydrological model structure discovery.

    Loop: calibrate → diagnose → record → check convergence → refine structure
    """

    def __init__(self, llm_client: BaseLLMClient, max_iterations: int = 4,
                 logger=None, enable_rollback: bool = True, rollback_patience: int = 2):
        self.llm = llm_client
        self.env = SuperflexEnv()
        self.doctor = HydroDiagnostician()
        self.max_iterations = max_iterations
        self.enable_rollback = enable_rollback
        self.rollback_patience = rollback_patience
        self.history: List[Dict[str, Any]] = []
        self.logger = logger  # Optional[ExperimentLogger]

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

            # Sanitize: fix missing params, broken inputs, extra fields
            try:
                structure = sanitize_structure(structure)
            except ValueError as ve:
                print(f"  [WARN] Init agent structure invalid: {ve}, using default.")
                return deepcopy(DEFAULT_INITIAL_STRUCTURE)

            print(f"  [Init Agent] Chose: {structure.get('model_name')} "
                  f"({len(structure['layers'])} layers)")

            if self.logger:
                self.logger.log_llm_response(0, prompt[:300], response_text, True)

            return structure
        except Exception as e:
            print(f"  [WARN] Init agent failed: {e}, using default.")
            return deepcopy(DEFAULT_INITIAL_STRUCTURE)

    def solve(
        self,
        forcing: pd.DataFrame,
        obs: pd.Series,
        target_nse: float = 0.6,
        initial_structure: Optional[dict] = None,
        basin_meta: Optional[dict] = None,
        floor_nse: float = -900.0,
        floor_patience: int = 2,
    ) -> Dict[str, Any]:
        """Run the agent reasoning loop to discover optimal model structure.

        Args:
            forcing: Meteorological forcing data (must have 'prcp' and 'ep' columns).
            obs: Observed streamflow series (mm/day).
            target_nse: Aspiration NSE target (used in LLM prompts, no longer triggers early stopping).
            initial_structure: Starting structure JSON. Highest priority if provided.
            basin_meta: Basin physical/climatic attributes dict. If provided (and initial_structure
                is None), the LLM initialization agent chooses a starting structure.
            floor_nse: If best_nse stays below this after floor_patience iterations, stop
                early. Default -900 only triggers on genuine calibration crashes (the -999
                sentinel); a valid-but-poor structure (e.g. NSE -0.01) keeps refining.
            floor_patience: Number of iterations to wait before applying floor check.

        Returns:
            Dict with 'best_nse', 'best_structure', 'best_params'.
        """
        if initial_structure is not None:
            structure = deepcopy(initial_structure)
        elif basin_meta is not None:
            structure = self._choose_initial_structure(basin_meta)
        else:
            structure = deepcopy(DEFAULT_INITIAL_STRUCTURE)
        best_nse = -999.0
        best_structure: Optional[dict] = None
        best_params: Dict[str, float] = {}
        failed_attempts: List[Dict[str, Any]] = []  # track failed refinements for rollback
        steps_since_improve = 0  # patience counter for rollback
        tried_types: set = set()  # track all component types tried across iterations

        for iteration in range(1, self.max_iterations + 1):
            t_iter_start = time.time()
            print(f"\n--- Iteration {iteration}/{self.max_iterations} ---")
            print(f"  Structure: {structure.get('model_name', 'unknown')}")

            # 1. Calibrate
            cal_result = self._calibrate(structure, forcing, obs)
            nse = cal_result['nse']
            params = cal_result['optimized_params']
            qsim = cal_result['qsim']
            print(f"  NSE: {nse:.4f}")

            # Track component types used in this iteration
            for layer in structure.get('layers', []):
                tried_types.add(layer.get('type', ''))

            # 2. Diagnose
            if nse > -900:
                report = self.doctor.generate_report(obs, qsim)
            else:
                report = {'metrics': self.doctor._empty_metrics(), 'semantic_feedback': ["Calibration failed."]}

            # 3. Record
            entry = {
                'iteration': iteration,
                'structure': deepcopy(structure),
                'nse': nse,
                'params': params,
                'report': report,
            }
            self.history.append(entry)

            # Log iteration
            if self.logger:
                duration_s = time.time() - t_iter_start
                self.logger.log_iteration(iteration, structure, cal_result, report, duration_s)

            # 4. Update best (patience-based rollback)
            if nse > best_nse:
                best_nse = nse
                best_structure = deepcopy(structure)
                best_params = params
                failed_attempts.clear()
                steps_since_improve = 0
                print(f"  *** New best! NSE={best_nse:.4f} ***")
            elif self.enable_rollback and best_structure is not None:
                steps_since_improve += 1
                failed_attempts.append({
                    'model_name': structure.get('model_name', ''),
                    'nse': round(nse, 4),
                    'types': [l.get('type', '') for l in structure.get('layers', [])],
                })
                if steps_since_improve >= self.rollback_patience:
                    # Patience exhausted — rollback to best known structure
                    structure = deepcopy(best_structure)
                    report = self.doctor.generate_report(
                        obs, self._calibrate(best_structure, forcing, obs)['qsim']
                    ) if best_nse > -900 else report
                    steps_since_improve = 0
                    print(f"  Rollback to {best_structure.get('model_name', '')} "
                          f"(best NSE={best_nse:.4f}) after {self.rollback_patience} failed steps")
                else:
                    # Still within patience — keep exploring from current structure
                    print(f"  NSE declined ({nse:.4f} < {best_nse:.4f}), "
                          f"patience {steps_since_improve}/{self.rollback_patience}")

            # 5. Check termination
            if iteration >= floor_patience and best_nse < floor_nse:
                print(f"\n  Floor protection: best NSE ({best_nse:.4f}) < {floor_nse} "
                      f"after {iteration} iterations. Stopping.")
                break

            if iteration >= self.max_iterations:
                print(f"\n  Max iterations ({self.max_iterations}) reached.")
                break

            # 6. Refine structure via LLM
            new_structure = self._reason_and_refine(
                structure, report, iteration, target_nse,
                failed_attempts=failed_attempts, tried_types=tried_types,
                steps_since_improve=steps_since_improve,
                basin_meta=basin_meta)
            if new_structure is not None:
                structure = new_structure
                print(f"  -> Refined to: {structure.get('model_name', 'unknown')}")
            else:
                print("  -> LLM refinement failed, retrying with current structure.")

        if self.logger:
            self.logger.finalize(best_nse, iteration, best_nse >= target_nse)

        return {
            'best_nse': best_nse,
            'best_structure': best_structure,
            'best_params': best_params,
        }

    def _calibrate(
        self,
        structure: dict,
        forcing: pd.DataFrame,
        obs: pd.Series,
    ) -> Dict[str, Any]:
        """Parse structure and run auto-calibration via Module B."""
        try:
            self.env.parse_structure(structure)
            result = self.env.auto_calibrate(forcing, obs)
            return result
        except Exception as e:
            print(f"  [WARN] Calibration failed: {e}")
            # Return sentinel values so the loop can continue
            return {
                'nse': -999.0,
                'optimized_params': {},
                'qsim': pd.Series(np.zeros(len(obs)), index=obs.index, name='qsim'),
            }

    def _reason_and_refine(
        self,
        structure: dict,
        report: dict,
        iteration: int,
        target_nse: float,
        failed_attempts: Optional[List[Dict[str, Any]]] = None,
        tried_types: Optional[set] = None,
        steps_since_improve: int = 0,
        basin_meta: Optional[dict] = None,
    ) -> Optional[dict]:
        """Two-agent refinement: diagnostician → structure designer."""

        # For MockLLMClient, use legacy single-prompt path
        if isinstance(self.llm, MockLLMClient):
            return self._reason_and_refine_legacy(
                structure, report, iteration, target_nse,
                failed_attempts, tried_types, steps_since_improve)

        # --- Step 1: Diagnostician Agent ---
        diag_prompt = build_diagnostician_prompt(
            structure, report, iteration, target_nse, failed_attempts,
            basin_meta=basin_meta)

        try:
            diagnosis = self.llm.chat(DIAGNOSTICIAN_PROMPT, diag_prompt)
            print(f"  [Diagnosis]: {diagnosis[:150]}...")
        except Exception as e:
            print(f"  [WARN] Diagnostician failed: {e}, falling back to legacy")
            return self._reason_and_refine_legacy(
                structure, report, iteration, target_nse,
                failed_attempts, tried_types, steps_since_improve)

        # --- Step 2: Structure Agent ---
        struct_prompt = build_structure_prompt(
            structure, diagnosis, report, iteration, target_nse,
            failed_attempts, tried_types, steps_since_improve,
            basin_meta=basin_meta)

        try:
            response_text = self.llm.chat(STRUCTURE_PROMPT, struct_prompt)
            new_structure = extract_json_from_response(response_text)
        except Exception as e:
            print(f"  [WARN] Structure agent failed: {e}")
            if self.logger:
                self.logger.log_llm_response(iteration, diag_prompt[:300], str(e), False)
            return None

        if self.logger:
            # Log both diagnosis and structure response
            combined_log = f"[DIAGNOSIS]\n{diagnosis}\n\n[STRUCTURE]\n{response_text}"
            self.logger.log_llm_response(iteration, diag_prompt[:300], combined_log,
                                          new_structure is not None)

        # Basic validation
        if not isinstance(new_structure, dict):
            print("  [WARN] LLM returned non-dict response.")
            return None
        if 'layers' not in new_structure:
            print("  [WARN] LLM response missing 'layers' key.")
            return None

        # Ensure required keys exist
        new_structure.setdefault('model_name', f'llm_v{iteration + 1}')
        new_structure.setdefault('lag_functions', [])
        new_structure.setdefault('system_output', [new_structure['layers'][-1]['id']]
                                 if new_structure['layers'] else ['fast'])

        # Sanitize: fix missing params, broken inputs, extra fields
        try:
            new_structure = sanitize_structure(new_structure)
        except ValueError as ve:
            print(f"  [WARN] Sanitize failed: {ve}")
            return None

        return new_structure

    def _reason_and_refine_legacy(
        self,
        structure: dict,
        report: dict,
        iteration: int,
        target_nse: float,
        failed_attempts: Optional[List[Dict[str, Any]]] = None,
        tried_types: Optional[set] = None,
        steps_since_improve: int = 0,
    ) -> Optional[dict]:
        """Legacy single-prompt refinement for MockLLMClient."""
        prompt = build_refinement_prompt(structure, report, iteration, target_nse,
                                         failed_attempts=failed_attempts,
                                         tried_types=tried_types,
                                         steps_since_improve=steps_since_improve)

        try:
            response_text = self.llm.chat(SYSTEM_PROMPT, prompt)
            new_structure = extract_json_from_response(response_text)
        except Exception as e:
            print(f"  [WARN] LLM refinement failed: {e}")
            if self.logger:
                self.logger.log_llm_response(iteration, prompt[:500], str(e), False)
            return None

        if self.logger:
            self.logger.log_llm_response(iteration, prompt[:500], response_text, new_structure is not None)

        if not isinstance(new_structure, dict):
            print("  [WARN] LLM returned non-dict response.")
            return None
        if 'layers' not in new_structure:
            print("  [WARN] LLM response missing 'layers' key.")
            return None

        new_structure.setdefault('model_name', f'llm_v{iteration + 1}')
        new_structure.setdefault('lag_functions', [])
        new_structure.setdefault('system_output', [new_structure['layers'][-1]['id']]
                                 if new_structure['layers'] else ['fast'])

        return new_structure
