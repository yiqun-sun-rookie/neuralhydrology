"""HydroAgent package extracted from neuralhydrology.hydroagent.

Submodules that depend on the optional `superflexpy` package
(`environment`, `agent`, `diagnosis`) are wrapped in try/except so the
package can still be imported in environments that only need
`data_loading` (e.g. an XAJ-only run on local dev). Names that fail to
load are exposed as `None`; calling code that actually needs them gets
an explicit error at use site rather than at import time.
"""

try:
    from .agent import (
        HydroAgent,
        BaseLLMClient,
        MockLLMClient,
        OpenAIClient,
        DeepSeekClient,
        ClaudeClient,
        OllamaClient,
    )
except (ImportError, ModuleNotFoundError):
    HydroAgent = None  # type: ignore[assignment,misc]
    BaseLLMClient = None  # type: ignore[assignment,misc]
    MockLLMClient = None  # type: ignore[assignment,misc]
    OpenAIClient = None  # type: ignore[assignment,misc]
    DeepSeekClient = None  # type: ignore[assignment,misc]
    ClaudeClient = None  # type: ignore[assignment,misc]
    OllamaClient = None  # type: ignore[assignment,misc]

try:
    from .diagnosis import HydroDiagnostician
except (ImportError, ModuleNotFoundError):
    HydroDiagnostician = None  # type: ignore[assignment,misc]

try:
    from .environment import SuperflexEnv
except (ImportError, ModuleNotFoundError):
    SuperflexEnv = None  # type: ignore[assignment,misc]

from .experiment_logger import ExperimentLogger

__all__ = [
    "HydroAgent",
    "BaseLLMClient",
    "MockLLMClient",
    "OpenAIClient",
    "DeepSeekClient",
    "ClaudeClient",
    "OllamaClient",
    "HydroDiagnostician",
    "SuperflexEnv",
    "ExperimentLogger",
]

