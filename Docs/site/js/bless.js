/*
 * Bless's site: the runtime every page loads first.
 *
 * window.Bless holds the page code: small DOM helpers, wrapped storage, a highlighter for every language in the
 * repository, the data model the explorer, the overview and the chapters' excerpts share (built once from
 * window.BlessData), the navigation, the figures (define, mount, deep links, controls: Braid's machinery), and the
 * self-check registry. Classic script, no modules and no fetch: the site is read from file://. Ported from
 * VeilGarde's docs/site/js/veilgarde.js, with the figures from Braid's docs/site/js/braid.js.
 *
 * SPDX-License-Identifier: GPL-3.0-only
 */
(function () {
  "use strict";
  var B = (window.Bless = window.Bless || {});
  var SVGNS = "http://www.w3.org/2000/svg";

  B.pages = [
    { file: "index.html", short: "Bless at a glance", start: true },
    { file: "01-hold.html", n: 1, short: "Why hold the reply?" },
    { file: "02-petition.html", n: 2, short: "What is a petition?" },
    { file: "03-reviewer.html", n: 3, short: "What can a reviewer do?" },
    { file: "04-ledger.html", n: 4, short: "What does the ledger prove?" },
    { file: "05-seal.html", n: 5, short: "What does the seal sign?" },
    { file: "06-deadline.html", n: 6, short: "What happens at the deadline?" },
    { file: "07-seam.html", n: 7, short: "How does it drop into an inference layer?" },
    { file: "08-playground.html", n: 8, short: "What does the playground show?" },
    { file: "09-hipaa.html", n: 9, short: "What does HIPAA ask, and what does Bless answer?" }
  ];
  B.appendices = [
    { file: "code.html", short: "The code explorer" },
    { file: "run.html", short: "What this run built" },
    { file: "lexicon.html", short: "The lexicon" },
    { file: "selfcheck.html", short: "The self-check" }
  ];

  // MARK: Small helpers

  function setAttrs(node, attrs) {
    if (!attrs) return;
    Object.keys(attrs).forEach(function (k) {
      var v = attrs[k];
      if (v === null || v === undefined || v === false) return;
      if (k === "text") node.textContent = v;
      else if (k.slice(0, 2) === "on" && typeof v === "function") node.addEventListener(k.slice(2), v);
      else node.setAttribute(k, v === true ? "" : String(v));
    });
  }
  function append(node, children) {
    if (children === null || children === undefined) return;
    if (!Array.isArray(children)) children = [children];
    children.forEach(function (c) {
      if (c === null || c === undefined || c === false) return;
      if (Array.isArray(c)) { append(node, c); return; }
      node.appendChild(typeof c === "string" || typeof c === "number" ? document.createTextNode(String(c)) : c);
    });
  }
  /** An element, its attributes and its children. Text always goes in as text nodes, never as HTML. */
  B.h = function (tag, attrs, children) { var node = document.createElement(tag); setAttrs(node, attrs); append(node, children); return node; };
  B.s = function (tag, attrs, children) { var node = document.createElementNS(SVGNS, tag); setAttrs(node, attrs); append(node, children); return node; };
  var h = B.h;

  /** localStorage can throw (a private window, blocked site data): every read and write is wrapped. */
  B.storage = {
    get: function (key, fallback) { try { var v = window.localStorage.getItem("bless:" + key); return v === null ? fallback : JSON.parse(v); } catch (e) { return fallback; } },
    set: function (key, value) { try { window.localStorage.setItem("bless:" + key, JSON.stringify(value)); } catch (e) { /* storage unavailable: the page works without it */ } },
    remove: function (key) { try { window.localStorage.removeItem("bless:" + key); } catch (e) { /* as above */ } }
  };
  B.fmt = {
    int: function (x) { return Number(x).toLocaleString("en-US"); },
    bytes: function (n) { return n >= 1048576 ? (n / 1048576).toFixed(2) + " MB" : n >= 1024 ? Math.round(n / 1024) + " KB" : n + " B"; },
    minus: function (s) { return String(s).replace(/^-/, "−"); }
  };
  B.root = function () { return (document.body && document.body.getAttribute("data-root")) || ""; };
  B.data = function () { return window.BlessData || {}; };
  B.toast = function (text) {
    var t = h("div", { class: "toast", role: "status" }, text);
    document.body.appendChild(t);
    setTimeout(function () { t.remove(); }, 1400);
  };
  /** Copies text, or shows it selected in a field beside `near` when the clipboard is refused. */
  B.copy = function (text, done, near) {
    function fallback() {
      var field = h("input", { class: "copy-field", value: text, readonly: true, "aria-label": "Copy this" });
      var host = near || document.body, old = host.querySelector(".copy-field");
      if (old) old.remove();
      host.appendChild(field);
      field.select();
    }
    try {
      if (navigator.clipboard && navigator.clipboard.writeText) navigator.clipboard.writeText(text).then(function () { B.toast(done); }, fallback);
      else fallback();
    } catch (e) { fallback(); }
  };

  // MARK: Highlighting, one line at a time, with the state a line hands the next

  function words(s) { var o = {}; s.split(/\s+/).forEach(function (w) { if (w) o[w] = true; }); return o; }
  var KW = {
    swift: words("func let var if else guard return for in while struct enum class public private fileprivate internal open package static mutating nonmutating case switch default nil true false self Self super init deinit extension protocol import throws throw try rethrows where some any inout defer break continue repeat do catch lazy weak unowned final override async await typealias associatedtype subscript convenience required indirect is as get set willSet didSet fallthrough actor nonisolated consuming borrowing"),
    python: words("def class return if elif else for while in not and or is None True False import from as with try except finally raise pass break continue lambda yield global nonlocal assert del async await"),
    shell: words("if then else elif fi for in do done while until case esac function return local export set unset source exit readonly shift trap"),
    javascript: words("var let const function return if else for while do switch case default break continue new this typeof instanceof in of try catch finally throw null undefined true false delete void class extends super yield async await"),
    json: words("true false null"),
    toml: words("true false"),
    yaml: words("true false null yes no")
  };
  var CFG = {
    swift: { line: "//", block: ["/*", "*/"], strings: ['"""', '"'], raw: true, types: true, at: true, hash: true },
    python: { line: "#", strings: ['"""', "'''", '"', "'"], types: true, at: true },
    shell: { line: "#", strings: ['"', "'"], vars: true },
    javascript: { line: "//", block: ["/*", "*/"], strings: ['"', "'", "`"], types: true },
    css: { block: ["/*", "*/"], strings: ['"', "'"] },
    html: { block: ["<!--", "-->"], strings: ['"', "'"], tags: true },
    json: { strings: ['"'], keys: true },
    toml: { line: "#", strings: ['"', "'"], keys: true },
    yaml: { line: "#", strings: ['"', "'"], keys: true },
    text: { line: "#" }
  };
  /** The tokens of one line as nodes: comments, strings, numbers, keywords, types. `st` carries an open block
   *  comment, multi-line string or code fence to the next line. */
  B.highlight = function (line, lang, st) {
    st = st || {};
    lang = lang || "swift";
    var out = [], buf = "", i = 0, n = line.length, m;
    function flush() { if (buf) { out.push(document.createTextNode(buf)); buf = ""; } }
    function push(cls, s) { if (!s) return; flush(); out.push(h("span", { class: cls }, s)); }
    if (lang === "markdown") {
      if (/^\s*(```|~~~)/.test(line)) { st.fence = !st.fence; push("tk-c", line); return out; }
      if (st.fence) { push("tk-s", line); return out; }
      if (/^#{1,6}\s/.test(line)) { push("tk-k", line); return out; }
      line.split(/(`[^`]+`)/).forEach(function (part) { if (/^`[^`]+`$/.test(part)) push("tk-s", part); else if (part) { flush(); out.push(document.createTextNode(part)); } });
      return out;
    }
    var cfg = CFG[lang] || CFG.text, kw = KW[lang] || {};
    if (st.block) {
      var e = line.indexOf(st.block);
      if (e < 0) { push("tk-c", line); return out; }
      push("tk-c", line.slice(0, e + st.block.length));
      i = e + st.block.length;
      st.block = null;
    }
    if (st.str) {
      var close = findClose(line, 0, st.str, st.rawStr);
      if (close < 0) { push("tk-s", line); return out; }
      push("tk-s", line.slice(0, close + st.str.length));
      i = close + st.str.length;
      st.str = null;
    }
    while (i < n) {
      var c = line[i], rest = line.slice(i);
      if (cfg.line && rest.indexOf(cfg.line) === 0 && (lang !== "shell" && lang !== "text" || i === 0 || /\s/.test(line[i - 1]))) { push("tk-c", rest); i = n; break; }
      if (cfg.block && rest.indexOf(cfg.block[0]) === 0) {
        var end = line.indexOf(cfg.block[1], i + cfg.block[0].length);
        if (end < 0) { push("tk-c", rest); st.block = cfg.block[1]; i = n; break; }
        push("tk-c", line.slice(i, end + cfg.block[1].length));
        i = end + cfg.block[1].length;
        continue;
      }
      if (cfg.raw && (m = /^(#+)("""|")/.exec(rest))) {
        var closer = m[2] + m[1], at = line.indexOf(closer, i + m[0].length);
        if (at < 0) { push("tk-s", rest); if (m[2] === '"""') { st.str = closer; st.rawStr = true; } i = n; break; }
        push("tk-s", line.slice(i, at + closer.length));
        i = at + closer.length;
        continue;
      }
      var q = null;
      if (cfg.strings) for (var k = 0; k < cfg.strings.length; k++) if (rest.indexOf(cfg.strings[k]) === 0) { q = cfg.strings[k]; break; }
      if (q && !(lang === "shell" && q === "'" && i > 0 && /\w/.test(line[i - 1]))) {
        var cl = findClose(line, i + q.length, q, lang === "shell" && q === "'");
        if (cl < 0) { push("tk-s", rest); if (q.length === 3 || q === "`") { st.str = q; st.rawStr = false; } i = n; break; }
        var str = line.slice(i, cl + q.length);
        if (cfg.keys && /^\s*:/.test(line.slice(cl + q.length))) push("tk-t", str); else push("tk-s", str);
        i = cl + q.length;
        continue;
      }
      if (cfg.tags && c === "<" && (m = /^<\/?[A-Za-z][\w-]*/.exec(rest))) { push("tk-k", m[0]); i += m[0].length; continue; }
      if (cfg.vars && c === "$" && (m = /^\$(?:\{[^}]*\}|[A-Za-z_]\w*|[0-9@#?*$!-])/.exec(rest))) { push("tk-t", m[0]); i += m[0].length; continue; }
      if (cfg.at && c === "@" && (m = /^@[A-Za-z_][\w.]*/.exec(rest))) { push("tk-a", m[0]); i += m[0].length; continue; }
      if (cfg.hash && c === "#" && (m = /^#[A-Za-z_]\w*/.exec(rest))) { push("tk-a", m[0]); i += m[0].length; continue; }
      if (/[0-9]/.test(c) && (i === 0 || !/[\w$.]/.test(line[i - 1])) && (m = /^(?:0x[0-9A-Fa-f_]+|\d[\d_]*(?:\.\d[\d_]*)?(?:[eE][-+]?\d+)?)/.exec(rest))) {
        push("tk-n", m[0]); i += m[0].length; continue;
      }
      if ((m = /^[A-Za-z_$][\w$]*/.exec(rest)) && (i === 0 || !/[\w$]/.test(line[i - 1]))) {
        var w = m[0];
        if (kw[w]) push("tk-k", w);
        else if (cfg.keys && lang !== "json" && /^\s*[=:]/.test(line.slice(i + w.length)) && !line.slice(0, i).trim()) push("tk-t", w);
        else if (cfg.types && /^[A-Z]/.test(w)) push("tk-t", w);
        else buf += w;
        i += w.length;
        continue;
      }
      buf += c;
      i++;
    }
    flush();
    return out;
  };
  function findClose(line, from, q, raw) {
    for (var j = from; j < line.length; j++) {
      if (!raw && line[j] === "\\") { j++; continue; }
      if (line.indexOf(q, j) === j) return j;
    }
    return -1;
  }

  // MARK: The data model: every file, its declarations with their ids, the calls and the trails

  var KIND = { f: "func", i: "init", d: "deinit", s: "subscript", v: "var", S: "struct", C: "class", E: "enum", A: "actor", X: "extension", P: "protocol" };
  var STATUS = { a: "added", c: "changed", u: "unchanged" };
  B.KIND = KIND;
  B.CALLABLE = "fis";
  B.flags = { REQUIREMENT: 1, OPERATOR: 2, LOCAL: 4, ONE_LINE: 8 };
  function push(map, key, value) { (map[key] = map[key] || []).push(value); }
  function splitLines(text) {
    if (text === null || text === undefined) return null;
    var lines = text.split("\n");
    if (lines.length && lines[lines.length - 1] === "") lines.pop();
    return lines;
  }
  B.splitLines = splitLines;

  function scopesOf(file, rows, old) {
    var list = [];
    rows.forEach(function (row, k) {
      list.push({ local: k, file: file, old: !!old, kind: row[0], name: row[1], labels: row[2], mods: row[3], decl: row[4], sig: row[5], brace: row[6], end: row[7],
                  doc: row[8], parent: row[9], flags: row[10], status: old ? "removed" : STATUS[row[11]] || row[11], cases: row[12] || null });
    });
    var seen = {};
    list.forEach(function (sc) {
      var names = [], k = sc.local;
      while (k >= 0) { names.unshift(list[k].name); k = list[k].parent; }
      sc.qualified = names.join(".");
      sc.callable = B.CALLABLE.indexOf(sc.kind) >= 0;
      sc.labelText = sc.callable ? "(" + (sc.labels || []).map(function (l) { return l + ":"; }).join("") + ")" : "";
      var tail = sc.kind === "X" ? "extension:" + sc.qualified : sc.qualified + sc.labelText;
      var base = file.path + ":" + tail;
      seen[base] = (seen[base] || 0) + 1;
      sc.id = seen[base] === 1 ? base : base + "~" + seen[base];
      sc.tail = sc.id.slice(file.path.length + 1);
      sc.label = (sc.kind === "X" ? "extension " : "") + sc.qualified + sc.labelText;
      sc.depth = 0;
      for (var p = sc.parent; p >= 0; p = list[p].parent) sc.depth++;
      sc.from = sc.doc ? Math.min(sc.doc[0], sc.decl) : sc.decl;
      sc.to = sc.end || sc.sig;
    });
    return list;
  }

  var model = null;
  /** The model, built once from whatever data files the page loaded; null without data/index.js. */
  B.model = function () {
    if (model) return model;
    var D = B.data(), index = D.index;
    if (!index) return null;
    var groups = D.files || {}, recs = {}, missing = [], files = [], byPath = {}, scopes = [];
    index.groups.forEach(function (g) {
      if (!groups[g]) { missing.push(g); return; }
      groups[g].files.forEach(function (r) { recs[r.path] = r; });
    });
    index.files.forEach(function (meta, fi) {
      var rec = recs[meta.path] || null;
      var file = { i: fi, path: meta.path, name: meta.path.split("/").pop(), group: meta.group, status: meta.status, lang: meta.lang, lineCount: meta.lines,
                   bytes: meta.bytes, added: meta.added, removed: meta.removed, first: meta.first, scopeCount: meta.scopes, what: meta.what, loaded: !!rec,
                   text: rec ? rec.new : null, old: rec ? rec.old : null, hunks: rec ? rec.hunks : [], header: rec ? rec.header : null, marks: rec ? rec.marks : [],
                   from: rec ? rec.from || null : null, scopes: [], oldScopes: [], lines: null, oldLines: null };
      if (rec) {
        file.scopes = scopesOf(file, rec.scopes, false);
        file.scopes.forEach(function (sc) { sc.g = file.first + sc.local; scopes[sc.g] = sc; });
        file.oldScopes = scopesOf(file, rec.oldScopes || [], true);
      }
      files.push(file);
      byPath[file.path] = file;
    });
    var byQualified = {}, byName = {}, byLabelled = {};
    scopes.forEach(function (sc) {
      if (!sc) return;
      push(byQualified, sc.qualified, sc);
      push(byName, sc.name, sc);
      if (sc.callable) { push(byLabelled, sc.qualified + sc.labelText, sc); push(byLabelled, sc.name + sc.labelText, sc); }
    });
    var out = {}, into = {};
    index.edges.forEach(function (e) { if (scopes[e[0]] && scopes[e[1]]) { push(out, e[0], e); push(into, e[1], e); } });
    // The trail set: the code's (index.trails). It knows its trails and every place a declaration takes on them,
    // once a trail at most; the model's own trails, trailById, placesOf and entries are the set's.
    function setFrom(name, trails, picker, kinds) {
      var trailById = {}, onTrail = {}, entries = [];
      trails.forEach(function (t) {
        trailById[t.id] = t;
        t.steps.forEach(function (st) {
          st.entries.forEach(function (en, k) { push(onTrail, en.scope, { trail: t, step: st.n, pos: k }); entries.push({ trail: t, step: st.n, pos: k, entry: en }); });
        });
      });
      return { name: name, trails: trails, picker: picker, kinds: kinds, trailById: trailById, placesOf: function (g) { return onTrail[g] || []; }, entries: entries };
    }
    var sets = { code: setFrom("code", index.trails || [], index.picker || [], null) };
    var wanted = (document.body && document.body.getAttribute("data-trails")) || "code", set = sets[wanted] || sets.code;
    model = { index: index, files: files, byPath: byPath, scopes: scopes, byQualified: byQualified, byName: byName, byLabelled: byLabelled,
              out: function (g) { return out[g] || []; }, into: function (g) { return into[g] || []; },
              sets: sets, set: set, wanted: wanted,
              trails: set.trails, trailById: set.trailById, placesOf: set.placesOf, entries: set.entries, missing: missing, stripped: {} };
    return model;
  };
  B.linesOf = function (file) { if (!file.lines) file.lines = splitLines(file.text) || []; return file.lines; };
  B.oldLinesOf = function (file) { if (!file.oldLines) file.oldLines = splitLines(file.old) || []; return file.oldLines; };
  /** A header's tagged lines as plain text, its comment marks stripped. */
  B.headerText = function (file, range, lines) {
    if (!range) return null;
    var style = (file.header && file.header.style) || "swift";
    return (lines || B.linesOf(file)).slice(range[0] - 1, range[1]).map(function (l) {
      if (style === "hash") return l.replace(/^#(?:\s+(?:WHAT|PIN|IN|OUT):)?/, "").replace(/^ {0,8}/, "");
      if (style === "doc") return l.replace(/^\s*(?:[rubRUB]?""")?\s*(?:(?:WHAT|PIN|IN|OUT):)?/, "").replace(/^ {0,8}/, "").replace(/"""/g, "");
      return l.replace(/^\/\/(?:  (?:WHAT|PIN|IN|OUT):)?/, "").replace(/^ {0,8}/, "");
    }).join("\n");
  };
  B.kindWords = function (sc) {
    var words = [];
    if (sc.mods) words.push(sc.mods);
    words.push(sc.flags & B.flags.LOCAL && sc.kind === "f" ? "local func" : KIND[sc.kind]);
    if (sc.flags & B.flags.REQUIREMENT) words.push("protocol requirement");
    if (sc.flags & B.flags.OPERATOR) words.push("operator");
    return words.join(" · ");
  };

  // MARK: The trail picker

  /** The trails as one grid, laid out by src/trails.json's picker: a row for each flow, a column for each kind, so a
   *  flow's training and its inference sit side by side and every cell lines up with the cells above it. A section
   *  with fewer kinds than the widest spans its last column. onPick(id) runs on a click; the arrow keys move between
   *  cells. B.pressTrail marks the chosen cell, and lights its row and its column. */
  B.trailPicker = function (picker, trailById, onPick, label) {
    var cols = Math.max.apply(null, picker.map(function (sec) { return sec.columns.length; }));
    var grid = h("div", { class: "trail-grid", role: "group", "aria-label": label, style: "--cols: " + cols });
    function span(n, i) { return i === n - 1 && n < cols ? "grid-column: span " + (cols - n + 1) : null; }
    picker.forEach(function (sec, si) {
      grid.appendChild(h("span", { class: "tg-sec" }, sec.title));
      sec.columns.forEach(function (c, ci) {
        grid.appendChild(h("span", { class: "tg-col", "data-sec": si, "data-col": ci, style: span(sec.columns.length, ci) }, c.label));
      });
      sec.rows.forEach(function (row, ri) {
        grid.appendChild(h("span", { class: "tg-row", "data-sec": si, "data-row": ri }, row.label));
        row.trails.forEach(function (id, ci) {
          var t = trailById[id];
          var b = h("button", { type: "button", class: "tg-cell", "data-trail": id, "data-kind": t.kind, "data-sec": si, "data-row": ri, "data-col": ci,
                                "aria-pressed": "false", "aria-label": t.title + ": " + t.subtitle, title: t.say, style: span(row.trails.length, ci) },
                    [h("span", { class: "tg-mark" }, t.mark), h("span", { class: "tg-sub" }, t.subtitle)]);
          b.addEventListener("click", function () { onPick(id); });
          grid.appendChild(b);
        });
      });
    });
    grid.addEventListener("keydown", function (e) {
      var b = e.target.closest ? e.target.closest(".tg-cell") : null, step = { ArrowLeft: [0, -1], ArrowRight: [0, 1], ArrowUp: [-1, 0], ArrowDown: [1, 0] }[e.key];
      if (!b || !step || e.metaKey || e.ctrlKey || e.altKey) return;
      var rows = [], at = null;
      grid.querySelectorAll(".tg-cell").forEach(function (c) {
        var key = c.getAttribute("data-sec") + ":" + c.getAttribute("data-row");
        if (!rows.length || rows[rows.length - 1].key !== key) rows.push({ key: key, cells: [] });
        rows[rows.length - 1].cells.push(c);
        if (c === b) at = [rows.length - 1, rows[rows.length - 1].cells.length - 1];
      });
      var r = at[0] + step[0], row = rows[r];
      if (!row) return;
      var next = row.cells[Math.max(0, Math.min(row.cells.length - 1, step[0] ? at[1] : at[1] + step[1]))];
      if (next && next !== b) { next.focus(); e.preventDefault(); }
    });
    return grid;
  };
  B.pressTrail = function (grid, id) {
    var on = grid.querySelector('.tg-cell[data-trail="' + id + '"]');
    grid.querySelectorAll(".tg-cell").forEach(function (c) { c.setAttribute("aria-pressed", c === on ? "true" : "false"); });
    grid.querySelectorAll(".tg-row, .tg-col").forEach(function (x) {
      var axis = x.classList.contains("tg-row") ? "data-row" : "data-col";
      x.classList.toggle("on", !!on && x.getAttribute("data-sec") === on.getAttribute("data-sec") && x.getAttribute(axis) === on.getAttribute(axis));
    });
  };

  // MARK: Code excerpts: <div class="code" data-excerpt="<id>"> quotes a declaration by its id, from the same verbatim data the explorer holds

  function renderExcerpt(node) {
    var id = node.getAttribute("data-excerpt"), m = B.model();
    var sc = m && m.scopes.filter(function (x) { return x && x.id === id; })[0];
    if (!sc) { node.appendChild(h("p", { class: "fig-error" }, "Missing excerpt " + id + ": rebuild with Docs/site/src/build.py, or load its data file.")); node.setAttribute("data-rendered", "missing"); return; }
    var lines = B.linesOf(sc.file), from = sc.from, to = sc.to, st = {};
    for (var k = 0; k < from - 1; k++) B.highlight(lines[k], sc.file.lang, st);
    node.appendChild(h("div", { class: "code-head" }, [h("span", null, sc.file.path + ":" + from + "–" + to),
      h("span", null, h("a", { href: B.root() + "code.html#" + sc.id, title: "Open it in the change explorer" }, "explore"))]));
    var pre = h("pre", { tabindex: "0", "aria-label": "Source of " + sc.label });
    for (var n = from; n <= to; n++) pre.appendChild(h("div", { class: "ln" + (n === sc.sig ? " hl" : "") }, [h("span", null, String(n)), h("span", null, B.highlight(lines[n - 1], sc.file.lang, st))]));
    node.appendChild(pre);
    node.setAttribute("data-rendered", "ok");
  }

  /** A word or number written in a chapter, checked against the data it was read from: data-fact names the path into
   *  BlessData.index.facts (the enums and defaults build.py reads from the Swift), data-round the decimals. */
  function factValue(path) {
    var v = (B.data().index || {}).facts;
    path.split(".").forEach(function (k) { v = v === undefined || v === null ? undefined : /^\d+$/.test(k) ? v[+k] : v[k]; });
    return v;
  }
  B.factValue = factValue;
  function factChecks() {
    return Array.prototype.map.call(document.querySelectorAll("[data-fact]"), function (el) {
      var path = el.getAttribute("data-fact"), want = factValue(path), round = el.getAttribute("data-round"), prefix = el.getAttribute("data-prefix");
      var shown = el.textContent.trim().replace(/−/g, "-").replace(/,/g, "").replace(/…$/, "");
      var expect = want === undefined ? undefined : round !== null ? Number(want).toFixed(+round) : prefix !== null ? String(want).slice(0, +prefix) : String(want);
      return { name: "the page's " + path + " reads " + el.textContent.trim(), ok: expect !== undefined && shown === expect, detail: "the data says " + (expect === undefined ? "nothing" : expect) };
    });
  }

  // MARK: Navigation

  function currentFile() { return location.pathname.split("/").pop() || "index.html"; }
  function buildNav() {
    var side = document.querySelector("nav.side");
    if (!side || side.childElementCount) return;
    var here = currentFile(), root = B.root();
    side.appendChild(h("a", { class: "brand", href: root + "index.html" }, "Bless"));
    side.appendChild(h("p", { class: "brand-sub" }, "Human-in-the-loop approval for a model's replies: the chapters, the code and the run"));
    var list = h("ol", { class: "questions" });
    B.pages.forEach(function (c) {
      var a = h("a", { class: "q" + (c.later ? " later" : ""), href: root + c.file }, [h("span", { class: "n" }, c.start ? "▸" : String(c.n)), h("span", null, c.short + (c.later ? " · later" : ""))]);
      if (c.file === here) a.setAttribute("aria-current", "page");
      list.appendChild(h("li", null, a));
    });
    side.appendChild(list);
    side.appendChild(h("h3", null, "Appendices"));
    var more = h("ol", { class: "more" });
    B.appendices.forEach(function (c) {
      var a = h("a", { class: "q", href: root + c.file }, [h("span", { class: "n" }, "·"), h("span", null, c.short)]);
      if (c.file === here) a.setAttribute("aria-current", "page");
      more.appendChild(h("li", null, a));
    });
    side.appendChild(more);
    var menu = document.querySelector("button.menu");
    if (menu) {
      menu.setAttribute("aria-controls", "side-nav");
      side.id = side.id || "side-nav";
      menu.addEventListener("click", function () { var open = side.classList.toggle("open"); menu.setAttribute("aria-expanded", open ? "true" : "false"); if (open) { var first = side.querySelector("a"); if (first) first.focus(); } });
      side.addEventListener("keydown", function (e) { if (e.key === "Escape" && side.classList.contains("open")) { side.classList.remove("open"); menu.setAttribute("aria-expanded", "false"); menu.focus(); } });
    }
    var main = document.querySelector("main.page"), index = B.pages.findIndex(function (c) { return c.file === here; });
    if (main && index >= 0 && !main.querySelector("nav.prevnext")) {
      var prev = B.pages[index - 1], next = B.pages[index + 1];
      main.appendChild(h("nav", { class: "prevnext", "aria-label": "Previous and next chapter" }, [
        prev ? h("a", { class: "prev", href: root + prev.file, rel: "prev" }, [h("small", null, "← Previous"), prev.short]) : h("span"),
        next ? h("a", { class: "next", href: root + next.file, rel: "next" }, [h("small", null, "Next →"), next.short]) : null
      ]));
    }
    document.querySelectorAll("main h2[id]").forEach(function (hd) {
      if (!hd.querySelector(".anchor")) hd.appendChild(h("a", { class: "anchor", href: "#" + hd.id, "aria-label": "Link to this section" }, "#"));
    });
  }
  function openTarget() {
    var id = decodeURIComponent((location.hash || "").slice(1)), node = id && document.getElementById(id);
    if (!node) return;
    for (var d = node.closest("details"); d; d = d.parentElement && d.parentElement.closest("details")) d.open = true;
    if (node.tagName === "DETAILS") node.open = true;
  }

  // MARK: Loading the change's files

  /** Loads data/files/<group>.js for each group, or every group the index lists when `groups` is null, then calls
   *  done. They are classic scripts, injected: file:// allows those where it blocks fetch. A group that fails to
   *  load is reported by the self-check. */
  B.loadGroups = function (groups, done) {
    var idx = B.data().index;
    if (!idx) { done(); return; }
    var have = B.data().files || {};
    var want = (groups || idx.groups).filter(function (g, i, all) { return idx.groups.indexOf(g) >= 0 && !have[g] && all.indexOf(g) === i; });
    var left = want.length;
    if (!left) { model = null; done(); return; }
    want.forEach(function (g) {
      var s = document.createElement("script");
      s.src = B.root() + "data/files/" + g + ".js";
      s.onload = s.onerror = function () { if (--left === 0) { model = null; done(); } };
      document.head.appendChild(s);
    });
  };
  /** The groups this page needs: body[data-groups] ("all", or a comma list) and those its data-excerpt blocks quote from. */
  function groupsWanted() {
    var idx = B.data().index, attr = (document.body.getAttribute("data-groups") || "").trim();
    if (!idx) return [];
    if (attr === "all") return null;
    var out = attr ? attr.split(",").map(function (g) { return g.trim(); }) : [];
    document.querySelectorAll("[data-excerpt]").forEach(function (node) {
      var id = node.getAttribute("data-excerpt"), path = id.slice(0, id.indexOf(":")), f = idx.files.filter(function (x) { return x.path === path; })[0];
      if (f) out.push(f.group);
    });
    return out;
  }

  // MARK: Figures (Braid's machinery): <figure class="fig" data-fig="<name>" data-<param>="…"> with a figcaption

  var defined = (B.figures = {}), mounted = (B.mounted = {});
  /** Registers a figure: { title, params: { name: { type, default, link } }, render(body, state, ctx), selfCheck(state, ctx) }. */
  B.define = function (name, spec) { defined[name] = spec; };
  B.reducedMotion = function () { try { return window.matchMedia("(prefers-reduced-motion: reduce)").matches; } catch (e) { return false; } };

  function parseValue(spec, key, value) {
    var p = (spec.params || {})[key];
    if (!p) return value;
    if (p.type === "int") { var n = parseInt(value, 10); return isNaN(n) ? p.default : n; }
    if (p.type === "number") { var x = parseFloat(value); return isNaN(x) ? p.default : x; }
    return value;
  }
  /** #fig-<name>;key=value;… as { id, params }. */
  function hashTarget() {
    var raw = decodeURIComponent((location.hash || "").slice(1));
    if (!raw) return null;
    var parts = raw.split(";"), params = {};
    parts.slice(1).forEach(function (kv) { var i = kv.indexOf("="); if (i > 0) params[kv.slice(0, i)] = kv.slice(i + 1); });
    return { id: parts[0], params: params };
  }
  /** Makes `top` hold `fresh`'s drawing while `kept` (a control the reader is using) never leaves the page: only the
   *  elements on the path from `top` to `kept` are reused. False, changing nothing, when the two paths differ. */
  function graft(top, fresh, kept, twin) {
    var oldPath = [], newPath = [], a;
    for (a = kept; a && a !== top; a = a.parentNode) oldPath.unshift(a);
    for (a = twin; a && a !== fresh; a = a.parentNode) newPath.unshift(a);
    if (!oldPath.length || oldPath.length !== newPath.length) return false;
    for (var i = 0; i < oldPath.length; i++) if (oldPath[i].nodeName !== newPath[i].nodeName) return false;
    for (i = 0; i < oldPath.length; i++) {
      var oldParent = i ? oldPath[i - 1] : top, newParent = i ? newPath[i - 1] : fresh;
      if (i) {
        Array.prototype.slice.call(oldParent.attributes).forEach(function (at) { if (!newParent.hasAttribute(at.name)) oldParent.removeAttribute(at.name); });
        Array.prototype.slice.call(newParent.attributes).forEach(function (at) { oldParent.setAttribute(at.name, at.value); });
      }
      var stay = oldPath[i], skip = newPath[i], before = true;
      Array.prototype.slice.call(oldParent.childNodes).forEach(function (c) { if (c !== stay) oldParent.removeChild(c); });
      Array.prototype.slice.call(newParent.childNodes).forEach(function (c) {
        if (c === skip) { before = false; return; }
        if (before) oldParent.insertBefore(c, stay); else oldParent.appendChild(c);
      });
    }
    return true;
  }
  function mountFigure(fig) {
    var name = fig.getAttribute("data-fig"), spec = defined[name], id = fig.id ? fig.id.replace(/^fig-/, "") : name;
    if (!fig.id) fig.id = "fig-" + id;
    if (mounted[id] && mounted[id].fig === fig) return;
    var caption = fig.querySelector(":scope > figcaption");
    var body = h("div", { class: "fig-body" });
    var linkButton = h("button", { type: "button", title: "Copy a link to this figure as it is set now", "aria-label": "Copy a link to this figure" }, "link");
    fig.insertBefore(h("div", { class: "fig-head" }, [h("span", { class: "fig-title" }, fig.getAttribute("data-title") || (spec && spec.title) || name),
                                                      h("span", { class: "fig-tools" }, linkButton)]), caption || null);
    fig.insertBefore(body, caption || null);
    if (!spec) { body.appendChild(h("p", { class: "fig-error" }, "Unknown figure: " + name)); fig.setAttribute("data-rendered", "error"); return; }
    var state = {};
    Object.keys(spec.params || {}).forEach(function (k) { state[k] = spec.params[k].default; });
    Object.keys(spec.params || {}).forEach(function (k) { var v = fig.getAttribute("data-" + k); if (v !== null) state[k] = parseValue(spec, k, v); });
    var target = hashTarget();
    if (target && target.id === fig.id) Object.keys(target.params).forEach(function (k) { state[k] = parseValue(spec, k, target.params[k]); });
    var record = { fig: fig, spec: spec, id: id, body: body, state: state, checks: null }, pending = false;
    var ctx = {
      id: id, fig: fig, reducedMotion: B.reducedMotion(), h: h, s: B.s, data: B.data,
      get: function () { return record.state; },
      /** Updates the state now and redraws once, on the next frame. */
      set: function (partial) {
        record.state = Object.assign({}, record.state, partial);
        if (pending) return;
        pending = true;
        (window.requestAnimationFrame || function (f) { return setTimeout(f, 16); })(function () { pending = false; draw(); });
      },
      redraw: function () { draw(); },
      width: function () { return body.clientWidth || fig.clientWidth || 640; }
    };
    record.ctx = ctx;
    /** Draws into a detached container, then swaps it in, keeping a control the reader is using (a pressed slider, a
     *  text box being typed into) in the page so a drag goes on and a caret stays put. */
    function draw() {
      var active = document.activeElement, focusKey = active && body.contains(active) ? active.getAttribute("data-key") : null, kept = null;
      body.querySelectorAll("[data-keep]").forEach(function (el) {
        if (kept) return;
        var pressed = el.getAttribute("data-active") === "1" || el.querySelector('[data-active="1"]');
        var typing = el.contains(active) && (el.matches("textarea, input[type=text]") || el.querySelector("textarea, input[type=text]"));
        if (pressed || typing) kept = el;
      });
      var fresh = document.createElement("div");
      try {
        spec.render(fresh, record.state, ctx);
        var twin = kept ? fresh.querySelector('[data-keep="' + kept.getAttribute("data-keep") + '"]') : null;
        if (!twin || !graft(body, fresh, kept, twin)) {
          body.textContent = "";
          while (fresh.firstChild) body.appendChild(fresh.firstChild);
        }
        fig.setAttribute("data-rendered", "ok");
      } catch (e) {
        body.textContent = "";
        body.appendChild(h("p", { class: "fig-error" }, "This figure could not draw: " + (e && e.message)));
        fig.setAttribute("data-rendered", "error");
        if (window.console) console.error(e);
      }
      if (!focusKey || (body.contains(document.activeElement) && document.activeElement !== document.body)) return;
      var again = body.querySelector('[data-key="' + focusKey + '"]');
      if (again) again.focus();
    }
    linkButton.addEventListener("click", function () { copyFigureLink(record); });
    mounted[id] = record;
    draw();
    if (spec.selfCheck) {
      var details = h("details", { class: "fig-check" }, h("summary", null, "What this figure checks"));
      details.addEventListener("toggle", function () {
        if (!details.open || details.querySelector("ul")) return;
        details.appendChild(h("ul", null, runFigureChecks(record).map(function (r) {
          return h("li", null, [h("span", { class: r.ok ? "ok" : "bad" }, r.ok ? "✓ " : "✗ "), r.name, r.detail ? " · " + r.detail : ""]);
        })));
      });
      fig.appendChild(details);
    }
  }
  function runFigureChecks(record) {
    if (record.checks) return record.checks;
    try { record.checks = record.spec.selfCheck(record.state, record.ctx) || []; }
    catch (e) { record.checks = [{ name: record.id, ok: false, detail: "the check threw: " + e.message }]; }
    return record.checks;
  }
  function figureLink(record) {
    var parts = [record.fig.id];
    Object.keys(record.spec.params || {}).forEach(function (k) {
      var v = record.state[k];
      if (record.spec.params[k].link === false || v === undefined || v === null) return;
      parts.push(k + "=" + v);
    });
    return location.href.split("#")[0] + "#" + parts.join(";");
  }
  B.linkFor = function (id) { return mounted[id] ? figureLink(mounted[id]) : null; };
  function copyFigureLink(record) {
    var url = figureLink(record);
    try { history.replaceState(null, "", "#" + url.split("#")[1]); } catch (e) { /* the hash stays */ }
    B.copy(url, "Link copied", record.body);
  }
  /** Re-applies #fig-<name>;key=value to a mounted figure when the hash changes. */
  function applyFigureHash() {
    var target = hashTarget(), record = target && mounted[target.id.replace(/^fig-/, "")];
    if (!record || !Object.keys(target.params).length) return;
    var next = {};
    Object.keys(target.params).forEach(function (k) { next[k] = parseValue(record.spec, k, target.params[k]); });
    record.ctx.set(next);
  }
  B.mountFigures = function (root) { (root || document).querySelectorAll("figure.fig[data-fig]").forEach(mountFigure); };

  /** A labelled slider. While the pointer holds its knob it is marked active, so a redraw keeps this very element. */
  B.slider = function (label, value, min, max, step, onInput, text) {
    var key = "slider:" + label, out = h("output", null, text ? text(value) : String(value));
    var input = h("input", { type: "range", min: min, max: max, step: step, value: value, "aria-label": label, "aria-valuetext": text ? text(value) : String(value), "data-key": key });
    input.addEventListener("input", function () { var v = parseFloat(input.value); out.textContent = text ? text(v) : String(v); input.setAttribute("aria-valuetext", out.textContent); onInput(v); });
    input.addEventListener("pointerdown", function () { input.setAttribute("data-active", "1"); });
    input.addEventListener("blur", function () { input.removeAttribute("data-active"); });
    return h("label", { "data-keep": key }, [label, input, out]);
  };
  ["pointerup", "pointercancel"].forEach(function (type) {
    window.addEventListener(type, function () { document.querySelectorAll('[data-active="1"]').forEach(function (el) { el.removeAttribute("data-active"); }); }, true);
  });
  B.select = function (label, options, value, onChange) {
    var sel = h("select", { "aria-label": label, "data-key": "select:" + label }, options.map(function (o) { return h("option", { value: o.value, selected: o.value === value }, o.label); }));
    sel.addEventListener("change", function () { onChange(sel.value); });
    return h("label", null, [label, sel]);
  };
  B.legend = function (items) {
    return h("div", { class: "legend" }, items.map(function (it) {
      return h("span", { class: "key" }, [h("span", { class: "sw", style: "background: " + (it.color || "var(--fg-2)") }), it.label]);
    }));
  };

  // MARK: Mount and self-check

  B.extraChecks = [];
  /** Loads the data the page needs, runs `before` (an app's own mount), then the navigation, the excerpts and the
   *  orb, marks the page mounted, and runs `after`. */
  B.mount = function (before, after) {
    B.loadGroups(groupsWanted(), function () {
      if (before) before();
      buildNav();
      document.querySelectorAll("[data-excerpt]").forEach(renderExcerpt);
      B.mountFigures();
      openTarget();
      window.addEventListener("hashchange", applyFigureHash);
      window.addEventListener("hashchange", openTarget);
      if (B.ask && B.ask.mount) B.ask.mount();
      document.documentElement.setAttribute("data-mounted", "1");
      if (after) after();
    });
  };
  /** Every check the page can make, from every part that registered one, plus the page's own numbers and excerpts. */
  B.selfCheck = function () {
    var results = [];
    B.extraChecks.forEach(function (x) {
      var rows;
      try { rows = x.run() || []; } catch (e) { rows = [{ name: "its checks ran", ok: false, detail: e && e.message }]; }
      rows.forEach(function (r) { results.push(Object.assign({ part: x.name }, r)); });
    });
    factChecks().forEach(function (r) { results.push(Object.assign({ part: "numbers" }, r)); });
    Object.keys(mounted).forEach(function (id) {
      var record = mounted[id];
      results.push({ part: "figure " + id, name: "it drew", ok: record.fig.getAttribute("data-rendered") === "ok" });
      runFigureChecks(record).forEach(function (r) { results.push(Object.assign({ part: "figure " + id }, r)); });
    });
    document.querySelectorAll("[data-excerpt]").forEach(function (node) {
      results.push({ part: "excerpts", name: "the excerpt " + node.getAttribute("data-excerpt") + " drew from the data", ok: node.getAttribute("data-rendered") === "ok" });
    });
    return results;
  };
})();
