/*
 * A petition's life: pending, and the four ways out of it. Pick what happens and the figure lights the transition,
 * the standing it ends in, the release it allows (or none), and the ledger lines it writes. The standings drawn are
 * checked against Petition.Standing's cases, read from the Swift by build.py.
 *
 * SPDX-License-Identifier: GPL-3.0-only
 */
(function () {
  "use strict";
  var B = window.Bless, h = B.h, s = B.s;
  var STATES = { pending: { x: 30, y: 112, party: "reviewer" }, blessed: { x: 330, y: 18, party: "patient" }, withheld: { x: 330, y: 86, party: "withheld" },
                 expired: { x: 330, y: 154, party: "withheld" }, withdrawn: { x: 330, y: 222, party: "withheld" } };
  var EVENTS = [
    { id: "bless", label: "a reviewer blesses", to: "blessed", release: "blessed", ledger: "decided · bless, blessed, released · blessed", text: "the model's text, as written" },
    { id: "amend", label: "a reviewer amends", to: "blessed", release: "amended", ledger: "decided · amend, blessed, released · amended", text: "the reviewer's text" },
    { id: "withhold", label: "a reviewer withholds", to: "withheld", release: null, ledger: "decided · withhold, withheld", text: "nothing: the host shows a neutral notice" },
    { id: "lapse-hold", label: "the deadline passes, policy hold", to: "pending", release: null, ledger: "nothing: the petition waits", text: "nothing yet: it waits for a reviewer" },
    { id: "lapse-withhold", label: "the deadline passes, policy withhold", to: "expired", release: null, ledger: "expired · withhold", text: "nothing" },
    { id: "lapse-fallback", label: "the deadline passes, policy fallback", to: "expired", release: "lapsed", ledger: "expired · releaseFallback, released · lapsed", text: "the policy's fixed holding message, never the draft" },
    { id: "withdraw", label: "the host withdraws it", to: "withdrawn", release: null, ledger: "withdrawn", text: "nothing" }
  ];
  B.define("petition-states", {
    title: "A petition's life: one way in, four ways out",
    params: { event: { type: "string", default: "amend" } },
    render: function (body, state, ctx) {
      var ev = EVENTS.filter(function (e) { return e.id === state.event; })[0] || EVENTS[1];
      body.appendChild(h("div", { class: "fig-controls" }, B.select("What happens", EVENTS.map(function (e) { return { value: e.id, label: e.label }; }), ev.id, function (v) { ctx.set({ event: v }); })));
      var svg = B.draw.svg(720, 280, "A petition's standings: pending, and its four outcomes, with the release each allows");
      Object.keys(STATES).forEach(function (name) {
        var st = STATES[name], on = name === ev.to || name === "pending";
        B.draw.box(svg, { x: st.x, y: st.y, w: 140, h: 46, lines: [name, name === "pending" ? "the only open standing" : "final"], party: st.party, cls: on ? "lit" : "dim" });
      });
      Object.keys(STATES).forEach(function (name) {
        if (name === "pending") return;
        var st = STATES[name], on = name === ev.to, g = s("g", { class: on ? "" : "dim" });
        B.draw.arrow(g, 170, 135, 328, st.y + 23, { party: st.party, cls: on ? "lit" : "" });
        svg.appendChild(g);
      });
      if (ev.id === "lapse-hold") {
        var loop = s("g");
        loop.appendChild(s("path", { d: "M80,112 C80,70 140,70 140,108", class: "bd-line lit", style: "--p: var(--reviewer)" }));
        B.draw.arrow(loop, 139, 100, 140, 110, { party: "reviewer", cls: "lit" });
        svg.appendChild(loop);
      }
      var rel = [{ x: 560, y: 18, party: "patient", for: "blessed" }, { x: 560, y: 154, party: "withheld", for: "expired" }];
      rel.forEach(function (r) {
        var on = ev.release && STATES[ev.to] && r.for === ev.to;
        B.draw.box(svg, { x: r.x, y: r.y, w: 150, h: 46, lines: ["Release", r.for === "blessed" ? "basis blessed or amended" : "basis lapsed: the fallback"], party: r.party, cls: on ? "lit" : "dim", dashed: r.for === "expired" });
        var g = s("g", { class: on ? "" : "dim" });
        B.draw.arrow(g, 470, r.y + 23, 558, r.y + 23, { party: r.party, cls: on ? "lit" : "" });
        svg.appendChild(g);
      });
      body.appendChild(svg);
      body.appendChild(h("p", { class: "readout" }, [h("b", null, ev.label), " → ", h("b", null, ev.to), " · release: ", h("b", null, ev.release || "none"),
        h("br"), "the patient gets ", ev.text, h("br"), "the ledger writes: ", ev.ledger]));
    },
    selfCheck: function () {
      var facts = (B.data().index || {}).facts || {};
      var drawn = Object.keys(STATES), bases = [];
      EVENTS.forEach(function (e) { if (e.release && bases.indexOf(e.release) < 0) bases.push(e.release); });
      return [
        { name: "the standings drawn are Petition.Standing's cases, in order", ok: JSON.stringify(drawn) === JSON.stringify(facts.standings || []), detail: (facts.standings || []).join(", ") },
        { name: "the releases shown are Release.Basis's cases", ok: JSON.stringify(bases.slice().sort()) === JSON.stringify((facts.bases || []).slice().sort()), detail: (facts.bases || []).join(", ") },
        { name: "every lapse the figure offers is a Policy.Lapse case", ok: ["hold", "withhold", "releaseFallback"].every(function (l) { return (facts.lapses || []).indexOf(l) >= 0; }) && (facts.lapses || []).length === 3 }
      ];
    }
  });
})();
