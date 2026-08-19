"""Development-only history-conditioned differentiable HBV-lite IMM."""

from .hbv import HBV15Model, forecast_global_state, project_hbv15, recession_half_weights
from .filter import (
    DifferentiableInteractingMultipleModel,
    InteractionResult,
    InteractingStepResult,
    interact_model_states,
)
from .network import HistoryTransitionNetwork, build_history_features
from .synthetic import BlockSeeds, SyntheticBatch, generate_synthetic_batch, make_block_seeds
from .training import (
    DEFAULT_LOSS_WEIGHTS,
    LossBreakdown,
    LossWeights,
    RolloutResult,
    TrainingResult,
    TrainingStatistics,
    evaluate_checkpoint,
    fit_training_statistics,
    rollout_end_to_end,
    train_history_transition,
    train_one_epoch,
)
from .probability_audit import (
    ActiveRowOracle,
    TransitionRecoveryScores,
    active_transition_rows,
    balanced_active_row_oracle_brier,
    build_active_row_oracle,
    score_transition_recovery,
)

__all__ = [
    "HBV15Model",
    "forecast_global_state",
    "project_hbv15",
    "recession_half_weights",
    "DifferentiableInteractingMultipleModel",
    "InteractionResult",
    "InteractingStepResult",
    "interact_model_states",
    "HistoryTransitionNetwork",
    "build_history_features",
    "BlockSeeds",
    "SyntheticBatch",
    "generate_synthetic_batch",
    "make_block_seeds",
    "LossBreakdown",
    "LossWeights",
    "DEFAULT_LOSS_WEIGHTS",
    "RolloutResult",
    "TrainingResult",
    "TrainingStatistics",
    "evaluate_checkpoint",
    "fit_training_statistics",
    "rollout_end_to_end",
    "train_history_transition",
    "train_one_epoch",
    "ActiveRowOracle",
    "TransitionRecoveryScores",
    "active_transition_rows",
    "balanced_active_row_oracle_brier",
    "build_active_row_oracle",
    "score_transition_recovery",
]
