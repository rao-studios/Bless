#!/bin/zsh
# SPDX-License-Identifier: GPL-3.0-only
# Rebuilds the README's pictures: Docs/README_Assets/hero.png, from HTML rendered by Google Chrome through Playwright
# (pip install playwright; it drives the installed Chrome), as Braid's, AII's and VeilGarde's heroes are; and
# Docs/README_Assets/playground.png, the playground's window drawn off screen by its own snapshot mode.
set -euo pipefail
repo=${0:A:h:h:h:h}
cd "$repo"
python3 -I Docs/README_Assets/src/build.py Docs/README_Assets
swift build --package-path Examples -c release --product BlessPlayground -q
"$(swift build --package-path Examples -c release --show-bin-path)/BlessPlayground" --snapshot demo --out Docs/README_Assets/playground.png
echo "playground.png: written"
