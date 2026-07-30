/* Photonz mock · the agent conversation's behaviour — work cards, the composer,
   and the left conversation dock.
   Look lives in agent.css; the surface that hosts it lives in ask.{css,js}. */
(function () {
  var PZ = window.PZ || {};
  var all = PZ.all, isNarrow = PZ.isNarrow;

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

  /* ============================================================
     5 · DOCKING THE CONVERSATION — to the LEFT
     ============================================================
     The chat MOVES rather than being duplicated: one conversation, two hosts.
     Space comes from the right dock, which rails itself, so the canvas keeps
     its width. On a constrained shell the left dock floats over the canvas and
     soft-dismisses instead of eating layout width. */
  function editOf(pal) { return pal.closest('.edit') || pal.parentNode; }

  function ensureCdock(edit) {
    var c = edit.querySelector('.cdock');
    if (c) return c;
    c = document.createElement('div');
    c.className = 'cdock';
    c.innerHTML =
      '<div class="cdock-h"><i class="ic ic-sparkle"></i><span>Agent</span><span class="sp"></span>' +
      '<button class="btn ghost icon sm" data-ask-undock title="Float the conversation">' +
      '<i class="ic ic-maximize"></i></button></div>';
    edit.insertBefore(c, edit.firstElementChild);
    if (!edit.querySelector('.cdock-scrim')) {
      var scrim = document.createElement('div');
      scrim.className = 'cdock-scrim';
      edit.insertBefore(scrim, c);
      scrim.addEventListener('click', function () {   // soft dismiss
        var pal = edit.querySelector('.askpal');
        if (pal) setDocked(pal, false);
      });
    }
    return c;
  }

  function setDocked(pal, on) {
    var edit = editOf(pal);
    var chat = pal.querySelector('.chat') || (edit && edit.querySelector('.cdock .chat'));
    if (!chat || !edit) return;
    if (on) {
      ensureCdock(edit).appendChild(chat);
      // Space comes from the inspector, not the canvas. Remember what the dock
      // was doing so undocking can put it back exactly.
      if (!edit.hasAttribute('data-dock-prev')) {
        edit.setAttribute('data-dock-prev', edit.getAttribute('data-dock') || 'open');
      }
      edit.setAttribute('data-dock', 'closed');
      // too tight to be a panel? then be an overlay, not a narrower panel.
      edit.querySelector('.cdock').classList.toggle('as-overlay', isNarrow ? isNarrow(edit) : false);
      pal.classList.remove('on');
      pal.setAttribute('aria-hidden', 'true');
      var s1 = pal.parentNode && pal.parentNode.querySelector('.askscrim');
      if (s1) s1.classList.remove('on');
    } else {
      pal.appendChild(chat);
      var cd = edit.querySelector('.cdock'); if (cd) cd.remove();
      var sc = edit.querySelector('.cdock-scrim'); if (sc) sc.remove();
      if (edit.hasAttribute('data-dock-prev')) {
        edit.setAttribute('data-dock', edit.getAttribute('data-dock-prev'));
        edit.removeAttribute('data-dock-prev');
      }
      // Undocking has to REOPEN the overlay, or the conversation leaves the dock
      // into a hidden pal and from the user's side it has simply gone.
      pal.classList.add('on');
      pal.setAttribute('aria-hidden', 'false');
      var s2 = pal.parentNode && pal.parentNode.querySelector('.askscrim');
      if (s2) s2.classList.add('on');
    }
    all('[data-ask]').forEach(function (b) {
      if (document.querySelector(b.getAttribute('data-ask')) === pal) {
        b.setAttribute('aria-expanded', on ? 'false' : 'true');
      }
    });
    all('[data-ask-dock]', chat).forEach(function (b) {
      b.setAttribute('aria-pressed', on ? 'true' : 'false');
      b.title = on ? 'Float the conversation' : 'Dock the conversation';
    });
  }

  function isDocked(edit) { return !!(edit && edit.querySelector('.cdock .chat')); }

  document.addEventListener('click', function (e) {
    // Ask, while the conversation is docked, FLOATS IT BACK. It used to open the
    // empty overlay the chat had been moved out of, so the screen just dimmed
    // behind a blank panel with no way to tell what had happened.
    var ask = e.target.closest('[data-ask]');
    if (ask) {
      var pal0 = document.querySelector(ask.getAttribute('data-ask'));
      if (pal0 && isDocked(editOf(pal0))) { e.stopPropagation(); setDocked(pal0, false); }
      return;
    }
    var d = e.target.closest('[data-ask-dock]');
    if (d) {
      var pal = d.closest('.askpal') || (d.closest('.win') || document).querySelector('.askpal');
      if (pal) { e.stopPropagation(); setDocked(pal, !d.closest('.cdock')); }
      return;
    }
    var u = e.target.closest('[data-ask-undock]');
    if (u) {
      var p2 = (u.closest('.win') || document).querySelector('.askpal');
      if (p2) setDocked(p2, false);
    }
  }, true);

  document.addEventListener('keydown', function (e) {
    if (e.key !== 'Escape') return;
    all('.cdock.as-overlay').forEach(function (c) {
      var pal = (c.closest('.edit') || document).querySelector('.askpal');
      if (pal) setDocked(pal, false);
    });
  });

  // A page can author `data-ask-docked` on a shell to start docked.
  all('[data-ask-docked]').forEach(function (win) {
    var pal = win.querySelector('.askpal');
    if (pal) setDocked(pal, true);
  });
})();
