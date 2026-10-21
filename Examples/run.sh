#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
# WHAT: Build the playground app (release) and run it. The app is a bare SwiftPM binary with its
#       Info.plist linked in, so it is exec'd directly: no .app bundle, no codesign step.
#       Flags go to the app: `--provider fake` opens it on the offline fake model, with no key;
#       `--provider mistral`, `--model mistral-large-latest`; `--scenario medication|fever|missed-dose`
#       fills the composer. `run.sh clean` removes Examples/.build. CONFIG=debug builds debug.
# IN:   MISTRAL_API_KEY, when set, is one of the places the app looks for a key: after the
#       Keychain item it saves itself, before ~/.rao/keys/providers.json (Ambient's store).
# PIN:  Build then exec, never `swift run`: AppKit reads a bare path in argv as a document to open,
#       and an app with no document types then opens no window. So every argument is a flag. No
#       TCC grant is asked for, so the ad-hoc signature that changes every build costs nothing; the
#       key lives in a Keychain item written by /usr/bin/security, which trusts that tool and not
#       this binary.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ "${1:-}" = "clean" ]; then
    rm -rf "$HERE/.build"
    echo "run.sh: removed Examples/.build" >&2
    exit 0
fi
CONFIG="${CONFIG:-release}"
echo "run.sh: building BlessPlayground ($CONFIG)" >&2
swift build --package-path "$HERE" -c "$CONFIG" --product BlessPlayground -q >&2
bin_dir="$(swift build --package-path "$HERE" -c "$CONFIG" --show-bin-path)"
exec "$bin_dir/BlessPlayground" "$@"
