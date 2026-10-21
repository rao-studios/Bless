# SPDX-License-Identifier: GPL-3.0-only
"""Builds the README's hero from HTML, rendered by the installed Google Chrome through Playwright.

    Docs/README_Assets/src/build.sh       # runs this

Inputs:  this folder's rr-mark.png; Playfair Display Italic from ~/Library/Fonts; one petition's life as Bless's
         Gate wrote it, Tests/BlessTests/Fixtures/site/ledger.json: the digest of the draft it held and of the text
         it sent, which differ because the reviewer amended it.
Outputs: hero.png in argv[1], 2400×1260 (1200×630 at scale 2), in the family's style: Braid's and AII's heroes
         (their palette, title, caption and legend), VeilGarde's way of drawing real numbers on the line.
"""

import json
import math
import os
import sys
import tempfile

from PIL import Image
from playwright.sync_api import sync_playwright

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.abspath(sys.argv[1])
LEDGER = os.path.join(HERE, "..", "..", "..", "Tests", "BlessTests", "Fixtures", "site", "ledger.json")
PLAYFAIR = os.path.expanduser("~/Library/Fonts/PlayfairDisplay-Italic-VariableFont_wght.ttf")

# The family's hero colours (Braid's README_Assets/src/build.py): blue the model's drafts, gold the reviewer's seal,
# green the patient, the pale line what crosses.
BLUE, GREEN, GOLD, LINE = "#5e8fda", "#28a883", "#c7a659", "#cbc8c0"

Y = 469              # the motif's centre line, as in Braid's and AII's heroes
X0 = 68              # the drafts start at the title's leading edge
SEAL = 600           # the reviewer's seal, at the centre
WORDS_END = 1046     # the digests stop here; the green line runs on into the patient's mark at 1102
MARK = 1102


def shoot(browser, page_html, path, viewport=(1200, 630), scale=2, prepare=None):
    """Writes `page_html` beside the inputs (so relative URLs resolve) and screenshots it, after the fonts load and
    `prepare` (JavaScript) has run."""
    with tempfile.NamedTemporaryFile("w", suffix=".html", dir=HERE, delete=False, encoding="utf-8") as f:
        f.write(page_html)
        name = f.name
    try:
        page = browser.new_page(device_scale_factor=scale, viewport={"width": viewport[0], "height": viewport[1]})
        page.goto("file://" + name)
        page.evaluate("document.fonts.ready.then(() => true)")
        if prepare:
            page.evaluate(prepare)
        page.wait_for_timeout(150)
        page.screenshot(path=path, full_page=True)
        page.close()
    finally:
        os.unlink(name)


def strand(phase, x1, amplitude=40, period=250):
    """Braid's strand: a sine whose amplitude decays to nothing as it reaches x1."""
    points, x = [], X0
    while x <= x1:
        t = (x - X0) / (x1 - X0)
        a = amplitude * (1 - t) ** 1.25
        points.append((x, Y + a * math.sin(2 * math.pi * (x - X0) / period + phase)))
        x += 3
    return "M" + " L".join(f"{px:.1f},{py:.1f}" for px, py in points)


def hero(browser, ledger):
    held = next(e for e in ledger["events"] if e["kind"] == "submitted")
    sent = next(e for e in ledger["events"] if e["kind"] == "released")
    # The draft that was held and the text that was sent: two digests, because the reviewer amended it.
    stages = [("held", held["digest"][:6]), ("sent", sent["digest"][:6])]
    words = "".join(f'<span class="stage"><small>{name}</small> {value}</span>' for name, value in stages)
    # Two drafts braid into the seal; a third, withheld, fades out before it reaches it.
    drafts = "".join(f'<path d="{strand(phase, SEAL - 10)}" fill="none" stroke="{BLUE}" stroke-width="3.6" stroke-linecap="round" stroke-opacity="{op}"/>'
                     for phase, op in [(math.pi * 0.62, 1), (math.pi * 1.95, 0.72)])
    withheld = f'<path d="{strand(math.pi * 1.28, SEAL - 54, amplitude=44)}" fill="none" stroke="{BLUE}" stroke-width="3.6" stroke-linecap="round" mask="url(#fade)"/>'
    page = f"""<!doctype html><html><head><meta charset="utf-8"><style>
@font-face {{ font-family: "Playfair"; font-style: italic; font-weight: 400 900; src: url("file://{PLAYFAIR}") format("truetype"), local("Playfair Display Italic"); }}
html, body {{ margin: 0; width: 1200px; height: 630px; overflow: hidden; }}
body {{ position: relative; font-family: "Playfair", Georgia, serif; font-style: italic;
       background: radial-gradient(ellipse 90% 100% at 22% 20%, #20201c 0%, #191917 45%, #121211 100%); }}
.mark {{ position: absolute; left: 57.5px; top: 52px; width: 72px; }}
.caption {{ position: absolute; left: 143.5px; top: 72px; letter-spacing: .3em; font-size: 16.5px; color: #8b8a84; font-variant-numeric: lining-nums; }}
.title {{ position: absolute; left: 34px; top: 112px; padding-left: 40px; font-size: 220px; line-height: 1; font-weight: 500; letter-spacing: -.005em;
         background: linear-gradient(100deg, #8d9097 0%, #c8cad0 35%, #f2f3f6 58%, #b6b9c1 100%);
         -webkit-background-clip: text; background-clip: text; color: transparent; padding-right: 30px; }}
.sub {{ position: absolute; left: 65.5px; top: 334px; font-size: 45px; color: #9b9991; }}
svg {{ position: absolute; left: 0; top: 0; }}
.words {{ position: absolute; left: {SEAL + 30}px; top: {Y - 21}px; height: 40px; white-space: nowrap; font-size: 27px; line-height: 40px;
          color: {LINE}; font-variant-numeric: lining-nums; }}
.stage {{ margin-right: 18px; }}
.stage small {{ font-size: 16px; color: #8b8a84; letter-spacing: .04em; margin-right: 2px; }}
.legend {{ position: absolute; left: 66px; top: 543px; width: 1050px; display: flex; gap: 32px; align-items: baseline; font-size: 24px; color: #8b8a84; white-space: nowrap; }}
.legend b {{ font-weight: 400; color: #e9e7e0; }}
.dot {{ display: inline-block; width: 13px; height: 13px; border-radius: 50%; margin-right: 10px; transform: translateY(-1px); }}
.tag {{ margin-left: auto; }}
</style></head><body>
<img class="mark" src="rr-mark.png">
<div class="caption">RAO STUDIOS · HUMAN IN THE LOOP</div>
<div class="title">Bless</div>
<div class="sub">every reply held, read, signed, then sent</div>
<svg width="1200" height="630">
  <defs>
    <linearGradient id="fade-x" x1="{X0}" y1="0" x2="{SEAL - 54}" y2="0" gradientUnits="userSpaceOnUse">
      <stop offset="0" stop-color="#fff"/><stop offset="0.55" stop-color="#fff" stop-opacity="0.85"/><stop offset="1" stop-color="#fff" stop-opacity="0"/></linearGradient>
    <mask id="fade" maskUnits="userSpaceOnUse" x="0" y="{Y - 80}" width="1200" height="160">
      <rect x="0" y="{Y - 80}" width="1200" height="160" fill="url(#fade-x)"/></mask>
    <radialGradient id="glow" cx="0.5" cy="0.5" r="0.5">
      <stop offset="0" stop-color="{GOLD}" stop-opacity="0.22"/><stop offset="1" stop-color="{GOLD}" stop-opacity="0"/></radialGradient>
  </defs>
  {withheld}
  {drafts}
  <circle cx="{SEAL}" cy="{Y}" r="34" fill="url(#glow)"/>
  <circle cx="{SEAL}" cy="{Y}" r="11.5" fill="#161614" stroke="{GOLD}" stroke-width="2.6"/>
  <circle cx="{SEAL}" cy="{Y}" r="4.6" fill="{GOLD}"/>
  <line id="tail" x1="{WORDS_END}" y1="{Y}" x2="{MARK - 10}" y2="{Y}" stroke="{GREEN}" stroke-width="3" stroke-linecap="round"/>
  <circle cx="{MARK}" cy="{Y}" r="9.5" fill="none" stroke="{GREEN}" stroke-width="2.4"/>
  <circle cx="{MARK}" cy="{Y}" r="4" fill="{GREEN}"/>
</svg>
<div class="words">{words}</div>
<div class="legend">
  <span><i class="dot" style="background:{BLUE}"></i><b>Model</b> · drafts</span>
  <span><i class="dot" style="background:{GOLD}"></i><b>Reviewer</b> · blesses</span>
  <span><i class="dot" style="background:{GREEN}"></i><b>Patient</b> · receives</span>
  <span class="tag">no reply sent unread</span>
</div>
</body></html>"""
    # The digests end short of the patient's mark; the green line runs from the last into it.
    fit = f"""(() => {{ const w = document.querySelector('.words'), limit = {WORDS_END};
        while (w.getBoundingClientRect().right > limit && w.children.length > 1) w.firstElementChild.remove();
        const last = w.lastElementChild.getBoundingClientRect().right;
        document.getElementById('tail').setAttribute('x1', String(Math.round(last + 14))); }})()"""
    shoot(browser, page, os.path.join(OUT, "hero.png"), prepare=fit)


def main():
    os.makedirs(OUT, exist_ok=True)
    with open(LEDGER, encoding="utf-8") as f:
        ledger = json.load(f)
    with sync_playwright() as p:
        browser = p.chromium.launch(channel="chrome")
        hero(browser, ledger)
        browser.close()
    path = os.path.join(OUT, "hero.png")
    with Image.open(path) as im:
        print(f"hero.png: {im.size[0]}×{im.size[1]}, {os.path.getsize(path) // 1024} KB")


if __name__ == "__main__":
    main()
