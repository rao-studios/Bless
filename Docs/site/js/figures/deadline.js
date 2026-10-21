/*
 * The deadline: a petition held at time 0, a deadline, and a reviewer who answers at some time. Move the answer
 * past the deadline and the policy decides: hold waits for the reviewer, withhold sends nothing, fallback sends a
 * fixed holding message. The model's draft is never what a lapse releases. The choices are Policy.Lapse's cases.
 *
 * SPDX-License-Identifier: GPL-3.0-only
 */
(function () {
  "use strict";
  var B = window.Bless, h = B.h, s = B.s;
  var LAPSES = [{ value: "hold", label: "hold" }, { value: "withhold", label: "withhold" }, { value: "releaseFallback", label: "releaseFallback" }];
  /** What happens, by the rules in Petition.applying and Petition.lapsed. Pure. */
  function outcome(deadline, answer, lapse) {
    if (answer < deadline) return { standing: "blessed", release: "the reviewer's ruling", at: answer, refused: false };
    if (lapse === "hold") return { standing: "blessed", release: "the reviewer's ruling", at: answer, refused: false, late: true };
    if (lapse === "withhold") return { standing: "expired", release: null, at: deadline, refused: true };
    return { standing: "expired", release: "the policy's holding message", at: deadline, refused: true };
  }
  function clock(min) { var hh = Math.floor(min / 60), mm = Math.round(min % 60); return hh + ":" + (mm < 10 ? "0" : "") + mm; }
  B.define("deadline", {
    title: "The deadline: what the policy decides when no one answers",
    params: { deadline: { type: "int", default: 240 }, answer: { type: "int", default: 300 }, lapse: { type: "string", default: "releaseFallback" } },
    render: function (body, state, ctx) {
      var D = Math.max(15, Math.min(450, state.deadline)), R = Math.max(0, Math.min(480, state.answer));
      var lapse = LAPSES.some(function (l) { return l.value === state.lapse; }) ? state.lapse : "releaseFallback";
      body.appendChild(h("div", { class: "fig-controls" }, [
        B.slider("Deadline", D, 15, 450, 15, function (v) { ctx.set({ deadline: v }); }, function (v) { return clock(v) + " h"; }),
        B.slider("The reviewer answers at", R, 0, 480, 5, function (v) { ctx.set({ answer: v }); }, function (v) { return clock(v) + " h"; }),
        B.select("At the deadline", LAPSES, lapse, function (v) { ctx.set({ lapse: v }); })
      ]));
      var W = 720, H = 120, x0 = 30, x1 = 690, svg = B.draw.svg(W, H, "A timeline: held at 0, the deadline, and the reviewer's answer");
      function X(min) { return x0 + (x1 - x0) * min / 480; }
      if (lapse !== "hold") svg.appendChild(s("rect", { x: X(D), y: 30, width: x1 - X(D), height: 40, class: "tl-zone" }));
      svg.appendChild(s("line", { x1: x0, y1: 50, x2: x1, y2: 50, class: "tl-axis" }));
      [0, 120, 240, 360, 480].forEach(function (m) { svg.appendChild(s("text", { x: X(m), y: 92, "text-anchor": "middle", class: "bd-sub" }, clock(m) + " h")); });
      function mark(min, party, label, up) {
        var g = s("g", { class: "p-" + party });
        g.appendChild(s("line", { x1: X(min), y1: 32, x2: X(min), y2: 68, class: "tl-mark", style: "stroke: var(--" + party + ")" }));
        g.appendChild(s("text", { x: X(min), y: up ? 24 : 112, "text-anchor": "middle", class: "bd-t", style: "fill: var(--" + party + "-ink)" }, label));
        svg.appendChild(g);
      }
      mark(0, "model", "held", true);
      mark(D, "withheld", "deadline " + clock(D), true);
      mark(R, "reviewer", "the reviewer answers " + clock(R), false);
      body.appendChild(svg);
      var o = outcome(D, R, lapse);
      body.appendChild(h("p", { class: "readout" }, [
        h("b", null, R < D ? "The reviewer answers in time." : lapse === "hold" ? "The deadline passes and the petition keeps waiting." : "At " + clock(D) + " the petition expires."),
        h("br"), "The patient gets ", h("b", null, o.release || "nothing"), o.release ? " at " + clock(o.at) + " h" : "", ".",
        o.refused ? [h("br"), "The verdict at " + clock(R) + " h is refused: the petition is already decided."] : o.late ? [h("br"), "Under hold, a late answer is still heard: nothing unreviewed is ever sent."] : null
      ]));
    },
    selfCheck: function () {
      var facts = (B.data().index || {}).facts || {}, bad = [];
      LAPSES.forEach(function (l) { [240, 300, 480].forEach(function (R) { var o = outcome(240, R, l.value); if (o.release && /draft/.test(o.release)) bad.push(l.value + " at " + R); }); });
      return [
        { name: "the choices are Policy.Lapse's cases", ok: JSON.stringify(LAPSES.map(function (l) { return l.value; })) === JSON.stringify(facts.lapses || []), detail: (facts.lapses || []).join(", ") },
        { name: "Policy's default lapse is hold, as the figure's first choice", ok: (facts.policy || {}).onLapse === "hold" },
        { name: "no lapse ever releases the model's draft", ok: !bad.length, detail: bad.join(", ") },
        { name: "past the deadline, withhold and fallback refuse the late verdict, hold hears it", ok: outcome(240, 300, "withhold").refused && outcome(240, 300, "releaseFallback").refused && !outcome(240, 300, "hold").refused }
      ];
    }
  });
})();
