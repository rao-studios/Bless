# Bless and HIPAA

Bless is built with HIPAA's safeguards in mind. It is not certified, and no library is HIPAA compliant on its own: compliance belongs to a deployment, its people and its agreements. This page says which safeguards Bless's design supports, and which remain the deployer's. It is engineering guidance, not legal advice.

## What Bless is for

A covered entity that lets patients talk to a language model needs a clinician to stay responsible for what the patient is told. Bless makes that responsibility structural: every reply is held until a reviewer blesses, amends or withholds it, and the decision is signed and logged.

## The Security Rule's technical safeguards (45 CFR 164.312)

| Safeguard | What Bless provides | What the deployer must do |
|---|---|---|
| **Access control**, §164.312(a)(1) | Petition and ledger files are created 0600 in 0700 directories. Reviewers are named per petition; a verdict from anyone else is refused. | Authenticate users and reviewers; unique user ids; emergency access; automatic logoff; who may read the store. |
| **Encryption at rest**, §164.312(a)(2)(iv), addressable | `FilePetitionStore` with `AESGCMCipher` (AES-256-GCM) keeps petitions encrypted on disk. | Supply and protect the key (Keychain, Secure Enclave, a KMS); rotate it; encrypt backups; or store petitions in an encrypted database. |
| **Audit controls**, §164.312(b) | A hash-chained ledger records every submission, view, verdict, lapse, withdrawal, release and delivery, with who and when. `Ledger.verify` detects any change, gap or reordering. | Retain the ledger (documentation is kept six years, §164.316(b)(2)); review it (§164.308(a)(1)(ii)(D)); copy its head hash somewhere the application cannot rewrite. |
| **Integrity**, §164.312(c)(1) and (c)(2) | Every text is pinned by SHA-256. A release is verified against its petition: the digest, the quorum, every reviewer's seal. A verdict cannot apply to a text the reviewer did not read. | Protect the stores from deletion; back them up. |
| **Person or entity authentication**, §164.312(d) | Each verdict is signed with the reviewer's Ed25519 key and verified against their registered public key. | Issue keys to verified reviewers; keep private keys on their devices; revoke a key when a reviewer leaves (Bless has no revocation list). |
| **Transmission security**, §164.312(e)(1) | `BlessProviders` uses HTTPS to hosted models. | TLS between every party (patient, host, reviewer, model); a business associate agreement with every service that receives PHI. |

## Minimum necessary (§164.502(b), §164.514(d))

- A petition keeps only the latest messages the policy's `contextWindow` allows, and never the system prompt.
- The ledger holds no content and no free text: texts appear only as SHA-256 digests, rulings and errors only as code names. A withholding reason stays in the petition store, not in the log an auditor reads.
- The core library writes no logs at all; the layering test forbids `print` and unified logging in `Sources/`.

## What Bless does not do

- **It is not a business associate agreement.** Sending PHI to a model provider (Mistral, OpenAI, any hosted API) requires that provider's BAA, or a model you host. The playground uses invented scenarios; do not type real patient data into it with a hosted key.
- **It does not authenticate users** or decide who is a reviewer. The host builds the `Party` values, and its review queue decides who may read a petition ([INTEGRATION.md](INTEGRATION.md#4-open-the-review-queue)).
- **It does not store keys.** The host's key management does.
- **It does not anchor the ledger** outside the host; the [README](../README.md#where-it-stands-2026-10-20) lists it as not yet done.
- **It does not make clinical judgments.** A reviewer's blessing is a person's decision; Bless records it.

Before go-live, work through the checklist at the end of [INTEGRATION.md](INTEGRATION.md#8-before-go-live).
