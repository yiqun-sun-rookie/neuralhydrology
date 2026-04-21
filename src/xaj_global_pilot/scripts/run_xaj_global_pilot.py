"""Legacy CLI redirect for the archived Caravan-oriented pilot workflow."""

LEGACY_MESSAGE = (
    "This legacy CLI was archived under src/xaj_global_pilot/archive_legacy/. "
    "Use src.xaj_global_pilot.scripts.run_conceptual_screening for the active "
    "CAMELS-US conceptual benchmark workflow."
)


def main(argv=None) -> int:
    raise SystemExit(LEGACY_MESSAGE)


if __name__ == "__main__":
    main()
