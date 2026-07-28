# Contributing

Thanks for helping improve Mini CI.

## Setup

Mini CI supports Ruby 3.1 and newer.

```bash
bundle install
bundle exec rspec
```

Run one spec:

```bash
bundle exec rspec spec/cli_spec.rb
```

Run release checks:

```bash
bundle exec rake release:check
```

## Style

- Keep Ruby readable and beginner-friendly.
- Prefer small objects with clear responsibilities.
- Do not hide unexpected errors silently.
- Keep CLI output consistent and test behaviour rather than decorative formatting.
- Use safe YAML loading, safe path handling, and dependency injection in tests.

## Examples

Examples should be deterministic, fast, local, and documented. Avoid examples that require cloud accounts, remote services, Docker, or multiple installed Ruby versions.

## CLI Changes

When adding or changing CLI options, update:

- command parsing;
- command-level help;
- README command reference;
- specs for success and invalid usage;
- exit-code expectations.

## Plugin API Changes

Plugin API version 1 is part of the v1.0 compatibility surface. Any breaking plugin API change should be intentional, documented, and tested.

## Documentation

Update README and `docs/` when changing public behaviour, YAML fields, exit codes, security assumptions, or packaging.

## Pull Request Checklist

- Tests pass.
- Relevant examples pass.
- Documentation is updated.
- No generated runtime state is committed.
- Security impact is considered.

## Security

Please follow [SECURITY.md](SECURITY.md) for vulnerability reports.
