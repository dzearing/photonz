/* Photonz mock · the agent chat overlay, which is also the command palette (D6).
   Split out of photonz-ds.js; see shared/components/README.md. */
(function () {
  var PZ = window.PZ || {};
  var all = PZ.all, winOf = PZ.winOf, isNarrow = PZ.isNarrow, NARROW = PZ.NARROW;
  /* ---- 4b · ASK: the agent chat overlay (D6 revised) ----
     [data-ask="#id"] toggles that .askpal. The chat subsumes the ⌘K palette,
     so ⌘K opens the SAME surface and focuses its composer; typing "/" there
     filters the command list inline. Escape or the scrim closes it.
     The scrim is created here so a page only authors the .askpal itself. */
  function setAsk(pal, on) {
    pal.classList.toggle('on', on);
    pal.setAttribute('aria-hidden', on ? 'false' : 'true');
    var scrim = pal.parentNode && pal.parentNode.querySelector('.askscrim');
    if (scrim) scrim.classList.toggle('on', on);
    all('[data-ask]').forEach(function (b) {
      if (document.querySelector(b.getAttribute('data-ask')) !== pal) return;
      b.setAttribute('aria-expanded', on ? 'true' : 'false');
    });
    if (on) {
      var box = pal.querySelector('.chat-in input.box');
      if (box) requestAnimationFrame(function () { box.focus(); });
    }
  }

  // "/" in the composer turns the chat into the command palette: same field,
  // same Enter key, a filtered list of real commands instead of prose.
  function wireAskCommands(pal) {
    var box = pal.querySelector('.chat-in input.box');
    var cmd = pal.querySelector('.askcmd');
    if (!box || !cmd) return;
    var rows = Array.prototype.slice.call(cmd.querySelectorAll('.cpx'));
    var empty = cmd.querySelector('.empty');
    box.addEventListener('input', function () {
      var v = box.value.trim();
      if (v.charAt(0) !== '/') { cmd.classList.remove('on'); return; }
      var q = v.slice(1).toLowerCase();
      var hit = 0;
      rows.forEach(function (r) {
        var match = !q || r.textContent.toLowerCase().indexOf(q) > -1;
        r.style.display = match ? '' : 'none';
        r.classList.toggle('on', match && hit === 0);
        if (match) hit++;
      });
      if (empty) empty.style.display = hit ? 'none' : '';
      cmd.classList.add('on');
    });
    rows.forEach(function (r) {
      r.addEventListener('click', function () {
        box.value = '';
        cmd.classList.remove('on');
        box.focus();
      });
    });
  }

  all('.askpal').forEach(function (pal) {
    if (pal.parentNode && !pal.parentNode.querySelector('.askscrim')) {
      var scrim = document.createElement('div');
      scrim.className = 'askscrim';
      pal.parentNode.insertBefore(scrim, pal);
      scrim.addEventListener('click', function () { setAsk(pal, false); });
    }
    setAsk(pal, pal.classList.contains('on'));
    wireAskCommands(pal);
  });
  all('[data-ask]').forEach(function (btn) {
    var pal = document.querySelector(btn.getAttribute('data-ask'));
    if (!pal) return;
    btn.addEventListener('click', function (e) {
      e.stopPropagation();
      setAsk(pal, !pal.classList.contains('on'));
    });
  });
  all('[data-ask-close]').forEach(function (btn) {
    btn.addEventListener('click', function () {
      var pal = btn.closest('.askpal');
      if (pal) setAsk(pal, false);
    });
  });
  document.addEventListener('keydown', function (e) {
    if (e.key === 'Escape') {
      all('.askpal.on').forEach(function (p) { setAsk(p, false); });
      return;
    }
    // ⌘K opens the chat, not a separate palette — there is only one surface.
    if (e.key !== 'k' && e.key !== 'K') return;
    if (!e.metaKey && !e.ctrlKey) return;
    var pal = document.querySelector('.askpal');
    if (!pal) return;
    e.preventDefault();
    setAsk(pal, true);
  });
})();
