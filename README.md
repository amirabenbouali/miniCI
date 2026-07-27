# Mini CI

Mini CI is a lightweight local CI/CD pipeline runner written primarily in Ruby. It loads pipeline steps from a YAML configuration file, runs shell commands one after another on your local machine, records step durations, and prints a final execution summary.

## Current Milestone

Mini CI v0.6 supports:

- loading pipeline steps from `pipeline.yml`;
- loading a custom pipeline configuration path;
- a structured CLI with `run`, `validate`, `list`, `version`, and `help` commands;
- pipeline-level and step-level environment variables;
- step-level environment variables overriding global values;
- optional per-step command timeouts;
- validating pipeline configuration with clear error messages;
- running shell commands sequentially;
- recording each executed step result;
- printing each step duration;
- printing a final pipeline summary;
- stopping after the first failed command;
- returning a non-zero application exit status when the pipeline fails.

It does not yet support retries, parallel execution, secrets management, `.env` files, Docker, deployment logic, a web frontend, a database, or external APIs.

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

## CLI Usage

Mini CI uses subcommands:

```bash
bundle exec bin/mini-ci help
bundle exec bin/mini-ci version
bundle exec bin/mini-ci validate
bundle exec bin/mini-ci list
bundle exec bin/mini-ci run
```

Running without a command displays help and exits successfully:

```bash
bundle exec bin/mini-ci
```

### Command Reference

| Command | Description | Example |
| --- | --- | --- |
| `run [FILE]` | Execute a pipeline | `bundle exec bin/mini-ci run` |
| `validate [FILE]` | Validate a pipeline configuration without running commands | `bundle exec bin/mini-ci validate` |
| `list [FILE]` | Display configured pipeline steps without running commands | `bundle exec bin/mini-ci list` |
| `version` | Display the installed version | `bundle exec bin/mini-ci version` |
| `help` | Display usage information | `bundle exec bin/mini-ci help` |

`FILE` defaults to `pipeline.yml`.

## Pipeline Configuration

Mini CI looks for `pipeline.yml` in the current working directory by default.

### Format

A pipeline configuration file contains a pipeline name, optional global environment variables, and an ordered list of steps. Each step has a display name, a shell command to run, optional step-specific environment variables, and an optional timeout in seconds:

```yaml
name: Environment Example

env:
  APP_ENV: test
  LOG_LEVEL: info
  SHARED_VALUE: global

steps:
  - name: Print global variables
    run: bash scripts/print_env.sh

  - name: Override one variable
    run: ruby -e 'puts ENV.fetch("SHARED_VALUE")'
    timeout: 5
    env:
      SHARED_VALUE: step
      FEATURE_FLAG: enabled
```

### Custom Configuration Path

You can pass an optional file path to load a different configuration:

```bash
bundle exec bin/mini-ci run custom-pipeline.yml
bundle exec bin/mini-ci validate custom-pipeline.yml
bundle exec bin/mini-ci list custom-pipeline.yml
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
- a blank run command;
- `env` that is not a mapping/object;
- blank environment variable names;
- non-string environment variable names;
- environment variable names containing `=`, null bytes, spaces, hyphens, or other invalid characters;
- environment variable values that are arrays or mappings;
- null environment variable values;
- environment variable values containing null bytes;
- `timeout` values that are strings, booleans, null, arrays, or mappings;
- `timeout` values that are zero, negative, or non-finite.

If the `name` field is omitted, Mini CI uses the default pipeline name `Mini CI`.

YAML is loaded safely. Arbitrary Ruby objects and YAML aliases are not permitted.

### Environment Variables

Global variables apply to every step:

```yaml
env:
  APP_ENV: test
  DEBUG: "false"
```

Step-level variables apply only to that step:

```yaml
steps:
  - name: Run tests
    run: bundle exec rspec
    env:
      COVERAGE: "true"
```

Mini CI applies environment values in this order:

```text
existing process environment
pipeline-level environment variables
step-level environment variables
```

Later values override earlier values. For example, if your shell has `APP_ENV=development`, the pipeline has `APP_ENV=test`, and a step has `APP_ENV=integration`, that step receives `APP_ENV=integration`.

Simple YAML scalar values are converted to strings before commands run:

```yaml
env:
  PORT: 3000
  DEBUG: false
  EMPTY_VALUE: ""
```

Commands receive those values as strings: `PORT="3000"`, `DEBUG="false"`, and `EMPTY_VALUE=""`.

Access variables in Ruby:

```ruby
ENV.fetch("APP_ENV")
```

Access variables in Bash:

```bash
echo "$APP_ENV"
```

Do not store production secrets in pipeline files yet. Pipeline files may be committed to Git, the `list` command displays configured values, and secure secret masking has not been implemented.

### Step Timeouts

Each step can define a maximum execution time in seconds:

```yaml
steps:
  - name: Fast check
    run: ruby -e 'puts "done"'
    timeout: 5

  - name: Decimal timeout
    run: ruby -e 'sleep 1'
    timeout: 2.5
```

When a step exceeds its timeout, Mini CI terminates the command, marks the step as failed, stops the pipeline, and reports skipped steps. Timeout values must be positive numbers; strings such as `"10"` are intentionally rejected.

Mini CI starts each command in its own process group. On timeout, it sends `TERM` to the process group, waits briefly for graceful shutdown, then sends `KILL` if the command or its child processes are still running. This keeps commands such as `bash -c 'sleep 30 & wait'` from leaving child processes behind.

The current timeout implementation targets Unix-like environments such as Linux and macOS.

### Referencing Bash Scripts

Steps run shell commands directly. To run a Bash script, reference it in the `run` field:

```yaml
- name: Run Bash script
  run: bash scripts/print_env.sh
```

Make the script executable before running the pipeline:

```bash
chmod +x scripts/print_env.sh
```

Example script:

```bash
#!/usr/bin/env bash
set -euo pipefail

printf 'APP_ENV=%s\n' "${APP_ENV:-missing}"
printf 'LOG_LEVEL=%s\n' "${LOG_LEVEL:-missing}"
printf 'SHARED_VALUE=%s\n' "${SHARED_VALUE:-missing}"
```

## Validate A Pipeline

Validate the default configuration without running any commands:

```bash
bundle exec bin/mini-ci validate
```

Example output:

```text
Pipeline configuration is valid.

Name: Environment Example
Steps: 2
Environment variables: 3
File: pipeline.yml
```

Validate a custom file:

```bash
bundle exec bin/mini-ci validate examples/failing-pipeline.yml
```

## List Pipeline Steps

List the default pipeline steps without running them:

```bash
bundle exec bin/mini-ci list
```

Example output:

```text
Environment Example

Global environment:
  APP_ENV=test
  LOG_LEVEL=info
  SHARED_VALUE=global

1. Print global variables
   bash scripts/print_env.sh

2. Override one variable
   ruby -e 'puts ENV.fetch("SHARED_VALUE")'
   Timeout: 5s
   Environment:
     SHARED_VALUE=step
     FEATURE_FLAG=enabled
```

## Run The Example Pipeline

Run the example pipeline from the project root:

```bash
bundle exec bin/mini-ci run
```

When all steps pass, Mini CI prints output similar to:

```text
Mini CI — Environment Example

[1/2] Print global variables
APP_ENV=test
LOG_LEVEL=info
SHARED_VALUE=global
✓ Passed in 0.08s

[2/2] Override one variable
step
✓ Passed in 0.01s

Pipeline summary

Status: PASSED
Steps: 2 passed, 0 failed, 2 total
Duration: 0.09s
```

Inspect the process exit status:

```bash
echo $?
```

A successful pipeline exits with status `0`.

## Failing Example Pipeline

A second example demonstrates failure and skipped steps:

```bash
bundle exec bin/mini-ci run examples/failing-pipeline.yml
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

## Timeout Example Pipeline

Run the timeout example:

```bash
bundle exec bin/mini-ci run examples/timeout-pipeline.yml
echo $?
```

Expected output is similar to:

```text
Mini CI — Timeout Example

[1/3] Quick step
quick step completed
✓ Passed in 0.08s

[2/3] Slow step
starting slow step
✗ Timed out after 1.00s

Pipeline summary

Status: FAILED
Steps: 1 passed, 1 failed, 3 configured
Skipped: 1
Duration: 1.10s
Failure: Slow step timed out
```

The timeout pipeline exits with status `1`.

## Version And Help

Show the installed version:

```bash
bundle exec bin/mini-ci version
```

Example output:

```text
Mini CI 0.6.0
```

Show help:

```bash
bundle exec bin/mini-ci help
bundle exec bin/mini-ci --help
bundle exec bin/mini-ci -h
```

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

- exit code `0` — the command completed successfully;
- exit code `1` — pipeline execution failed;
- exit code `2` — configuration or CLI usage error.

Configuration errors are printed to standard error:

```text
Mini CI error: pipeline.yml was not found
```

Unknown commands are also printed to standard error:

```text
Mini CI error: unknown command "deploy"

Run `mini-ci help` for usage information.
```

## Current Limitations

- Steps run one at a time.
- A pipeline stops at the first failed command.
- No secrets management or secret masking.
- No `.env` file support.
- Timeout process-group termination is currently intended for Unix-like systems.
- No retries, parallel execution, Docker, deployment, frontend, or database support.

## Next Milestone

The next planned milestone adds retries.
