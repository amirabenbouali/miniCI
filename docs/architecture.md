# Mini CI Architecture

Mini CI is intentionally small and local. The CLI wires together objects with narrow responsibilities.

## Execution Flow

```text
CLI
-> configuration loader
-> validation
-> plugin registry freeze
-> matrix expansion
-> worker execution
-> item lifecycle
-> command execution
-> artifacts and cache
-> result aggregation
-> reporting
-> persistence
-> exit code
```

## Components

- `MiniCi::CLI` parses commands, handles known errors, wires dependencies, and returns stable exit codes.
- `MiniCi::ConfigLoader` safely reads YAML, validates schema, runs plugin validators, and builds model objects.
- `MiniCi::Step` represents one command item or plugin item.
- `MiniCi::Pipeline` executes setup hooks, main steps, cleanup hooks, retries, conditions, artifacts, cache, and plugin item callbacks for one job.
- `MiniCi::CommandRunner` executes shell commands, captures exit status, handles timeout process groups, and reaps child processes.
- `MiniCi::MatrixExpander` expands deterministic matrix combinations.
- `MiniCi::MatrixRunner` schedules matrix jobs with a bounded worker pool and aggregates results.
- `MiniCi::Reporter` prints human-readable terminal output.
- `MiniCi::ArtifactCollector` and `MiniCi::ArtifactRunStore` resolve and store artifact files.
- `MiniCi::CacheStore` restores and saves local cache entries atomically.
- `MiniCi::Plugin` owns the trusted local plugin registry and plugin API version 1.
- `MiniCi::RunRepository` persists local run history.
- `MiniCi::Dashboard::App` exposes the local Sinatra dashboard.

## Process and Thread Model

Non-matrix pipelines run in the main CLI process. Matrix pipelines use a bounded set of Ruby worker threads. Each matrix job has its own pipeline instance, reporter buffer, result state, and artifact directory.

Commands run through the system shell in a child process group. Timeout handling terminates the owned process group and waits for it to exit.

## Stability

Stable in v1.0:

- command names;
- documented CLI options;
- exit codes;
- core YAML fields;
- result statuses;
- plugin API version 1.

Internal in v1.0:

- Ruby class constructors;
- dashboard JSON event payload details;
- file layout inside `.mini-ci/runs` beyond documented filenames.
