# Repository Instructions for Copilot

- Always follow `DEVELOPMENT_GUIDELINES.md` in the repo root.
- Never suggest `--no-verify` or disabling tests.
- Prefer incremental, compilable changes with tests (red→green→refactor).
- For complex tasks, require `IMPLEMENTATION_PLAN.md` with 3–5 stages and keep status updated.
- Stop after **5** unsuccessful attempts; summarize failures and propose **2–3** alternatives.
- Choose solutions by: **Simplicity > Testability > Readability (6 months) > Reversibility**.
- Fail fast with descriptive errors; never swallow exceptions.
- Each commit must compile, pass all tests, and include tests for new code.
## Language Preferences
- When replying in chat or code review comments, prefer **Chinese**.
- Project documentation（README、接口说明、设计文档等）默认使用 **中文**，如有面向国际读者的部分可另写英文版本。
- Code identifiers（变量名、函数名、类名等）统一使用 **英文**，必要时在注释中用中文解释含义。

