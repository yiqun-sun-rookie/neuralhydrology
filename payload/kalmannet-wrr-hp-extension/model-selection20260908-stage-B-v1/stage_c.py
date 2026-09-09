"""C-only registration; original A/B configuration bytes remain unchanged."""
from decimal import Decimal

from evidence_contract import METRIC, require, verify_seal


def combos_from_lock(lock):
    verify_seal(lock, kind="TOP_THREE_LOCK")
    require(lock.get("metric") == METRIC and lock.get("new_seeds") == [45, 46, 47, 48, 49], "Wrong C lock metric/seeds")
    top = lock["top_three"]
    require(len(top) == 3 and [r["rank"] for r in top] == [1, 2, 3], "Wrong top-three rank inventory")
    rows, identities = [], set()
    for ranked in top:
        config = ranked["config"]
        require(set(config) == {"hidden_size", "num_layers", "in_out_mult", "lr"}, "C full configuration fields required")
        require(all(type(config[k]) is int and config[k] > 0 for k in ("hidden_size", "num_layers", "in_out_mult")), "C architecture malformed")
        lr = Decimal(str(config["lr"]))
        require(lr.is_finite() and lr > 0, "C learning rate malformed")
        identity = (config["hidden_size"], config["num_layers"], config["in_out_mult"], lr)
        require(identity not in identities, "Duplicate C configuration")
        identities.add(identity)
        for seed in (45, 46, 47, 48, 49):
            index = len(rows)
            rows.append(dict(config, lr=float(lr), seed=seed, effective_seed=seed, index=index, stage="C",
                             run_id=f"NGF-SELECT-20260908-C{index+1:02d}", role="five_new_seed_confirmation"))
    return rows


def validate_c_combo(lock, index, combo):
    require(type(index) is int and 0 <= index < 15, "C index outside 0..14")
    expected = combos_from_lock(lock)[index]
    require(combo == expected and all(type(combo[k]) is type(v) for k, v in expected.items()), "C combo identity mismatch")
    return combo
