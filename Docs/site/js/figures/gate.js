/*
 * The gate: a patient's question, the model's draft held at the Gate, the reviewer's ruling, and what reaches the
 * patient, in six steps. The texts and the ledger lines are the fixture's (SiteFixturesTests: one petition's whole
 * life, written by the real Gate), so the amend path shows exactly what Bless wrote.
 *
 * SPDX-License-Identifier: GPL-3.0-only
 */
(function () {
  "use strict";
  var B = window.Bless, h = B.h, s = B.s;
  var STEPS = [
    { n: 1, title: "The patient asks", lit: ["patient", "a-pm"] },
    { n: 2, title: "The model drafts", lit: ["model"] },
    { n: 3, title: "The draft is held as a petition", lit: ["a-mg", "gate"] },
    { n: 4, title: "The reviewer reads it", lit: ["a-gr", "reviewer"] },
    { n: 5, title: "The reviewer rules, with a seal", lit: ["a-rg", "reviewer", "gate"] },
    { n: 6, title: "A release, or nothing", lit: ["a-gp", "patient"] }
  ];
  var RULINGS = [{ value: "bless", label: "bless" }, { value: "amend", label: "amend" }, { value: "withhold", label: "withhold" }];
  function texts() { var fx = (B.data().fixtures || {}).ledger; return fx ? fx.texts : { question: "", proposed: "", amended: "" }; }
  /** The ledger lines each step writes, for a ruling. Pure, so the self-check can hold it to the fixture. */
  function events(step, ruling) {
    var out = [];
    if (step >= 3) out.push({ kind: "submitted" });
    if (step >= 4) out.push({ kind: "viewed", actor: "reviewer" });
    if (step >= 5) {
      out.push({ kind: "decided", actor: "reviewer", code: ruling });
      out.push(ruling === "withhold" ? { kind: "withheld", actor: "reviewer" } : { kind: "blessed" });
    }
    if (step >= 6 && ruling !== "withhold") out.push({ kind: "released", code: ruling === "amend" ? "amended" : "blessed" });
    return out;
  }
  function patientSees(step, ruling, t) {
    if (step <= 1) return { cls: "patient", text: t.question };
    if (step === 2) return { cls: "held", text: "Preparing a reply…" };
    if (step <= 5) return { cls: "held", text: "Held for review by your care team" };
    if (ruling === "withhold") return { cls: "none", text: "Your care team will contact you about this question directly." };
    return { cls: "patient", text: ruling === "amend" ? t.amended : t.proposed };
  }
  function picture(state) {
    var W = 720, H = 210, svg = B.draw.svg(W, H, "A patient, the model, the Gate and the reviewer; the step lights the part that acts"), lit = STEPS[state.step - 1].lit;
    function on(part) { return lit.indexOf(part) >= 0; }
    var withheld = state.ruling === "withhold" && state.step === 6;
    var boxes = [
      { part: "patient", x: 10, y: 50, w: 130, lines: ["Patient", "asks; reads releases"], party: "patient" },
      { part: "model", x: 200, y: 50, w: 130, lines: ["Model", "drafts the reply"], party: "model" },
      { part: "gate", x: 390, y: 50, w: 140, lines: ["Gate", "holds the petition"], party: "reviewer" },
      { part: "reviewer", x: 590, y: 50, w: 120, lines: ["Reviewer", "blesses, amends, withholds"], party: "reviewer" }
    ];
    boxes.forEach(function (b) { B.draw.box(svg, { x: b.x, y: b.y, w: b.w, h: 56, lines: b.lines, party: b.party, cls: on(b.part) ? "lit" : "dim" }); });
    function arrow(id, x1, y1, x2, y2, party, label, lx, ly) {
      var g = s("g", { class: on(id) ? "" : "dim" });
      B.draw.arrow(g, x1, y1, x2, y2, { party: party, cls: on(id) ? "lit" : "" });
      if (label) g.appendChild(s("text", { x: lx, y: ly, class: "bd-sub", "text-anchor": "middle" }, label));
      svg.appendChild(g);
    }
    arrow("a-pm", 140, 70, 198, 70, "patient", "question", 169, 62);
    arrow("a-mg", 330, 70, 388, 70, "model", "draft", 359, 62);
    arrow("a-gr", 530, 64, 588, 64, "reviewer", "petition", 559, 56);
    arrow("a-rg", 588, 92, 532, 92, "reviewer", "verdict", 560, 106);
    var back = s("g", { class: on("a-gp") ? "" : "dim" });
    var party = withheld ? "withheld" : "patient";
    back.appendChild(s("path", { d: "M460,106 V170 H75 V108", class: "bd-line" + (on("a-gp") ? " lit" : "") + (withheld ? " dash" : ""), style: "--p: var(--" + party + ")" }));
    B.draw.arrow(back, 75, 120, 75, 108, { party: party, cls: on("a-gp") ? "lit" : "" });
    back.appendChild(s("text", { x: 268, y: 164, class: "bd-sub", "text-anchor": "middle" }, withheld ? "withheld: no release, a neutral notice" : "release: the blessed text and its sealed verdict"));
    svg.appendChild(back);
    if (state.step >= 5) B.draw.seal(svg, 560, 128, 7);
    return svg;
  }
  B.define("gate", {
    title: "The gate: nothing reaches the patient but a release",
    params: { step: { type: "int", default: 1 }, ruling: { type: "string", default: "amend" } },
    render: function (body, state, ctx) {
      var step = Math.max(1, Math.min(STEPS.length, state.step || 1)), ruling = RULINGS.some(function (r) { return r.value === state.ruling; }) ? state.ruling : "amend";
      state = { step: step, ruling: ruling };
      var t = texts(), controls = h("div", { class: "fig-controls" }, [
        h("button", { type: "button", onclick: function () { ctx.set({ step: Math.max(1, step - 1) }); }, disabled: step === 1 }, "← Back"),
        STEPS.map(function (st) { return h("button", { type: "button", "aria-pressed": st.n === step ? "true" : "false", title: st.title, onclick: function () { ctx.set({ step: st.n }); } }, String(st.n)); }),
        h("button", { type: "button", onclick: function () { ctx.set({ step: Math.min(STEPS.length, step + 1) }); }, disabled: step === STEPS.length }, "Next →"),
        B.select("The reviewer's ruling", RULINGS, ruling, function (v) { ctx.set({ ruling: v }); })
      ]);
      body.appendChild(controls);
      body.appendChild(h("p", { class: "readout" }, [h("b", null, step + " · " + STEPS[step - 1].title)]));
      body.appendChild(picture(state));
      var sees = patientSees(step, ruling, t), draft = step >= 2 ? t.proposed : "";
      body.appendChild(h("div", { class: "gate-panel" }, [
        h("div", null, [h("h4", null, "What the patient sees"), h("div", { class: "bubble " + sees.cls }, sees.text)]),
        h("div", null, [h("h4", null, step >= 2 ? "The draft, held at the Gate" : "The draft"), draft ? h("div", { class: "bubble draft" }, draft) : h("div", { class: "bubble none" }, "Not written yet")]),
        h("div", null, [h("h4", null, "What the ledger has written"), (function () {
          var ev = events(step, ruling);
          return ev.length ? h("ul", { class: "events" }, ev.map(function (e, i) { return h("li", null, (i + 1) + " " + e.kind + (e.actor ? " · " + e.actor : "") + (e.code ? " · " + e.code : "")); }))
                           : h("p", { class: "fig-note" }, "Nothing yet: the question is the host's, and the ledger starts when a draft is held.");
        })()]),
        h("div", null, [h("h4", null, "What the ledger never holds"), h("p", { class: "fig-note" }, "The question, the draft, the amendment and any reason. Each text appears only as its SHA-256.")])
      ]));
    },
    selfCheck: function () {
      var facts = (B.data().index || {}).facts || {}, fx = (B.data().fixtures || {}).ledger, out = [];
      var kinds = [];
      ["bless", "amend", "withhold"].forEach(function (r) { events(6, r).forEach(function (e) { if (kinds.indexOf(e.kind) < 0) kinds.push(e.kind); }); });
      out.push({ name: "every ledger kind the steps write is one LedgerEvent.Kind declares", ok: kinds.every(function (k) { return (facts.ledgerKinds || []).indexOf(k) >= 0; }), detail: kinds.join(", ") });
      out.push({ name: "the rulings offered are Ruling.Kind's cases", ok: JSON.stringify(RULINGS.map(function (r) { return r.value; })) === JSON.stringify(facts.rulings || []), detail: (facts.rulings || []).join(", ") });
      if (fx) {
        var drawn = events(6, "amend").map(function (e) { return e.kind + ":" + (e.code || ""); }), real = fx.events.map(function (e) { return e.kind + ":" + (e.code || ""); });
        out.push({ name: "the amend path writes the ledger the real Gate wrote for the fixture", ok: JSON.stringify(drawn) === JSON.stringify(real), detail: real.join(" ") });
      }
      return out;
    }
  });
})();
