/* Photonz mock · selection — stamps the size bucket the frame adapts to.
   See selection.css for the model. Split out of the canvas rules so selection
   is one component you can read in one file. */
(function () {
  var PZ = window.PZ || {};
  var all = PZ.all;

  var XS = 16, SM = 44;   // px thresholds, matching selection.css

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
