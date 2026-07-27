/* Photonz mock · the canonical .slider, plus the zoom slider and scrubber.
   Split out of photonz-ds.js; see shared/components/README.md.

   `.slider` keeps a real <input type=range> for keyboard and accessibility and
   paints the look from `--p` (0..1). This pass writes `--p`, formats the value
   into the row's `.num` and the drag bubble, and adds `.drag` while the pointer
   is down. Idempotent: it marks what it has wired and skips it next time. */
(function () {
  var PZ = window.PZ || {};
  var all = PZ.all, winOf = PZ.winOf, isNarrow = PZ.isNarrow, NARROW = PZ.NARROW;

  /* ---- 0 · the canonical slider ---- */
  function fmt(el, v) {
    var dp = parseInt(el.getAttribute('data-dp') || '0', 10);
    var unit = el.getAttribute('data-unit') || '';
    var s = dp ? v.toFixed(dp) : String(Math.round(v));
    if (dp === 0 && el.getAttribute('data-sign') === '1' && v > 0) s = '+' + s;
    return s + unit;
  }
  function ensure(sl, cls, tag) {
    var el = sl.querySelector(':scope > .' + cls.split(' ').join('.'));
    if (!el) { el = document.createElement(tag || 'span'); el.className = cls; sl.appendChild(el); }
    return el;
  }
  all('.slider').forEach(function (sl) {
    if (sl.dataset.pzSlider) return;
    sl.dataset.pzSlider = '1';
    var track = ensure(sl, 'sl-track');
    if (!track.querySelector('.sl-fill')) { var f = document.createElement('i'); f.className = 'sl-fill'; track.appendChild(f); }
    ensure(sl, 'sl-thumb');
    var input = sl.querySelector('input[type=range]');
    var row = sl.closest('.slrow');
    var num = row && row.querySelector('.num');
    var bub = sl.querySelector('.sl-bub');

    if (sl.classList.contains('range')) { wireRange(sl); return; }
    if (!input) return;

    var min = parseFloat(input.min || 0), max = parseFloat(input.max || 100);

    /* A PAINT thumb carries the colour it is setting, so it has to repaint on
       every move — a hue knob that stays one colour while you drag it across
       the spectrum is telling you about the position and not the result, which
       is the one thing you are looking at. `--sl-c` is what the thumb fills
       with; `.hue` derives it from the angle, `.alpha` from the value, and any
       other paint track can declare `--sl-from` / `--sl-to` to be mixed. */
    var paint = sl.classList.contains('paint');
    function paintColor(p, v) {
      if (sl.classList.contains('hue')) return 'hsl(' + Math.round(p * 360) + ' 100% 50%)';
      var pct = Math.round(p * 100);
      if (sl.classList.contains('alpha')) {
        return 'color-mix(in srgb, var(--sl-to, ' + accent() + ') ' + pct + '%, transparent)';
      }
      var from = sl.style.getPropertyValue('--sl-from') || getComputedStyle(sl).getPropertyValue('--sl-from');
      if (from.trim()) return 'color-mix(in srgb, var(--sl-to) ' + pct + '%, var(--sl-from))';
      return '';
    }
    function accent() { return getComputedStyle(sl).getPropertyValue('--accent').trim() || '#4c6fff'; }

    function sync() {
      var v = parseFloat(input.value);
      var p = max === min ? 0 : (v - min) / (max - min);
      sl.style.setProperty('--p', p.toFixed(4));
      if (paint) {
        var c = paintColor(p, v);
        if (c) sl.style.setProperty('--sl-c', c);
      }
      var text = fmt(sl, v);
      if (num && num.dataset.pzFrozen !== '1') num.textContent = text;
      if (bub) bub.textContent = text;
      sl.setAttribute('aria-valuetext', text);
    }
    input.addEventListener('input', sync);
    ['pointerdown', 'keydown'].forEach(function (t) {
      input.addEventListener(t, function () { sl.classList.add('drag'); });
    });
    ['pointerup', 'pointercancel', 'blur', 'keyup'].forEach(function (t) {
      input.addEventListener(t, function () { sl.classList.remove('drag'); });
    });

    /* the number is a scrub field: drag it sideways to change the slider.
       This is the Photoshop/Figma gesture and it is the reason the value is
       not a plain <span> anywhere in the app. */
    if (num) {
      num.tabIndex = 0;
      num.addEventListener('pointerdown', function (e) {
        e.preventDefault();
        num.setPointerCapture(e.pointerId);
        var x0 = e.clientX, v0 = parseFloat(input.value);
        var step = (max - min) / 200;
        sl.classList.add('drag');
        function move(ev) {
          var v = Math.max(min, Math.min(max, v0 + (ev.clientX - x0) * step));
          input.value = v;
          input.dispatchEvent(new Event('input', { bubbles: true }));
        }
        function up() {
          sl.classList.remove('drag');
          num.removeEventListener('pointermove', move);
          num.removeEventListener('pointerup', up);
        }
        num.addEventListener('pointermove', move);
        num.addEventListener('pointerup', up);
      });
    }
    sync();
  });

  /* a two-value slider has no native equivalent, so it is driven directly.
     Pointerdown picks the NEARER thumb, which is the only rule that makes a
     range feel right when both thumbs sit close together. */
  function wireRange(sl) {
    var hi = sl.querySelector('.sl-thumb.hi');
    if (!hi) { hi = document.createElement('span'); hi.className = 'sl-thumb hi'; sl.appendChild(hi); }
    var out = sl.closest('.slrow') && sl.closest('.slrow').querySelector('.num');
    function get(n) { return parseFloat(getComputedStyle(sl).getPropertyValue(n)) || 0; }
    function paint() {
      if (out) out.textContent = Math.round(get('--p') * 100) + '–' + Math.round(get('--p2') * 100) + (sl.getAttribute('data-unit') || '');
    }
    sl.addEventListener('pointerdown', function (e) {
      var r = sl.getBoundingClientRect();
      var p = Math.max(0, Math.min(1, (e.clientX - r.left) / r.width));
      var which = Math.abs(p - get('--p')) <= Math.abs(p - get('--p2')) ? '--p' : '--p2';
      sl.setPointerCapture(e.pointerId);
      sl.classList.add('drag');
      function move(ev) {
        var q = Math.max(0, Math.min(1, (ev.clientX - r.left) / r.width));
        if (which === '--p') q = Math.min(q, get('--p2')); else q = Math.max(q, get('--p'));
        sl.style.setProperty(which, q.toFixed(4));
        paint();
      }
      move(e);
      function up() {
        sl.classList.remove('drag');
        sl.removeEventListener('pointermove', move);
        sl.removeEventListener('pointerup', up);
      }
      sl.addEventListener('pointermove', move);
      sl.addEventListener('pointerup', up);
    });
    paint();
  }

  /* ---- 7 · zoom slider + scrubber readouts ----
     VISUAL RULE 5: zoom drives the canvas grid density, not just a readout.
     The slider owns the canvases in ITS shell only (a page can host several
     windows / walkthrough steps), so scope up to the nearest canvas column
     before collecting them. `.canvas.mini` specimens never zoom. */
  all('.zslider').forEach(function (s) {
    var out = (s.closest('.zoomctl') || document).querySelector('.zval');
    var scope = s.closest('.cnv, .edit, .wt-step, .win, .shell');
    var canvases = scope ? all('.canvas:not(.mini)', scope)
      : (all('.canvas:not(.mini)').length === 1 ? all('.canvas:not(.mini)') : []);
    var sync = function () {
      var z = (parseFloat(s.value) || 100) / 100;
      if (out) out.textContent = Math.round(z * 100) + '%';
      canvases.forEach(function (c) { c.style.setProperty('--zoom', z); });
    };
    s.addEventListener('input', sync);
    sync();
  });
  function tcode(sec) {
    sec = Math.max(0, sec);
    var m = Math.floor(sec / 60), s = Math.floor(sec % 60);
    return m + ':' + (s < 10 ? '0' : '') + s;
  }
  all('.scrub').forEach(function (sc) {
    var fill = sc.querySelector('.fill');
    var knob = sc.querySelector('.knob');
    var cur = (sc.parentNode || document).querySelector('.tc.cur');
    var dur = parseFloat(sc.getAttribute('data-duration') || '0');
    function seek(e) {
      var r = sc.getBoundingClientRect();
      var p = Math.max(0, Math.min(1, (e.clientX - r.left) / r.width));
      if (fill) fill.style.width = (p * 100) + '%';
      if (knob) knob.style.left = (p * 100) + '%';
      if (cur && dur) cur.textContent = tcode(p * dur);
    }
    sc.addEventListener('pointerdown', function (e) {
      e.preventDefault();
      if (sc.setPointerCapture) sc.setPointerCapture(e.pointerId);
      sc.dataset.seeking = '1';
      seek(e);
    });
    sc.addEventListener('pointermove', function (e) { if (sc.dataset.seeking) seek(e); });
    ['pointerup', 'pointercancel'].forEach(function (t) {
      sc.addEventListener(t, function () { delete sc.dataset.seeking; });
    });
  });
})();
