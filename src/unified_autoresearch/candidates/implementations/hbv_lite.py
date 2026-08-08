"""HBV-lite: a calibrated conceptual bucket model with a snow store.

Four stores -- snowpack, soil moisture, upper zone, lower zone -- and eight calibrated
parameters per basin. Unlike the reference methods in this directory, this is an actual
hydrological model: water entering a store leaves it only as discharge, evaporation, or a
change in storage.

Potential evaporation is deliberately *not* computed from shortwave radiation. The usual
Hargreaves form needs extraterrestrial radiation, and substituting the measured shortwave
flux understates potential evaporation several-fold. Latitude is not among the approved
inputs, so this method instead takes a temperature-driven seasonal shape and scales it so
its long-run mean matches ``pet_mean``, which is one of the twenty-seven frozen static
attributes. The scale is fixed during training and carried in the model, so prediction
never re-derives it from the window it is scoring.
"""

from __future__ import annotations

import math
import random


CATEGORY = "conceptual_rainfall_runoff"
CANDIDATE_ID = "hbv-lite-calibrated-v1"
METHOD_FAMILY = "hbv_lite_bucket"

PARAMETER_NAMES = ("tt", "cfmax", "fc", "beta", "lp", "perc", "k_fast", "k_slow")
PARAMETER_BOUNDS = {
    "tt": (-2.5, 2.5),
    "cfmax": (0.5, 10.0),
    "fc": (50.0, 700.0),
    "beta": (1.0, 6.0),
    "lp": (0.3, 1.0),
    "perc": (0.0, 6.0),
    "k_fast": (0.05, 0.9),
    "k_slow": (0.001, 0.15),
}
INITIAL_PARAMETERS = {
    "tt": 0.0,
    "cfmax": 3.0,
    "fc": 250.0,
    "beta": 2.0,
    "lp": 0.7,
    "perc": 1.5,
    "k_fast": 0.3,
    "k_slow": 0.03,
}
# States every simulation starts from, so a prediction window never inherits training state.
INITIAL_STATES = {"snowpack": 0.0, "soil_moisture": 0.5, "upper_zone": 0.0, "lower_zone": 5.0}
EVAPORATION_TEMPERATURE_BASE = 0.0

POPULATION_SIZE = 24
GENERATIONS = 60
DIFFERENTIAL_WEIGHT = 0.7
CROSSOVER_RATE = 0.9


def _mean_temperature(row: dict) -> float:
    return (float(row["tmin"]) + float(row["tmax"])) / 2.0


def temperature_shape(rows: list[dict]) -> list[float]:
    """Seasonal evaporative-demand shape from temperature alone; radiation is never read."""
    return [max(0.0, _mean_temperature(row) - EVAPORATION_TEMPERATURE_BASE) for row in rows]


def potential_evaporation_scale(rows: list[dict], *, pet_mean: float) -> float:
    """Scale the temperature shape so its mean matches the frozen ``pet_mean`` attribute."""
    shape = temperature_shape(rows)
    total = sum(shape)
    if total <= 0.0:
        return 0.0
    return float(pet_mean) * len(rows) / total


def simulate(rows: list[dict], parameters: dict, *, pet_scale: float, report_balance: bool = False) -> dict:
    """Run the four stores forward over one basin's ordered rows."""
    tt = float(parameters["tt"])
    cfmax = float(parameters["cfmax"])
    fc = max(1e-6, float(parameters["fc"]))
    beta = float(parameters["beta"])
    lp = max(1e-6, float(parameters["lp"]))
    perc = float(parameters["perc"])
    k_fast = min(1.0, max(0.0, float(parameters["k_fast"])))
    k_slow = min(1.0, max(0.0, float(parameters["k_slow"])))

    snowpack = INITIAL_STATES["snowpack"]
    soil_moisture = INITIAL_STATES["soil_moisture"] * fc
    upper_zone = INITIAL_STATES["upper_zone"]
    lower_zone = INITIAL_STATES["lower_zone"]
    initial_storage = snowpack + soil_moisture + upper_zone + lower_zone

    discharge: list[float] = []
    evaporation_total = 0.0
    for row in rows:
        precipitation = float(row["prcp"])
        temperature = _mean_temperature(row)
        potential = max(0.0, temperature - EVAPORATION_TEMPERATURE_BASE) * pet_scale

        if temperature < tt:
            snowpack += precipitation
            liquid = 0.0
        else:
            melt = min(snowpack, cfmax * (temperature - tt))
            snowpack -= melt
            liquid = precipitation + melt

        saturation = min(1.0, max(0.0, soil_moisture / fc))
        recharge = liquid * (saturation**beta)
        soil_moisture += liquid - recharge

        actual = min(soil_moisture, potential * min(1.0, soil_moisture / (lp * fc)))
        soil_moisture -= actual
        evaporation_total += actual

        upper_zone += recharge
        percolation = min(upper_zone, perc)
        upper_zone -= percolation
        lower_zone += percolation

        fast = k_fast * upper_zone
        upper_zone -= fast
        slow = k_slow * lower_zone
        lower_zone -= slow
        discharge.append(fast + slow)

    result = {"discharge": discharge}
    if report_balance:
        final_storage = snowpack + soil_moisture + upper_zone + lower_zone
        result.update(
            {
                "snowpack": snowpack,
                "soil_moisture": soil_moisture,
                "upper_zone": upper_zone,
                "lower_zone": lower_zone,
                "evaporation": evaporation_total,
                "storage_change": final_storage - initial_storage,
            }
        )
    return result


def _objective(simulated: list[float], observed: list[float], denominator: float, mean_observed: float) -> float:
    """Nash--Sutcliffe efficiency against the training window; higher is better."""
    if denominator <= 0.0:
        error = sum((value - target) ** 2 for value, target in zip(simulated, observed))
        return -error
    error = sum((value - target) ** 2 for value, target in zip(simulated, observed))
    value = 1.0 - error / denominator
    return value if math.isfinite(value) else -1.0e12


def _clip(name: str, value: float) -> float:
    low, high = PARAMETER_BOUNDS[name]
    return min(high, max(low, value))


def _calibrate(rows: list[dict], observed: list[float], pet_scale: float, seed: int) -> tuple[dict, float, float]:
    """Seeded differential evolution over the eight parameters; deterministic for a seed."""
    mean_observed = sum(observed) / len(observed)
    denominator = sum((value - mean_observed) ** 2 for value in observed)

    def score(parameters: dict) -> float:
        simulated = simulate(rows, parameters, pet_scale=pet_scale)["discharge"]
        return _objective(simulated, observed, denominator, mean_observed)

    initial_objective = score(INITIAL_PARAMETERS)
    generator = random.Random(seed)
    population = [dict(INITIAL_PARAMETERS)]
    for _ in range(POPULATION_SIZE - 1):
        population.append(
            {name: generator.uniform(*PARAMETER_BOUNDS[name]) for name in PARAMETER_NAMES}
        )
    scores = [score(member) for member in population]
    # Recorded so a caller can tell evolution apart from plain random sampling of the population.
    initial_population_objective = max(scores)

    for _ in range(GENERATIONS):
        for index in range(len(population)):
            choices = [position for position in range(len(population)) if position != index]
            first, second, third = generator.sample(choices, 3)
            forced = generator.randrange(len(PARAMETER_NAMES))
            trial = {}
            for position, name in enumerate(PARAMETER_NAMES):
                if position == forced or generator.random() < CROSSOVER_RATE:
                    mutated = population[first][name] + DIFFERENTIAL_WEIGHT * (
                        population[second][name] - population[third][name]
                    )
                    trial[name] = _clip(name, mutated)
                else:
                    trial[name] = population[index][name]
            trial_score = score(trial)
            if trial_score > scores[index]:
                population[index] = trial
                scores[index] = trial_score

    best = max(range(len(population)), key=lambda position: scores[position])
    return population[best], float(scores[best]), float(initial_objective), float(initial_population_objective)


def _group_by_basin(features: list[dict]) -> dict[str, list[dict]]:
    grouped: dict[str, list[dict]] = {}
    for row in features:
        grouped.setdefault(row["basin"], []).append(row)
    return {basin: sorted(rows, key=lambda item: item["date_key"]) for basin, rows in grouped.items()}


def train_model(features: list[dict], targets: dict, statics: dict, seed: int) -> dict:
    """Calibrate one parameter set per basin against the training window."""
    grouped = _group_by_basin(features)
    attributes = statics["basins"]
    basins: dict[str, dict] = {}
    for offset, (basin, rows) in enumerate(sorted(grouped.items())):
        observed = [float(targets[(row["basin"], row["date_key"])]) for row in rows]
        pet_mean = float(attributes[basin]["pet_mean"]) if basin in attributes else 0.0
        pet_scale = potential_evaporation_scale(rows, pet_mean=pet_mean)
        # Offsetting by basin keeps each basin's search independent of the iteration order.
        parameters, objective, initial, population_best = _calibrate(
            rows, observed, pet_scale, seed * 1_000_003 + offset
        )
        basins[basin] = {
            "parameters": {name: float(parameters[name]) for name in PARAMETER_NAMES},
            "pet_scale": float(pet_scale),
            "training_objective": objective,
            "initial_objective": initial,
            "initial_population_objective": population_best,
        }
    fallback = sum(float(value) for value in targets.values()) / max(1, len(targets))
    return {"basins": basins, "fallback_discharge": float(fallback)}


def predict(features: list[dict], statics: dict, model: dict) -> list[float]:
    """Simulate each basin from the fixed initial states, never from training state."""
    del statics
    grouped = _group_by_basin(features)
    by_key: dict[tuple[str, str], float] = {}
    for basin, rows in grouped.items():
        entry = model["basins"].get(basin)
        if entry is None:
            for row in rows:
                by_key[(basin, row["date_key"])] = max(0.0, float(model["fallback_discharge"]))
            continue
        discharge = simulate(rows, entry["parameters"], pet_scale=float(entry["pet_scale"]))["discharge"]
        for row, value in zip(rows, discharge):
            by_key[(basin, row["date_key"])] = float(value)
    return [by_key[(row["basin"], row["date_key"])] for row in features]
