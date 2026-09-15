/* Photonz mock · curve · THE ONE EASING VOCABULARY, defined once.
   ------------------------------------------------------------------
   Four different lists of easing options used to be on screen at the
   same time: the icon pages offered Linear / Ease in-out / Spring,
   icon-states offered Linear / Ease out / Spring, icon-drawon offered
   Linear / Ease out / Ease in-out, and the video pages offered two
   buttons or three of their own. The same control said different
   things on different screens for no reason a person could see.

   So the list lives HERE, in one place, and a page asks for it:

     <div class="popover menu pop" id="curveMenu" data-curve-menu></div>
     <div class="popover pop" id="bezPop" data-curve-editor=".34,.56,.64,1"></div>

   and gets the canonical rows, in the canonical order, each drawing
   the shape it does, ending in "Draw a curve...". The names and the
   numbers are the app's own (PhotonzCore EasingCurve, written down in
   docs/design/layer-motion.md), so a mock and the thing it proposes
   cannot say different words for the same curve.

   Three of these ARE the design language's motion tokens under the
   names people use for them: Ease in out is --ease-standard, Ease out
   is --ease-decel, and --ease-spring is what Ease out back does.

   `node shared/check-easing.mjs` is the gate: it fails a page that
   writes its own easing rows instead of asking for these. */
(function () {
  "use strict";
  var PZ = window.PZ || {};
  var all = PZ.all || function (s, r) { return [].slice.call((r || document).querySelectorAll(s)); };

  /* THE LIST. Order is part of the contract: the four standard eases
     first, because they are what nearly every motion wants, then the
     shaped ones that overshoot or jump, then the one you draw. */
  var CURVES = [
    { id: "linear",       el: "easLin",     group: "Standard", label: "Linear",
      d: "M2 22 22 2",                                  css: "linear" },
    { id: "ease-in-out",  el: "easInOut",   group: "Standard", label: "Ease in out",
      d: "M2 22C8 22 16 2 22 2",                        css: "cubic-bezier(.4, 0, .2, 1)",
      token: "--ease-standard" },
    { id: "ease-in",      el: "easIn",      group: "Standard", label: "Ease in",
      d: "M2 22C14 22 22 14 22 2",                      css: "cubic-bezier(.4, 0, 1, 1)" },
    { id: "ease-out",     el: "easOut",     group: "Standard", label: "Ease out",
      d: "M2 22C2 10 10 2 22 2",                        css: "cubic-bezier(0, 0, .2, 1)",
      token: "--ease-decel" },
    { id: "ease-in-out-sine", el: "easSine", group: "Shaped",  label: "Ease in out sine",
      d: "M2 22C10 22 14 2 22 2",                       css: "cubic-bezier(.37, 0, .63, 1)" },
    { id: "ease-out-back", el: "easBack",   group: "Shaped",   label: "Ease out back",
      d: "M2 22C6 26 12 2 22 2",                        css: "cubic-bezier(.34, 1.4, .5, 1)",
      token: "--ease-spring" },
    { id: "ease-out-elastic", el: "easElastic", group: "Shaped", label: "Ease out elastic",
      d: "M2 22c3 0 4-22 6-16s3 12 5 9 2-6 9-6",        css: "cubic-bezier(.22, 1.4, .36, 1)" },
    { id: "steps-4",      el: "easSteps",   group: "Shaped",   label: "Steps, 4",
      d: "M2 22h6v-7h6v-6h8V2",                         css: "steps(4, end)" }
  ];
  /* Not one of the named eight: the door out of the vocabulary, for
     the curve no name covers. It ends every curve menu. */
  var DRAW = { id: "custom", el: "easCustom", label: "Draw a curve…", sc: "⌥⌘C" };

  var NOTE = "Named curves are the front door and <b>Draw a curve</b> is the rest of it. " +
    "The shape beside each name is the point: nobody can tell <i>out back</i> from " +
    "<i>out elastic</i> by reading them. Same control on every page that has timing.";

  function thumb(c, cls) {
    return '<svg class="cvth' + (cls ? " " + cls : "") + '" viewBox="0 0 24 24" aria-hidden="true">' +
      '<path d="' + c.d + '"/></svg>';
  }

  /* The rows, with the group labels and separators that make eight
     names readable as two short lists rather than one long one. */
  function menuHTML(opts) {
    opts = opts || {};
    var out = "", group = null;
    CURVES.forEach(function (c) {
      if (c.group !== group) {
        if (group !== null) out += '<div class="menu-sep"></div>';
        out += '<div class="mlabel">' + c.group + "</div>";
        group = c.group;
      }
      out += '<div class="menuitem" id="' + c.el + '" data-curve="' + c.id + '">' +
        thumb(c) + " " + c.label + "</div>";
    });
    out += '<div class="menu-sep"></div>' +
      '<div class="menuitem" id="' + DRAW.el + '" data-curve="' + DRAW.id + '">' +
      '<i class="ic ic-curves"></i> ' + DRAW.label +
      ' <span class="sc">' + DRAW.sc + "</span></div>";
    if (opts.note !== false) out += '<p class="mnote">' + NOTE + "</p>";
    return out;
  }

  /* The drawn curve: a grid, the two handle arms, the curve itself,
     the two handles, and the four numbers CSS and SVG both take. A
     page says where the handles start; everything else is the same
     everywhere, which is the whole point of this file. */
  function editorHTML(pts, opts) {
    opts = opts || {};
    var p = String(pts || ".34,.56,.64,1").split(",").map(function (n) { return parseFloat(n); });
    var x1 = p[0], y1 = p[1], x2 = p[2], y2 = p[3];
    var X1 = (x1 * 100).toFixed(0), Y1 = (100 - y1 * 100).toFixed(0);
    var X2 = (x2 * 100).toFixed(0), Y2 = (100 - y2 * 100).toFixed(0);
    var num = function (n) { return String(n).replace(/^0\./, "."); };
    var read = "cubic-bezier(" + [x1, y1, x2, y2].map(num).join(", ") + ")";
    return '<div class="mlabel" style="margin:0 0 var(--gap-sm)">' +
        (opts.title || "Draw a curve") + "</div>" +
      '<svg class="bez" viewBox="0 0 100 100" aria-label="Curve editor">' +
        '<path class="gr" d="M0 25H100M0 50H100M0 75H100M25 0V100M50 0V100M75 0V100"/>' +
        '<path class="hl" id="bzL1" d="M0 100 ' + X1 + " " + Y1 + '"/>' +
        '<path class="hl" id="bzL2" d="M100 0 ' + X2 + " " + Y2 + '"/>' +
        '<path class="cv" id="bzCurve" d="M0 100 C' + X1 + " " + Y1 + " " + X2 + " " + Y2 + ' 100 0"/>' +
        '<circle class="hd" id="bzH1" cx="' + X1 + '" cy="' + Y1 + '" r="5.5"/>' +
        '<circle class="hd" id="bzH2" cx="' + X2 + '" cy="' + Y2 + '" r="5.5"/>' +
      "</svg>" +
      '<div class="bezval"><code id="bzVal">' + read + "</code></div>" +
      '<p class="note" style="margin-top:var(--gap-sm)">Drag either handle. The readout is ' +
      "the same four numbers CSS and SVG both take, so what you draw here is what ships.</p>";
  }

  /* Idempotent, like every component here: filling a host marks it, so
     running twice does nothing and a page that has no curve control
     pays nothing. */
  function upgrade(root) {
    all("[data-curve-menu]", root).forEach(function (m) {
      if (m.getAttribute("data-curve-ready") === "1") return;
      m.setAttribute("data-curve-ready", "1");
      m.classList.add("curvemenu");
      m.innerHTML = menuHTML({ note: m.getAttribute("data-curve-note") !== "off" }) + m.innerHTML;
    });
    all("[data-curve-editor]", root).forEach(function (b) {
      if (b.getAttribute("data-curve-ready") === "1") return;
      b.setAttribute("data-curve-ready", "1");
      b.innerHTML = editorHTML(b.getAttribute("data-curve-editor"),
        { title: b.getAttribute("data-curve-title") }) + b.innerHTML;
    });
  }

  upgrade(document);

  /* Published so a page can read the list rather than retype it: the
     interactive video mock drives its own keyframe engine off these
     names and their cubic-beziers. */
  PZ.curve = {
    list: CURVES, draw: DRAW, menuHTML: menuHTML, editorHTML: editorHTML,
    upgrade: upgrade, thumb: thumb,
    /* the row for an id, so a readout can print the canonical label */
    get: function (id) {
      for (var i = 0; i < CURVES.length; i++) if (CURVES[i].id === id) return CURVES[i];
      return null;
    },
    /* How far along the change is, t of the way through the time. The
       same answers PhotonzCore's EasingCurve.value(at:) gives, so the
       mock moves the way the app would. */
    at: function (id, t) {
      t = Math.max(0, Math.min(1, t));
      if (id === "linear") return t;
      if (id === "ease-in-out-sine") return -(Math.cos(Math.PI * t) - 1) / 2;
      if (id === "ease-out-back") {
        var c1 = 1.70158, c3 = c1 + 1, q = t - 1;
        return 1 + c3 * q * q * q + c1 * q * q;
      }
      if (id === "ease-out-elastic") {
        if (t === 0 || t === 1) return t;
        return Math.pow(2, -10 * t) * Math.sin((t * 10 - 0.75) * (2 * Math.PI) / 3) + 1;
      }
      if (id === "steps-4") return t >= 1 ? 1 : Math.floor(4 * t) / 4;
      if (id === "ease-in-out") return bezier(t, 0.4, 0, 0.2, 1);
      if (id === "ease-in") return bezier(t, 0.4, 0, 1, 1);
      if (id === "ease-out") return bezier(t, 0, 0, 0.2, 1);
      var m = /^custom:([-\d.]+),([-\d.]+),([-\d.]+),([-\d.]+)$/.exec(String(id));
      if (m) return bezier(t, +m[1], +m[2], +m[3], +m[4]);
      return bezier(t, 0.4, 0, 0.2, 1);
    }
  };

  /* cubic-bezier evaluated the way a browser does it: find the
     parameter whose x is the time you asked for, then read its y.
     Newton first, bisection after it, because Newton stalls where the
     curve is flat and a stalled solver returns the wrong shape
     silently rather than failing. Same shape as the Swift one. */
  function bezier(t, x1, y1, x2, y2) {
    function curve(a, b, u) { var v = 1 - u; return 3 * v * v * u * a + 3 * v * u * u * b + u * u * u; }
    function slope(a, b, u) {
      var v = 1 - u;
      return 3 * v * v * (a) + 6 * v * u * (b - a) + 3 * u * u * (1 - b);
    }
    var u = t, i;
    for (i = 0; i < 8; i++) {
      var x = curve(x1, x2, u) - t, d = slope(x1, x2, u);
      if (Math.abs(x) < 1e-6) return curve(y1, y2, u);
      if (Math.abs(d) < 1e-6) break;
      u -= x / d;
    }
    var lo = 0, hi = 1; u = t;
    for (i = 0; i < 24; i++) {
      var cx = curve(x1, x2, u);
      if (Math.abs(cx - t) < 1e-6) break;
      if (cx > t) hi = u; else lo = u;
      u = (lo + hi) / 2;
    }
    return curve(y1, y2, u);
  }

  window.PZ = PZ;
})();
