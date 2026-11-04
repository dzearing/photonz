/* Photonz mock · the agent conversation's behaviour — work cards, the composer,
   and the left conversation dock.
   Look lives in agent.css; the surface that hosts it lives in ask.{css,js}. */
(function () {
  var PZ = window.PZ || {};
  var all = PZ.all;

  /* ============================================================
     1 · A STEP IS A VIEW ONTO A LAYER
     ============================================================
     Clicking one selects that layer rather than highlighting a line of chat, so
     there is ONE selection in the app rather than a second one living in the
     transcript. That is the only interaction a step has — the list is readonly,
     and the way to change your mind is the composer. */
  function steps(chat) { return all('.step', chat); }

  function applySel(chat) {
    var win = chat.closest('.win') || document;
    var keys = steps(chat)
      .filter(function (n) { return n.getAttribute('aria-pressed') === 'true'; })
      .map(function (n) { return n.getAttribute('data-layer'); })
      .filter(Boolean);
    all('.lrow[data-layer]', win).forEach(function (row) {
      row.classList.toggle('sel', keys.indexOf(row.getAttribute('data-layer')) > -1);
    });
  }

  /* ============================================================
     2 · BEFORE / AFTER, per card
     ============================================================
     A view switch, not an edit: the whole card flips at once, the values in
     every row swap emphasis, and the card says out loud that you are looking at
     the original. Card-level rather than per-row precisely so a stray click
     cannot quietly revert one property and leave the canvas disagreeing with
     the report. */
  function setView(work, before) {
    work.classList.toggle('before', before);
    var n = all('.step[data-state="done"]', work).length;
    var t = work.querySelector('.work-note .t');
    if (t) {
      t.innerHTML = '<b>Showing the before.</b> The canvas has ' + n +
        (n === 1 ? ' change' : ' changes') + ' switched off.';
    }
    all('.work-view button', work).forEach(function (b) {
      var isBefore = /before/i.test(b.textContent);
      b.classList.toggle('on', isBefore === before);
    });
  }

  /* ============================================================
     3 · THE COMPOSER
     ============================================================ */
  function grow(box) {
    box.style.height = 'auto';
    box.style.height = Math.min(box.scrollHeight, 96) + 'px';
  }

  function addAtt(chat, name) {
    var atts = chat.querySelector('.ask-atts');
    if (!atts) return;
    var chip = document.createElement('span');
    chip.className = 'ask-att';
    chip.innerHTML = '<span class="th"></span><span class="nm"></span>' +
      '<button class="x" type="button" title="Remove"><i class="ic ic-x"></i></button>';
    chip.querySelector('.nm').textContent = name;
    atts.appendChild(chip);
  }

  function wireComposer(chat) {
    var composer = chat.querySelector('.composer');
    var box = composer && composer.querySelector('textarea.box');
    if (!box) return;
    grow(box);
    box.addEventListener('input', function () { grow(box); });
    // Enter sends, Shift+Enter is a newline — the ordinary convention, and how
    // the field can be multi-line without losing a one-key send.
    box.addEventListener('keydown', function (e) {
      if (e.key === 'Enter' && !e.shiftKey) e.preventDefault();
    });
    // an image on the clipboard becomes an attachment, not pasted text
    box.addEventListener('paste', function (e) {
      var items = (e.clipboardData || {}).items || [];
      for (var i = 0; i < items.length; i++) {
        if (items[i].type && items[i].type.indexOf('image') === 0) {
          e.preventDefault(); addAtt(chat, 'Pasted image'); return;
        }
      }
    });
    ['dragenter', 'dragover'].forEach(function (t) {
      composer.addEventListener(t, function (e) { e.preventDefault(); composer.classList.add('drop'); });
    });
    ['dragleave', 'drop'].forEach(function (t) {
      composer.addEventListener(t, function (e) { e.preventDefault(); composer.classList.remove('drop'); });
    });
    composer.addEventListener('drop', function (e) {
      var name = 'Screenshot';
      try {
        var f = e.dataTransfer && e.dataTransfer.files && e.dataTransfer.files[0];
        if (f) name = f.name;
        else { var t = e.dataTransfer && e.dataTransfer.getData('text/plain'); if (t) name = t; }
      } catch (_) {}
      addAtt(chat, name);
    });
    composer.addEventListener('click', function (e) {
      var x = e.target.closest('.ask-att>.x');
      if (x) x.parentNode.remove();
    });
  }

  /* ============================================================
     4 · WIRING ONE CONVERSATION
     ============================================================
     The host is normally a `.chat`, but a spec page shows a work card on its
     own with no composer around it. `[data-convo]` marks any other element
     that scopes one conversation. */
  all('.chat, [data-convo]').forEach(function (chat) {
    if (chat.hasAttribute('data-agent-wired')) return;
    chat.setAttribute('data-agent-wired', '');

    chat.addEventListener('click', function (e) {
      // ONLY THE INNERMOST HOST HANDLES A CLICK. A spec page can mark a wrapper
      // `[data-convo]` that itself contains a real `.chat`, and then both are
      // wired and both fire — which toggled `collapsed` twice and made a card
      // look like it simply would not open.
      if (e.target.closest('.chat, [data-convo]') !== chat) return;

      // a · the After/Before switch, before anything reads the click otherwise
      var v = e.target.closest('.work-view button');
      if (v) {
        e.stopPropagation();
        setView(v.closest('.work'), /before/i.test(v.textContent));
        return;
      }
      // b · the header opens and closes the card
      var h = e.target.closest('.work-h');
      if (h && chat.contains(h)) {
        if (e.target.closest('.btn')) return;   // Stop is not disclosure
        var work = h.closest('.work');
        var open = !work.classList.toggle('collapsed');
        h.setAttribute('aria-expanded', open ? 'true' : 'false');
        return;
      }
      // c · a step selects the layer it touched
      var s = e.target.closest('.step');
      if (s && chat.contains(s)) {
        var add = e.metaKey || e.ctrlKey || e.shiftKey;
        var on = s.getAttribute('aria-pressed') === 'true';
        if (!add) steps(chat).forEach(function (n) { n.setAttribute('aria-pressed', 'false'); });
        s.setAttribute('aria-pressed', (add && on) ? 'false' : 'true');
        applySel(chat);
      }
    });

    steps(chat).forEach(function (n) {
      if (!n.hasAttribute('aria-pressed')) n.setAttribute('aria-pressed', 'false');
    });
    all('.work', chat).forEach(function (w) { setView(w, w.classList.contains('before')); });
    wireComposer(chat);
  });

  /* The left dock this section used to build is gone: the user took it out on
     2026-11-04. The right panel's Agent group is the one Agent place, a plain
     history with its details on hover (agent-generate-wt.html). Never rebuild it. */
})();
