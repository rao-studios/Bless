/*
 * The figures' drawing kit: Bless.draw makes the SVG parts every figure is drawn with: an svg, a box of centred
 * lines, an arrow with a drawn head (so no <marker> is needed), a line, text, a dashed frame. Ported from Braid's
 * docs/site/js/boards.js, the SVG half; a box takes a party class (p-model, p-reviewer, p-patient, p-withheld) for
 * its colour.
 *
 * SPDX-License-Identifier: GPL-3.0-only
 */
(function () {
  "use strict";
  var B = window.Bless, s = B.s;
  function r1(v) { return Math.round(v * 10) / 10; }
  var draw = (B.draw = {});
  draw.svg = function (W, H, label) {
    return s("svg", { viewBox: "0 0 " + W + " " + H, role: "img", "aria-label": label });
  };
  /** A box with centred lines, the first its title. o: x, y, w, h, lines, party, cls, part, dashed, lh. */
  draw.box = function (g, o) {
    var grp = s("g", { class: [o.party ? "p-" + o.party : "", o.cls || ""].join(" ").trim() || null, "data-part": o.part || null });
    grp.appendChild(s("rect", { x: r1(o.x), y: r1(o.y), width: r1(o.w), height: r1(o.h), rx: o.rx === undefined ? 7 : o.rx,
                                class: "bd-box bd-plain" + (o.dashed ? " bd-dashed" : "") }));
    var lines = (o.lines || []).filter(function (l) { return l !== null && l !== undefined && l !== ""; });
    var lh = o.lh || 13, cx = r1(o.x + o.w / 2), top = o.y + o.h / 2 - (lines.length - 1) * lh / 2 + 4;
    lines.forEach(function (text, i) {
      grp.appendChild(s("text", { x: cx, y: r1(top + i * lh), "text-anchor": "middle", class: i === 0 ? "bd-t" : "bd-sub" }, text));
    });
    g.appendChild(grp);
    return grp;
  };
  /** An arrow from (x1, y1) to (x2, y2) with a drawn head. o: cls, dashed, party. */
  draw.arrow = function (g, x1, y1, x2, y2, o) {
    o = o || {};
    var grp = s("g", { class: o.party ? "p-" + o.party : null });
    var a = Math.atan2(y2 - y1, x2 - x1), len = 7, half = 3.6;
    var bx = x2 - len * Math.cos(a), by = y2 - len * Math.sin(a), px = -Math.sin(a) * half, py = Math.cos(a) * half;
    grp.appendChild(s("line", { x1: r1(x1), y1: r1(y1), x2: r1(bx), y2: r1(by), class: "bd-line" + (o.dashed ? " dash" : "") + (o.cls ? " " + o.cls : "") }));
    grp.appendChild(s("path", { d: "M" + r1(x2) + "," + r1(y2) + " L" + r1(bx + px) + "," + r1(by + py) + " L" + r1(bx - px) + "," + r1(by - py) + " Z",
                                class: "bd-head" + (o.cls ? " " + o.cls : "") }));
    g.appendChild(grp);
    return grp;
  };
  draw.line = function (g, x1, y1, x2, y2, cls) {
    g.appendChild(s("line", { x1: r1(x1), y1: r1(y1), x2: r1(x2), y2: r1(y2), class: cls || "bd-line" }));
  };
  draw.text = function (g, x, y, lines, cls, anchor, lh) {
    var grp = s("g");
    (Array.isArray(lines) ? lines : [lines]).forEach(function (t, i) {
      grp.appendChild(s("text", { x: r1(x), y: r1(y + i * (lh || 13)), class: cls || "bd-sub", "text-anchor": anchor || "start" }, t));
    });
    g.appendChild(grp);
    return grp;
  };
  draw.frame = function (g, o) {
    var grp = s("g");
    grp.appendChild(s("rect", { x: r1(o.x), y: r1(o.y), width: r1(o.w), height: r1(o.h), rx: 10, class: "bd-frame" }));
    if (o.title) grp.appendChild(s("text", { x: r1(o.x + 10), y: r1(o.y + 15), class: "bd-cap" }, o.title));
    g.appendChild(grp);
    return grp;
  };
  /** The family's mark, a gold ring and dot: here, the reviewer's seal. */
  draw.seal = function (g, x, y, r) {
    g.appendChild(s("circle", { cx: r1(x), cy: r1(y), r: r || 9, class: "seal-ring" }));
    g.appendChild(s("circle", { cx: r1(x), cy: r1(y), r: (r || 9) * 0.42, class: "seal-dot" }));
  };
})();
