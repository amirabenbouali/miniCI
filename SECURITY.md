# Security Policy

## Supported Versions

Mini CI 1.x is the supported release line once v1.0.0 is released.

## Reporting Vulnerabilities

Please report suspected vulnerabilities through GitHub's private vulnerability reporting for this repository, or open a security-focused issue if private reporting is not available. Do not include secrets, private tokens, or exploit details in a public issue.

## Trust Model

Mini CI is a local automation tool. It runs shell commands with the permissions of the current user.

Plugins are trusted Ruby code. A plugin can access files, processes, environment variables, and network resources available to the Ruby process. Only load plugins you trust and do not make plugin directories writable by untrusted users.

The dashboard is intended for trusted local use. It has no authentication. Binding it to a non-loopback host can expose run history and run-launch controls to other users on the network.

Artifacts and caches are local filesystem data. Mini CI validates configured paths and blocks traversal outside the workspace for artifact and cache inputs, but collected files and restored cache contents should still be treated as trusted local data.

Mini CI does not provide a secret vault, secret masking, or `.env` loading. Avoid printing secrets from commands, plugins, or scripts.

## Responsible Disclosure

Please give maintainers reasonable time to investigate and fix confirmed issues before sharing details publicly.
