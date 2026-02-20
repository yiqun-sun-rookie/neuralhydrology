# hydroagent

LLM-based hydrological diagnosis agent (HydroAgent).

## Overview

Uses a reinforcement learning environment (`SuperflexEnv`) with LLM-driven diagnosis (`HydroDiagnostician`) to automatically calibrate and analyze hydrological models.

## Structure

- `agent.py` — `HydroAgent` main class
- `diagnosis.py` — `HydroDiagnostician` for LLM-based analysis
- `environment.py` — `SuperflexEnv` RL environment
- `configs/` — agent configuration
- `tests/` — unit and integration tests
- `examples/` — demo scripts
- `docs/` — workflow and spec documentation

## Usage

```python
from src.hydroagent import HydroAgent

agent = HydroAgent(config_path="src/hydroagent/configs/...")
```

> Note: The deprecated import path `neuralhydrology.hydroagent` raises `ImportError` and redirects here.
