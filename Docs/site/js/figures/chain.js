/*
 * The ledger's chain: the fixture's five events, each hash recomputed here from its canonical bytes and the hash
 * before it. Change a field of one event and watch where Ledger.verify would stop; re-hash the changed event to
 * hide it and the break moves to the next link. The bytes are bless/event/1, written by js/hash.js.
 *
 * SPDX-License-Identifier: GPL-3.0-only
 */
(function () {
  "use strict";
  var B = window.Bless, h = B.h;
  var FIELDS = [{ value: "code", label: "its code" }, { value: "kind", label: "its kind" }, { value: "actor", label: "its actor" }];
  function fixture() { return (B.data().fixtures || {}).ledger || null; }
  /** The events after an edit, and what verify finds. Pure. */
  function chain(events, edit) {
    var rows = [], previous = "0".repeat(64), firstBad = null;
    events.forEach(function (e, i) {
      var ev = Object.assign({}, e), edited = edit && edit.index === i && edit.value !== String(e[edit.field] === undefined || e[edit.field] === null ? "" : e[edit.field]);
      if (edited) ev[edit.field] = edit.value === "" ? undefined : edit.value;
      var bytes = B.canonical.event(ev).bytes, recomputed = B.hex(B.sha256(bytes));
      if (edited && edit.rehash) ev.hash = recomputed;
      var ok = ev.previous === previous && ev.hash === recomputed;
      if (!ok && firstBad === null) firstBad = ev.seq;
      rows.push({ ev: ev, edited: edited, ok: ok, recomputed: recomputed, linkOK: ev.previous === previous, bytes: bytes });
      previous = ev.hash;
    });
    return { rows: rows, firstBad: firstBad };
  }
  B.define("ledger-chain", {
    title: "The ledger's chain, recomputed in this browser",
    params: { event: { type: "int", default: 3 }, field: { type: "string", default: "code" }, value: { type: "string", default: "", link: false }, rehash: { type: "string", default: "no" } },
    render: function (body, state, ctx) {
      var fx = fixture();
      if (!fx) { body.appendChild(h("p", { class: "fig-error" }, "The fixtures are not in the data: run Docs/site/src/build.sh.")); return; }
      var index = Math.max(1, Math.min(fx.events.length, state.event || 3)) - 1, field = FIELDS.some(function (f) { return f.value === state.field; }) ? state.field : "code";
      var original = fx.events[index][field] === undefined || fx.events[index][field] === null ? "" : String(fx.events[index][field]);
      var value = state.value === "" || state.value === undefined ? original : state.value, rehash = state.rehash === "yes";
      var input = h("input", { type: "text", value: value, "aria-label": "The field's value", "data-key": "chain-value", size: 14 });
      input.addEventListener("input", function () { ctx.set({ value: input.value }); });
      body.appendChild(h("div", { class: "fig-controls" }, [
        B.select("Change event", fx.events.map(function (e) { return { value: String(e.seq), label: e.seq + " · " + e.kind }; }), String(index + 1), function (v) { ctx.set({ event: +v, value: "" }); }),
        B.select("field", FIELDS, field, function (v) { ctx.set({ field: v, value: "" }); }),
        h("label", { "data-keep": "chain-value" }, ["to", input]),
        h("label", null, [h("input", { type: "checkbox", checked: rehash, onchange: function (e) { ctx.set({ rehash: e.target.checked ? "yes" : "no" }); } }), "and re-hash it to hide the change"]),
        h("button", { type: "button", onclick: function () { ctx.set({ value: "", rehash: "no" }); } }, "Restore")
      ]));
      var result = chain(fx.events, { index: index, field: field, value: value, rehash: rehash });
      body.appendChild(h("p", { class: "readout" }, result.firstBad === null ? [h("b", null, "Ledger.verify: " + fx.events.length + " events, the chain holds.")]
        : [h("b", null, "Ledger.verify stops at event " + result.firstBad + "."), result.firstBad === index + 1 ? " Its hash no longer covers its fields." : " Its previous no longer names the hash before it: hiding one change breaks the next link."]));
      body.appendChild(h("div", { class: "chain" }, result.rows.map(function (r) {
        var e = r.ev;
        return h("div", { class: "link-card" + (r.ok ? "" : " bad") + (r.edited ? " edited" : "") }, [
          h("div", { class: "seq" }, String(e.seq)),
          h("div", null, [h("div", null, [h("span", { class: "kind" }, e.kind), e.actor ? " · " + e.actor : "", e.code ? " · " + e.code : ""]),
            h("div", { class: "fields" }, ["digest " + (e.digest ? e.digest.slice(0, 16) + "…" : "none"), h("br"), "previous " + e.previous.slice(0, 16) + "…" + (r.linkOK ? "" : " ≠ the hash before"), h("br"),
              "hash " + e.hash.slice(0, 16) + "…" + (e.hash === r.recomputed ? "" : " ≠ " + r.recomputed.slice(0, 16) + "… recomputed")])]),
          h("div", { class: "verdict " + (r.ok ? "ok" : "bad") }, r.ok ? "✓ links" : "✗ breaks")
        ]);
      })));
      var shown = result.rows[index];
      body.appendChild(h("p", { class: "fig-note" }, "Event " + (index + 1) + "'s canonical bytes, bless/event/1, " + shown.bytes.length + " bytes; its hash is their SHA-256:"));
      body.appendChild(h("div", { class: "bytes" }, B.canonical.event(shown.ev).marks.map(function (m) {
        var hex = B.hex(shown.bytes.slice(m.at, m.at + m.length));
        return h("span", { class: m.label === "tag" ? "tag" : r_changed(m.label) ? "changed" : null, title: m.label }, hex + " ");
      })));
      function r_changed(label) { return shown.edited && label === field; }
    },
    selfCheck: function () {
      var fx = fixture();
      if (!fx) return [{ name: "the fixtures are loaded", ok: false }];
      var clean = chain(fx.events, null), tampered = chain(fx.events, { index: 2, field: "code", value: "withhold", rehash: false }), hidden = chain(fx.events, { index: 2, field: "code", value: "withhold", rehash: true });
      var texts = fx.texts;
      return [
        { name: "every fixture hash recomputes here, and the chain holds", ok: clean.firstBad === null, detail: fx.events.length + " events" },
        { name: "changing event 3's code breaks the chain at event 3; re-hashing it moves the break to event 4", ok: tampered.firstBad === 3 && hidden.firstBad === 4 },
        { name: "the held digest is the SHA-256 of the model's draft, and the released one of the amendment", ok: fx.events[0].digest === B.digest(texts.proposed) && fx.events[4].digest === B.digest(texts.amended) }
      ];
    }
  });
})();
