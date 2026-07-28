# Changelog

## Unreleased

- Release preparation changes after v1.0.0 will be listed here.

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
