# Mini CI Configuration

Mini CI loads YAML with Ruby's safe YAML loader. Aliases and arbitrary Ruby objects are not allowed.

## Top-Level Fields

| Field | Required | Default | Description |
| --- | --- | --- | --- |
| `name` | No | `Mini CI` | Pipeline display name. |
| `env` | No | `{}` | Global environment variables. |
| `concurrency` | No | automatic | Matrix worker count, 1 to 32. |
| `matrix` | No | none | Mapping of matrix dimensions to arrays of scalar values. |
| `before_all` | No | `[]` | Setup hooks. |
| `steps` | Yes | none | Main pipeline items. |
| `after_all` | No | `[]` | Cleanup hooks. |

## Item Fields

Each item in `before_all`, `steps`, and `after_all` supports:

| Field | Required | Description |
| --- | --- | --- |
| `name` | Yes | Non-empty display name. |
| `run` | Yes for commands | Shell command executed by the system shell. |
| `uses` | Yes for plugin items | Registered plugin item type. |
| `with` | No | Mapping passed to a plugin item. |
| `env` | No | Item-specific environment variables. |
| `timeout` | No | Positive number of seconds. |
| `retries` | No | Non-negative integer retry count. |
| `retry_delay` | No | Non-negative seconds between retry attempts. |
| `when` | No | `success`, `failure`, `always`, or `never`. |
| `if` | No | Environment comparison condition. |
| `artifacts` | No | Artifact collection policy and paths. |
| `cache` | No | Local dependency cache policy and paths. |

An item may define `run` or `uses`, but not both. Plugin items do not support command timeout or retry semantics.

## Environment Precedence

Command environment values are resolved in this order:

```text
parent process environment
pipeline env
matrix env
item env
```

Mini CI does not mutate the parent Ruby process environment.

## Conditions

`when` defaults:

- `before_all`: `success`
- `steps`: `success`
- `after_all`: `always`

`if` supports only:

```text
env.NAME == "value"
env.NAME != "value"
```

Single-quoted values are also supported. Logical operators, regular expressions, shell expansion, and Ruby evaluation are not supported.

## Matrix

Matrix dimensions are expanded in YAML order using deterministic Cartesian-product expansion. Values are exposed as upper-case environment variables prefixed with `MATRIX_`.

Example:

```yaml
matrix:
  ruby:
    - "3.1"
    - "3.2"
```

Creates `MATRIX_RUBY`.

## Timeouts and Retries

Timeouts apply to command process groups on Unix-like systems. A retry runs only after the previous attempt has finished or timed out. Retries do not apply to skipped items.

## Hooks and Cleanup

`after_all` hooks default to `when: always`, so cleanup runs after setup or main-step failures. Cleanup failures are reported without hiding the primary failure from normal work.

## Artifacts

```yaml
artifacts:
  when: always
  paths:
    - reports/
```

Allowed `when` values are `always`, `success`, and `failure`. Paths must stay inside the workspace. Missing artifact paths produce warnings; unsafe paths and real copy failures are reported as failures.

## Cache

```yaml
cache:
  key: bundle-${{ checksum("Gemfile.lock") }}
  restore_keys:
    - bundle-
  paths:
    - vendor/bundle
  save_when: success
```

Cache paths must stay inside the workspace. `save_when` may be `success` or `always`.

Supported key expressions:

```text
${{ checksum("relative/file") }}
${{ env.NAME }}
```

## Unsupported

Mini CI does not support remote runners, Docker orchestration, secret vaults, YAML anchors, arbitrary YAML objects, distributed cache, or hosted services.
