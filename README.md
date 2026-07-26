# Mini CI

Mini CI is a lightweight local CI/CD pipeline runner written primarily in Ruby. It loads pipeline steps from a YAML configuration file, runs shell commands one after another on your local machine, records step durations, and prints a final execution summary.

## Current Milestone

Mini CI v0.3 supports:

- loading pipeline steps from `pipeline.yml`;
- loading a custom pipeline configuration path;
- validating pipeline configuration with clear error messages;
- running shell commands sequentially;
- recording each executed step result;
- printing each step duration;
- printing a final pipeline summary;
- stopping after the first failed command;
- returning a non-zero application exit status when the pipeline fails.

It does not yet support retries, parallel execution, timeouts, environment variables, Docker, deployment logic, a web frontend, a database, or external APIs.

## Requirements

- Ruby
- Bundler

## Installation

Install the project dependencies:

```bash
bundle install
```

## Running Tests

Run the RSpec test suite:

```bash
bundle exec rspec
```

You can also run the default Rake task:

```bash
bundle exec rake
```

## Pipeline Configuration

Mini CI looks for `pipeline.yml` in the current working directory by default.

### Format

A pipeline configuration file contains a pipeline name and an ordered list of steps. Each step has a display name and a shell command to run:

```yaml
name: Mini CI Example

steps:
  - name: Check Ruby version
    run: ruby --version

  - name: Print message
    run: echo "Running checks"

  - name: Run Bash script
    run: bash scripts/example_check.sh
```

### Custom Configuration Path

You can pass an optional file path to load a different configuration:

```bash
bundle exec bin/mini-ci custom-pipeline.yml
```

The path is resolved relative to the current working directory.

### Validation Rules

Mini CI validates the configuration before running any commands. It raises clear errors for:

- a missing configuration file;
- invalid YAML syntax;
- a top-level configuration that is not a mapping/object;
- a missing `steps` key;
- a `steps` value that is not an array;
- an empty `steps` array;
- a step that is not a mapping/object;
- a step missing `name`;
- a step missing `run`;
- a blank step name;
- a blank run command.

If the `name` field is omitted, Mini CI uses the default pipeline name `Mini CI`.

YAML is loaded safely. Arbitrary Ruby objects and YAML aliases are not permitted.

### Referencing Bash Scripts

Steps run shell commands directly. To run a Bash script, reference it in the `run` field:

```yaml
- name: Run Bash script
  run: bash scripts/example_check.sh
```

Make the script executable before running the pipeline:

```bash
chmod +x scripts/example_check.sh
```

Example script:

```bash
#!/usr/bin/env bash
set -euo pipefail

echo "Example check completed"
```

## Running The Example Pipeline

Run the example pipeline from the project root:

```bash
bundle exec bin/mini-ci
```

When all steps pass, Mini CI prints output similar to:

```text
Mini CI — Mini CI Example

[1/3] Check Ruby version
ruby 3.3.0
✓ Passed in 0.08s

[2/3] Print message
Running checks
✓ Passed in 0.01s

[3/3] Run Bash script
Example check completed
✓ Passed in 0.04s

Pipeline summary

Status: PASSED
Steps: 3 passed, 0 failed, 3 total
Duration: 0.13s
```

Inspect the process exit status:

```bash
echo $?
```

A successful pipeline exits with status `0`.

## Failing Example Pipeline

A second example demonstrates failure and skipped steps:

```bash
bundle exec bin/mini-ci examples/failing-pipeline.yml
```

Expected output is similar to:

```text
Mini CI — Failing Example

[1/3] Successful step
Step one passed
✓ Passed in 0.01s

[2/3] Failing step
Test failure
✗ Failed with exit code 1 in 1.42s

Pipeline summary

Status: FAILED
Steps: 1 passed, 1 failed, 3 configured
Skipped: 1
Duration: 1.50s
```

Inspect the exit status:

```bash
echo $?
```

This pipeline exits with a non-zero status because one step failed.

## Step Durations

Mini CI measures elapsed time with Ruby's monotonic clock:

```ruby
Process.clock_gettime(Process::CLOCK_MONOTONIC)
```

Durations are shown with two decimal places, such as `0.08s`, `1.42s`, or `65.30s`. This keeps elapsed-time measurement independent from wall-clock changes.

## Passed, Failed, and Skipped Counts

The final summary reports:

- `passed` — executed steps whose command exited with status `0`;
- `failed` — executed steps whose command exited with a non-zero status;
- `skipped` — configured steps that did not run because an earlier step failed.

When all configured steps run, the summary reports the configured count as `total`. When the pipeline stops early, it reports the configured count and includes a `Skipped:` line.

## Exit Status

Mini CI uses process exit codes to report pipeline success or failure:

- exit code `0` — all configured steps completed successfully;
- non-zero exit code — a step failed or the configuration could not be loaded.

Configuration errors are printed to standard error:

```text
Mini CI error: pipeline.yml was not found
```

## Current Limitations

- Steps run one at a time.
- A pipeline stops at the first failed command.
- No CLI subcommands yet for `run`, `validate`, or `list`.
- No environment variable management, retries, parallel execution, timeouts, Docker, deployment, frontend, or database support.

## Next Milestone

The next planned milestone adds CLI subcommands for `run`, `validate`, and `list`.
