# Changelog

## Unreleased

- Fixed crashes running pipelines (especially matrix jobs) outside a UTF-8 locale, where non-ASCII output such as the `✓`/`✗` status symbols or unicode job and pipeline names could raise internal errors.
- Fixed run history, cache metadata, and dashboard views failing to read back records containing non-ASCII content under the same conditions.
- Fixed YAML validation error handling breaking entirely on Ruby versions whose Psych library doesn't define `Psych::AliasesNotEnabled`.
- Fixed two dead branches with no observable effect in the CLI and dashboard.
- Fixed CI failing on Ruby 3.1/3.2 due to incompatible transitive dependency and Bundler versions.
- Added RuboCop static analysis, wired into `rake` and CI, and a CI check that runs the test suite under a non-UTF-8 locale.

## 1.0.0

Release date: pending

- Stable YAML pipeline runner with `before_all`, `steps`, and `after_all`.
- Pipeline and item-level environment variables.
- Timeouts, retries, retry delays, and conditional execution.
- Matrix builds with deterministic expansion and controlled parallel workers.
- Local artifact collection with manifests and matrix job isolation.
- Local dependency cache with exact and fallback restore keys.
- Trusted local Ruby plugin API version 1.
- Run history with `run.json`, `events.jsonl`, and `output.log`.
- Local Sinatra dashboard for run history, output, artifacts, and dashboard-launched runs.
- CLI commands for `run`, `validate`, `list`, `cache`, `plugins`, `dashboard`, `version`, and `help`.
- Gem packaging, release documentation, and GitHub Actions CI.
