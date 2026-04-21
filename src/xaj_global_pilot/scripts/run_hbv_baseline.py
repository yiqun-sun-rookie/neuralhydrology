"""Legacy script redirect for the archived HBV baseline rerun workflow."""

LEGACY_MESSAGE = (
    "This legacy HBV baseline script was archived under src/xaj_global_pilot/archive_legacy/. "
    "Use src.xaj_global_pilot.scripts.run_conceptual_screening for the active "
    "CAMELS-US conceptual benchmark workflow."
)


def main() -> int:
    raise SystemExit(LEGACY_MESSAGE)


if __name__ == "__main__":
    main()
