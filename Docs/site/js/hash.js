/*
 * Bless's bytes in the browser: SHA-256 (pure, synchronous, the same bytes in every browser and from file://,
 * Braid's docs/site/js/model.js), hex and base64, the canonical layouts a seal signs and a ledger hash covers
 * (Sources/Bless/Support/Canonical.swift, written again here field for field), and Web Crypto's SHA-256 and
 * Ed25519 where the browser has them. The chain and seal figures recompute the fixtures' bytes with these, and the
 * self-check holds them to the fixtures' own hex.
 *
 * SPDX-License-Identifier: GPL-3.0-only
 */
(function () {
  "use strict";
  var B = window.Bless;
  var K = new Uint32Array([0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5, 0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
    0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174, 0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da, 0x983e5152,
    0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967, 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb,
    0x81c2c92e, 0x92722c85, 0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070, 0x19a4c116, 0x1e376c08, 0x2748774c,
    0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3, 0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2]);
  function utf8(text) { return new TextEncoder().encode(text); }
  /** SHA-256 of a string's UTF-8 bytes, or of bytes, as 32 bytes. */
  B.sha256 = function (input) {
    var bytes = typeof input === "string" ? utf8(input) : input;
    var len = bytes.length, total = ((len + 9 + 63) >> 6) << 6, buf = new Uint8Array(total);
    buf.set(bytes); buf[len] = 0x80;
    var bits = len * 8, view = new DataView(buf.buffer);
    view.setUint32(total - 8, Math.floor(bits / 0x100000000)); view.setUint32(total - 4, bits >>> 0);
    var h = new Uint32Array([0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19]), w = new Uint32Array(64);
    for (var off = 0; off < total; off += 64) {
      for (var i = 0; i < 16; i++) w[i] = view.getUint32(off + i * 4);
      for (var j = 16; j < 64; j++) {
        var x = w[j - 15], y = w[j - 2];
        var s0 = ((x >>> 7) | (x << 25)) ^ ((x >>> 18) | (x << 14)) ^ (x >>> 3), s1 = ((y >>> 17) | (y << 15)) ^ ((y >>> 19) | (y << 13)) ^ (y >>> 10);
        w[j] = (w[j - 16] + s0 + w[j - 7] + s1) >>> 0;
      }
      var a = h[0], b = h[1], c = h[2], d = h[3], e = h[4], f = h[5], g = h[6], hh = h[7];
      for (var r = 0; r < 64; r++) {
        var S1 = ((e >>> 6) | (e << 26)) ^ ((e >>> 11) | (e << 21)) ^ ((e >>> 25) | (e << 7)), ch = (e & f) ^ (~e & g);
        var t1 = (hh + S1 + ch + K[r] + w[r]) >>> 0;
        var S0 = ((a >>> 2) | (a << 30)) ^ ((a >>> 13) | (a << 19)) ^ ((a >>> 22) | (a << 10)), maj = (a & b) ^ (a & c) ^ (b & c);
        var t2 = (S0 + maj) >>> 0;
        hh = g; g = f; f = e; e = (d + t1) >>> 0; d = c; c = b; b = a; a = (t1 + t2) >>> 0;
      }
      h[0] = (h[0] + a) >>> 0; h[1] = (h[1] + b) >>> 0; h[2] = (h[2] + c) >>> 0; h[3] = (h[3] + d) >>> 0;
      h[4] = (h[4] + e) >>> 0; h[5] = (h[5] + f) >>> 0; h[6] = (h[6] + g) >>> 0; h[7] = (h[7] + hh) >>> 0;
    }
    var out = new Uint8Array(32), ov = new DataView(out.buffer);
    for (var q = 0; q < 8; q++) ov.setUint32(q * 4, h[q]);
    return out;
  };
  B.hex = function (bytes) { return Array.from(bytes).map(function (b) { return b.toString(16).padStart(2, "0"); }).join(""); };
  B.fromHex = function (hex) { var out = new Uint8Array(hex.length / 2); for (var i = 0; i < out.length; i++) out[i] = parseInt(hex.substr(i * 2, 2), 16); return out; };
  B.fromBase64 = function (text) { var raw = atob(text), out = new Uint8Array(raw.length); for (var i = 0; i < raw.length; i++) out[i] = raw.charCodeAt(i); return out; };
  B.digest = function (text) { return B.hex(B.sha256(text)); };

  // MARK: The canonical layouts (Canonical.swift): strings counted in UInt32, int64s big-endian, digests raw,
  // optionals 0x00 or 0x01 then the value, enum cases as their names

  function Writer() { this.parts = []; this.size = 0; this.marks = []; }
  Writer.prototype.push = function (bytes, label) { this.marks.push({ at: this.size, length: bytes.length, label: label || "" }); this.parts.push(bytes); this.size += bytes.length; };
  Writer.prototype.u32 = function (v) { var b = new Uint8Array(4); new DataView(b.buffer).setUint32(0, v); return b; };
  Writer.prototype.string = function (v, label) { var u = utf8(v); var out = new Uint8Array(4 + u.length); out.set(this.u32(u.length)); out.set(u, 4); this.push(out, label); };
  Writer.prototype.optional = function (v, label) { if (v === null || v === undefined) this.push(new Uint8Array([0]), label); else { this.push(new Uint8Array([1]), label); this.string(v, label); } };
  Writer.prototype.int64 = function (v, label) { var b = new Uint8Array(8), dv = new DataView(b.buffer); dv.setUint32(0, Math.floor(v / 0x100000000)); dv.setUint32(4, v >>> 0); this.push(b, label); };
  Writer.prototype.digest = function (hex, label) { this.push(B.fromHex(hex), label); };
  Writer.prototype.optionalDigest = function (hex, label) { if (!hex) this.push(new Uint8Array([0]), label); else { this.push(new Uint8Array([1]), label); this.digest(hex, label); } };
  Writer.prototype.bytes = function () { var out = new Uint8Array(this.size), at = 0; this.parts.forEach(function (p) { out.set(p, at); at += p.length; }); return out; };

  B.canonical = {
    /** bless/event/1: what a ledger event's hash covers, from the event's JSON. { bytes, marks } */
    event: function (e) {
      var w = new Writer();
      w.string("bless/event/1", "tag"); w.int64(e.seq, "seq"); w.int64(e.at, "at"); w.string(e.kind, "kind"); w.string(e.petitionID, "petitionID");
      w.optional(e.actor, "actor"); w.optionalDigest(e.digest, "digest"); w.optional(e.code, "code"); w.digest(e.previous, "previous");
      return { bytes: w.bytes(), marks: w.marks };
    },
    /** bless/verdict/1: what a reviewer's seal signs, from the verdict's JSON. { bytes, marks } */
    verdict: function (v) {
      var w = new Writer(), r = v.ruling;
      w.string("bless/verdict/1", "tag"); w.string(v.petitionID, "petitionID"); w.string(v.reviewer, "reviewer"); w.string(r.kind, "ruling");
      if (r.kind === "amend") w.string(r.content, "content");
      if (r.kind === "withhold") w.string(r.reason, "reason");
      w.digest(v.digest, "digest"); w.optional(v.note, "note"); w.int64(v.issued, "issued");
      return { bytes: w.bytes(), marks: w.marks };
    }
  };

  // MARK: Web Crypto, where the browser has it (file:// counts as a secure context in Chrome and Safari)

  function subtle() { try { return window.crypto && window.crypto.subtle ? window.crypto.subtle : null; } catch (e) { return null; } }
  /** SHA-256 by Web Crypto, as hex; resolves null without it. */
  B.subtleDigest = function (bytes) {
    var c = subtle();
    if (!c) return Promise.resolve(null);
    return c.digest("SHA-256", bytes).then(function (d) { return B.hex(new Uint8Array(d)); }, function () { return null; });
  };
  var ED = { name: "Ed25519" };
  B.ed25519 = {
    /** Whether this browser verifies Ed25519 (Chrome 137 and Safari 17 do). */
    verify: function (publicRaw, signature, bytes) {
      var c = subtle();
      if (!c) return Promise.resolve(null);
      return c.importKey("raw", publicRaw, ED, false, ["verify"])
        .then(function (key) { return c.verify(ED, key, signature, bytes); })
        .catch(function () { return null; });
    },
    /** A fresh key pair made in this browser: { publicRaw, privateKey }, or null. */
    generate: function () {
      var c = subtle();
      if (!c) return Promise.resolve(null);
      return c.generateKey(ED, true, ["sign", "verify"])
        .then(function (pair) { return c.exportKey("raw", pair.publicKey).then(function (raw) { return { publicRaw: new Uint8Array(raw), privateKey: pair.privateKey }; }); })
        .catch(function () { return null; });
    },
    sign: function (privateKey, bytes) {
      var c = subtle();
      if (!c) return Promise.resolve(null);
      return c.sign(ED, privateKey, bytes).then(function (sig) { return new Uint8Array(sig); }, function () { return null; });
    }
  };

  if (B.extraChecks) B.extraChecks.push({ name: "hash", run: function () {
    var out = [{ name: "SHA-256 of \"abc\" is the standard's answer", ok: B.digest("abc") === "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad" },
               { name: "SHA-256 of \"hello\" is the digest CanonicalTests pins", ok: B.digest("hello") === "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824" }];
    var fx = (B.data().fixtures || {}).ledger;
    if (fx) {
      var bad = fx.events.filter(function (e, i) { return B.hex(B.canonical.event(e).bytes) !== fx.canonical[i]; });
      out.push({ name: "every fixture event's canonical bytes, written here, equal Swift's", ok: !bad.length, detail: bad.length ? "event " + bad[0].seq : fx.events.length + " events" });
    }
    var seal = (B.data().fixtures || {}).seal;
    if (seal) out.push({ name: "the fixture verdict's canonical bytes, written here, equal Swift's", ok: B.hex(B.canonical.verdict(seal.verdict).bytes) === seal.canonical });
    return out;
  } });
})();
