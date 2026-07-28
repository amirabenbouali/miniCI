# Dashboard Visual Checklist

Use this checklist for screenshot preparation and manual dashboard QA.

## Setup

```bash
bundle exec bin/mini-ci run examples/showcase-pipeline.yml --concurrency 2
bundle exec bin/mini-ci dashboard
```

Open the local dashboard URL printed by the command, normally:

```text
http://127.0.0.1:4567
```

## Pages

- Overview desktop: summary metrics, recent runs, system information, active navigation.
- Overview narrow width: sidebar becomes compact top navigation, metrics stack cleanly.
- Runs table: filters, status badges, horizontal table scrolling, empty state.
- Successful run detail: status summary, metadata, jobs, output and artifacts links.
- Failed run detail: failure summary is visible near the top.
- Running log view: output remains escaped, copy works, wrapping toggle works, auto-scroll is usable.
- Matrix run: jobs remain in deterministic order and matrix values are readable.
- Artifacts: relative paths, size, type and safe download links render.
- Empty history: empty state explains that no runs have been recorded.
- Error state: user-facing error panel renders without stack traces.

## Interaction

- Refresh action reloads the current page.
- New run action opens the launch form.
- Launch form shows a loading state after submit.
- Cancellation asks for explicit confirmation.
- Deleting a terminal run asks for explicit confirmation.
- Keyboard focus is visible on links, buttons and form controls.
- Escape closes the confirmation dialog.
- Narrow-width controls remain reachable and text does not overlap.
- Reduced motion preference disables nonessential transitions.

## Security

- Log output is displayed as text, not HTML.
- Pipeline names and run IDs are escaped.
- Artifact links stay under `/runs/:run_id/artifacts`.
- State-changing forms include CSRF tokens.
- The dashboard displays a local-only notice and does not imply authentication.
