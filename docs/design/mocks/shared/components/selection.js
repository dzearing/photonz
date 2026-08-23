/* Photonz mock · selection — builds the frame, and stamps the size bucket the
   frame adapts to. See selection.css for the model. Split out of the canvas
   rules so selection is one component you can read in one file. */
(function () {
  var PZ = window.PZ || {};
  var all = PZ.all;

  var XS = 16, SM = 44;   // px thresholds, matching selection.css

  /* ============================================================
     0 · THE FRAME IS DECLARED, NOT DRAWN
     ============================================================
     Every selected object on every canvas needs the same four things — a ring
     on the bounds, four corner grabs, and a tag with its numbers — and for 88
     frames across 55 pages that was four lines of markup retyped by hand:

       <span class="sel-ring"></span>
       <span class="handle tl"></span><span class="handle tr"></span>
       <span class="handle bl"></span><span class="handle br"></span>
       <span class="mtag">Frame · 268 × 95</span>

     Retyping it is how it goes wrong. Five separate tasks in one cycle each
     fixed the SAME defect on a different page: the copy said something was
     selected and the canvas drew nothing, because drawing it was four lines
     nobody remembered to write. A page that forgets a line it never has to
     write cannot forget it.

     So a page DECLARES the selection and this builds it, the way `data-shell`
     builds the title bar:

       <div class="selwrap" data-sel-frame="Frame · 268 × 95"></div>

     The value is the measurement tag. Leave it empty for a frame with no tag.
     If the tag carries page state (a walkthrough retags it by id), author the
     `.mtag` yourself inside the host and this leaves its text alone, moving it
     after the handles so the paint order matches:

       <div class="selwrap wt-off" id="selFrame" data-sel-frame>
         <span class="mtag" id="selFrameMtag">Frame · 268 × 95</span>
       </div>

     `data-sel-parts` adds the rarer pieces, space separated:
       edges    the four edge midpoints (.tc/.bc/.ml/.mr), for single-axis resize
       rotate   the rotate knob on its stem above the top edge
       none     ring only, no grabs — a preview, or a frame you cannot transform

     WHAT IT DOES NOT DO is decide where the frame lands. The parts are
     absolutely positioned, so they hug the nearest POSITIONED ancestor — put
     the attribute on the object's own box and give that box `.selwrap`
     (`position:relative`, nothing else) if it has no positioning of its own.
     Pages that toggle a whole frame with `.wt-off` often hang it on an empty
     wrapper inside the box instead, and that keeps working untouched: this
     builds the parts and never moves them. */

  var CORNERS = ['tl', 'tr', 'bl', 'br'];
  var EDGES = ['tc', 'bc', 'ml', 'mr'];

  function el(tag, cls) {
    var n = document.createElement(tag);
    n.className = cls;
    return n;
  }

  function build(host) {
    // Idempotent: this runs again on every mutation, and walkthrough steps
    // replay a snapshot that already contains what we built.
    if (host.querySelector(':scope > .sel-ring')) return;

    var parts = (host.getAttribute('data-sel-parts') || '').split(/\s+/);
    var has = function (p) { return parts.indexOf(p) >= 0; };

    host.appendChild(el('div', 'sel-ring'));

    if (!has('none')) {
      CORNERS.forEach(function (c) { host.appendChild(el('span', 'handle ' + c)); });
      if (has('edges')) EDGES.forEach(function (c) { host.appendChild(el('span', 'handle ' + c)); });
      if (has('rotate')) {
        host.appendChild(el('span', 'rotstem'));
        host.appendChild(el('span', 'rot'));
      }
    }

    /* The tag goes LAST, after the grabs, so it paints over them exactly as the
       hand-written form did. An authored one is moved rather than replaced:
       its text is the page's to change. */
    var tag = host.querySelector(':scope > .mtag');
    var text = host.getAttribute('data-sel-frame');
    if (!tag && text) { tag = el('span', 'mtag'); tag.textContent = text; }
    if (tag) host.appendChild(tag);
  }

  /* The FRAME is constant at every size; only the handles change, and they
     change on the measured box rather than on a page-authored class, so a
     selection that is resized (or drawn small in one page and large in
     another) always lands in the right bucket without anyone remembering. */
  /* Work off the RING, not off `.selwrap`. Seven pages position a ring inside
     their own wrapper (.ig-selbox, .gc-el, .wnode, .hoel …) and never use
     `.selwrap` at all; keying on the wrapper class would have left exactly
     those pages un-adapted, which is how the old inconsistency spread. The
     element that gets stamped is whatever the ring is positioned against. */
  function hostOf(ring) {
    return ring.offsetParent || ring.parentElement;
  }

  function stamp(ring) {
    var host = hostOf(ring);
    if (!host) return;
    var r = host.getBoundingClientRect();
    if (!r.width && !r.height) return;               // not laid out yet
    var min = Math.min(r.width, r.height);
    host.setAttribute('data-sel', min < XS ? 'xs' : (min < SM ? 'sm' : 'md'));

    // the tag needs room above it, or it gets clipped by the canvas edge
    if (host.querySelector('.mtag')) {
      var canvas = host.closest('.canvas') || host.closest('.cnv');
      var top = canvas ? canvas.getBoundingClientRect().top : 0;
      host.setAttribute('data-mtag', r.top - top < 34 ? 'below' : 'above');
    }
  }

  function scan(root) {
    all('[data-sel-frame]', root || document).forEach(build);
    all('.sel-ring', root || document).forEach(stamp);
  }

  scan();

  // Selections move, resize and get created by walkthrough steps, so measure
  // on change rather than once at load.
  if (window.ResizeObserver) {
    var seen = new WeakSet();
    var ro = new ResizeObserver(function (entries) {
      entries.forEach(function (e) {
        var ring = e.target.querySelector(':scope > .sel-ring') ||
                   e.target.querySelector('.sel-ring');
        if (ring) stamp(ring);
      });
    });
    var observe = function () {
      all('[data-sel-frame]').forEach(build);
      all('.sel-ring').forEach(function (ring) {
        var host = hostOf(ring);
        if (host && !seen.has(host)) { seen.add(host); ro.observe(host); }
        stamp(ring);
      });
    };
    observe();
    if (window.MutationObserver) {
      var pending = null;
      new MutationObserver(function () {
        clearTimeout(pending);
        pending = setTimeout(observe, 60);
      }).observe(document.documentElement, { childList: true, subtree: true });
    }
  }
  window.addEventListener('resize', function () { scan(); });
})();
