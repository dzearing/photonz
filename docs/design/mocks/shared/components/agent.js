/* Photonz mock · the agent conversation's behaviour — run cards, transcript
   selection, and docking the conversation into the panel dock.
   Look lives in agent.css; the surface that hosts it lives in ask.{css,js}. */
(function () {
  var PZ = window.PZ || {};
  var all = PZ.all;

  /* ---- 1 · TRANSCRIPT SELECTION IS DOCUMENT SELECTION ----
     A `.run-tgt` or a `.step` is a view onto a layer, so clicking one selects
     that layer rather than highlighting a line of chat. There is therefore ONE
     pressed item per conversation, not a second selection model living in the
     transcript; ⌘/⇧ extends, exactly as it does in the Layers panel.

     The mock reflects it back onto any `.lrow[data-layer]` in the same window,
     so the link is visible rather than merely asserted. */
  function selectables(chat) {
    return all('.run-tgt, .step', chat);
  }

  function applySel(chat) {
    var win = chat.closest('.win') || document;
    var keys = selectables(chat)
      .filter(function (n) { return n.getAttribute('aria-pressed') === 'true'; })
      .map(function (n) { return n.getAttribute('data-layer'); })
      .filter(Boolean);
    all('.lrow[data-layer]', win).forEach(function (row) {
      row.classList.toggle('sel', keys.indexOf(row.getAttribute('data-layer')) > -1);
    });
  }

  /* The host is the CONVERSATION, which is normally a `.chat` — but a spec page
     shows a run card on its own, with no composer around it, and those rows have
     to select too. `[data-convo]` marks any other element that scopes one
     transcript's selection. */
  all('.chat, [data-convo]').forEach(function (chat) {
    if (chat.hasAttribute('data-agent-wired')) return;
    chat.setAttribute('data-agent-wired', '');

    chat.addEventListener('click', function (e) {
      // per-step revert first: it is inside the step, and it is not a selection
      var x = e.target.closest('.step-x');
      if (x) {
        e.stopPropagation();
        var st = x.closest('.step');
        if (st) st.setAttribute('data-state', st.getAttribute('data-state') === 'skip' ? 'done' : 'skip');
        return;
      }
      var hit = e.target.closest('.run-tgt, .step');
      if (hit && chat.contains(hit)) {
        var add = e.metaKey || e.ctrlKey || e.shiftKey;
        var on = hit.getAttribute('aria-pressed') === 'true';
        if (!add) selectables(chat).forEach(function (n) { n.setAttribute('aria-pressed', 'false'); });
        hit.setAttribute('aria-pressed', (add && on) ? 'false' : 'true');
        applySel(chat);
        return;
      }
      // a run header collapses its own card, so a long transcript stays readable
      var h = e.target.closest('.run-h');
      if (h && h.parentNode.classList.contains('run') && h.parentNode.querySelector('.run-b')) {
        if (e.target.closest('.btn')) return;   // Stop / Undo are not disclosure
        h.parentNode.classList.toggle('collapsed');
      }
    });

    selectables(chat).forEach(function (n) {
      if (!n.hasAttribute('aria-pressed')) n.setAttribute('aria-pressed', 'false');
    });
  });

  /* ---- 2 · DOCKING THE CONVERSATION ----
     The overlay covers the document it is editing. That is the right trade for
     one sentence and the wrong one for a run you want to supervise, so the same
     `.chat` can move into an Agent group in the right dock and stay there. It
     MOVES rather than being duplicated — one conversation, two hosts — which is
     the reason the run card was split out of ask.css in the first place. */
  function dockOf(pal) {
    var edit = pal.closest('.edit') || pal.parentNode;
    return edit && edit.querySelector('.pdock');
  }

  /* FIRST in the dock, not appended. A dock already holding Layers, Properties,
     Effects and Library has no leftover height to give a new group at the
     bottom, so an appended conversation lands below the fold — docked in name
     and invisible in fact. The thing you are steering with goes where you are
     looking. */
  function ensureGroup(dock) {
    var g = dock.querySelector('.dgrp[data-grp="agent"]');
    if (g) return g;
    g = document.createElement('div');
    g.className = 'dgrp grow agent-docked';
    g.setAttribute('data-grp', 'agent');
    g.innerHTML =
      '<div class="dgrp-h" role="button" tabindex="0"><i class="chev ic xs ic-chevron-down"></i>' +
      '<span class="ttl">Agent</span><span class="cnt">live</span>' +
      '<button class="btn ghost icon sm" data-ask-undock title="Float the conversation">' +
      '<i class="ic ic-maximize"></i></button></div>' +
      '<div class="dgrp-b"></div>';
    var host = dock.querySelector('.dock-body') || dock;
    host.insertBefore(g, host.firstElementChild);
    return g;
  }

  /* ONE EXPANDED GROUP PER INTENT. While you are steering a run, that is the
     intent, and the dock's other groups fold to their headers to pay for the
     height — otherwise the conversation gets whatever is left over, which on a
     full dock is nothing.

     Layers is the pointed case and gets a reason in its header, because the run
     card genuinely replaces it: it already lists every layer that changed. The
     rest simply fold, keeping their title and count, so nothing is hidden
     without a label. All of it is marked `.auto-collapsed` — collapsed BY THE
     APP, undone when the conversation leaves, and never overriding a collapse
     the user made themselves. */
  function autoCollapse(dock, on) {
    all('.dgrp', dock).forEach(function (g) {
      if (g.getAttribute('data-grp') === 'agent') return;
      if (on) {
        if (g.classList.contains('collapsed')) return;    // the user's call wins
        g.classList.add('collapsed', 'auto-collapsed');
        var h = g.querySelector('.dgrp-h');
        if (h && g.getAttribute('data-grp') === 'layers' && !h.querySelector('.why')) {
          h.insertAdjacentHTML('beforeend', '<span class="why">the run lists what changed</span>');
        }
      } else if (g.classList.contains('auto-collapsed')) {
        g.classList.remove('collapsed', 'auto-collapsed');
        var w = g.querySelector('.dgrp-h .why');
        if (w) w.remove();
      }
    });
  }

  function setDocked(pal, on) {
    var dock = dockOf(pal);
    // The conversation is a single node that lives in one of two hosts, so look
    // in both. (Looking only in the overlay is why undocking used to no-op: once
    // docked, the pal has no `.chat` left to find.)
    var chat = pal.querySelector('.chat') ||
      (dock && dock.querySelector('.dgrp[data-grp="agent"] .chat'));
    if (!chat || !dock) return;
    if (on) {
      ensureGroup(dock).querySelector('.dgrp-b').appendChild(chat);
      pal.classList.remove('on');
      var scrim = pal.parentNode && pal.parentNode.querySelector('.askscrim');
      if (scrim) scrim.classList.remove('on');
    } else {
      pal.appendChild(chat);
      var g = dock.querySelector('.dgrp[data-grp="agent"]');
      if (g && !g.querySelector('.chat')) g.remove();
      // Undocking has to REOPEN the overlay. Otherwise the conversation leaves
      // the dock and lands in a hidden pal, and from the user's side it is gone.
      pal.classList.add('on');
      pal.setAttribute('aria-hidden', 'false');
      var sc = pal.parentNode && pal.parentNode.querySelector('.askscrim');
      if (sc) sc.classList.add('on');
      all('[data-ask]').forEach(function (b) {
        if (document.querySelector(b.getAttribute('data-ask')) === pal) {
          b.setAttribute('aria-expanded', 'true');
        }
      });
    }
    autoCollapse(dock, on);
    all('[data-ask-dock]', chat).forEach(function (b) {
      b.setAttribute('aria-pressed', on ? 'true' : 'false');
      b.title = on ? 'Float the conversation' : 'Dock the conversation';
    });
  }

  document.addEventListener('click', function (e) {
    var d = e.target.closest('[data-ask-dock]');
    if (d) {
      var pal = d.closest('.askpal');
      if (!pal) {
        // already docked: the button rode along inside the chat
        var win = d.closest('.win') || document;
        pal = win.querySelector('.askpal');
      }
      if (pal) { e.stopPropagation(); setDocked(pal, !d.closest('.dgrp')); }
      return;
    }
    var u = e.target.closest('[data-ask-undock]');
    if (u) {
      var w2 = u.closest('.win') || document;
      var p2 = w2.querySelector('.askpal');
      if (p2) setDocked(p2, false);
    }
  });

  // A page can author `data-ask-docked` on a shell to start in the docked
  // arrangement, which is how the spec page shows both without a click.
  all('[data-ask-docked]').forEach(function (win) {
    var pal = win.querySelector('.askpal');
    if (pal) setDocked(pal, true);
  });
})();
