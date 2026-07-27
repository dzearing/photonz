/* Photonz mock · redline callouts.
   See redline.css for the markup contract. This pass owns three things:

     1. numbering      — filled from DOM order, so a page never hand-numbers
     2. positioning    — the row, the gutter side and the leader-line length are
                         MEASURED from the target, every time the layout moves
     3. the card       — click to open, one at a time, Escape or outside to close

   Idempotent and a no-op on a page with no `.rl-frame`. Lives with the shared
   components so `app-shell` and every doc page get the same behaviour instead
   of app-shell keeping a private copy. */
(function () {
  var PZ = window.PZ || {};
  var all = PZ.all || function (sel, root) {
    return [].slice.call((root || document).querySelectorAll(sel));
  };

  var frames = all('.rl-frame').filter(function (f) { return !f.dataset.pzRedline; });
  if (!frames.length) return;

  /* one document-level close handler for every frame on the page */
  if (!document.documentElement.dataset.pzRedlineDoc) {
    document.documentElement.dataset.pzRedlineDoc = '1';
    var closeAll = function () {
      all('.rl-co.open').forEach(function (x) { x.classList.remove('open'); });
    };
    document.addEventListener('click', closeAll);
    document.addEventListener('keydown', function (e) { if (e.key === 'Escape') closeAll(); });
  }

  frames.forEach(function (frame) {
    frame.dataset.pzRedline = '1';
    var cos = all('.rl-co', frame);
    if (!cos.length) return;

    cos.forEach(function (co, i) {
      var btn = co.querySelector('.n');
      if (!btn) return;
      /* number and label the marker from its own card, so the page writes the
         prose once and the accessible name comes along for free */
      if (!btn.textContent.trim()) btn.textContent = String(i + 1);
      if (!btn.getAttribute('aria-label')) {
        var t = co.querySelector('.card b');
        btn.setAttribute('aria-label', 'Region ' + btn.textContent.trim() + (t ? ': ' + t.textContent : ''));
      }
      btn.addEventListener('click', function (e) {
        e.stopPropagation();
        var open = co.classList.contains('open');
        all('.rl-co.open').forEach(function (x) { x.classList.remove('open'); });
        if (!open) co.classList.add('open');
      });
      /* a click inside the card must not close it */
      var card = co.querySelector('.card');
      if (card) card.addEventListener('click', function (e) { e.stopPropagation(); });
    });

    /* Build the leader once per callout: halo group under, accent on top, so
       the outline follows the exact silhouette of line + elbow + dot. */
    var NS = 'http://www.w3.org/2000/svg';
    function svgEl(name, attrs) {
      var n = document.createElementNS(NS, name);
      for (var k in attrs) n.setAttribute(k, attrs[k]);
      return n;
    }
    cos.forEach(function (co) {
      var host = co.querySelector('.l');
      if (!host || host.querySelector('svg')) return;
      var svg = svgEl('svg', {});
      var g = svgEl('g', { 'class': 'halo' });
      g.appendChild(svgEl('path', {}));
      g.appendChild(svgEl('circle', { r: 2 }));
      svg.appendChild(g);
      svg.appendChild(svgEl('path', { 'class': 'core' }));
      svg.appendChild(svgEl('circle', { 'class': 'core', r: 2 }));
      host.appendChild(svg);
    });

    /* line of length W, elbowing by `drop` at the target end. y = 0 is the
       marker's row; the dot sits at (W, drop). */
    function leader(co, W, drop) {
      var svg = co.querySelector('.l svg');
      if (!svg) return;
      var M = Math.max(Math.abs(drop), 6) + 6;
      var d;
      if (Math.abs(drop) < 0.5) {
        d = 'M0 0 H' + W;
      } else {
        var s = drop > 0 ? 1 : -1;
        var R = Math.min(7, Math.abs(drop));
        d = 'M0 0 H' + (W - R) + ' Q' + W + ' 0 ' + W + ' ' + (s * R) + ' V' + drop;
      }
      /* the box is exactly the line's length, so mirroring it about its own
         centre for a right-gutter callout puts x=0 back at the marker and
         x=W at the target. Round caps overhang, which overflow:visible allows. */
      svg.setAttribute('width', W);
      svg.setAttribute('height', 2 * M);
      svg.setAttribute('viewBox', '0 ' + (-M) + ' ' + W + ' ' + (2 * M));
      svg.style.top = (-M) + 'px';
      svg.querySelectorAll('path').forEach(function (p) { p.setAttribute('d', d); });
      svg.querySelectorAll('circle').forEach(function (c) {
        c.setAttribute('cx', W); c.setAttribute('cy', drop);
      });
    }

    function visible(el) {
      if (!el) return false;
      var s = getComputedStyle(el);
      if (s.display === 'none' || s.visibility === 'hidden') return false;
      var r = el.getBoundingClientRect();
      return r.width > 0 && r.height > 0;
    }
    function anchor(r, co) {
      var x = co.getAttribute('data-rl-x') || 'center';
      var y = co.getAttribute('data-rl-y') || 'center';
      var dx = parseFloat(co.getAttribute('data-rl-dx') || 0);
      var dy = parseFloat(co.getAttribute('data-rl-dy') || 0);
      return {
        x: (x === 'left' ? r.left : x === 'right' ? r.right : (r.left + r.right) / 2) + dx,
        y: (y === 'top' ? r.top : y === 'bottom' ? r.bottom : (r.top + r.bottom) / 2) + dy
      };
    }

    function place() {
      var fr = frame.getBoundingClientRect();
      if (fr.width < 2) return;
      cos.forEach(function (co) {
        var sel = co.getAttribute('data-rl-for');
        var target = sel ? frame.querySelector(sel) : null;
        /* a callout with no resolvable, visible target hides rather than
           pointing at empty background (a collapsed dock, a hidden panel) */
        if (sel && !visible(target)) { co.style.display = 'none'; return; }
        co.style.display = '';
        if (!target) return;

        var a = anchor(target.getBoundingClientRect(), co);
        var ax = a.x - fr.left, ay = a.y - fr.top;

        /* gutter: whichever side the anchor is nearer, unless the page says */
        var side = co.getAttribute('data-rl-side');
        if (side !== 'l' && side !== 'r') side = ax < fr.width / 2 ? 'l' : 'r';
        co.classList.toggle('l-side', side === 'l');
        co.classList.toggle('r-side', side === 'r');

        /* data-rl-row lifts the marker off its target's row so several
           callouts on one dense specimen do not stack. The leader elbows
           back down (or up) to the dot by exactly that much. */
        var row = parseFloat(co.getAttribute('data-rl-row') || 0);
        co.style.top = Math.round(ay + row - 9.5) + 'px';

        var line = Math.max(16, Math.round(side === 'l' ? (ax - 24) : (fr.width - 24 - ax)));
        co.style.setProperty('--rl-line', line + 'px');
        leader(co, line, -row);
        /* a marker low in the frame opens its card upward so it stays on screen */
        co.classList.toggle('up', (ay + row) > fr.height * 0.62);
      });
    }

    requestAnimationFrame(place);
    window.addEventListener('resize', place);
    /* the specimen can change shape without the window doing so: a dock
       collapses, a panel group closes, an image finishes loading. Re-place on
       both, and once more after the 0.2s chrome transition has settled. */
    if (window.ResizeObserver) new ResizeObserver(function () { place(); }).observe(frame);
    new MutationObserver(function () {
      requestAnimationFrame(place);
      setTimeout(place, 240);
    }).observe(frame, { attributes: true, subtree: true, attributeFilter: ['data-dock', 'data-ws', 'class'] });
  });
})();
