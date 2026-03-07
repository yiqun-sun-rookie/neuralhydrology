from .auto_pgd import AutoPGD
from .cw_regression import CWRegression
from .sparse_temporal import SparseTemporalAttack
from .causal_trigger import CausalTriggerAttack
from .spectral import SpectralAttack
from .uap import UAP
from .fgsm import FGSM
from .random_noise import GaussianNoise, MultiplicativeBias, TemporalCorrelatedNoise

ATTACK_REGISTRY = {
    "auto_pgd": AutoPGD,
    "cw_regression": CWRegression,
    "sparse_temporal": SparseTemporalAttack,
    "causal_trigger": CausalTriggerAttack,
    "spectral": SpectralAttack,
    "uap": UAP,
    "fgsm": FGSM,
    "gaussian_noise": GaussianNoise,
    "multiplicative_bias": MultiplicativeBias,
    "temporal_correlated_noise": TemporalCorrelatedNoise,
}

__all__ = [
    "AutoPGD", "CWRegression", "SparseTemporalAttack",
    "CausalTriggerAttack", "SpectralAttack", "UAP",
    "FGSM", "GaussianNoise", "MultiplicativeBias", "TemporalCorrelatedNoise",
    "ATTACK_REGISTRY",
]
