"""Governance — the four evidence firewalls that keep the auto-research framework
honest, so the failure modes a real research episode exposed do not recur.

  1. RESULTS     only real, executed, measured outcomes count. A reported number
                 must trace to a tamper-evident (hash-chained) ledger row with a
                 predictions sha. is_real_result / verify_number / verify_provenance
                 / verify_chain.
  2. AUTONOMY    every constraint on the search is declared INVARIANT or CAGE; a
                 healthy framework has zero active cages. Orchestration prompts are
                 scanned for prose cages AND menus encoded as data (keyed dicts or
                 menu-ish arrays). load_constraints / active_cages /
                 scan_orchestration_for_cages / scan_for_data_menus.
  3. NOVELTY     novelty is grounded against literature, not self-asserted.
                 validate_novelty.
  4. CONCLUSIONS a claim is EVIDENCE-BASED (cites real, provenance-verified ledger
                 rows) or a HYPOTHESIS (names the runnable settling test).
                 validate_conclusion / append_conclusion.

THREAT MODEL + ITS LIMIT (be honest): the adversary is our own agents/hands taking
shortcuts, not a cryptographic attacker. These firewalls make lazy/accidental
cheating break loudly and surface everything for review. They CANNOT stop a
DELIBERATE in-environment agent: the hash-chain is keyless (an agent can recompute
row_hash and drop a matching predictions file), and any local artifact an agent can
write, it can forge. The actual last line of defense against deliberate fabrication
is a TRUSTED VERIFIER OUTSIDE THE AGENT'S REACH — the human judge + an independent
audit from a clean context (which is what caught these residuals), or an
out-of-environment re-execution of the candidate. Local checks raise the bar and
keep the human honest; they are not a substitute for that verifier.

Enforcing self-audit:  python -m fair_benchmark.governance --scan <orchestration prompts>
"""
from __future__ import annotations

import re
import sys
from dataclasses import dataclass, field
from pathlib import Path

from ruamel.yaml import YAML

_yaml = YAML(typ="safe")
_HERE = Path(__file__).resolve().parent


def _read_yaml(path):
    p = Path(path)
    if not p.exists():
        return None
    with p.open("r", encoding="utf-8") as f:
        return _yaml.load(f)


# ============================ Firewall 2: AUTONOMY ============================
def load_constraints(path=None) -> dict:
    path = Path(path) if path else _HERE / "constraints.yaml"
    with path.open("r", encoding="utf-8") as f:
        return _yaml.load(f) or {}


def active_cages(constraints: dict) -> list:
    return [c for c in (constraints.get("constraints") or []) if c.get("kind") == "cage"]


def invariants(constraints: dict) -> list:
    return [c for c in (constraints.get("constraints") or []) if c.get("kind") == "invariant"]


CAGE_SIGNAL_PATTERNS = [
    r"cpu[- ]?fast\s+(class\s+)?only",
    r"\bonly\b[^.\n]{0,20}\bcpu\b",
    r"\bchoose from\b",
    r"\bpick from\b",
    r"from (this|the) (menu|list|following)",
    r"restricted to (the )?(following|these|a (menu|list|class))",
    r"\bstay within\b[^.\n]{0,30}\b(slate|catalog|list|menu)\b",
    r"\b(exclusively|only) from\b[^.\n]{0,30}\b(slate|catalog|list|menu)\b",
    r"\bdo not (train|run|propose|consider|use)\b",
    r"\bonly (propose|pick|select|choose)\b[^.\n]{0,40}\b(from|within|these|the following)\b",
]
# menu-ish keys (candidate-semantic; config lists use descriptive names, not these)
_MENU_KEY_LINE = re.compile(r"""['"]?\b(name|technique|method|model|approach|candidate)\b['"]?\s*[:=]\s*['"]""", re.I)
# a menu-ish VARIABLE assigned an array literal (catches `const CANDS = [`), but not
# legitimate config lists (STATIC_27 = [...], DYN = [...]) whose names are not menu-ish.
_MENU_VAR_ARRAY = re.compile(
    r"""\b(cand|cands|candidates|slate|catalog|menu|techniques?|methods?|models?|approaches?|options?|choices?)\b\s*[:=]\s*\[""",
    re.I)


def scan_orchestration_for_cages(paths, patterns=None) -> list:
    """Scan orchestration/prompt files for search-narrowing cage signals (prose)."""
    pats = [re.compile(p, re.IGNORECASE) for p in (patterns or CAGE_SIGNAL_PATTERNS)]
    hits = []
    for raw in paths:
        p = Path(raw)
        if not p.exists() or p.is_dir():
            continue
        for i, line in enumerate(p.read_text(encoding="utf-8", errors="replace").splitlines(), 1):
            for pat in pats:
                if pat.search(line):
                    hits.append({"file": str(p), "line": i, "pattern": pat.pattern, "text": line.strip()[:200]})
    return hits


def scan_for_data_menus(paths, min_items: int = 8) -> list:
    """Flag a hardcoded candidate/method menu encoded as DATA: N+ menu-keyed entries
    (name/technique/method/...) OR a menu-ish variable assigned an array literal."""
    hits = []
    for raw in paths:
        p = Path(raw)
        if not p.exists() or p.is_dir():
            continue
        lines = p.read_text(encoding="utf-8", errors="replace").splitlines()
        key_idxs = [i for i, l in enumerate(lines, 1) if _MENU_KEY_LINE.search(l)]
        if len(key_idxs) >= min_items:
            hits.append({"file": str(p), "line": key_idxs[0], "pattern": "data-menu(keys)",
                         "text": f"{len(key_idxs)} menu-key entries — likely a hardcoded candidate/method menu", "count": len(key_idxs)})
        for i, l in enumerate(lines, 1):
            if _MENU_VAR_ARRAY.search(l):
                hits.append({"file": str(p), "line": i, "pattern": "data-menu(var-array)",
                             "text": f"menu-ish variable assigned an array: {l.strip()[:90]}"})
    return hits


# eval-period target-leakage signals in a TRAIN script (which legally reads only
# TRAIN-period obs). References to the held answer key or the eval window are suspect.
_EVAL_LEAK_PATTERNS = [
    r"obs_eval", r"answer[_-]?key", r"track0_forcing_only_obs_eval",
    r"1989-10", r"\beval[_-]?(period|window|obs|start|end)\b",
]


def scan_train_for_eval_leakage(train_py, patterns=None) -> list:
    """Heuristically flag a train.py that references the held answer key or the eval
    window — a target-leakage channel (read eval obs in train.py, bake into model/)."""
    p = Path(train_py)
    if not p.exists():
        return []
    pats = [re.compile(x, re.I) for x in (patterns or _EVAL_LEAK_PATTERNS)]
    hits = []
    for i, line in enumerate(p.read_text(encoding="utf-8", errors="replace").splitlines(), 1):
        for pat in pats:
            if pat.search(line):
                hits.append({"file": str(p), "line": i, "pattern": pat.pattern, "text": line.strip()[:160]})
    return hits


# ============================ Firewall 3: NOVELTY =============================
ALLOWED_NOVELTY = {"reproduction", "incremental", "new-to-hydrology", "genuinely-novel", "unassessed"}


def validate_novelty(novelty_class: str, prior_art) -> tuple:
    errors = []
    if novelty_class not in ALLOWED_NOVELTY:
        errors.append(f"novelty_class '{novelty_class}' not in {sorted(ALLOWED_NOVELTY)}")
    prior_art = list(prior_art or [])
    if novelty_class != "unassessed" and not prior_art:
        errors.append("novelty claim requires prior_art citations (what was it checked against?)")
    return (not errors, errors)


# ============================ Firewall 1: RESULTS ============================
def _read_ledger(ledger_path) -> list:
    from . import ledger as L
    return L.read_rows(ledger_path)


def is_real_result(experiment_id: str, ledger_path) -> bool:
    return any(r.get("experiment_id") == experiment_id for r in _read_ledger(ledger_path))


def verify_number(experiment_id: str, claimed: float, ledger_path,
                  tol: float = 1e-6, column: str = "challenger_median") -> tuple:
    rows = [r for r in _read_ledger(ledger_path) if r.get("experiment_id") == experiment_id]
    if not rows:
        return (False, f"no ledger row for '{experiment_id}' — claim is not a real result")
    try:
        actual = float(rows[-1][column])
    except (KeyError, TypeError, ValueError):
        return (False, f"ledger row for '{experiment_id}' has no numeric {column}")
    if abs(actual - claimed) > tol:
        return (False, f"claimed {claimed} != ledger {actual} (delta {actual - claimed:+.6f})")
    return (True, f"matches ledger ({actual})")


def verify_chain(ledger_path) -> dict:
    """Recompute the ledger hash-chain; a row not written by append_attempt (e.g. a
    hand-appended fake winner) breaks it. NOTE: keyless — catches lazy/accidental
    tampering, not a deliberate in-environment forge (see module threat-model note)."""
    from . import ledger as L
    rows = L.read_rows(ledger_path)
    breaks, prev = [], L.GENESIS
    for i, r in enumerate(rows):
        content = {k: r.get(k, "") for k in L.CONTENT_FIELDS}
        expect = L.row_hash(prev, content)
        if (r.get("row_hash") or "") != expect:
            breaks.append({"index": i, "experiment_id": r.get("experiment_id"),
                           "expected": expect[:12], "found": (r.get("row_hash") or "")[:12]})
        prev = r.get("row_hash") or expect
    return {"ok": not breaks, "rows": len(rows), "breaks": breaks}


def verify_provenance(ledger_path, experiments_root=None) -> list:
    """Re-hash each predictions file vs its ledger sha. Falls back to the committed
    predictions.sha256 sidecar when the (git-ignored) csv is absent: 'sha-only' means
    the sidecar cross-checks the ledger sha (number not silently editable) though the
    full hydrograph can't be re-hashed; 'unlocatable' means no artifact at all."""
    from .io import sha256_file
    root = Path(experiments_root) if experiments_root else _HERE / "experiments"
    out = []
    for r in _read_ledger(ledger_path):
        eid = r.get("experiment_id")
        sha = r.get("predictions_sha") or ""
        sub = root / str(eid) / "submission"
        pred, side = sub / "predictions.csv", sub / "predictions.sha256"
        if pred.exists():
            out.append({"experiment_id": eid, "status": "ok" if sha256_file(pred) == sha else "MISMATCH"})
        elif side.exists():
            recorded = side.read_text(encoding="utf-8").strip()
            out.append({"experiment_id": eid, "status": "sha-only" if recorded == sha else "MISMATCH"})
        else:
            out.append({"experiment_id": eid, "status": "unlocatable"})
    return out


# ========================== Firewall 4: CONCLUSIONS ==========================
@dataclass
class Conclusion:
    statement: str
    kind: str                                  # 'evidence-based' | 'hypothesis'
    evidence: list = field(default_factory=list)
    settling_test: str = ""


def validate_conclusion(c: Conclusion, ledger_path, require_provenance: bool = False,
                        experiments_root=None) -> tuple:
    errors = []
    if c.kind not in {"evidence-based", "hypothesis"}:
        errors.append(f"kind '{c.kind}' must be 'evidence-based' or 'hypothesis'")
    if c.kind == "evidence-based":
        if not c.evidence:
            errors.append("evidence-based conclusion must cite >=1 ledger experiment_id")
        prov = {}
        if require_provenance:
            prov = {p["experiment_id"]: p["status"] for p in verify_provenance(ledger_path, experiments_root)}
        for eid in c.evidence:
            if not is_real_result(eid, ledger_path):
                errors.append(f"cited evidence '{eid}' is not a real ledger result")
            elif require_provenance and prov.get(eid) not in {"ok", "sha-only"}:
                errors.append(f"cited evidence '{eid}' fails provenance ({prov.get(eid)})")
    if c.kind == "hypothesis" and not c.settling_test.strip():
        errors.append("a hypothesis must name the runnable test that would settle it")
    return (not errors, errors)


def append_conclusion(path, c: Conclusion, ledger_path=None, **kw) -> None:
    if ledger_path is None:  # no silent bypass — conclusions are always gated
        raise ValueError("append_conclusion requires ledger_path: a conclusion must be validated against the ledger")
    ok, errors = validate_conclusion(c, ledger_path, **kw)
    if not ok:
        raise ValueError(f"invalid conclusion: {errors}")
    p = Path(path)
    p.parent.mkdir(parents=True, exist_ok=True)
    tail = ("; settle by: " + c.settling_test) if c.kind == "hypothesis" else ""
    line = (f"- [{c.kind}] {c.statement}  "
            f"(evidence: {', '.join(c.evidence) if c.evidence else '-'}{tail})\n")
    with p.open("a", encoding="utf-8") as f:
        f.write(line)


# ===================== Live gate: governance preflight ======================
def governance_preflight(exp_dir, constraints_path=None) -> dict:
    """Run before a candidate is scored (called by run_candidate). Enforces no active
    cages + a valid novelty.yaml, and surfaces train.py eval-leakage."""
    exp_dir = Path(exp_dir)
    errors, warnings = [], []

    cages = active_cages(load_constraints(constraints_path))
    if cages:
        errors.append(f"AUTONOMY: {len(cages)} active cage(s): {[c.get('id') for c in cages]}")

    novelty_class, prior_art = "unassessed", []
    nov = _read_yaml(exp_dir / "novelty.yaml")
    if nov is not None:
        novelty_class = nov.get("novelty_class", "unassessed")
        prior_art = list(nov.get("prior_art") or [])
        ok, errs = validate_novelty(novelty_class, prior_art)
        errors.extend(f"NOVELTY: {e}" for e in errs)
    else:
        warnings.append("NOVELTY: no novelty.yaml — recorded 'unassessed' (a contribution claim requires one)")

    train_leak = scan_train_for_eval_leakage(exp_dir / "train.py")
    if train_leak:
        warnings.append(f"LEAKAGE: train.py references eval-window/answer-key signals "
                        f"({len(train_leak)} hit) — possible target leakage, audit required")

    return {"ok": not errors, "novelty_class": novelty_class, "prior_art": prior_art,
            "warnings": warnings, "errors": errors, "train_leakage": train_leak}


def _legacy_unverifiable() -> set:
    f = _HERE / "registry" / "legacy_unverifiable.txt"
    if not f.exists():
        return set()
    return {l.strip() for l in f.read_text(encoding="utf-8").splitlines()
            if l.strip() and not l.startswith("#")}


# ============================== Self-audit CLI ===============================
def main(argv=None):
    import argparse
    ap = argparse.ArgumentParser(description="Framework governance self-audit (4 firewalls) — ENFORCING")
    ap.add_argument("--ledger", default=str(_HERE / "registry" / "portfolio_ledger.csv"))
    ap.add_argument("--scan", nargs="*", default=None, help="orchestration prompt files to scan for cages/menus")
    ap.add_argument("--experiments-root", default=None)
    a = ap.parse_args(argv)
    problems = []

    cons = load_constraints()
    cages = active_cages(cons)
    print(f"[autonomy] invariants: {len(invariants(cons))}; ACTIVE CAGES: {len(cages)} (healthy=0)")
    if cages:
        problems.append(f"{len(cages)} active cage(s)")

    committed = [p for p in _HERE.glob("*.py") if p.name != "governance.py"]
    targets = committed + [Path(p) for p in (a.scan or [])]
    cage_hits = scan_orchestration_for_cages(targets)
    menu_hits = scan_for_data_menus(targets)
    print(f"[autonomy] cage-signal hits: {len(cage_hits)}; data-menu hits: {len(menu_hits)}")
    for h in (cage_hits + menu_hits)[:25]:
        print(f"   {h['file']}:{h.get('line')}: {h.get('pattern')}  {h['text'][:110]}")
    if cage_hits:
        problems.append(f"{len(cage_hits)} cage-signal hit(s)")
    if menu_hits:
        problems.append(f"{len(menu_hits)} data-menu hit(s)")
    if not a.scan:
        print("[autonomy][WARN] orchestration prompts not scanned (pass via --scan); a clean committed-code scan is not an all-clear.")

    chain = verify_chain(a.ledger)
    print(f"[results] ledger rows: {chain['rows']}; chain breaks: {len(chain['breaks'])}")
    for b in chain["breaks"][:10]:
        print(f"   BREAK row {b['index']} ({b['experiment_id']}): found {b['found']} expected {b['expected']}")
    if not chain["ok"]:
        problems.append(f"{len(chain['breaks'])} ledger chain break(s)")

    legacy = _legacy_unverifiable()
    prov = {p["experiment_id"]: p["status"] for p in verify_provenance(a.ledger, a.experiments_root)}
    fails, warns = [], []
    for r in _read_ledger(a.ledger):
        if r.get("verdict") not in {"PASS", "HOLD"}:
            continue
        eid, st = r.get("experiment_id"), prov.get(r.get("experiment_id"))
        if st in {"ok", "sha-only"}:
            continue
        if st == "unlocatable" and eid in legacy:
            warns.append((eid, st))
        else:
            fails.append((eid, st))
    print(f"[results] provenance: {len(fails)} FAIL, {len(warns)} legacy-WARN (acknowledged)")
    for eid, st in fails[:10]:
        print(f"   FAIL {eid}: {st}")
    for eid, st in warns[:10]:
        print(f"   warn {eid}: {st} (legacy, in legacy_unverifiable.txt)")
    if fails:
        problems.append(f"{len(fails)} PASS/HOLD row(s) not provenance-verifiable")

    if problems:
        print("GOVERNANCE: FAIL — " + "; ".join(problems))
        sys.exit(1)
    print("GOVERNANCE: PASS — firewalls clean on scanned scope (legacy rows acknowledged).")
    return {"ok": True}


if __name__ == "__main__":
    main()
