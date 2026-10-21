/*
 * The seal: the fixture's sealed amendment, verified here with Web Crypto's Ed25519 against the reviewer's public
 * key. Edit the amended text and the same signature no longer verifies: the seal covers the words. "Sign it here"
 * makes a key pair in this browser and seals the edited text, as a reviewer's device would. Where the browser has
 * no Ed25519, the figure shows the bytes and says it could not verify them.
 *
 * SPDX-License-Identifier: GPL-3.0-only
 */
(function () {
  "use strict";
  var B = window.Bless, h = B.h;
  var results = {}, own = null, ownSigs = {};
  function fixture() { return (B.data().fixtures || {}).seal || null; }
  function verdictWith(text) {
    var v = JSON.parse(JSON.stringify(fixture().verdict));
    if (v.ruling.kind === "amend") v.ruling.content = text;
    return v;
  }
  /** Verifies once per bytes and key, then redraws with the answer. */
  function check(keyHex, sigHex, bytesHex, ctx, publicRaw, sig, bytes) {
    var k = keyHex + ":" + sigHex + ":" + bytesHex;
    if (results[k] === undefined) {
      results[k] = "pending";
      B.ed25519.verify(publicRaw, sig, bytes).then(function (ok) { results[k] = ok; ctx.redraw(); });
    }
    return results[k];
  }
  function verdictLine(r, what) {
    if (r === "pending") return h("p", { class: "seal-result wait" }, "Verifying with Web Crypto…");
    if (r === null) return h("p", { class: "seal-result wait" }, "This browser has no Ed25519 in Web Crypto: the bytes are shown, not verified.");
    return h("p", { class: "seal-result " + (r ? "ok" : "bad") }, r ? "✓ " + what + " verifies over these bytes." : "✗ " + what + " does not verify: the bytes it signed are not these.");
  }
  B.define("seal", {
    title: "The seal: a reviewer's signature over the exact words",
    params: { text: { type: "string", default: "", link: false } },
    render: function (body, state, ctx) {
      var fx = fixture();
      if (!fx) { body.appendChild(h("p", { class: "fig-error" }, "The fixtures are not in the data: run Docs/site/src/build.sh.")); return; }
      var original = fx.verdict.ruling.content || "", text = state.text === "" || state.text === undefined ? original : state.text;
      var v = verdictWith(text), canon = B.canonical.verdict(v), bytesHex = B.hex(canon.bytes);
      var area = h("textarea", { "aria-label": "The amended text the reviewer sealed", "data-key": "seal-text" }, text);
      area.addEventListener("input", function () { ctx.set({ text: area.value }); });
      var publicRaw = B.fromHex(fx.publicKey), sig = B.fromBase64(fx.verdict.signature);
      var r = check(fx.publicKey, fx.signature, bytesHex, ctx, publicRaw, sig, canon.bytes);
      var left = h("div", null, [
        h("h4", null, "The verdict"),
        h("dl", { class: "kv" }, [
          h("dt", null, "petition · reviewer"), h("dd", null, v.petitionID + " · " + v.reviewer),
          h("dt", null, "ruling"), h("dd", null, v.ruling.kind),
          h("dt", null, "the text the reviewer read, as SHA-256"), h("dd", null, v.digest),
          h("dt", null, "note"), h("dd", null, v.note || "none"),
          h("dt", null, "issued, in milliseconds"), h("dd", null, String(v.issued))
        ]),
        h("h4", { style: "margin-top:.7rem" }, "The amended text: edit it"),
        h("div", { "data-keep": "seal-text" }, area),
        h("div", { class: "fig-controls", style: "margin:.5rem 0 0" }, [
          h("button", { type: "button", onclick: function () { ctx.set({ text: "" }); }, disabled: text === original }, "Restore"),
          h("button", { type: "button", onclick: function () {
            B.ed25519.generate().then(function (pair) {
              if (!pair) { own = { none: true }; ctx.redraw(); return; }
              own = pair;
              ctx.redraw();
            });
          } }, own && !own.none ? "New key" : "Sign it here")
        ])
      ]);
      var right = h("div", null, [
        h("h4", null, "Signed by " + fx.reviewer.displayName),
        h("dl", { class: "kv" }, [
          h("dt", null, "public key, 32 bytes"), h("dd", null, fx.publicKey),
          h("dt", null, "signature, 64 bytes"), h("dd", null, fx.signature)
        ]),
        verdictLine(r, "Dr. Okafor's signature"),
        h("h4", { style: "margin-top:.7rem" }, "What it signs: bless/verdict/1, " + canon.bytes.length + " bytes"),
        h("div", { class: "bytes" }, canon.marks.map(function (m) {
          return h("span", { class: m.label === "tag" ? "tag" : m.label === "content" && text !== original ? "changed" : null, title: m.label }, B.hex(canon.bytes.slice(m.at, m.at + m.length)) + " ");
        }))
      ]);
      if (own && own.none) right.appendChild(h("p", { class: "seal-result wait" }, "This browser cannot make an Ed25519 key."));
      else if (own) {
        var pub = B.hex(own.publicRaw), key = pub + ":" + bytesHex;
        if (!ownSigs[key]) { ownSigs[key] = "pending"; B.ed25519.sign(own.privateKey, canon.bytes).then(function (s) { ownSigs[key] = s; ctx.redraw(); }); }
        var mine = ownSigs[key];
        right.appendChild(h("h4", { style: "margin-top:.7rem" }, "Sealed here, with a key made in this browser"));
        right.appendChild(h("dl", { class: "kv" }, [h("dt", null, "public key"), h("dd", null, pub), h("dt", null, "signature"), h("dd", null, mine && mine !== "pending" ? B.hex(mine) : "signing…")]));
        if (mine && mine !== "pending") right.appendChild(verdictLine(check(pub, B.hex(mine), bytesHex, ctx, own.publicRaw, mine, canon.bytes), "Your signature"));
      }
      body.appendChild(h("div", { class: "seal-grid" }, [left, right]));
    },
    selfCheck: function () {
      var fx = fixture(), ledger = (B.data().fixtures || {}).ledger;
      if (!fx || !ledger) return [{ name: "the fixtures are loaded", ok: false }];
      return [
        { name: "the verdict's canonical bytes, written here, equal the bytes Swift signed", ok: B.hex(B.canonical.verdict(fx.verdict).bytes) === fx.canonical },
        { name: "the verdict pins the model's draft: its digest is the SHA-256 of the text the ledger held", ok: fx.verdict.digest === B.digest(ledger.texts.proposed) },
        { name: "the amendment it signs is the text the ledger released", ok: B.digest(fx.verdict.ruling.content) === ledger.events[4].digest },
        { name: "the reviewer's verifying key is the public key shown", ok: B.hex(B.fromBase64(fx.reviewer.verifyingKey)) === fx.publicKey && B.hex(B.fromBase64(fx.verdict.signature)) === fx.signature }
      ];
    }
  });
})();
