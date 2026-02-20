"""Deprecated import path for HydroAgent.

Use:
    from hydroagent import HydroAgent, HydroDiagnostician, SuperflexEnv
or:
    from hydroagent.environment import SuperflexEnv
"""

raise ImportError(
    "Deprecated module path: 'neuralhydrology.hydroagent'. "
    "Please import from 'hydroagent' (package lives in 'src/hydroagent')."
)
