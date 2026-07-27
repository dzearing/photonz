/* ============================================================
   photonz-ds.js — INTENTIONALLY EMPTY
   ============================================================
   Behaviour now lives one file per component in shared/components/,
   assembled into this URL by dev-server.mjs (and by `node shared/build-ds.mjs`
   for static hosting). See shared/components/README.md.

   core.js runs first and publishes the four shared helpers on window.PZ
   (all / winOf / isNarrow / NARROW). Every other component is its own guarded
   IIFE that pulls those back in, so components cannot reach into each other.

   Do not add behaviour here. Add a component file and register it in
   shared/components/order.json.

   This file is kept only so the URL every page links stays valid.
   ============================================================ */
