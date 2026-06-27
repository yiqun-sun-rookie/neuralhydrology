"""Tests for the cheap Level-1 forbidden-data-access scanner."""
from fair_benchmark.leakage import DEFAULT_FORBIDDEN, leakage_ok, scan_for_forbidden_access


def _write(d, name, text):
    p = d / name
    p.write_text(text, encoding="utf-8")
    return p


def test_clean_experiment_has_no_hits(tmp_path):
    _write(tmp_path, "model.py", "import pandas as pd\nx = pd.read_csv('maurer/01022500_forcing.txt')\n")
    assert scan_for_forbidden_access(tmp_path) == []
    assert leakage_ok(tmp_path) is True


def test_reading_observed_streamflow_is_flagged(tmp_path):
    _write(tmp_path, "loader.py",
           "q = pd.read_csv('data/camels_us/usgs_streamflow/01/01022500_streamflow_qc.txt')\n")
    hits = scan_for_forbidden_access(tmp_path)
    assert len(hits) >= 1
    assert leakage_ok(tmp_path) is False


def test_hit_reports_file_line_and_pattern(tmp_path):
    _write(tmp_path, "a.py", "ok = 1\nq = open('usgs_streamflow/x.txt')\n")
    hits = scan_for_forbidden_access(tmp_path)
    h = hits[0]
    assert h["file"].endswith("a.py")
    assert h["line"] == 2
    assert "usgs_streamflow" in h["pattern"]


def test_hydro_signature_attribute_is_flagged(tmp_path):
    # runoff_ratio etc. are computed FROM observed discharge -> target leakage
    _write(tmp_path, "feat.py", "feature = attrs['runoff_ratio']\n")
    assert leakage_ok(tmp_path) is False


def test_non_code_files_are_ignored(tmp_path):
    (tmp_path / "blob.bin").write_bytes(b"usgs_streamflow\x00\x01")
    assert scan_for_forbidden_access(tmp_path) == []


def test_custom_patterns_let_track1_allow_past_q(tmp_path):
    # Track 1 (past observed Q allowed) drops usgs_streamflow from forbidden
    _write(tmp_path, "ar.py", "q = pd.read_csv('usgs_streamflow/01022500.txt')\n")
    track1_patterns = [p for p in DEFAULT_FORBIDDEN if "usgs_streamflow" not in p]
    assert leakage_ok(tmp_path, patterns=track1_patterns) is True
