# Integrating Bless

Bless keeps a language model's reply from reaching a user until a trusted person approves it. Two parties build on it:

1. **The first party** runs the chat: the app that talks to the model and to the user, such as a clinic's patient app. It holds every reply at a Gate and opens a review queue.
2. **The third party** approves: the reviewer's tool, such as a doctor's dashboard. It pulls what is pending from that queue, and sends back a signed ruling.

One rule joins them: **nothing reaches the user but a Release**, and a Release exists only after a reviewer has ruled.

```
user ──▶ first party ──▶ model
             │ the draft is held at the Gate
             ▼
        review queue  ◀────────── third party: the reviewer's app
             │                      pulls what is pending, signs a ruling
             ▼
          Release ──▶ user
```

## Part 1 · The first party: hold every reply

### 1. Add the package

```swift
// Package.swift
.package(url: "https://github.com/rao-studios/Bless.git", branch: "main"),
.product(name: "Bless", package: "Bless"),
.product(name: "BlessProviders", package: "Bless"),
```

### 2. Wrap the model

```swift
import Bless
import BlessProviders

let gate = Gate(store: try FilePetitionStore(directory: petitionsURL, cipher: try AESGCMCipher(keyData: storeKey)),
                ledger: try Ledger(store: FileLedgerStore(url: ledgerURL)))

let model = OpenAICompatibleProvider(preset: .mistral, apiKey: key)   // or .openAI, .sewn(sewn:), .custom(name:baseURL:)
let blessed = Blessed(upstream: model, gate: gate) { request in
    Routing(conversationID: visit.id, recipient: patient, reviewers: [doctor],
            policy: Policy(deadline: .seconds(4 * 3600), onLapse: .releaseFallback("Your care team will reply soon.")))
}

do {
    let reply = try await blessed.complete(request)   // returns only once a reviewer has ruled
    send(reply)
} catch let error as BlessError {
    showNotice()                                      // withheld, expired or withdrawn: a neutral notice
}
```

That is the whole change on the chat side: call `blessed` where you called `model`. Show the user a neutral notice when nothing is released, never the reviewer's reason. A streaming client calls `blessed.stream(request)`: its first delta carries only the petition's id, so the app can say "your care team is reviewing this", and the blessed text follows as one piece.

`doctor` is the reviewer's `Party`: their id, their name, and the public key their app registered (Part 2, step 1).

### 3. Keep the records

- **Stores.** Petitions are private files, sealed with AES-GCM when given a key; the ledger is a private JSON-lines file. To use your database instead, conform it to `PetitionStore` and `LedgerStore`.
- **Deadlines.** Call `try await gate.sweep()` on a timer, once a minute. A waiting caller also wakes itself at its deadline.
- **One owner.** One process owns the Gate. Nothing else may open its files: the ledger's last hash lives in that process, and a second writer would fork the chain.

### 4. Open the review queue

The Gate lives in your process, so the reviewer's app reaches it through an API you serve. Four routes cover it:

| Route | Gate call | Returns |
|---|---|---|
| `GET /reviewers/{id}/petitions` | `pending(for:)` | the reviewer's queue |
| `GET /petitions/{id}` | `markViewed(_:by:)`, then `petition(_:)` | one petition, and the ledger records who opened it |
| `POST /petitions/{id}/verdicts` | `decide(_:)` | the petition after the ruling |
| `GET /reviewers/{id}/events` | `observe()` | server-sent events, one per change |

As plain handlers, for any web framework:

```swift
/// What the reviewer's app needs: the petition, the text the user would get now, and its digest, which a
/// verdict must name.
struct ForReview: Encodable {
    let petition: Petition
    let message: ChatMessage
    let digest: Sha256
    init(_ p: Petition) { petition = p; message = p.message; digest = p.digest }
}

struct ReviewQueue {
    let gate: Gate

    func pending(for reviewer: Party.ID) async throws -> Data {
        try JSONCoding.encoder().encode(try await gate.pending(for: reviewer).map(ForReview.init))
    }

    func open(_ id: Petition.ID, by reviewer: Party.ID) async throws -> Data {
        try await gate.markViewed(id, by: reviewer)
        return try JSONCoding.encoder().encode(ForReview(try await gate.petition(id)))
    }

    func rule(_ body: Data, by reviewer: Party.ID) async throws -> Data {
        let verdict = try JSONCoding.decoder().decode(Verdict.self, from: body)
        guard verdict.reviewer == reviewer else { throw BlessError.notAReviewer(reviewer) }   // only for oneself
        return try JSONCoding.encoder().encode(ForReview(try await gate.decide(verdict)))       // the seal is checked here
    }

    func events(for reviewer: Party.ID, send: (Data) async -> Void) async throws {
        for await petition in await gate.observe() where petition.reviewer(reviewer) != nil {
            await send(Data("data: ".utf8) + (try JSONCoding.encoder().encode(ForReview(petition))) + Data("\n\n".utf8))
        }
    }
}
```

`reviewer` is the id of whoever signed in to your API. The queue carries patients' words, so:
- authenticate the reviewer, and map the sign-in to their `Party.ID`;
- serve each reviewer only the petitions that name them;
- serve it over TLS.

The seal proves who ruled. It does not decide who may read.

Map refusals to statuses the app can act on:

| `BlessError` | Status | The reviewer's app |
|---|---|---|
| `staleVerdict` | 409 | someone amended the text since it loaded: reload, read again |
| `alreadyDecided` | 409 | another reviewer ruled, or the deadline passed: drop it from the queue |
| `badSeal`, `sealRequired` | 422 | the signature does not verify: check the key the app registered |
| `notAReviewer` | 403 | not this reviewer's petition |
| `unknownPetition` | 404 | gone |

## Part 2 · The third party: approve what is pending

### 1. Give each reviewer a key

Each reviewer signs with an Ed25519 key that never leaves their device. In a browser:

```js
const keys = await crypto.subtle.generateKey({ name: "Ed25519" }, false, ["sign", "verify"]);   // the private key cannot be exported
const publicKey = new Uint8Array(await crypto.subtle.exportKey("raw", keys.publicKey));         // 32 bytes: register these
```

Keep `keys.privateKey` in IndexedDB, and send the public key to the first party once. They put it on the reviewer's `Party` as `verifyingKey`. A Swift app uses `ReviewerIdentity` instead, which holds the private key as 32 bytes for the keychain.

### 2. Pull the queue

Fetch it, and keep it fresh from the event stream:

```js
let queue = await (await fetch(`/reviewers/${me}/petitions`)).json();
new EventSource(`/reviewers/${me}/events`).onmessage = e => {
  const item = JSON.parse(e.data);
  queue = queue.filter(q => q.petition.id !== item.petition.id);
  if (item.petition.standing === "pending") queue.push(item);
};
```

Polling the first route works too. Each item is a `ForReview`: `petition`, `message` and `digest`.

### 3. Show the petition

- **The question.** `petition.context` holds the conversation the policy lets a reviewer see. It never holds the system prompt.
- **The reply.** `message.content` is the text the user would get. Let the reviewer edit it to amend.
- **The deadline.** `petition.deadline` is milliseconds since 1970.

Open the petition through `GET /petitions/{id}`, so the ledger records who read it.

### 4. Sign the ruling and send it

A ruling is `{"kind": "bless"}`, `{"kind": "amend", "content": …}` or `{"kind": "withhold", "reason": …}`. The seal signs a fixed byte layout, written out here:

```js
function verdictBytes(v) {                      // bless/verdict/1
  const enc = new TextEncoder(), parts = [];
  const u32 = n => { const b = new Uint8Array(4); new DataView(b.buffer).setUint32(0, n); return b; };
  const str = s => { const u = enc.encode(s); parts.push(u32(u.length), u); };
  const hex = h => parts.push(Uint8Array.from(h.match(/../g), x => parseInt(x, 16)));
  str("bless/verdict/1"); str(v.petitionID); str(v.reviewer); str(v.ruling.kind);
  if (v.ruling.kind === "amend") str(v.ruling.content);
  if (v.ruling.kind === "withhold") str(v.ruling.reason);
  hex(v.digest);
  if (v.note == null) parts.push(new Uint8Array([0])); else { parts.push(new Uint8Array([1])); str(v.note); }
  const t = new Uint8Array(8), dv = new DataView(t.buffer);
  dv.setUint32(0, Math.floor(v.issued / 2 ** 32)); dv.setUint32(4, v.issued >>> 0); parts.push(t);
  const out = new Uint8Array(parts.reduce((n, p) => n + p.length, 0));
  parts.reduce((at, p) => (out.set(p, at), at + p.length), 0);
  return out;
}

async function rule(item, ruling, note) {
  const verdict = { petitionID: item.petition.id, reviewer: me, ruling, digest: item.digest,
                    issued: Date.now(), ...(note ? { note } : {}) };
  const sig = await crypto.subtle.sign({ name: "Ed25519" }, keys.privateKey, verdictBytes(verdict));
  verdict.signature = btoa(String.fromCharCode(...new Uint8Array(sig)));
  return fetch(`/petitions/${item.petition.id}/verdicts`, { method: "POST", body: JSON.stringify(verdict) });
}

await rule(item, { kind: "amend", content: edited }, "dose");
```

Sign over `item.digest`, the digest of the text the reviewer read. If the text changed since, the Gate refuses the verdict as stale: reload and read again. A Swift app does the same in two lines:

```swift
let verdict = try doctor.verdict(.amend(content: edited), on: petition, note: "dose")
let body = try JSONCoding.encoder().encode(verdict)       // POST it to /petitions/{id}/verdicts
```

### 5. What happens next

The first party's Gate checks the seal and applies the ruling. A blessing or an amendment releases the text to the user. A withholding releases nothing, and the reason stays in the first party's records. With two or more reviewers required, an amendment needs the others to bless the amended text.

## Reference

### The JSON

All Bless JSON has sorted keys, timestamps as integer milliseconds since 1970, digests as lowercase hex and bytes as base64. A queue item:

```json
{
  "digest": "3b573785a1ad8e4ea122cd4f6196aa8a65ad9af827f37bb85c8ee0da345d0f87",
  "message": {"role": "assistant", "content": "Yes, ibuprofen is fine with lisinopril for a few days."},
  "petition": {
    "id": "p-7f3a", "conversationID": "visit-0412", "standing": "pending",
    "submitted": 1760961600000, "deadline": 1760976000000,
    "context": [{"role": "user", "content": "Can I take ibuprofen with my lisinopril for a sore knee?"}],
    "proposed": {"role": "assistant", "content": "Yes, ibuprofen is fine with lisinopril for a few days."},
    "recipient": {"id": "patient-ada", "displayName": "Ada"},
    "reviewers": [{"id": "dr-okafor", "displayName": "Dr. Okafor", "verifyingKey": "iojj3XQJ8ZX9UtstPLpd…"}],
    "policy": {"quorum": 1, "deadlineMilliseconds": 14400000, "onLapse": "withhold", "allowsAmendment": true, "requiresSeal": true},
    "provenance": {"provider": "mistral", "model": "mistral-small-latest", "requestID": "cmpl-0412", "created": 1760961600000},
    "verdicts": []
  }
}
```

A verdict, as the reviewer's app posts it:

```json
{"petitionID": "p-7f3a", "reviewer": "dr-okafor", "issued": 1760961835000, "note": "NSAID with an ACE inhibitor",
 "ruling": {"kind": "amend", "content": "Please avoid ibuprofen with lisinopril: …"},
 "digest": "3b573785a1ad8e4ea122cd4f6196aa8a65ad9af827f37bb85c8ee0da345d0f87",
 "signature": "IFr5Z+JCduGLixS91vg9…"}
```

The key and the signature are shortened here: they are 32 and 64 bytes in base64.

### The signed bytes

Signatures and ledger hashes cover a fixed layout, not JSON:

| Form | Bytes |
|---|---|
| string | UInt32 big-endian byte count, then the UTF-8 bytes |
| int64 | 8 bytes big-endian |
| sha256 | the 32 raw bytes |
| optional | `0x00` when absent; `0x01` then the value |

| Record | Fields, in order |
|---|---|
| verdict, `bless/verdict/1` | the tag, petitionID, reviewer, ruling kind, then the amendment's content or the withholding's reason, digest, note (optional), issued |
| ledger event, `bless/event/1` | the tag, seq, at, kind, petitionID, actor (optional), digest (optional), code (optional), previous |

A seal is Ed25519 over a verdict's bytes. An event's hash is SHA-256 over its bytes, and `previous` is the hash before it.

### Checking records anywhere

Anyone holding an export can check it. In Python, with `cryptography`:

```python
import hashlib, struct
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PublicKey

def string(v): b = v.encode(); return struct.pack(">I", len(b)) + b
def opt_string(v): return b"\x00" if v is None else b"\x01" + string(v)
def int64(v): return struct.pack(">q", v)
def opt_digest(h): return b"\x00" if h is None else b"\x01" + bytes.fromhex(h)

def event_bytes(e):
    return (string("bless/event/1") + int64(e["seq"]) + int64(e["at"]) + string(e["kind"]) + string(e["petitionID"])
            + opt_string(e.get("actor")) + opt_digest(e.get("digest")) + opt_string(e.get("code")) + bytes.fromhex(e["previous"]))

def verdict_bytes(v):
    r = v["ruling"]
    out = string("bless/verdict/1") + string(v["petitionID"]) + string(v["reviewer"]) + string(r["kind"])
    out += string(r["content"]) if r["kind"] == "amend" else string(r["reason"]) if r["kind"] == "withhold" else b""
    return out + bytes.fromhex(v["digest"]) + opt_string(v.get("note")) + int64(v["issued"])

previous = "00" * 32
for i, e in enumerate(events, start=1):        # a ledger export, one JSON object per line
    assert e["seq"] == i and e["previous"] == previous and hashlib.sha256(event_bytes(e)).hexdigest() == e["hash"]
    previous = e["hash"]

Ed25519PublicKey.from_public_bytes(public_key).verify(signature, verdict_bytes(verdict))   # raises if forged
```

Bless's tests hold its Swift bytes to vectors this Python computed.

### Inference layers

| Layer | Preset | Note |
|---|---|---|
| Mistral | `.mistral` | bearer key |
| OpenAI | `.openAI` | bearer key |
| AII's Sewn | `.sewn(sewn: ["owner_id": …, "scope": …])` | loopback, no key; the preset sends the `sewn` object the chat route requires. Sewn writes a conversation into the person's memory before it returns, so until a hook inside Sewn moves that write after the release, unreviewed drafts reach Sewn's memory |
| vLLM, Ollama, LM Studio, a gateway | `.custom(name:baseURL:)` | any `/chat/completions` server |

### Before go-live

- [ ] Every path that sends model text to a user goes through `Blessed`, or delivers only a `Release`.
- [ ] The review queue authenticates reviewers, serves each only their petitions, and runs over TLS.
- [ ] Reviewers' private keys stay on their devices; their public keys are registered on their `Party`.
- [ ] Petitions are stored encrypted; the store key is in your key management.
- [ ] The ledger is kept for your retention period, and a copy of its last hash is kept where the app cannot rewrite it.
- [ ] Every service that receives patient data, the model provider included, has a business associate agreement ([HIPAA.md](HIPAA.md)).
- [ ] A dry run in the [playground](../Examples/README.md) has shown the team the flow.
