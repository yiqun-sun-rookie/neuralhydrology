"""Append-only, tamper-evident portfolio ledger.

Every gated attempt (PASS/HOLD/REJECT alike) is recorded here. This is the
multiplicity denominator: when N methods are tried against a fixed test set,
~alpha*N clear the bar by chance, so a reader must be able to recover N to
correct for it. Winners-only leaderboards hide N; this ledger does not.

Tamper-evidence (Results firewall): each row carries a `row_hash` =
sha256(prev_row_hash | row content). Rows are written ONLY by append_attempt
(called only by score.score_submission). A row inserted/edited by hand — e.g. a
fabricated PASS — breaks the chain, which governance.verify_chain detects. This
is a hash CHAIN, not a signature: proportionate to the real threat (our own
agents/hands taking shortcuts), not a cryptographic adversary. Append-only by
contract — never rewrite or delete rows (migrate_chain is the sole, one-time
exception used to introduce the chain over already-recorded honest rows).
"""
import csv
import hashlib
from pathlib import Path

CONTENT_FIELDS = [
    "timestamp", "experiment_id", "track", "verdict",
    "median_paired_delta", "wilcoxon_p", "n",
    "challenger_median", "baseline_median", "predictions_sha",
]
FIELDS = CONTENT_FIELDS + ["row_hash"]
GENESIS = "GENESIS"


def row_hash(prev_hash: str, record: dict) -> str:
    payload = (prev_hash or GENESIS) + "|" + "|".join(str(record.get(k, "")) for k in CONTENT_FIELDS)
    return hashlib.sha256(payload.encode("utf-8")).hexdigest()


def read_rows(ledger_path) -> list:
    path = Path(ledger_path)
    if not path.exists():
        return []
    with path.open(newline="", encoding="utf-8") as f:
        return list(csv.DictReader(f))


def append_attempt(ledger_path, record: dict) -> None:
    path = Path(ledger_path)
    path.parent.mkdir(parents=True, exist_ok=True)
    rows = read_rows(path)
    prev = rows[-1].get("row_hash", GENESIS) if rows else GENESIS
    row = {k: record.get(k, "") for k in CONTENT_FIELDS}
    row["row_hash"] = row_hash(prev, row)
    write_header = not path.exists()
    with path.open("a", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=FIELDS, extrasaction="ignore")
        if write_header:
            writer.writeheader()
        writer.writerow(row)


def count_attempts(ledger_path) -> int:
    return len(read_rows(ledger_path))


def migrate_chain(ledger_path) -> int:
    """One-time: re-stamp an existing unchained ledger with a valid hash chain.
    Use ONLY to introduce the chain over already-recorded honest rows."""
    path = Path(ledger_path)
    rows = read_rows(path)
    if not rows:
        return 0
    prev = GENESIS
    for r in rows:
        content = {k: r.get(k, "") for k in CONTENT_FIELDS}
        r["row_hash"] = row_hash(prev, content)
        prev = r["row_hash"]
    with path.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=FIELDS, extrasaction="ignore")
        writer.writeheader()
        for r in rows:
            writer.writerow({k: r.get(k, "") for k in FIELDS})
    return len(rows)
