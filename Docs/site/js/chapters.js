/*
 * The chapters' live checks: a chapter that lists Bless's vocabulary in prose (the standings, the ledger's kinds,
 * the rulings, the lapses, the release bases) marks the list with data-enum="<name>", and the self-check holds it
 * to the cases build.py read from the Swift (BlessData.index.facts). Defaults written with data-fact are checked
 * by bless.js.
 *
 * SPDX-License-Identifier: GPL-3.0-only
 */
(function () {
  "use strict";
  var B = window.Bless;
  B.extraChecks.push({ name: "chapters", run: function () {
    var facts = (B.data().index || {}).facts || {};
    return Array.prototype.map.call(document.querySelectorAll("[data-enum]"), function (el) {
      var name = el.getAttribute("data-enum"), want = facts[name] || [];
      var shown = Array.prototype.map.call(el.querySelectorAll("code"), function (c) { return c.textContent.trim(); });
      return { name: "the page lists " + name + " as the code declares them", ok: JSON.stringify(shown) === JSON.stringify(want), detail: want.join(", ") };
    });
  } });
})();
