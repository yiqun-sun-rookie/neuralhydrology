"""HydroAgent package extracted from neuralhydrology.hydroagent."""

from .agent import (
    HydroAgent,
    BaseLLMClient,
    MockLLMClient,
    OpenAIClient,
    DeepSeekClient,
    ClaudeClient,
    OllamaClient,
)
from .diagnosis import HydroDiagnostician
from .environment import SuperflexEnv

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
]

