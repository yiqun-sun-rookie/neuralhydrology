"""Legacy script redirect for the archived full-comparison workflow."""

LEGACY_MESSAGE = (
    "This legacy comparison script was archived under src/xaj_global_pilot/archive_legacy/. "
    "Use src.xaj_global_pilot.scripts.run_conceptual_screening for the active "
    "CAMELS-US conceptual benchmark workflow."
)


def main() -> int:
    raise SystemExit(LEGACY_MESSAGE)


if __name__ == "__main__":
    main()
