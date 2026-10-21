[![Bless, by Rao Studios: every reply held, read, signed, then sent. Three blue strands, the model's drafts, braid toward a gold seal at the centre, the reviewer's; one fades before it reaches the seal, withheld. Past the seal the line carries two digests from a real petition, the draft held, 3b5737, and the different text sent, a79778, and runs in green to the patient's mark. A legend names the model, which drafts, the reviewer, who blesses, and the patient, who receives: no reply sent unread.](Docs/README_Assets/hero.png)](Docs/README_Assets/hero.png)

# Bless

Bless holds a language model's reply until a person who answers for it has read it:
- **The gate** holds every reply the model drafts as a petition. Nothing reaches the person who asked.
- **The reviewer** blesses it, amends it or withholds it, and signs the ruling with a key of their own. Only then does a release go out, carrying the ruling.
- **The ledger** chains every step by SHA-256 and holds ids, digests and codes, never words, so what was sent and who allowed it can be proved later.

The case it was built for is a patient talking to a model while their general practitioner stays responsible for what the patient is told. It is a Swift package, built to be an add-on to [AII](https://github.com/rao-studios/AII)'s Sewn, and it works with any inference layer that speaks the chat-completions wire: Mistral, OpenAI, vLLM, Ollama, LM Studio, a hospital's own gateway.

## The pattern at a glance

```swift
// Package.swift
.package(url: "https://github.com/rao-studios/Bless.git", branch: "main"),
.product(name: "Bless", package: "Bless"), .product(name: "BlessProviders", package: "Bless"),
```

```swift
import Bless
import BlessProviders

let model = OpenAICompatibleProvider(preset: .mistral, apiKey: key)       // or .openAI, .sewn(sewn:), .custom(...)
let gate = Gate(store: try FilePetitionStore(directory: petitions, cipher: try AESGCMCipher(keyData: storeKey)),
                ledger: try Ledger(store: FileLedgerStore(url: ledgerFile)))
let blessed = Blessed(upstream: model, gate: gate) { request in
    Routing(conversationID: visit, recipient: patient, reviewers: [doctor.party],
            policy: Policy(deadline: .seconds(4 * 3600), onLapse: .releaseFallback("Your care team will reply soon.")))
}

let reply = try await blessed.complete(request)              // returns only once a reviewer has ruled

// On the reviewer's device, where their key lives:
try await gate.decide(petitionID, .amend(content: edited), as: doctor)
```

`Blessed` is itself an `InferenceProvider`, so anything that took the model takes it. `complete` throws when a reviewer withholds the reply or the deadline passes with nothing to send; show the patient a neutral notice, never the reviewer's reason.

## Integrating Bless into your chat system

**[Docs/INTEGRATION.md](Docs/INTEGRATION.md) is the guide**, in two parts:
1. **The first party**, the app that talks to the model, wraps it in `Blessed` and opens a review queue: four routes over the Gate, for the pending queue, opening a petition, posting a ruling, and live events.
2. **The third party**, the reviewer's dashboard, pulls what is pending, signs a ruling with the reviewer's own Ed25519 key in the browser, and posts it back.

Its reference section has the JSON, the exact bytes a seal signs and a ledger hash covers, and a Python check that verifies any ledger or seal.

## The playground

[![The playground's window, drawn by its snapshot mode. On the left, the patient Ada Moreno: her question about ibuprofen with lisinopril, the doctor's amended answer marked reviewed and edited by Dr. Okafor, and a second question about a missed sertraline dose, held for review. In the middle, the model: the offline fake provider and its draft, "Yes, take two tablets today", held for review, with its SHA-256. On the right, the reviewer Dr. Okafor: one petition waiting with its countdown, the conversation the policy allows, the draft in an editor, and Bless, a note, and Withhold. Below, the ledger: seven events, submitted, viewed, decided, blessed, released, submitted, viewed, each with its digest and hash, the chain verified.](Docs/README_Assets/playground.png)](Docs/README_Assets/playground.png)

A macOS app that puts a patient, a model and a reviewer in one window at one Gate, against Mistral, any OpenAI-compatible layer, or an offline fake that needs no key. The patient sees only releases; the model's pane shows the draft as it is written; the reviewer blesses, amends or withholds with a sealed identity; the ledger verifies its chain and exports JSON lines.

```sh
Examples/run.sh                          # Mistral, with the key it finds; the offline fake if none
Examples/run.sh --provider fake --scenario medication
```

The key comes from the app's own Keychain item, `MISTRAL_API_KEY`, or `~/.rao/keys/providers.json`, and is never shown. The scenarios are invented: do not type real patient data while a hosted model is selected. [Examples/README.md](Examples/README.md) is the run sheet.

## Bless, step by step

Nine short chapters, each titled as a question, from why a reply is held to what HIPAA asks, with five figures that recompute Bless's own records in the browser: the ledger's chain from its canonical bytes, and a reviewer's Ed25519 seal verified with Web Crypto, broken by editing one word. A code explorer holds every file of the repository with seven trails that walk the code in the order it runs; the first, the whole flow, routes into the rest. Double-click `Scripts/site.command`, or open [Docs/site/index.html](Docs/site/index.html) in a browser; it is plain HTML with no build step. [Docs/site/README.md](Docs/site/README.md) says how it is rebuilt and checked.

Every page has an ask orb that answers questions about what you are looking at, through Mistral's API from the browser. On the owner's Mac, `Scripts/site.command` gives it the local key from a gitignored file. Anywhere else, the orb opens without a key and asks for your own Mistral key, which stays in your browser and goes only to Mistral.

## HIPAA

Bless is built with HIPAA's Security Rule in mind, and it is not certified: compliance belongs to a deployment, not a library. Its ledger supports audit controls and integrity, its seals person authentication, its context window and digest-only log minimum necessary, and its stores encryption at rest. Access control, keys, encryption in transit, retention and every business associate agreement, the model provider's included, stay the deployer's. [Docs/HIPAA.md](Docs/HIPAA.md) maps each safeguard.

## Where it stands (2026-10-20)

| | |
|---|---|
| **Passes** | `Scripts/test.sh`: 82 tests in 10 suites for the core, 16 in 3 for the providers, 12 in 2 for the playground · the canonical bytes match an independent Python implementation, which verifies the Swift seal · a live Mistral run through `Blessed` held a streamed reply whole and released only the amendment · `Docs/site/src/build.sh`: 14 pages in light, dark, phone and storage-blocked modes, every self-check, the explorer, orb and figure tests, no network request |
| **Not yet** | a reference HTTP adapter for the review queue, which the guide sketches · the hook inside AII's Sewn, which must also move Sewn's memory writes after the release · a cryptographic quorum, a k-of-n release over a content key · anchoring the ledger's head outside the host · key revocation · a quorum above one in the playground · any third-party security review |

## Requirements and tests

- Xcode 27 (Swift 6.4). The library runs on macOS 15 and iOS 18; the playground on macOS 26.
- `Scripts/test.sh` builds and runs every suite, then the playground's.
- The site's checks need Python 3 with `playwright`, and Google Chrome.

| Target | Holds |
|---|---|
| `Bless` | the Gate, petitions, policies, rulings, verdicts and releases; the seal; the ledger and its stores; private and AES-GCM petition stores; `Blessed`. Foundation, CryptoKit and Synchronization only: no networking, no UI, no logging |
| `BlessProviders` | `OpenAICompatibleProvider`, with presets for Mistral, OpenAI and Sewn, and server-sent events read byte by byte |
| `Examples/` | the macOS app, a package of its own |

The site's chapters tell the design: the rules by name, the canonical bytes, the ledger, the seal, deadlines, and the seam into an inference layer. The README's pictures are rebuilt by `Docs/README_Assets/src/build.sh`.

GNU General Public License v3.0 (see [LICENSE](LICENSE)).

> *"I am the rest between two notes that barely grow used to each other … But in the dark interval both are reconciled, trembling. And the song stays beautiful." — Rainer Maria Rilke, The Book of Hours*
