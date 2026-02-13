# Repository Instructions for Copilot

- Always follow `DEVELOPMENT_GUIDELINES.md` in the repo root.
- Never suggest `--no-verify` or disabling tests.
- Prefer incremental, compilable changes with tests (red→green→refactor).
- For complex tasks, require `IMPLEMENTATION_PLAN.md` with 3–5 stages and keep status updated.
- Stop after **5** unsuccessful attempts; summarize failures and propose **2–3** alternatives.
- Choose solutions by: **Simplicity > Testability > Readability (6 months) > Reversibility**.
- Fail fast with descriptive errors; never swallow exceptions.
- Each commit must compile, pass all tests, and include tests for new code.
