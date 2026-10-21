# The Bless playground

A macOS app that shows the human-in-the-loop pattern working: a patient, a model and a reviewer in one window, at one Gate. Nothing the model writes reaches the patient until the reviewer rules on it.

## Run it

```sh
Examples/run.sh                        # Mistral, with the key it finds (or the offline fake if none)
Examples/run.sh --provider fake        # no key, no network
Examples/run.sh --scenario medication  # fills the composer: medication, fever, missed-dose
Examples/run.sh --model mistral-large-latest
Examples/run.sh clean
```

`run.sh` builds the app in release and runs the binary. From Xcode, open `Examples/Package.swift` and Run. Do not use `swift run`: AppKit reads a bare path in argv as a document and opens no window.

## A demo in five steps

1. Choose **Scenario ▸ Ibuprofen with lisinopril** and press **Send** (⌘↩).
2. Watch the **Model** pane write the draft. The patient sees only "Held for review".
3. In the **Reviewer** pane, read the conversation and the draft. Edit it, then press **Amend and Release** (⌘⇧A), or **Bless** (⌘B) to send it as written.
4. The **Patient** pane shows the released text, marked "Reviewed and edited by Dr. Okafor".
5. In the **Ledger**, press **Verify Chain**. Each event is listed with digests only; the text itself is not in the ledger.

Try **Withhold** with a reason (the patient gets a neutral notice, never the reason), **Withdraw** while a reply is held, or a 15-second deadline under **Policy** to watch a lapse.

## The key

The app looks for a Mistral key in this order:
1. its own Keychain item (service `nyc.rao.bless.playground`), saved with **Key…**;
2. `MISTRAL_API_KEY` in the environment;
3. `~/.rao/keys/providers.json`.

**Forget** removes only the app's own item. The key is never shown or logged. With no key, the app opens on the offline fake model.

Do not type real patient data while a hosted model is selected: the provider would need a business associate agreement ([HIPAA.md](../Docs/HIPAA.md)).

## Where things are kept

| What | Where |
|---|---|
| The key you save | the Keychain, service `nyc.rao.bless.playground` |
| The reviewer's signing key | `~/Library/Application Support/nyc.rao.bless.playground/reviewer.json`, mode 0600 |
| Provider and policy choices | the app's defaults (`nyc.rao.bless.playground`) |
| Petitions and the ledger | memory, for this session; **Export JSONL…** saves the ledger |

## Tests and pictures

```sh
swift test --package-path Examples                                  # the whole flow on the fake model, no window
.build/…/BlessPlayground --snapshot demo --out playground.png [--dark] # draws the window off screen
```

The README's picture of the app comes from the snapshot mode (`Docs/README_Assets/src/build.sh`).

## Troubleshooting

- **No window appears.** An argument without a flag was passed; run through `run.sh`.
- **The window opens behind other apps.** macOS gives focus only to an app launched by the app you are using. Launched from your own Terminal it comes forward; launched from a background process, click its Dock icon.
- **"Mistral needs a key".** Add one under **Key…**, or choose **Offline fake**.
- **A 401 from Mistral.** The key was rejected: save a new one, or press **Check** to test it.
