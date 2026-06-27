"""The four evidence firewalls have real teeth (Results / Autonomy / Novelty / Conclusions).

These tests encode the failure modes a real research episode exposed, so they
cannot silently recur: estimates posing as results, smuggled search cages,
self-asserted novelty, and hypotheses dressed as conclusions.
"""
import pytest

from fair_benchmark import governance as G
from fair_benchmark.governance import Conclusion


def _ledger(tmp_path):
    p = tmp_path / "ledger.csv"
    p.write_text(
        "timestamp,experiment_id,track,verdict,median_paired_delta,wilcoxon_p,n,"
        "challenger_median,baseline_median,predictions_sha\n"
        "t,001_x,track0,HOLD,-0.1,0.0,424,0.6523,0.7526,abc\n",
        encoding="utf-8")
    return p


# ---- Firewall 1: RESULTS (only real runs count) ----
def test_is_real_result(tmp_path):
    led = _ledger(tmp_path)
    assert G.is_real_result("001_x", led)
    assert not G.is_real_result("999_ghost", led)


def test_verify_number_matches_ledger_and_rejects_fabrication(tmp_path):
    led = _ledger(tmp_path)
    assert G.verify_number("001_x", 0.6523, led, tol=1e-3)[0]
    assert not G.verify_number("001_x", 0.75, led)[0]          # wrong number
    assert not G.verify_number("999_ghost", 0.5, led)[0]       # claim with no real run


# ---- Firewall 2: AUTONOMY (explicit constraints; no smuggled cages) ----
def test_shipped_framework_has_zero_active_cages():
    c = G.load_constraints()
    assert G.active_cages(c) == []                              # healthy = no cages
    ids = {x["id"] for x in G.invariants(c)}
    assert "information_budget" in ids and "held_eval_observations" in ids


def test_cage_scanner_flags_a_smuggled_constraint(tmp_path):
    f = tmp_path / "loop.py"
    f.write_text('p = "Pick the next candidate from the CPU-FAST class only; '
                 'choose from these techniques."\n', encoding="utf-8")
    assert len(G.scan_orchestration_for_cages([f])) >= 1


def test_cage_scanner_clean_on_an_open_prompt(tmp_path):
    f = tmp_path / "open.py"
    f.write_text('p = "Propose or invent any method from anywhere in ML/AI; '
                 'the fairness budget is the only thing that bounds you."\n', encoding="utf-8")
    assert G.scan_orchestration_for_cages([f]) == []


# ---- Firewall 3: NOVELTY (literature-grounded, never self-asserted) ----
def test_novelty_requires_citations():
    assert G.validate_novelty("genuinely-novel", ["Smith 2024, WRR"])[0]
    assert not G.validate_novelty("genuinely-novel", [])[0]     # novel without prior-art check
    assert not G.validate_novelty("totally-new", ["x"])[0]      # unknown class


# ---- Firewall 4: CONCLUSIONS (evidence-based or labelled hypothesis) ----
def test_evidence_based_conclusion_must_cite_real_runs(tmp_path):
    led = _ledger(tmp_path)
    assert G.validate_conclusion(Conclusion("X improves on Y", "evidence-based", ["001_x"]), led)[0]
    assert not G.validate_conclusion(Conclusion("X improves on Y", "evidence-based", ["999_ghost"]), led)[0]
    assert not G.validate_conclusion(Conclusion("X improves on Y", "evidence-based", []), led)[0]


def test_hypothesis_must_name_a_settling_test(tmp_path):
    led = _ledger(tmp_path)
    assert not G.validate_conclusion(Conclusion("Z might win", "hypothesis", settling_test=""), led)[0]
    assert G.validate_conclusion(Conclusion("Z might win", "hypothesis", settling_test="run experiment 004"), led)[0]


def test_append_conclusion_rejects_estimate_dressed_as_conclusion(tmp_path):
    led = _ledger(tmp_path)
    with pytest.raises(ValueError):
        G.append_conclusion(tmp_path / "c.md",
                            Conclusion("no winner exists", "evidence-based", []), ledger_path=led)


# ---- Firewall 1 hardening: tamper-evident ledger (hash-chain) ----
def test_chain_verifies_for_rows_written_by_append(tmp_path):
    from fair_benchmark import ledger as L
    led = tmp_path / "l.csv"
    L.append_attempt(led, {"experiment_id": "a", "verdict": "HOLD", "challenger_median": 0.5})
    L.append_attempt(led, {"experiment_id": "b", "verdict": "PASS", "challenger_median": 0.8})
    assert G.verify_chain(led)["ok"]


def test_chain_detects_hand_appended_fake_winner(tmp_path):
    from fair_benchmark import ledger as L
    led = tmp_path / "l.csv"
    L.append_attempt(led, {"experiment_id": "a", "verdict": "HOLD", "challenger_median": 0.5})
    with led.open("a", encoding="utf-8") as f:  # the gamer's exact exploit
        f.write("t,999_fake_winner,track0,PASS,0.1,0.0,424,0.81,0.75,deadbeef,deadbeefhash\n")
    res = G.verify_chain(led)
    assert not res["ok"] and any(b["experiment_id"] == "999_fake_winner" for b in res["breaks"])


# ---- Firewall 2 hardening: menu-as-data-array detection ----
def test_data_menu_scanner_flags_hardcoded_slate(tmp_path):
    f = tmp_path / "rerank.js"
    f.write_text("\n".join(f"  {{ rank: {i}, name: 'method_{i}', win: 0.1 }}," for i in range(10)),
                 encoding="utf-8")
    assert len(G.scan_for_data_menus([f])) >= 1


def test_data_menu_scanner_clean_below_threshold(tmp_path):
    f = tmp_path / "few.js"
    f.write_text("name: 'a'\nname: 'b'\n", encoding="utf-8")
    assert G.scan_for_data_menus([f]) == []


# ---- Firewall 4 hardening: provenance-strict conclusions ----
def test_conclusion_provenance_strict_rejects_unlocatable(tmp_path):
    from fair_benchmark import ledger as L
    led = tmp_path / "l.csv"
    L.append_attempt(led, {"experiment_id": "x1", "verdict": "HOLD",
                           "challenger_median": 0.6, "predictions_sha": "abc"})
    ok, _ = G.validate_conclusion(Conclusion("x1 holds", "evidence-based", ["x1"]),
                                  led, require_provenance=True, experiments_root=tmp_path / "noexp")
    assert not ok                                            # cited row not provenance-verifiable
    assert G.validate_conclusion(Conclusion("x1 holds", "evidence-based", ["x1"]), led)[0]  # lax mode still ok


# ---- Round-4 hardening ----
def test_provenance_sidecar_cross_checks_when_csv_absent(tmp_path):
    from fair_benchmark import ledger as L
    led = tmp_path / "l.csv"
    L.append_attempt(led, {"experiment_id": "e1", "verdict": "HOLD", "predictions_sha": "abc123"})
    sub = tmp_path / "exp" / "e1" / "submission"
    sub.mkdir(parents=True)
    (sub / "predictions.sha256").write_text("abc123\n", encoding="utf-8")  # csv gone, sidecar matches
    prov = {p["experiment_id"]: p["status"] for p in G.verify_provenance(led, tmp_path / "exp")}
    assert prov["e1"] == "sha-only"
    (sub / "predictions.sha256").write_text("WRONG\n", encoding="utf-8")   # tampered sidecar
    prov = {p["experiment_id"]: p["status"] for p in G.verify_provenance(led, tmp_path / "exp")}
    assert prov["e1"] == "MISMATCH"


def test_data_menu_scanner_flags_bare_var_array(tmp_path):
    f = tmp_path / "loop.js"
    f.write_text("const CANDS = [\n  'a', 'b', 'c'\n]\n", encoding="utf-8")
    assert any(h["pattern"] == "data-menu(var-array)" for h in G.scan_for_data_menus([f]))


def test_train_eval_leakage_scanner(tmp_path):
    clean = tmp_path / "train_clean.py"
    clean.write_text("# trains on 1999-2008 train obs only\nx = load(start='1999-10-01')\n", encoding="utf-8")
    assert G.scan_train_for_eval_leakage(clean) == []
    dirty = tmp_path / "train_dirty.py"
    dirty.write_text("obs = read('track0_forcing_only_obs_eval.parquet')  # cheat\n", encoding="utf-8")
    assert len(G.scan_train_for_eval_leakage(dirty)) >= 1


def test_append_conclusion_requires_ledger_path(tmp_path):
    import pytest as _pt
    with _pt.raises(ValueError):
        G.append_conclusion(tmp_path / "c.md", Conclusion("x", "hypothesis", settling_test="run it"))
