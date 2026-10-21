#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
# WHAT: Build and run every test: the root package's suites (Bless, BlessProviders, the layering
#       rules, the site fixtures), then build the playground app and run its suites. Extra
#       arguments go to the root `swift test` (e.g. --filter GateTests).
# IN:   BLESS_WRITE_FIXTURES=1 rewrites Tests/BlessTests/Fixtures/site/*.json from the code.
#       BLESS_SKIP_PLAYGROUND=1 skips the playground.
# PIN:  The site's own checks (Playwright, Chrome, minutes) are Docs/site/src/build.sh, not here.
#
#   Scripts/test.sh
#   Scripts/test.sh --filter GateWaitingTests
#
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

swift build --build-tests
swift test --skip-build "$@"

if [ "${BLESS_SKIP_PLAYGROUND:-0}" != "1" ] && [ -f Examples/Package.swift ]; then
    swift build --package-path Examples --product BlessPlayground
    swift build --package-path Examples --build-tests
    swift test --package-path Examples --skip-build
fi
