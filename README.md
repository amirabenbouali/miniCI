# Mini CI

Mini CI is a lightweight local CI/CD pipeline runner written primarily in Ruby. It loads pipeline steps and hooks from a YAML configuration file, runs shell commands on your local machine, restores and saves local dependency caches, records durations, and prints a final execution summary.

## Current Milestone

Mini CI v0.14 supports:

- loading pipeline steps from `pipeline.yml`;
- loading a custom pipeline configuration path;
- a structured CLI with `run`, `validate`, `list`, `version`, and `help` commands;
- setup hooks with `before_all`;
- cleanup hooks with `after_all`;
- guaranteed cleanup after setup or main-step failures;
- conditional execution with `when` policies;
- environment-variable `if` conditions;
- structured skipped results and skipped counts;
- matrix builds with deterministic Cartesian-product expansion;
- parallel matrix job execution with a bounded worker pool;
- buffered per-job matrix output;
- fail-late matrix aggregate results;
- build artifact collection for steps and hooks;
- artifact manifests under each run directory;
- local filesystem dependency caching for steps and hooks;
- exact cache restores and fallback restore-key prefixes;
- SHA-256 checksum cache key expressions;
- environment and matrix cache key expressions;
- cache listing and clearing commands;
- trusted local Ruby plugins loaded from `.mini-ci/plugins/` or CLI paths;
- plugin metadata, API version checks, lifecycle callbacks, configuration validators, and custom pipeline item types;
- plugin result metadata in artifact manifests;
- pipeline-level and step-level environment variables;
- step-level environment variables overriding global values;
- optional per-step command timeouts;
- per-step retries with configurable retry delays;
- validating pipeline configuration with clear error messages;
- running shell commands sequentially;
- recording each executed step result;
- printing each step duration;
- printing a final pipeline summary;
- continuing to evaluate later configured items after failures;
- returning a non-zero application exit status when the pipeline fails.

It does not yet support a local dashboard, remote plugin marketplaces, automatic plugin installation, remote cache servers, remote artifact storage, cloud uploads, compression, cache eviction policies, secrets management, `.env` files, Docker, deployment logic, a web frontend, a database, or external APIs.

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
bundle exec bin/mini-ci cache list
bundle exec bin/mini-ci plugins validate
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
| `run [FILE] [--concurrency N] [--artifacts-dir DIR] [--cache-dir DIR] [--no-cache]` | Execute a pipeline | `bundle exec bin/mini-ci run examples/cache-basic-pipeline.yml --cache-dir tmp/cache` |
| `validate [FILE]` | Validate a pipeline configuration without running commands | `bundle exec bin/mini-ci validate` |
| `list [FILE]` | Display configured pipeline steps without running commands | `bundle exec bin/mini-ci list` |
| `cache list [--cache-dir DIR]` | Display saved cache entries | `bundle exec bin/mini-ci cache list` |
| `cache clear --yes [--cache-dir DIR]` | Clear saved cache entries | `bundle exec bin/mini-ci cache clear --yes` |
| `plugins list [--plugin FILE] [--plugin-dir DIR]` | Display loaded local plugins | `bundle exec bin/mini-ci plugins list --plugin examples/plugins/message_item.rb` |
| `plugins validate [--plugin FILE] [--plugin-dir DIR]` | Load plugins and validate metadata/registrations | `bundle exec bin/mini-ci plugins validate --plugin examples/plugins/message_item.rb` |
| `version` | Display the installed version | `bundle exec bin/mini-ci version` |
| `help` | Display usage information | `bundle exec bin/mini-ci help` |

`FILE` defaults to `pipeline.yml`.

## Pipeline Configuration

Mini CI looks for `pipeline.yml` in the current working directory by default.

### Format

A pipeline configuration file contains a pipeline name, optional global environment variables, optional hooks, and an ordered list of steps. Each step and hook has a display name, a shell command to run, optional item-specific environment variables, an optional timeout in seconds, optional retries, and an optional retry delay:

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

Matrix pipelines may also set top-level concurrency:

```yaml
name: Parallel Matrix Example
concurrency: 2

matrix:
  job:
    - alpha
    - beta

steps:
  - name: Parallel check
    run: bash scripts/matrix_parallel_check.sh
```

### Hooks

Hooks are reusable commands that run around the main pipeline:

```yaml
name: Hook Example

before_all:
  - name: Prepare workspace
    run: bash scripts/prepare_workspace.sh

steps:
  - name: Run tests
    run: bundle exec rspec

after_all:
  - name: Clean workspace
    run: bash scripts/cleanup_workspace.sh
```

Execution order is always:

```text
before_all hooks
main steps
after_all hooks
```

`before_all` and `after_all` are optional. Missing hook sections behave like empty arrays. Hooks support the same fields as normal steps:

```yaml
name: Prepare workspace
run: bash scripts/prepare_workspace.sh
env:
  SETUP_MODE: local
timeout: 5
retries: 1
retry_delay: 0.5
```

Failure behavior:

- If a `before_all` hook fails after retries, later setup hooks and main steps are still evaluated. Default `when: success` items skip, while `when: failure` and `when: always` items can run.
- If a main step fails after retries, later main steps are still evaluated. Default `when: success` items skip, while failure handlers and always-run items can continue.
- If an `after_all` hook fails, Mini CI keeps running the remaining cleanup hooks and marks the pipeline as failed.
- If normal work already failed, that remains the primary failure and cleanup failures are reported separately.
- If normal work passed but cleanup failed, the cleanup failure becomes the primary failure.

### Conditional Execution

Steps and hooks can include an optional `when` policy:

```yaml
when: success
when: failure
when: always
when: never
```

Defaults are phase-specific:

- normal `steps` default to `when: success`;
- `before_all` hooks default to `when: success`;
- `after_all` hooks default to `when: always` so cleanup remains guaranteed unless explicitly configured otherwise.

Policy meanings:

- `success` runs only when no previous executed item has failed;
- `failure` runs only after a previous executed item has failed;
- `always` runs regardless of earlier success or failure;
- `never` always skips the item.

A successful failure-handler does not reset pipeline failure state. Once an executed item fails, later `when: success` items skip unless the pipeline is a new run.

Items can also include an optional `if` expression:

```yaml
if: env.DEPLOY == "true"
if: env.APP_ENV != "production"
if: env.BRANCH == 'main'
```

The supported grammar is intentionally small:

```text
env.VARIABLE == "value"
env.VARIABLE != "value"
```

Single-quoted values are also supported. Logical operators, parentheses, shell expansion, method calls, regular expressions, numeric comparison, and nested expressions are not supported.

Condition environment precedence matches command execution:

```text
parent process environment
pipeline-level environment
step-level or hook-level environment
```

Missing variables behave as empty strings, so `env.MISSING == ""` is true and `env.MISSING != "production"` is also true.

When both `when` and `if` are present, both must pass. Mini CI evaluates `when` first; if it fails, the `if` expression is not evaluated for that item.

Conditions are parsed by Mini CI's small parser. They are not evaluated as Ruby, passed to `eval`, executed as shell code, or interpolated into commands.

### Matrix Builds

A pipeline can define a top-level `matrix` mapping. Mini CI creates one matrix job for every combination of matrix values:

```yaml
name: Ruby Matrix Example

matrix:
  ruby:
    - "3.2"
    - "3.3"

  database:
    - sqlite
    - postgres

steps:
  - name: Print matrix values
    run: ruby -e 'puts "ruby=#{ENV.fetch("MATRIX_RUBY")} database=#{ENV.fetch("MATRIX_DATABASE")}"'
```

This generates four jobs in deterministic Cartesian-product order:

```text
1. ruby=3.2, database=sqlite
2. ruby=3.2, database=postgres
3. ruby=3.3, database=sqlite
4. ruby=3.3, database=postgres
```

Mini CI preserves matrix key order from the YAML file and value order within each matrix array. Matrix jobs run through a fixed-size worker pool. Jobs may finish in any order, but the final summary always follows the deterministic expansion order.

Matrix values are exposed as environment variables by uppercasing the key and adding the `MATRIX_` prefix:

```text
ruby         -> MATRIX_RUBY
database     -> MATRIX_DATABASE
feature_flag -> MATRIX_FEATURE_FLAG
```

Scalar matrix values are converted to strings, so booleans and numbers become values such as `true`, `false`, and `1`.

Matrix environment precedence is:

```text
parent process environment
pipeline-level environment
matrix environment
step-level or hook-level environment
```

Step-level and hook-level variables may explicitly override matrix variables:

```yaml
steps:
  - name: Override matrix value
    run: ruby -e 'puts ENV.fetch("MATRIX_RUBY")'
    env:
      MATRIX_RUBY: custom
```

Matrix variables are available to `before_all`, normal `steps`, `after_all`, and `if` condition evaluation:

```yaml
steps:
  - name: PostgreSQL-only test
    run: echo "postgres test"
    if: env.MATRIX_DATABASE == "postgres"
```

Matrix runs use a fail-late policy. If one job fails, Mini CI finishes that job's cleanup, continues running later jobs, and returns exit code `1` after all jobs finish if any job failed.

Each job gets a stable display name:

```text
Ruby Matrix Example [ruby=3.2, database=sqlite]
```

Mini CI rejects matrix definitions that expand beyond `256` jobs to avoid accidental huge runs.

### Matrix Concurrency

Matrix pipelines can define:

```yaml
concurrency: 2
```

`concurrency` must be a positive integer and may not exceed `32`. When omitted, Mini CI chooses an automatic value based on available processors, capped by the number of generated jobs and the maximum of `32`. Non-matrix pipelines still run directly without using the matrix worker pool.

The CLI can override YAML concurrency:

```bash
bundle exec bin/mini-ci run examples/matrix-parallel-pipeline.yml --concurrency 4
bundle exec bin/mini-ci run examples/matrix-parallel-pipeline.yml -j 4
```

Precedence is:

```text
CLI override
YAML concurrency
automatic default
```

Each matrix job receives its own pipeline instance, command runner, reporter, output buffer, effective environment, timeout handling, retry state, and failure state. Mini CI does not mutate global `ENV` and does not temporarily replace global `$stdout` or `$stderr`.

Command and reporter output is buffered per matrix job. Mini CI prints each completed job as one contiguous block, so output from concurrent jobs does not interleave. Completed job blocks are printed as jobs finish, while the final matrix summary remains in expansion order.

Matrix summary duration has two meanings:

- `Wall-clock duration` is the elapsed runtime of the whole matrix run.
- `Combined job time` is the sum of individual job durations.

Timeouts remain scoped to the command process group for that job. A timed-out matrix job should not signal another matrix job's process group.

### Build Artifacts

Steps and hooks can declare files or directories to collect after they execute:

```yaml
steps:
  - name: Run tests
    run: bash scripts/generate_test_artifacts.sh
    artifacts:
      when: always
      paths:
        - coverage/
        - reports/results.xml
        - logs/**/*.log
```

`artifacts` must be a mapping. `paths` must be a non-empty array of strings. `when` is optional and defaults to `always`.

Artifact policies:

- `always` collects after any executed result;
- `success` collects only when the item ultimately succeeds;
- `failure` collects only when the item ultimately fails, including timeout failures.

Skipped items do not collect artifacts. Retries collect only once, after the final attempt, using the final filesystem state. After a timeout, Mini CI waits for the command process group to terminate before collecting eligible artifacts.

Artifact source paths are resolved relative to the pipeline workspace. Mini CI supports direct file paths, directories, and Ruby glob patterns such as `reports/**/*.xml`. Source paths must stay inside the workspace: absolute paths, `..` traversal, and symlinks resolving outside the workspace are rejected or reported as artifact collection errors.

Missing paths produce warnings and do not fail the step:

```text
Warning: artifact path "coverage/" did not match any files
```

Real copy failures, unsafe symlinks, or manifest write failures fail the overall run because the user explicitly requested those outputs be preserved. If the command already failed, that command remains the primary failure and the artifact problem is reported separately.

Artifacts are stored under a unique run directory:

```text
.mini-ci/artifacts/
  run-20260728T101530Z-a1b2c3/
    job-001/
      step-001-run-tests/
        coverage/
        reports/results.xml
    manifest.json
```

Matrix jobs receive isolated job directories such as:

```text
job-001-job-alpha/
job-002-job-beta/
```

Parallel matrix jobs write only inside their own job artifact directory, so artifact destinations do not overwrite each other.

Use a custom artifact root with:

```bash
bundle exec bin/mini-ci run examples/artifacts-success-pipeline.yml --artifacts-dir tmp/artifacts
```

Relative artifact destinations are resolved from the current working directory. Absolute artifact destinations are allowed because they are output locations chosen by the user.

Each run writes `manifest.json` with run metadata, final status, jobs, artifact item directories, file counts, and warnings. It does not include command environments or secret values.

### Dependency Caching

Steps and hooks can declare a local dependency cache:

```yaml
steps:
  - name: Install dependencies
    run: bundle install
    cache:
      key: bundle-${{ checksum("Gemfile.lock") }}
      restore_keys:
        - bundle-
      paths:
        - vendor/bundle
```

Mini CI restores the cache before the item runs and saves configured paths after the final attempt. Artifacts are collected before caches are saved, so diagnostic files are preserved first when both features are configured.

Cache fields:

- `key` is required and must be a non-empty string.
- `paths` is required and must be a non-empty array of relative paths or globs.
- `restore_keys` is optional and must be an array of fallback key prefixes.
- `save_when` is optional and may be `success` or `always`; the default is `success`.

Restore behaviour:

- Mini CI first looks for an exact match for the resolved `key`.
- If no exact match exists, it tries `restore_keys` in order.
- A restore key is treated as a prefix; Mini CI restores the newest matching cache.
- Mini CI always saves under the resolved primary `key`, never under a restore key.

Cache key expressions are intentionally small and safe:

```text
${{ checksum("relative/file") }}
${{ env.VARIABLE }}
```

`checksum` uses SHA-256 and only accepts files inside the workspace. Absolute paths, `..` traversal, directories, missing files, and symlinks resolving outside the workspace are rejected before the command executes. Mini CI does not use Ruby `eval`, shell execution, arbitrary functions, or YAML object loading for cache keys.

Caches are stored locally under:

```text
.mini-ci/cache/
```

Use a custom cache root:

```bash
bundle exec bin/mini-ci run examples/cache-basic-pipeline.yml --cache-dir tmp/cache
```

Disable caching for a run:

```bash
bundle exec bin/mini-ci run examples/cache-basic-pipeline.yml --no-cache
```

Inspect and clear cache entries:

```bash
bundle exec bin/mini-ci cache list
bundle exec bin/mini-ci cache clear --yes
```

Cache saves are written to a temporary directory and then atomically moved into place. Matrix jobs share the same cache store and use process-local per-key locks for concurrent saves. Restore and save filesystem problems are reported as warnings and do not fail the pipeline; invalid cache configuration and key-resolution errors fail before the item command executes.

Working examples:

```bash
bundle exec bin/mini-ci run examples/cache-basic-pipeline.yml
bundle exec bin/mini-ci run examples/cache-fallback-pipeline.yml
bundle exec bin/mini-ci run examples/cache-matrix-pipeline.yml
bundle exec bin/mini-ci run examples/cache-failure-pipeline.yml
```

### Plugins

Mini CI can load trusted local Ruby plugins. Plugins can register lifecycle callbacks, custom configuration validators, and custom pipeline item types.

Security warning:

- Plugins are fully trusted Ruby code.
- Plugins run inside the Mini CI process and are not sandboxed.
- Plugins can access files, processes, environment variables, and network resources.
- Only load plugins you trust.
- Do not make plugin directories writable by untrusted users or tools.
- Mini CI does not download plugins, install plugins from remote URLs, or provide isolation.

Plugins are loaded from the default directory when it exists:

```text
.mini-ci/plugins/**/*.rb
```

Directory plugin files load in deterministic alphabetical order. Explicit CLI directories load after the default directory, and explicit CLI files load after directories:

```text
default .mini-ci/plugins
--plugin-dir values in CLI order
--plugin values in CLI order
```

Load plugins explicitly:

```bash
bundle exec bin/mini-ci plugins validate \
  --plugin examples/plugins/run_logger.rb \
  --plugin examples/plugins/message_item.rb

bundle exec bin/mini-ci plugins list \
  --plugin examples/plugins/run_logger.rb \
  --plugin examples/plugins/message_item.rb
```

Validate and run a pipeline that uses plugin items:

```bash
bundle exec bin/mini-ci validate examples/plugin-basic-pipeline.yml \
  --plugin examples/plugins/run_logger.rb \
  --plugin examples/plugins/message_item.rb

bundle exec bin/mini-ci run examples/plugin-basic-pipeline.yml \
  --plugin examples/plugins/run_logger.rb \
  --plugin examples/plugins/message_item.rb

echo $?
```

The primary registration API is declarative:

```ruby
MiniCi::Plugin.register(
  name: "message-plugin",
  version: "1.0.0",
  description: "Adds a message pipeline item"
) do |plugin|
  plugin.register_item_type("message") do |input, context|
    context.output.puts input.fetch("text")

    MiniCi::Plugin::ItemResult.new(
      success: true,
      plugin_name: "message-plugin",
      item_type: "message",
      metadata: {
        "message_length" => input.fetch("text").length
      }
    )
  end
end
```

Plugin metadata requires:

- `name`, matching `[a-z0-9][a-z0-9_-]*`;
- `version`, a non-empty string.

Optional metadata:

- `description`;
- `author`;
- `homepage`;
- `api_version`.

`MiniCi::PLUGIN_API_VERSION` is currently `1`. This is separate from the Mini CI package version and from each plugin's own version. Plugins may declare `api_version: "1"`; incompatible versions are rejected before pipeline execution.

Supported lifecycle callbacks include:

```ruby
plugin.before_run { |context| }
plugin.after_run { |context| }
plugin.before_pipeline { |context| }
plugin.after_pipeline { |context| }
plugin.before_item { |context| }
plugin.after_item { |context| }
plugin.after_report { |context| }
```

Callbacks execute in deterministic order:

1. plugin load order;
2. callback declaration order within each plugin.

`after_*` callbacks use the same order. Callbacks may run concurrently during parallel matrix jobs. Plugin authors should write callbacks to be thread-safe, or mark a callback as serial for that plugin:

```ruby
plugin.after_item(serial: true) do |context|
  # protected by this plugin callback's mutex
end
```

Mini CI uses plugin-specific callback mutexes, not one global plugin lock.

Callback contexts expose only event-relevant values, such as:

- `context.configuration`;
- `context.result`;
- `context.item`;
- `context.item_result`;
- `context.phase`;
- `context.matrix_values`;
- `context.workspace`;
- `context.run_id`;
- `context.metadata`;
- `context.output`.

Mini CI does not expose the full parent process environment to plugin contexts. Use:

```ruby
context.environment_variable("MATRIX_RUBY")
```

That reads configured pipeline, matrix, and step/hook variables only.

Plugins can add structured run metadata:

```ruby
context.metadata["quality_gate"] = {
  "status" => "passed"
}
```

Plugin metadata must be string-keyed, JSON-compatible, non-recursive, and no larger than 1 MB. Mini CI does not automatically include secrets.

Plugins can register custom validators:

```ruby
plugin.validate_configuration do |configuration|
  "pipeline name is required" unless configuration.name_explicit
end
```

Plugin validation runs after core YAML parsing and validation. Plugin errors prevent execution and cannot suppress core errors.

Plugins can register custom item types used through `uses` and `with`:

```yaml
steps:
  - name: Print plugin message
    uses: message
    with:
      text: Hello from a plugin
```

Core rules:

- `uses` must be a non-empty string;
- `with` must be a mapping when supplied;
- an item cannot define both `run` and `uses`;
- the referenced item type must be registered by a loaded plugin;
- in-process plugin items support conditions, artifacts, caching, matrix execution, and normal result reporting;
- in-process plugin items do not support command timeouts or retries.

Plugin callback failures fail the Mini CI run. If a command already failed, that command remains the primary failure and the plugin failure is reported additionally. A `before_item` plugin failure prevents that item from executing and marks the run failed while still allowing guaranteed cleanup to be evaluated.

Example plugins:

```text
examples/plugins/run_logger.rb
examples/plugins/message_item.rb
examples/plugins/policy_validator.rb
examples/plugins/callback_failure.rb
```

Example plugin pipelines:

```bash
bundle exec bin/mini-ci run examples/plugin-basic-pipeline.yml \
  --plugin examples/plugins/run_logger.rb \
  --plugin examples/plugins/message_item.rb

bundle exec bin/mini-ci run examples/plugin-matrix-pipeline.yml \
  --plugin examples/plugins/message_item.rb \
  --concurrency 2

bundle exec bin/mini-ci validate examples/plugin-validation-failure-pipeline.yml \
  --plugin examples/plugins/policy_validator.rb

bundle exec bin/mini-ci run examples/plugin-callback-failure-pipeline.yml \
  --plugin examples/plugins/callback_failure.rb
```

Artifact manifests include loaded plugin metadata, plugin failures, plugin run metadata, and per-item plugin metadata when an artifact run directory is active.

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
- `before_all` or `after_all` values that are not arrays;
- hook entries that are not mappings/objects;
- hook entries missing `name` or `run`;
- blank hook names or run commands;
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
- `timeout` values that are zero, negative, or non-finite;
- `retries` values that are negative, decimal numbers, strings, booleans, null, arrays, or mappings;
- `retry_delay` values that are negative, strings, booleans, null, arrays, mappings, or non-finite.
- `concurrency` values that are zero, negative, decimal numbers, strings, booleans, null, arrays, or mappings;
- `concurrency` values greater than `32`;
- `artifacts` values that are not mappings;
- artifact definitions missing `paths`;
- artifact `paths` values that are empty or are not arrays;
- artifact path values that are blank, non-strings, null, absolute, or escape the workspace;
- artifact `when` values other than `success`, `failure`, or `always`;
- unknown artifact fields;
- `cache` values that are not mappings;
- cache definitions missing `key` or `paths`;
- cache keys that are blank, non-strings, or contain null bytes;
- cache `paths` values that are empty or are not arrays;
- cache path values that are blank, non-strings, null, absolute, or escape the workspace;
- cache `restore_keys` values that are not arrays;
- cache restore keys that are blank, non-strings, or contain null bytes;
- cache `save_when` values other than `success` or `always`;
- unsupported cache key expressions;
- `when` values other than `success`, `failure`, `always`, or `never`;
- `if` values that are blank, non-strings, or outside the supported grammar.
- `matrix` values that are not mappings or are empty;
- matrix keys that do not match `[A-Za-z_][A-Za-z0-9_]*`;
- matrix value lists that are empty or are not arrays;
- matrix values that are null, arrays, or mappings;
- matrices that expand beyond `256` generated jobs.

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
step-level or hook-level environment variables
```

Later values override earlier values. For example, if your shell has `APP_ENV=development`, the pipeline has `APP_ENV=test`, and a step or hook has `APP_ENV=integration`, that item receives `APP_ENV=integration`.

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

When a step exceeds its timeout, Mini CI terminates the command, marks the step as failed, and continues evaluating later configured items. Later default `when: success` items skip. Timeout values must be positive numbers; strings such as `"10"` are intentionally rejected.

Mini CI starts each command in its own process group. On timeout, it sends `TERM` to the process group, waits briefly for graceful shutdown, then sends `KILL` if the command or its child processes are still running. This keeps commands such as `bash -c 'sleep 30 & wait'` from leaving child processes behind.

The current timeout implementation targets Unix-like environments such as Linux and macOS.

### Step Retries

Each step can retry after a normal failure or timeout:

```yaml
steps:
  - name: Check external service
    run: bash scripts/flaky_check.sh
    retries: 2
    retry_delay: 1
```

`retries` means additional attempts after the first run:

```text
retries: 0 -> 1 total attempt
retries: 2 -> 3 total attempts
```

`retry_delay` is the number of seconds to wait between failed attempts. It accepts integers and decimals:

```yaml
retry_delay: 0
retry_delay: 1
retry_delay: 0.5
```

Mini CI does not wait before the first attempt, after a successful attempt, or after the final failed attempt. Step duration includes retry delays because they are part of the real elapsed time.

Timed-out attempts count as failed attempts. If retries remain, Mini CI retries after the configured delay and preserves timeout details in the attempt history.

### Referencing Bash Scripts

Steps and hooks run shell commands directly. To run a Bash script, reference it in the `run` field:

```yaml
- name: Run Bash script
  run: bash scripts/print_env.sh
```

Make the script executable before running the pipeline:

```bash
chmod +x scripts/print_env.sh
chmod +x scripts/prepare_workspace.sh
chmod +x scripts/cleanup_workspace.sh
chmod +x scripts/cache_dependency_demo.sh
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
Configured concurrency: automatic
Before-all hooks: 0
Steps: 2
After-all hooks: 0
Environment variables: 3
Conditional items: 0
Artifact-producing items: 0
Cache-producing items: 0
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

Steps:
  1. Print global variables
     bash scripts/print_env.sh

  2. Override one variable
     ruby -e 'puts ENV.fetch("SHARED_VALUE")'
     Timeout: 5s
     Environment:
       SHARED_VALUE=step
       FEATURE_FLAG=enabled
```

Hook pipelines are grouped by phase:

```text
Hooks Success Example

Before all:
  1. Prepare workspace
     bash scripts/prepare_workspace.sh

Steps:
  1. Check marker exists
     test -f tmp/mini_ci_hooks/marker.txt

After all:
  1. Clean workspace
     bash scripts/cleanup_workspace.sh
```

Conditional settings are shown only when explicitly configured:

```text
2. Deploy
   bash scripts/conditional_deploy.sh
   When: success
   If: env.DEPLOY == "true"
```

Matrix pipelines show dimensions, generated job counts, and combinations for small matrices:

```text
Basic Matrix

Concurrency: automatic

Matrix:
  ruby: 3.2, 3.3
  database: sqlite, postgres

Generated jobs: 4

Combinations:
  1. ruby=3.2, database=sqlite
  2. ruby=3.2, database=postgres
  3. ruby=3.3, database=sqlite
  4. ruby=3.3, database=postgres
```

## Run The Example Pipeline

Run the example pipeline from the project root:

```bash
bundle exec bin/mini-ci run
```

When all steps pass, Mini CI prints output similar to:

```text
Mini CI — Environment Example

Pipeline

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
Main steps: 2 passed, 0 failed, 0 skipped, 2 total
Attempts: 2
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

Pipeline

[1/3] Successful step
Step one passed
✓ Passed in 0.01s

[2/3] Failing step
Test failure
✗ Failed with exit code 1 in 1.42s

[3/3] Skipped step
– Skipped: requires previous success

Pipeline summary

Status: FAILED
Main steps: 1 passed, 1 failed, 1 skipped, 3 configured
Attempts: 2
Duration: 1.50s

Primary failure:
  Failing step failed with exit code 1
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

Pipeline

[1/3] Quick step
quick step completed
✓ Passed in 0.08s

[2/3] Slow step
starting slow step
✗ Timed out after 1.00s

Pipeline summary

Status: FAILED
Main steps: 1 passed, 1 failed, 1 skipped, 3 configured
Attempts: 2
Duration: 1.10s

Primary failure:
  Slow step timed out after 1.00s
```

The timeout pipeline exits with status `1`.

## Retry Example Pipelines

Run the retry-success example:

```bash
bundle exec bin/mini-ci run examples/retry-pipeline.yml
echo $?
```

Expected output includes a flaky step failing once, retrying, and then succeeding:

```text
[2/3] Flaky check

Attempt 1/3
✗ Failed with exit code 1 in 0.02s
Retrying in 0.10s...

Attempt 2/3
✓ Passed in 0.02s

[3/3] Pipeline continued
pipeline continued after retry

Pipeline summary

Status: PASSED
Main steps: 3 passed, 0 failed, 0 skipped, 3 total
Retried steps: 1
Attempts: 4
Duration: 0.20s
```

Run the exhausted-retries example:

```bash
bundle exec bin/mini-ci run examples/retry-failure-pipeline.yml
echo $?
```

Expected output includes all attempts failing and the later step being skipped:

```text
Step failed after 3 attempts.

Pipeline summary

Status: FAILED
Main steps: 1 passed, 1 failed, 1 skipped, 3 configured
Retried steps: 1
Attempts: 4

Primary failure:
  Always flaky check failed after 3 attempts with exit code 1
```

## Hook Example Pipelines

Run the successful hook example:

```bash
bundle exec bin/mini-ci run examples/hooks-success-pipeline.yml
echo $?
```

It exits with status `0` after setup, main steps, and cleanup all pass.

Run the main-failure hook example:

```bash
bundle exec bin/mini-ci run examples/hooks-main-failure-pipeline.yml
echo $?
```

It exits with status `1`. The failing main step causes later default-success main steps to skip, but the cleanup hook still runs.

Run the cleanup-failure hook example:

```bash
bundle exec bin/mini-ci run examples/hooks-cleanup-failure-pipeline.yml
echo $?
```

It exits with status `1`. The first cleanup hook fails, the later cleanup hook still runs, and the summary includes cleanup failures.

## Conditional Example Pipelines

Run the success example:

```bash
bundle exec bin/mini-ci run examples/conditions-success-pipeline.yml
echo $?
```

It exits with status `0`. It demonstrates a skipped `when: failure` item, a running `when: always` item, a true `if` condition, and a false `if` condition.

Run the failure example:

```bash
bundle exec bin/mini-ci run examples/conditions-failure-pipeline.yml
echo $?
```

It exits with status `1`. It demonstrates a failing normal step, skipped success-only work, a running failure diagnostic step, a running always step, and cleanup still running.

Run the never example:

```bash
bundle exec bin/mini-ci run examples/conditions-never-pipeline.yml
echo $?
```

It exits with status `0`. The disabled `when: never` item is reported as skipped and its command is not executed.

## Matrix Example Pipelines

Validate and list the basic matrix example:

```bash
bundle exec bin/mini-ci validate examples/matrix-basic-pipeline.yml
bundle exec bin/mini-ci list examples/matrix-basic-pipeline.yml
```

Run the basic matrix example:

```bash
bundle exec bin/mini-ci run examples/matrix-basic-pipeline.yml
echo $?
```

It generates four jobs, runs them with the resolved matrix concurrency, and exits with status `0` when every job passes.

Run the conditional matrix example:

```bash
bundle exec bin/mini-ci run examples/matrix-conditional-pipeline.yml
echo $?
```

It demonstrates matrix values in setup hooks, normal steps, cleanup hooks, and `if` conditions. It also shows a step-level environment override of `MATRIX_RUBY`.

Run the partial-failure matrix example:

```bash
bundle exec bin/mini-ci run examples/matrix-partial-failure-pipeline.yml
echo $?
```

It makes exactly one combination fail, continues running later jobs, runs cleanup for the failed job, and exits with status `1`.

## Parallel Matrix Example Pipelines

Validate and list the parallel matrix example:

```bash
bundle exec bin/mini-ci validate examples/matrix-parallel-pipeline.yml
bundle exec bin/mini-ci list examples/matrix-parallel-pipeline.yml
```

Run it with YAML concurrency:

```bash
bundle exec bin/mini-ci run examples/matrix-parallel-pipeline.yml
echo $?
```

Run it with a CLI concurrency override:

```bash
bundle exec bin/mini-ci run examples/matrix-parallel-pipeline.yml --concurrency 4
echo $?
```

Run it sequentially for comparison:

```bash
bundle exec bin/mini-ci run examples/matrix-parallel-pipeline.yml -j 1
echo $?
```

Run the parallel failure example:

```bash
bundle exec bin/mini-ci run examples/matrix-parallel-failure-pipeline.yml
echo $?
```

It fails one matrix job, continues all later jobs, runs cleanup for every job, and exits with status `1`.

Run the timeout example:

```bash
bundle exec bin/mini-ci run examples/matrix-parallel-timeout-pipeline.yml
echo $?
```

It demonstrates one timed-out matrix job while another job finishes normally.

## Artifact Example Pipelines

Validate and list the successful artifact example:

```bash
bundle exec bin/mini-ci validate examples/artifacts-success-pipeline.yml
bundle exec bin/mini-ci list examples/artifacts-success-pipeline.yml
```

Run the successful artifact example:

```bash
bundle exec bin/mini-ci run examples/artifacts-success-pipeline.yml
echo $?
```

It generates coverage, report, and log files; copies them into `.mini-ci/artifacts/run-...`; writes `manifest.json`; warns about one missing optional path; and exits with status `0`.

Run the failing artifact example:

```bash
bundle exec bin/mini-ci run examples/artifacts-failure-pipeline.yml
echo $?
```

It creates a failure log, exits non-zero, collects logs because `artifacts.when` is `failure`, skips the later default-success step, runs cleanup, and exits with status `1`.

Run the matrix artifact example with parallel execution:

```bash
bundle exec bin/mini-ci run examples/artifacts-matrix-pipeline.yml --concurrency 2
echo $?
```

It runs three matrix jobs, stores each job's artifacts in a separate job directory, and exits with status `0`.

## Version And Help

Show the installed version:

```bash
bundle exec bin/mini-ci version
```

Example output:

```text
Mini CI 0.14.0
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
- `skipped` — configured items that did not run because `when` or `if` did not allow them.

When no main steps are skipped, the summary reports the configured count as `total`. When any main step is skipped, it reports the configured count as `configured`. Setup and cleanup hooks report passed, failed, and skipped counts separately.

## Exit Status

Mini CI uses process exit codes to report pipeline success or failure:

- exit code `0` — the command completed successfully;
- exit code `1` — pipeline execution failed;
- exit code `2` — configuration or CLI usage error;
- exit code `3` — internal Mini CI execution error.

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

- Steps within one pipeline job run one at a time.
- Matrix jobs can run concurrently, but only on the local machine.
- Artifacts are stored locally only.
- Dependency caches are stored locally only.
- Cache entries are not compressed and do not have eviction policies yet.
- Plugins are trusted local Ruby code and are not sandboxed.
- Plugin files are local only; there is no remote marketplace or automatic installer.
- In-process plugin item handlers do not support command timeout or retry semantics.
- Artifact collection happens once per item after final retry, not once per attempt.
- Matrix runs are fail-late: one failed job does not stop later jobs.
- Later configured items are evaluated after failure, but only supported `when` and `if` rules are available.
- Cleanup hooks still run after setup or main-step failures.
- Cleanup hooks keep running after cleanup failures.
- Conditions only compare environment variables to quoted string values.
- No secrets management or secret masking.
- No `.env` file support.
- Timeout process-group termination is currently intended for Unix-like systems.
- No local dashboard, remote cache servers, remote artifact storage, compression, Docker, deployment, frontend, or database support.

## Next Milestone

The next planned milestone adds a local dashboard.
