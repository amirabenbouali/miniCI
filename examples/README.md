# Mini CI Examples

All examples are local and deterministic. Run them from the repository root with `bundle exec bin/mini-ci`.

| Example | Purpose | Expected exit code | Notes |
| --- | --- | --- | --- |
| `showcase-pipeline.yml` | Polished v1.0 demo with matrix jobs, hooks, retries, and artifacts | `0` | Recommended for screenshots and demos. |
| `failing-pipeline.yml` | Basic command failure and skipped follow-up work | `1` | Intentionally fails. |
| `timeout-pipeline.yml` | Command timeout handling | `1` | Intentionally times out. |
| `retry-pipeline.yml` | Retry that eventually passes | `0` | Uses `scripts/flaky_check.sh`. |
| `retry-failure-pipeline.yml` | Exhausted retries | `1` | Intentionally fails. |
| `hooks-success-pipeline.yml` | Setup and cleanup hooks | `0` | Demonstrates normal hook flow. |
| `hooks-main-failure-pipeline.yml` | Cleanup after main failure | `1` | Intentionally fails. |
| `hooks-cleanup-failure-pipeline.yml` | Cleanup failure reporting | `1` | Intentionally fails. |
| `conditions-success-pipeline.yml` | `when` and `if` success path | `0` | Includes skipped conditional items. |
| `conditions-failure-pipeline.yml` | Failure handlers and cleanup | `1` | Intentionally fails. |
| `conditions-never-pipeline.yml` | `when: never` | `0` | Verifies disabled items do not run. |
| `matrix-basic-pipeline.yml` | Deterministic matrix expansion | `0` | Sequential unless concurrency is configured. |
| `matrix-conditional-pipeline.yml` | Conditions with matrix values | `0` | Uses `MATRIX_` environment values. |
| `matrix-parallel-pipeline.yml` | Parallel matrix workers | `0` | Try `--concurrency 2`. |
| `matrix-partial-failure-pipeline.yml` | Fail-late matrix aggregation | `1` | Intentionally fails one job. |
| `matrix-parallel-failure-pipeline.yml` | Parallel fail-late behaviour | `1` | Intentionally fails one job. |
| `matrix-parallel-timeout-pipeline.yml` | Timeout inside a matrix job | `1` | Intentionally times out. |
| `artifacts-success-pipeline.yml` | Artifact collection and warnings | `0` | Writes local artifacts. |
| `artifacts-failure-pipeline.yml` | Failure-only artifact collection | `1` | Intentionally fails. |
| `artifacts-matrix-pipeline.yml` | Isolated matrix artifact directories | `0` | Safe for parallel runs. |
| `cache-basic-pipeline.yml` | Local cache save and restore | `0` | Creates local cache state. |
| `cache-fallback-pipeline.yml` | Fallback restore keys | `0` | Demonstrates prefix restore. |
| `cache-matrix-pipeline.yml` | Cache with matrix jobs | `0` | Uses per-key locks. |
| `cache-failure-pipeline.yml` | Cache behaviour after failures | `1` | Intentionally fails. |
| `plugin-basic-pipeline.yml` | Trusted local plugin item | `0` | Requires `--plugin examples/plugins/message_item.rb`; add other plugin files as needed. |
| `plugin-matrix-pipeline.yml` | Plugin items inside matrix jobs | `0` | Requires `--plugin examples/plugins/message_item.rb`. |
| `plugin-validation-failure-pipeline.yml` | Plugin validator failure | `2` | Requires `--plugin examples/plugins/policy_validator.rb`; intentionally invalid. |
| `plugin-callback-failure-pipeline.yml` | Runtime callback failure | `1` | Requires `--plugin examples/plugins/callback_failure.rb`; intentionally fails after commands pass. |

Generated runtime output belongs under ignored directories such as `.mini-ci/`, `tmp/`, `logs/`, `reports/`, and `matrix-artifacts/`.
