#!/usr/bin/env bash
set -euo pipefail

bundle check
bundle exec bin/mini-ci version
bundle exec bin/mini-ci help >/dev/null
bundle exec bin/mini-ci validate examples/showcase-pipeline.yml
bundle exec bin/mini-ci list examples/showcase-pipeline.yml >/dev/null
bundle exec bin/mini-ci run examples/showcase-pipeline.yml --concurrency 2 --no-history
gem build mini_ci.gemspec >/dev/null
