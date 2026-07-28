# Release Checklist

- [ ] Version updated.
- [ ] Changelog updated.
- [ ] All tests passing.
- [ ] Random seeds passing.
- [ ] Examples passing.
- [ ] Gem builds.
- [ ] Gem installs in an isolated GEM_HOME.
- [ ] Installed executable works.
- [ ] Package contents reviewed.
- [ ] README accurate.
- [ ] Configuration docs accurate.
- [ ] Architecture docs present.
- [ ] Security documentation present.
- [ ] CI green.
- [ ] Git status clean.
- [ ] Tag prepared.
- [ ] Release notes drafted.
- [ ] Smoke test passes.
- [ ] Screenshots added or intentionally deferred.
- [ ] Repository description set.
- [ ] Topics set.
- [ ] No secrets tracked.
- [ ] No generated files tracked.
- [ ] GitHub Release created.
- [ ] Repository pinned if desired.

## Manual GitHub Settings

Suggested repository description:

```text
Lightweight local CI pipeline runner written in Ruby with matrix builds, caching, artifacts and plugins.
```

Suggested topics:

```text
ruby
ci
continuous-integration
developer-tools
automation
yaml
pipeline
cli
matrix-builds
testing
build-system
```

## Tag Commands

After final review:

```bash
git tag -a v1.0.0 -m "Mini CI v1.0.0"
git push origin v1.0.0
```
