// Where each drawing in a run came from, so climbing the score by looking
// things up shows as a number (the user, 2026-10-20: Ask scored 92 on drawings
// while it drew one cat for every cat request). The app says it on every
// add_drawing answer ("from": "built-in: cat", "illustration: ...", "your
// svg"); PhotonzCore's AskDrawingSource reads it the same way.

/// "stored" (a built-in looked up by name), "template" (a coded
/// illustration), "drawn" (made for the request), or null for a step that is
/// not a drawing or an answer that does not say.
export function sourceOf(tool, answer) {
  if (tool === "add_shape" || tool === "add_path") return "drawn";
  if (tool !== "add_drawing") return null;
  const from = String(answer ?? "").match(/"from"\s*:\s*"([^"]*)"/)?.[1];
  if (!from) return null;
  if (from.startsWith("built-in")) return "stored";
  if (from.startsWith("illustration")) return "template";
  if (from.startsWith("your svg")) return "drawn";
  return null;
}

/// A run's tally from its cases' `sources` lists: how many drawings came from
/// each place, the share looked up (stored or template) of all drawings, and
/// how many cases were answered by lookups alone.
export function tally(cases) {
  const out = { stored: 0, template: 0, drawn: 0, lookupShare: null, casesByLookupOnly: 0, casesWithDrawings: 0 };
  for (const c of Object.values(cases)) {
    const sources = (c.sources ?? []).filter((s) => s in out);
    for (const s of sources) out[s] += 1;
    if (sources.length) {
      out.casesWithDrawings += 1;
      if (sources.every((s) => s !== "drawn")) out.casesByLookupOnly += 1;
    }
  }
  const all = out.stored + out.template + out.drawn;
  if (all) out.lookupShare = Math.round((out.stored + out.template) / all * 100);
  return out;
}

/// One line for a person: "drawings 12 stored, 3 template, 2 drawn for the
/// request (88% looked up); 14 of 16 cases answered by lookup alone".
export function describe(t) {
  if (!t || !(t.stored + t.template + t.drawn)) return "drawings: none made";
  return `drawings ${t.stored} stored, ${t.template} template, ${t.drawn} drawn for the request (${t.lookupShare}% looked up); `
    + `${t.casesByLookupOnly} of ${t.casesWithDrawings} cases answered by lookup alone`;
}

/// The tools a skill session called, with what each answered, from its
/// stream-json transcript lines, so the skill engine counts the same way.
export function sourcesFromTranscript(lines) {
  const names = new Map();
  const sources = [];
  for (const line of lines) {
    let event;
    try { event = JSON.parse(line); } catch { continue; }
    for (const part of event.message?.content ?? []) {
      if (part.type === "tool_use") names.set(part.id, String(part.name).replace(/^mcp__[^_]+__/, ""));
      if (part.type === "tool_result") {
        const text = Array.isArray(part.content) ? part.content.map((c) => c.text ?? "").join("") : String(part.content ?? "");
        const source = part.is_error ? null : sourceOf(names.get(part.tool_use_id), text);
        if (source) sources.push(source);
      }
    }
  }
  return sources;
}
