# Bless's site

The documentation for Bless as plain HTML read from disk: nine chapters, each titled as a question, with five figures that recompute Bless's own bytes; a code explorer that holds every file of the repository with seven trails through it, the first the whole flow; the run's record; a lexicon; a self-check; and an ask orb on every page. Ported from VeilGarde's `docs/site`, with the figure machinery of Braid's.

Open it with `Scripts/site.command` (double-click it in Finder), or open `Docs/site/index.html` in a browser. Nothing is built or served to read it.

| Page | What it holds |
|---|---|
| `index.html` | Bless at a glance, the gate figure, the tour |
| `01-hold.html` … `09-hipaa.html` | the chapters: why hold the reply, the petition, the reviewer, the ledger, the seal, the deadline, the seam, the playground, HIPAA |
| `code.html` | the code explorer |
| `run.html` | what this run built: the request, the layers lit by each trail step, counts, commands, tests, decisions, open questions |
| `lexicon.html` | the words, as the code spells them |
| `selfcheck.html` | every check the browser can make, with the five figures mounted |

## Rebuilding and checking

```sh
Docs/site/src/build.sh             # the parser's self-test, the data, then every page in Chrome
python3 -I Docs/site/src/build.py  # the data only: data/run.js, index.js, fixtures.js, files/<group>.js
python3 -I Docs/site/src/check.py --prose
python3 -I Docs/site/src/check.py --pages index.html,code.html --shots /tmp/shots
```

Rebuild after any change to the code, the trails, the run's record, the fixtures or the site: the data embeds every file verbatim, and `check.py` fails when a file changed since the build. Reading needs only a browser. Rebuilding needs Python 3 with `playwright`, and Google Chrome.

## The constraints a page lives under

- **From `file://`.** Chrome blocks `fetch` and ES modules there, so every data file is a classic script that adds to `window.BlessData`, and every page loads its scripts with `<script src>`.
- **Two globals.** `Bless` (the code) and `BlessData` (the data). `check.py` fails on a third.
- **One network call.** The orb's, to Mistral's chat API, and only when a reader sends a message. Every check refuses every network request.
- **No HTML from strings.** Every node is built with `Bless.h` and text nodes.
- **Storage may throw.** Every use of `localStorage` is wrapped; the pages work with it blocked.

## The data

`src/build.py` reads the repository from git's empty tree to the working tree, so every file reads as added. It leaves out test fixtures, images, `Package.resolved`, `LICENSE`, anything gitignored, binaries, and any file holding a key-shaped string; the index lists each by name and size.

- **Declarations.** A lexer that knows strings, raw strings, interpolation and comments, and a walk over the braces, ported from Braid's `sources.py` by way of VeilGarde. Each Swift file's declarations are counted twice, by the walk and by their keywords, and the build fails when the two disagree. `--self-test` holds the parser to the hard shapes, Bless's own among them.
- **Ids.** `<path>:<Qualified.name>(<labels>)`, such as `Sources/Bless/Gate/Gate.swift:Gate.release(for:)`.
- **Calls.** Matched by name and argument labels, each edge marked exact, likely or ambiguous.
- **Facts.** The standings, the ledger's kinds, the rulings, the lapses, the release bases and the policy's defaults, read from the Swift. A chapter that lists them marks the list with `data-enum`, and the self-check holds it to the code.
- **Fixtures.** `data/fixtures.js` holds `Tests/BlessTests/Fixtures/site/{ledger,seal}.json`, which `SiteFixturesTests` writes with the real Gate, a fixed clock and a test key. `BLESS_WRITE_FIXTURES=1 swift test --filter SiteFixtures` rewrites them.
- **Size.** The data stays under 3 MB; it is about 1.1 MB.

## The trails

`src/trails.json` holds seven trails, each 3 to 9 steps, each step a few declarations in the order the code runs, with a note, a cite and the chapters that tell it: **F** the whole flow, **H** a reply held, **R** a reviewer's ruling, **T** a deadline, **L** the ledger's chain, **S** the seal, **A** Blessed dropping into an inference layer. The picker lays them out in sections by kind, the whole flow first.

The whole flow is of kind `flow`, and each of its steps lists `routes`: the steps of other trails, such as `reply-held-3`, that tell its stage in depth. The explorer shows them where "next on this trail" sits, in the card and in the strip above the code: **Go deeper** on a step of the whole flow, and on any other step **In the whole flow**, the flow step that routes there and the one after it. `build.py` fails on a route that names no step, on a route from a trail that is not a flow, on a flow step that routes nowhere, and when the whole flow reaches no step of some trail; the self-check holds the same, and that every step of every trail leads back into the flow. Every anchor is a line that must still be inside its declaration; a cite is `PIN`, `WHAT`, `test:<name>`, `doc:<declaration>`, `run#<id>`, `chapter:<page>#<id>` or `<file>.md#<heading>`, and the build fails on one that does not resolve.

Deep links: `code.html#<path>`, `#<path>:<line>`, `#<id>`, `#trail-<id>-<n>`, `#trail-<id>-<n>;n=<k>`, `#q=<text>`.

## The figures

A figure is `<figure class="fig" data-fig="<name>">` with a figcaption. `Bless.define(name, { title, params, render, selfCheck })` registers it (`js/bless.js`, Braid's machinery); `#fig-<name>;key=value` sets it from a link, and its link button copies one.

| Figure | Chapter | What it recomputes |
|---|---|---|
| `gate` | index, 1 | the fixture's texts and ledger lines through six steps; checked against the fixture's real ledger |
| `petition-states` | 2, 3 | the standings and releases; checked against `Petition.Standing` and `Release.Basis` |
| `ledger-chain` | 4 | every fixture hash, from bless/event/1 written in `js/hash.js`; a forged field stops verify at its event |
| `seal` | 5 | the fixture's Ed25519 seal, verified with Web Crypto over bless/verdict/1; an edited word refuses it |
| `deadline` | 6 | the lapse rules; checked against `Policy.Lapse` and the policy's default |

`js/hash.js` writes the canonical layouts again, field for field, and the self-check holds them to the bytes Swift wrote.

## The ask orb

Every page has an orb at the bottom right. It opens into a chat about what the reader is looking at: on the code explorer the selected declaration, a map of the whole codebase and four tools that read the rest from the data the page holds; on any other page the page's text. It calls `https://api.mistral.ai/v1/chat/completions` from the browser, streamed, `mistral-large-4` with reasoning off.

- **The owner's key.** `src/askkey.py` reads `MISTRAL_API_KEY`, else `~/.rao/keys/providers.json`, and writes `local/ask.js` with mode 600, only after git confirms it ignores that path. `Scripts/site.command` runs it before it opens the site. It never prints the key.
- **Anyone else's.** Without `local/ask.js`, the chat opens a dialog that asks for the reader's own Mistral key. The key stays in that browser and goes only to Mistral. A key Mistral refuses is forgotten and asked for again; "Forget the key" is beside the chat. `?ask-key=none` on any page shows the site as another engineer sees it.
- **Tested without Mistral.** The checks replace the orb's transport with a stand-in and block every network request.

## The checks

`src/check.py` fails on: data not exactly as `build.py` writes it, an embedded file that changed since the build, a link or `#id` that does not resolve, a link that leaves the site, a third global, an ES module, a `fetch` outside the orb, an absolute path, `local/` not ignored, the key's value in any file git can see, a banned phrase or a parenthesis in prose. In Chrome, every page in light, dark, 390 px light and dark, and with storage blocked: no console error, no failed request, no network request, no sideways scroll, the right background, every self-check. On `code.html` it drives the explorer; on the ledger and seal chapters it forges an event and edits a seal; on `index.html`, `code.html` and a chapter it runs the orb's stand-in test, and on `index.html` the key dialog.

## The voice

Say the idea first, one move to a paragraph, in plain words and short sentences. No hedging, no parentheses inside a paragraph, no "simply", "just", "note that" or "basically". Every number names where it came from. `check.py --prose` lists the rest.
