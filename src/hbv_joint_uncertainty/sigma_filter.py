"""Modified unscented Kalman filter with regenerated measurement sigma points."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Callable

import numpy as np


ArrayFunction = Callable[[np.ndarray], np.ndarray]


def _finite_vector(values, size: int, label: str) -> np.ndarray:
    vector = np.asarray(values, dtype=np.float64)
    if vector.shape != (size,):
        raise ValueError(f"{label} must have shape ({size},), got {vector.shape}")
    if not np.all(np.isfinite(vector)):
        raise ValueError(f"{label} must contain only finite values")
    return vector


def _finite_symmetric_matrix(values, size: int, label: str) -> np.ndarray:
    matrix = np.asarray(values, dtype=np.float64)
    if matrix.shape != (size, size):
        raise ValueError(f"{label} must have shape ({size}, {size}), got {matrix.shape}")
    if not np.all(np.isfinite(matrix)):
        raise ValueError(f"{label} must contain only finite values")
    if not np.allclose(matrix, matrix.T, rtol=0.0, atol=1e-12):
        raise ValueError(f"{label} must be symmetric")
    return 0.5 * (matrix + matrix.T)


def _finite_observation(values, size: int) -> np.ndarray:
    observed = np.asarray(values, dtype=np.float64)
    if observed.ndim == 0 and size == 1:
        observed = observed.reshape(1)
    return _finite_vector(observed, size, "observation")


class ScaledSigmaPoints:
    """Van der Merwe scaled sigma points with bounded covariance repair."""

    def __init__(self, n: int, alpha: float = 0.6874, beta: float = 2.0, kappa: float = -2.0):
        if n <= 0:
            raise ValueError("n must be positive")
        self.n = int(n)
        self.alpha = float(alpha)
        self.beta = float(beta)
        self.kappa = float(kappa)
        if not np.all(np.isfinite([self.alpha, self.beta, self.kappa])):
            raise ValueError("sigma-point parameters must be finite")
        self.lambda_ = self.alpha**2 * (self.n + self.kappa) - self.n
        self.scale = self.n + self.lambda_
        if self.scale <= 0.0:
            raise ValueError("alpha and kappa must give a positive sigma-point scale")

        self.mean_weights = np.full(2 * self.n + 1, 1.0 / (2.0 * self.scale), dtype=np.float64)
        self.covariance_weights = self.mean_weights.copy()
        self.mean_weights[0] = self.lambda_ / self.scale
        self.covariance_weights[0] = self.mean_weights[0] + 1.0 - self.alpha**2 + self.beta

    @property
    def count(self) -> int:
        return 2 * self.n + 1

    def sigma_points(self, mean, covariance) -> np.ndarray:
        mean_vector = _finite_vector(mean, self.n, "mean")
        covariance_matrix = _finite_symmetric_matrix(covariance, self.n, "covariance")
        eigenvalues = np.linalg.eigvalsh(covariance_matrix)
        minimum_eigenvalue = float(np.min(eigenvalues))
        spectral_scale = max(float(np.max(np.abs(eigenvalues))), 1.0)
        roundoff_tolerance = max(
            1e-12,
            np.finfo(np.float64).eps * self.n * spectral_scale * 100.0,
        )
        if minimum_eigenvalue < -roundoff_tolerance:
            raise ValueError(
                "covariance must be positive semidefinite before bounded jitter; "
                f"minimum eigenvalue is {minimum_eigenvalue}"
            )

        scaled = self.scale * covariance_matrix
        try:
            root = np.linalg.cholesky(scaled)
        except np.linalg.LinAlgError:
            jitter = max(roundoff_tolerance, -minimum_eigenvalue + roundoff_tolerance)
            try:
                root = np.linalg.cholesky(self.scale * (covariance_matrix + jitter * np.eye(self.n)))
            except np.linalg.LinAlgError as error:
                raise ValueError("covariance must be positive semidefinite after bounded jitter") from error

        sigmas = np.empty((self.count, self.n), dtype=np.float64)
        sigmas[0] = mean_vector
        for index in range(self.n):
            offset = root[:, index]
            sigmas[index + 1] = mean_vector + offset
            sigmas[self.n + index + 1] = mean_vector - offset
        return sigmas


def unscented_transform(
    sigmas: np.ndarray,
    mean_weights: np.ndarray,
    covariance_weights: np.ndarray,
    additive_covariance: np.ndarray | None = None,
) -> tuple[np.ndarray, np.ndarray]:
    """Transform sigma points into their weighted mean and covariance."""
    points = np.asarray(sigmas, dtype=np.float64)
    if points.ndim != 2 or not np.all(np.isfinite(points)):
        raise ValueError("sigmas must be a finite two-dimensional array")
    mean_weights = _finite_vector(mean_weights, points.shape[0], "mean_weights")
    covariance_weights = _finite_vector(covariance_weights, points.shape[0], "covariance_weights")
    mean = mean_weights @ points
    deviations = points - mean
    covariance = np.einsum("i,ij,ik->jk", covariance_weights, deviations, deviations)
    if additive_covariance is not None:
        covariance = covariance + _finite_symmetric_matrix(
            additive_covariance, points.shape[1], "additive_covariance"
        )
    covariance = 0.5 * (covariance + covariance.T)
    if not np.all(np.isfinite(covariance)):
        raise ValueError("unscented covariance is non-finite")
    return mean, covariance


def _gaussian_log_likelihood(innovation: np.ndarray, covariance: np.ndarray) -> float:
    sign, log_determinant = np.linalg.slogdet(covariance)
    if sign <= 0 or not np.isfinite(log_determinant):
        raise ValueError("innovation covariance must be positive definite")
    try:
        root = np.linalg.cholesky(covariance)
        whitened = np.linalg.solve(root, innovation)
    except np.linalg.LinAlgError as error:
        raise ValueError("innovation covariance is singular") from error
    scale = float(np.max(np.abs(whitened)))
    if scale == 0.0:
        mahalanobis = 0.0
    else:
        scaled_squared_norm = float(np.sum((whitened / scale)**2))
        maximum = np.finfo(np.float64).max
        if scale > np.sqrt(maximum / scaled_squared_norm):
            mahalanobis = maximum
        else:
            mahalanobis = scale**2 * scaled_squared_norm
    dimension = len(innovation)
    result = -0.5 * (dimension * np.log(2.0 * np.pi) + log_determinant + mahalanobis)
    if not np.isfinite(result):
        raise ValueError("log likelihood is non-finite")
    return float(result)


@dataclass(frozen=True)
class FilterStepResult:
    prior_state: np.ndarray
    prior_covariance: np.ndarray
    prior_observation: np.ndarray
    innovation: np.ndarray
    innovation_covariance: np.ndarray
    posterior_state: np.ndarray
    posterior_covariance: np.ndarray
    log_likelihood: float


class ModifiedUnscentedFilter:
    """Predict, add process covariance, regenerate sigma points, then observe."""

    def __init__(
        self,
        state,
        covariance,
        transition: ArrayFunction,
        observation: ArrayFunction,
        process_covariance,
        observation_covariance,
        state_projector: ArrayFunction | None = None,
        alpha: float = 0.6874,
        beta: float = 2.0,
        kappa: float = -2.0,
    ):
        state_vector = np.asarray(state, dtype=np.float64)
        if state_vector.ndim != 1:
            raise ValueError("state must be one-dimensional")
        self.n_state = len(state_vector)
        self.state = _finite_vector(state_vector, self.n_state, "state").copy()
        self.covariance = _finite_symmetric_matrix(covariance, self.n_state, "covariance").copy()
        self.process_covariance = _finite_symmetric_matrix(
            process_covariance, self.n_state, "process_covariance"
        ).copy()
        observation_matrix = np.asarray(observation_covariance, dtype=np.float64)
        if observation_matrix.ndim == 0:
            observation_matrix = observation_matrix.reshape(1, 1)
        if observation_matrix.ndim != 2 or observation_matrix.shape[0] != observation_matrix.shape[1]:
            raise ValueError("observation_covariance must be square")
        self.n_observation = observation_matrix.shape[0]
        self.observation_covariance = _finite_symmetric_matrix(
            observation_matrix, self.n_observation, "observation_covariance"
        ).copy()
        self.transition = transition
        self.observation = observation
        if state_projector is not None and not callable(state_projector):
            raise TypeError("state_projector must be callable or None")
        self.state_projector = state_projector
        self.sigma_generator = ScaledSigmaPoints(self.n_state, alpha=alpha, beta=beta, kappa=kappa)
        self._prior_state = None
        self._prior_covariance = None

    def predict(self) -> tuple[np.ndarray, np.ndarray]:
        sigmas = self.sigma_generator.sigma_points(self.state, self.covariance)
        transformed = np.asarray([self.transition(point.copy()) for point in sigmas], dtype=np.float64)
        if transformed.shape != sigmas.shape or not np.all(np.isfinite(transformed)):
            raise ValueError("transition must return one finite state vector per sigma point")
        prior_state, prior_covariance = unscented_transform(
            transformed,
            self.sigma_generator.mean_weights,
            self.sigma_generator.covariance_weights,
            self.process_covariance,
        )
        self._prior_state = prior_state
        self._prior_covariance = prior_covariance
        return prior_state.copy(), prior_covariance.copy()

    def predict_without_observation(self) -> tuple[np.ndarray, np.ndarray]:
        """Advance and commit the same unscented prior while skipping observation updating."""
        prior_state, prior_covariance = self.predict()
        self.state = prior_state.copy()
        self.covariance = prior_covariance.copy()
        self._prior_state = None
        self._prior_covariance = None
        return prior_state, prior_covariance

    def update(self, observation) -> FilterStepResult:
        if self._prior_state is None or self._prior_covariance is None:
            raise RuntimeError("predict must be called before update")
        observed = _finite_observation(observation, self.n_observation)
        sigmas = self.sigma_generator.sigma_points(self._prior_state, self._prior_covariance)
        observation_sigmas = np.asarray([self.observation(point.copy()) for point in sigmas], dtype=np.float64)
        if observation_sigmas.shape == (len(sigmas),):
            observation_sigmas = observation_sigmas[:, None]
        if observation_sigmas.shape != (len(sigmas), self.n_observation):
            raise ValueError(
                "observation function returned shape "
                f"{observation_sigmas.shape}; expected ({len(sigmas)}, {self.n_observation})"
            )
        if not np.all(np.isfinite(observation_sigmas)):
            raise ValueError("observation function returned non-finite values")

        prior_observation, innovation_covariance = unscented_transform(
            observation_sigmas,
            self.sigma_generator.mean_weights,
            self.sigma_generator.covariance_weights,
            self.observation_covariance,
        )
        state_deviations = sigmas - self._prior_state
        observation_deviations = observation_sigmas - prior_observation
        cross_covariance = np.einsum(
            "i,ij,ik->jk",
            self.sigma_generator.covariance_weights,
            state_deviations,
            observation_deviations,
        )
        try:
            gain = np.linalg.solve(innovation_covariance.T, cross_covariance.T).T
        except np.linalg.LinAlgError as error:
            raise ValueError("innovation covariance is singular") from error
        innovation = observed - prior_observation
        posterior_state = self._prior_state + gain @ innovation
        if self.state_projector is not None:
            posterior_state = _finite_vector(
                self.state_projector(posterior_state.copy()),
                self.n_state,
                "projected posterior state",
            )
        posterior_covariance = self._prior_covariance - gain @ innovation_covariance @ gain.T
        posterior_covariance = 0.5 * (posterior_covariance + posterior_covariance.T)
        if not np.all(np.isfinite(posterior_state)) or not np.all(np.isfinite(posterior_covariance)):
            raise ValueError("posterior state or covariance is non-finite")

        log_likelihood = _gaussian_log_likelihood(innovation, innovation_covariance)
        result = FilterStepResult(
            prior_state=self._prior_state.copy(),
            prior_covariance=self._prior_covariance.copy(),
            prior_observation=prior_observation.copy(),
            innovation=innovation.copy(),
            innovation_covariance=innovation_covariance.copy(),
            posterior_state=posterior_state.copy(),
            posterior_covariance=posterior_covariance.copy(),
            log_likelihood=log_likelihood,
        )
        self.state = posterior_state
        self.covariance = posterior_covariance
        self._prior_state = None
        self._prior_covariance = None
        return result

    def step(self, observation) -> FilterStepResult:
        observed = _finite_observation(observation, self.n_observation)
        self.predict()
        return self.update(observed)
