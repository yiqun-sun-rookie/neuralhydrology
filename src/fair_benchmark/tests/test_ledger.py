"""Tests for the append-only portfolio ledger (multiple-testing denominator)."""
from fair_benchmark.ledger import append_attempt, count_attempts, FIELDS


def _rec(eid, verdict="HOLD"):
    return {
        "timestamp": "2026-06-25T10:00:00", "experiment_id": eid,
        "track": "track0_forcing_only", "verdict": verdict,
        "median_paired_delta": 0.012, "wilcoxon_p": 0.03, "n": 425,
        "challenger_median": 0.771, "baseline_median": 0.759,
        "predictions_sha": "abc123",
    }


def test_creates_file_with_header_then_one_row(tmp_path):
    led = tmp_path / "portfolio_ledger.csv"
    append_attempt(led, _rec("001_x"))
    lines = led.read_text().strip().splitlines()
    assert lines[0] == ",".join(FIELDS)
    assert len(lines) == 2  # header + 1 row


def test_append_is_additive_header_written_once(tmp_path):
    led = tmp_path / "portfolio_ledger.csv"
    append_attempt(led, _rec("001_x"))
    append_attempt(led, _rec("002_y"))
    append_attempt(led, _rec("003_z"))
    lines = led.read_text().strip().splitlines()
    assert lines.count(",".join(FIELDS)) == 1
    assert len(lines) == 4  # header + 3 rows


def test_count_attempts_counts_data_rows(tmp_path):
    led = tmp_path / "portfolio_ledger.csv"
    assert count_attempts(led) == 0  # missing file -> 0
    append_attempt(led, _rec("001_x"))
    append_attempt(led, _rec("002_y"))
    assert count_attempts(led) == 2


def test_earlier_rows_preserved(tmp_path):
    led = tmp_path / "portfolio_ledger.csv"
    append_attempt(led, _rec("001_first"))
    append_attempt(led, _rec("002_second"))
    text = led.read_text()
    assert "001_first" in text and "002_second" in text
