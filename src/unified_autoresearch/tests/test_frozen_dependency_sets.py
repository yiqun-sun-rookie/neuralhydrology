"""A candidate may only declare a dependency set that was frozen in advance.

The cluster cannot build an environment matching the original pins: its conda is broken and
its glibc is too old for wheels of those versions. So a second set is frozen for the cluster
environment. It is hardcoded, not read from whatever happens to be installed -- deriving the
declaration from the environment would turn the check into an identity that always passes.
"""

import json

import pytest

from unified_autoresearch.candidates.catalog import (
    FROZEN_DEPENDENCY_SETS,
    PINNED_DEPENDENCIES,
    PINNED_DEPENDENCIES_CLUSTER,
)


def test_both_frozen_sets_are_hardcoded_literals_and_distinct():
    assert PINNED_DEPENDENCIES == ("numpy==1.26.4", "pandas==2.3.3", "pyarrow==22.0.0")
    assert PINNED_DEPENDENCIES_CLUSTER == ("numpy==1.26.4", "pandas==2.2.3", "pyarrow==17.0.0")
    assert set(FROZEN_DEPENDENCY_SETS) == {PINNED_DEPENDENCIES, PINNED_DEPENDENCIES_CLUSTER}
    assert PINNED_DEPENDENCIES != PINNED_DEPENDENCIES_CLUSTER


@pytest.mark.parametrize("dependencies", [PINNED_DEPENDENCIES, PINNED_DEPENDENCIES_CLUSTER])
def test_a_candidate_may_declare_either_frozen_set(tmp_path, dependencies):
    from unified_autoresearch.candidates.catalog import materialize_hbv_lite_candidate

    materialized = materialize_hbv_lite_candidate(
        output_root=tmp_path / f"candidate_{len(dependencies)}_{hash(dependencies) & 0xFFFF}",
        dependencies=dependencies,
    )

    descriptor = json.loads(materialized.descriptor_path.read_text(encoding="utf-8"))
    assert tuple(descriptor["dependencies"]) == dependencies


def test_the_original_pins_remain_the_default(tmp_path):
    from unified_autoresearch.candidates.catalog import materialize_hbv_lite_candidate

    materialized = materialize_hbv_lite_candidate(output_root=tmp_path / "default")

    descriptor = json.loads(materialized.descriptor_path.read_text(encoding="utf-8"))
    assert tuple(descriptor["dependencies"]) == PINNED_DEPENDENCIES


@pytest.mark.parametrize(
    "dependencies",
    [
        ("numpy==1.26.4", "pandas==2.3.3"),
        ("numpy==1.26.4", "pandas==2.3.3", "pyarrow==22.0.0", "scipy==1.11.0"),
        ("numpy==2.3.3", "pandas==2.3.2", "pyarrow==20.0.0"),  # what the cluster ships; never frozen
        (),
    ],
)
def test_a_dependency_set_that_was_never_frozen_is_refused(tmp_path, dependencies):
    from unified_autoresearch.candidates.catalog import materialize_hbv_lite_candidate

    with pytest.raises(ValueError, match="dependency set is not one of the frozen declarations"):
        materialize_hbv_lite_candidate(output_root=tmp_path / "rejected", dependencies=dependencies)
    assert not (tmp_path / "rejected").exists()


def test_the_declaration_is_not_taken_from_the_running_environment(tmp_path):
    """Whatever is installed here must not influence what the candidate declares."""
    import importlib.metadata as metadata

    from unified_autoresearch.candidates.catalog import materialize_hbv_lite_candidate

    installed = tuple(f"{name}=={metadata.version(name)}" for name in ("numpy", "pandas", "pyarrow"))
    materialized = materialize_hbv_lite_candidate(output_root=tmp_path / "declared")
    descriptor = json.loads(materialized.descriptor_path.read_text(encoding="utf-8"))

    assert tuple(descriptor["dependencies"]) == PINNED_DEPENDENCIES
    if installed not in FROZEN_DEPENDENCY_SETS:
        assert tuple(descriptor["dependencies"]) != installed


def test_reference_candidates_keep_the_original_pins(tmp_path):
    from unified_autoresearch.candidates.catalog import materialize_reference_candidate

    materialized = materialize_reference_candidate(
        category="conceptual_rainfall_runoff", output_root=tmp_path / "reference"
    )

    descriptor = json.loads(materialized.descriptor_path.read_text(encoding="utf-8"))
    assert tuple(descriptor["dependencies"]) == PINNED_DEPENDENCIES


@pytest.mark.parametrize("dependencies", [PINNED_DEPENDENCIES, PINNED_DEPENDENCIES_CLUSTER])
def test_reference_candidates_may_declare_either_frozen_set(tmp_path, dependencies):
    from unified_autoresearch.candidates.catalog import materialize_reference_candidate

    materialized = materialize_reference_candidate(
        category="custom_python",
        output_root=tmp_path / f"reference_{hash(dependencies) & 0xFFFF}",
        dependencies=dependencies,
    )

    descriptor = json.loads(materialized.descriptor_path.read_text(encoding="utf-8"))
    assert tuple(descriptor["dependencies"]) == dependencies


def test_reference_candidate_rejects_a_dependency_set_that_was_never_frozen(tmp_path):
    from unified_autoresearch.candidates.catalog import materialize_reference_candidate

    with pytest.raises(ValueError, match="dependency set is not one of the frozen declarations"):
        materialize_reference_candidate(
            category="custom_python",
            output_root=tmp_path / "rejected-reference",
            dependencies=("numpy==1.26.4",),
        )
    assert not (tmp_path / "rejected-reference").exists()


def test_single_candidate_resolver_passes_the_selected_set_to_reference_candidates(tmp_path):
    from unified_autoresearch.scripts.run_single_candidate import _resolve

    materialized = _resolve("custom_python", PINNED_DEPENDENCIES_CLUSTER)(
        output_root=tmp_path / "resolved-reference"
    )

    descriptor = json.loads(materialized.descriptor_path.read_text(encoding="utf-8"))
    assert tuple(descriptor["dependencies"]) == PINNED_DEPENDENCIES_CLUSTER
