"""Unit tests for the independent safety logic of the supervised-loop verifier.

These pin the milestone-four honesty fix: the run gate must be built only from checks the
verifier computes from raw evidence, never from a loop's self-declared safety flags.
"""

from unified_autoresearch.scripts.verify_supervised_real_loops import (
    forbidden_access_count,
    milestone_gate_inputs,
)


def test_forbidden_access_count_counts_only_deny_decisions():
    records = [
        {"decision": "allow", "path": "a"},
        {"decision": "allow", "path": "b"},
        {"decision": "deny", "reason": "sealed region"},
        {"event": "bootstrap", "recorder": "parent"},  # no decision key at all
        {"decision": "deny", "reason": "outside read root"},
    ]
    assert forbidden_access_count(records) == 2
    assert forbidden_access_count([]) == 0
    assert forbidden_access_count([{"decision": "allow"}]) == 0


def test_milestone_gate_inputs_exclude_self_declared_safety_flags():
    """A loop's self-declared safety flags must never be an input to the run gate; the gate is
    built only from independently-verified booleans."""
    clean_loop = {
        "five_gates_all_pass": True,
        "supervised_run_count": 16,
        "controlled_stop_count": 0,
        "independent_forbidden_access_count": 0,
        # A self-declaration claiming everything is fine -- must not influence the gate.
        "declared_safety_flags_all_false": True,
    }
    inputs = milestone_gate_inputs(clean_loop)

    assert "declared_safety_flags_all_false" not in inputs
    assert set(inputs) == {
        "five_gates_all_pass",
        "fully_supervised",
        "no_controlled_stop",
        "forbidden_access_independently_zero",
    }
    assert all(inputs.values())


def test_milestone_gate_fails_on_independently_recounted_forbidden_access():
    """Even when the loop still self-declares itself clean, a real forbidden access recounted
    from raw logs must fail the gate inputs."""
    tampered_loop = {
        "five_gates_all_pass": True,
        "supervised_run_count": 16,
        "controlled_stop_count": 0,
        "independent_forbidden_access_count": 1,
        "declared_safety_flags_all_false": True,
    }
    inputs = milestone_gate_inputs(tampered_loop)

    assert inputs["forbidden_access_independently_zero"] is False
    assert not all(inputs.values())


def test_milestone_gate_inputs_flag_missing_supervision_and_stops():
    partial_loop = {
        "five_gates_all_pass": True,
        "supervised_run_count": 15,
        "controlled_stop_count": 1,
        "independent_forbidden_access_count": 0,
        "declared_safety_flags_all_false": True,
    }
    inputs = milestone_gate_inputs(partial_loop)

    assert inputs["fully_supervised"] is False
    assert inputs["no_controlled_stop"] is False
