# Examples Directory

`examples/` is for tutorial notebooks and sample configs only.

## Scope

- Keep educational notebooks and demonstration YAML files here.
- Do not place production experiment configs for active ideas here.
- Active idea configs/scripts must live under `src/<idea>/...`.

## Non-Dependency Rule

- Production scripts under `src/` must not require files from `examples/`.
- If a demo path is needed in code, use a placeholder path under `data/` and document it.
