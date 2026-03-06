from .auto_pgd import AutoPGD
from .cw_regression import CWRegression
from .sparse_temporal import SparseTemporalAttack
from .causal_trigger import CausalTriggerAttack
from .spectral import SpectralAttack
from .uap import UAP

ATTACK_REGISTRY = {
    "auto_pgd": AutoPGD,
    "cw_regression": CWRegression,
    "sparse_temporal": SparseTemporalAttack,
    "causal_trigger": CausalTriggerAttack,
    "spectral": SpectralAttack,
    "uap": UAP,
}

__all__ = [
    "AutoPGD", "CWRegression", "SparseTemporalAttack",
    "CausalTriggerAttack", "SpectralAttack", "UAP",
    "ATTACK_REGISTRY",
]
