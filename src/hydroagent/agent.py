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
Available SuperflexPy Components (6 types):

== Runoff Generation ==
1. UnsaturatedReservoir (HBV-style)
   - Role: Soil moisture accounting (partitions precipitation into runoff vs storage)
   - Parameters: Smax (max storage, mm), Ce, m, beta (nonlinearity)
   - Inputs: prcp, ep (precipitation + potential evapotranspiration)
   - Best for: General-purpose soil moisture partitioning

2. ProductionStore (GR4J-style)
   - Role: Alternative runoff generation with different saturation curve
   - Parameters: x1 (max capacity, mm), alpha, beta, ni
   - Inputs: ep, prcp (NOTE: PET first, then precipitation — reversed order)
   - Best for: Basins where UnsaturatedReservoir underperforms; provides structural diversity

3. SnowReservoir (Thur-model)
   - Role: Snow accumulation and melt driven by temperature threshold
   - Parameters: t0 (melt threshold, °C), k (melt rate), m
   - Inputs: prcp, temperature (requires temp data in forcing)
   - Best for: Snow-dominated or cold-region basins with seasonal snowpack

== Flow Routing ==
4. PowerReservoir (HBV-style)
   - Role: Fast/nonlinear flow routing (surface runoff, interflow)
   - Parameters: k (residence time), alpha (nonlinearity exponent)
   - Inputs: inflow from upstream element
   - Best for: Quick-response flow paths

5. LinearReservoir (Hymod-style)
   - Role: Slow/linear flow routing (baseflow, groundwater)
   - Parameters: k (residence time)
   - Inputs: inflow from upstream element
   - Best for: Baseflow, slow groundwater discharge

6. RoutingStore (GR4J-style)
   - Role: Nonlinear routing with groundwater exchange term
   - Parameters: x2 (exchange coeff), x3 (capacity, mm), gamma, omega
   - Inputs: inflow from upstream element
   - Best for: Complex routing with gaining/losing stream interactions

Connection Rules:
- Layers are connected sequentially; each layer's input references upstream outputs.
- Parallel pathways can be defined by having multiple layers receive the same upstream output.
- system_output lists which layer outputs are summed as total discharge.
- lag_functions (optional): list of {"target": "<layer_id>", "lag_steps": N} for channel routing delay.
- SnowReservoir MUST be a root layer (receives forcing directly) and needs temperature data.
- ProductionStore input order is [ep, prcp], NOT [prcp, ep].
"""

SYSTEM_PROMPT = """You are a senior hydrologist with deep expertise in conceptual rainfall-runoff modeling.

Your task: Given diagnostic metrics from a hydrological model, suggest structural improvements
to the model architecture to improve NSE (Nash-Sutcliffe Efficiency).

Key principles for structure → operation mapping:
- Poor baseflow (Low_Flow_Bias < -0.3): Add a parallel LinearReservoir or RoutingStore as slow groundwater pathway.
- Peak timing lag (Peak_Lag > 3h): Remove or reduce lag_functions; decrease routing parameters.
- Recession too fast (Recession_K_Ratio > 1.3): Add a slow reservoir (LinearReservoir or RoutingStore) with large k.
- Over-smoothed signal (Energy_Ratio < 0.6): Replace LinearReservoir with PowerReservoir for nonlinearity.
- NSE very low (< 0.3): Add parallel flow paths to capture multiple flow regimes.
- Snow-dominated basin (winter overestimate, Winter_Bias > 0.3): Add SnowReservoir as root layer to store precipitation as snow (needs temperature).
- UnsaturatedReservoir underperforms: Try ProductionStore (GR4J) as alternative runoff generation.

You MUST respond with ONLY a valid JSON object representing the improved structure.
No explanations, no markdown formatting — just the raw JSON.

The JSON must have these keys:
- "model_name": string (descriptive name for this version)
- "layers": list of layer objects, each with "id", "type", "parameters", "inputs"
- "lag_functions": list (can be empty)
- "system_output": list of layer IDs whose outputs are summed
"""

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


def build_refinement_prompt(structure: dict, report: dict, iteration: int, target_nse: float) -> str:
    """Build the user-message prompt sent to the LLM for structure refinement."""
    metrics = report.get('metrics', {})
    feedback = report.get('semantic_feedback', [])

    metrics_str = '\n'.join(f"  - {k}: {v}" for k, v in metrics.items())
    feedback_str = '\n'.join(f"  - {fb}" for fb in feedback) if feedback else "  (No specific issues detected)"

    return f"""## Iteration {iteration} — Current Model Performance

### Current Structure
```json
{json.dumps(structure, indent=2)}
```

### Diagnostic Metrics (24 indicators)
{metrics_str}

### Semantic Feedback from Diagnostician
{feedback_str}

### Target
Improve NSE to >= {target_nse:.2f}. Current NSE = {metrics.get('NSE', -999):.4f}.

### Available Components
{AVAILABLE_COMPONENTS}

### Instructions
Analyze the diagnostic feedback and return an improved structure JSON.
Focus on the most critical issue first. Make ONE structural change per iteration.
Return ONLY the JSON object — no explanation."""


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

        elif winter_bias > 0.3 and 'SnowReservoir' not in layer_types:
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

    def __init__(self, api_key: Optional[str] = None, model: str = 'claude-opus-4-6'):
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


# ---------------------------------------------------------------------------
# Step 4: HydroAgent main class
# ---------------------------------------------------------------------------

class HydroAgent:
    """
    Module C: 数字水文学家 (The Brain)
    LLM-driven reasoning loop for hydrological model structure discovery.

    Loop: calibrate → diagnose → record → check convergence → refine structure
    """

    def __init__(self, llm_client: BaseLLMClient, max_iterations: int = 4):
        self.llm = llm_client
        self.env = SuperflexEnv()
        self.doctor = HydroDiagnostician()
        self.max_iterations = max_iterations
        self.history: List[Dict[str, Any]] = []

    def solve(
        self,
        forcing: pd.DataFrame,
        obs: pd.Series,
        target_nse: float = 0.6,
        initial_structure: Optional[dict] = None,
    ) -> Dict[str, Any]:
        """Run the agent reasoning loop to discover optimal model structure.

        Args:
            forcing: Meteorological forcing data (must have 'prcp' and 'ep' columns).
            obs: Observed streamflow series (mm/day).
            target_nse: NSE threshold to stop optimization.
            initial_structure: Starting structure JSON. Uses DEFAULT_INITIAL_STRUCTURE if None.

        Returns:
            Dict with 'best_nse', 'best_structure', 'best_params'.
        """
        structure = deepcopy(initial_structure or DEFAULT_INITIAL_STRUCTURE)
        best_nse = -999.0
        best_structure: Optional[dict] = None
        best_params: Dict[str, float] = {}

        for iteration in range(1, self.max_iterations + 1):
            print(f"\n--- Iteration {iteration}/{self.max_iterations} ---")
            print(f"  Structure: {structure.get('model_name', 'unknown')}")

            # 1. Calibrate
            cal_result = self._calibrate(structure, forcing, obs)
            nse = cal_result['nse']
            params = cal_result['optimized_params']
            qsim = cal_result['qsim']
            print(f"  NSE: {nse:.4f}")

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

            # 4. Update best
            if nse > best_nse:
                best_nse = nse
                best_structure = deepcopy(structure)
                best_params = params
                print(f"  *** New best! NSE={best_nse:.4f} ***")

            # 5. Check convergence
            if best_nse >= target_nse:
                print(f"\n  Target NSE ({target_nse}) reached at iteration {iteration}!")
                break

            if iteration >= self.max_iterations:
                print(f"\n  Max iterations ({self.max_iterations}) reached.")
                break

            # 6. Refine structure via LLM
            new_structure = self._reason_and_refine(structure, report, iteration, target_nse)
            if new_structure is not None:
                structure = new_structure
                print(f"  -> Refined to: {structure.get('model_name', 'unknown')}")
            else:
                print("  -> LLM refinement failed, retrying with current structure.")

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
    ) -> Optional[dict]:
        """Ask the LLM to analyze diagnostics and propose a refined structure."""
        prompt = build_refinement_prompt(structure, report, iteration, target_nse)

        try:
            response_text = self.llm.chat(SYSTEM_PROMPT, prompt)
            new_structure = extract_json_from_response(response_text)
        except Exception as e:
            print(f"  [WARN] LLM refinement failed: {e}")
            return None

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

        return new_structure
