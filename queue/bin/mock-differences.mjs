// Every difference from the mock an audit lists has to name what settles it.
//
// The rule has been in the runner prompt for weeks: a difference from the
// user's mock in layout, colour, control type, spacing or copy length is fixed
// in the task, filed as its own task, or put to the user on a decision card.
// It is never just a note. On 2026-10-02 and 10-03 four audits in a row wrote
// differences into `rough` with a reason and nothing else (audio effects drawn
// as a section where the mock draws a dock group; the EQ rows without the
// mock's grip and dot; the pivot tool left off the tool bar; the timing strip's
// glyph ends, wrap and bright headings), so the user's mocks were undercut
// quietly, two days running. This reads an audit's `rough` lines, picks out the
// ones that describe a difference from a mock, and says which of them name
// nothing that settles them. queue-lib's done gate refuses on what it finds.
//
// Pure: no file reads. The caller says which ids are cards and tasks.

// A line is about the mock when it says so, or names a mock page by its file.
// The dashboard's own index.html is not a mock page.
const MOCK_WORD = /\bmock(s|'s|s')?\b/i;
const MOCK_PAGE = /\b(?!index\.html\b)[a-z0-9][a-z0-9-]*\.html\b/i;

// Lines that mention a mock without being a difference from one.
//   - no mock covers this surface at all
//   - the app adds something the mock does not draw: going further than the
//     mock is allowed (objectives principle 4), only below or away is not
//   - it says outright that it goes beyond the mock
const NO_MOCK = new RegExp([
  String.raw`\bno mock\b`,
  String.raw`\bthere is no mock\b`,
  String.raw`\bnothing in (the|any) mocks?\b`,
  String.raw`\bnone of the mocks?\b`,
  String.raw`\bno ([a-z-]+ ){0,3}mocks? (page|frame|surface)\b`,
  String.raw`\bno side.by.side\b`,
].join('|'), 'i');
const ADDS_TO_MOCK = new RegExp([
  String.raw`\bmocks?('s)? (does not|doesn't|did not|do not|don't) (draw|show|have|cover|print|include|carry)\b`,
  String.raw`\bmocks?('s)?( [a-z-]+){0,3}( \([^)]*\))? (draws?|has|have|shows?|covers?|prints?) (no|nothing)\b`,
  String.raw`\bnot in (the|any|a) ([a-z-]+ )?mocks?\b`,
  String.raw`\b(further|beyond) (than )?(the|any|its|their) (\w+ )?mocks?\b`,
  String.raw`\bbeyond (the mock|it)\b`,
  String.raw`\bgoes (further|beyond)\b`,
].join('|'), 'i');
// A line that only reports a match ("as the mock does", "matches the mock")
// with nothing in it pointing the other way.
const MATCH_CUE = /\bmatch(es|ed|ing)?\b|\b(looks|reads) the same\b|\bas the (\w+ )?mock('s)?\b|\bthe mock's exactly\b|\bsame as (in )?the mock\b|\b(is|are) the mock's\b/i;
const DIFF_CUE = /\b(not|no|isn't|aren't|doesn't|don't|didn't|instead|rather than|differs?|different|unlike|but|left out|missing|yet|still|without|stops short|short of|where the mock|while the mock|than the mock)\b/i;

// The one sanctioned way to leave a mock's words out of the panel: a line over
// the copy budget moves, in the mock's words, behind the section's question
// mark or into the control's tip (UX-PATTERNS §4), and the audit names it.
// That is the rule working, not a difference to settle.
const BUDGET_MOVE = /\bbehind the question marks?\b|\bbehind the [a-z ]{0,20}question marks?\b|\bin(to)? the tip of\b/i;

export function mentionsMock(line) {
  const s = String(line || '');
  return MOCK_WORD.test(s) || MOCK_PAGE.test(s);
}

// Whether a rough line describes a difference from a mock that someone has to
// settle. It is read a sentence (or a clause after a semicolon) at a time,
// because a line often matches the mock in one breath and departs from it in
// the next ("the chips match. The mock's rows show a box alone; ours keep a
// track"), and the departure is the part that needs an answer. Any sentence
// about the mock that is not a match, an addition or "no mock" is a
// difference: missing one costs the user the mock, a false one costs the
// runner one id.
export function sentencesOf(line) {
  return String(line || '').split(/(?<=[.!?])\s+(?=[A-Z(])|;\s*/).map((x) => x.trim()).filter(Boolean);
}
function sentenceDiffers(s) {
  if (!mentionsMock(s)) return false;
  if (NO_MOCK.test(s) || ADDS_TO_MOCK.test(s) || BUDGET_MOVE.test(s)) return false;
  if (MATCH_CUE.test(s) && !DIFF_CUE.test(s)) return false;
  return true;
}
export function isMockDifference(line) {
  return sentencesOf(line).some(sentenceDiffers);
}

// The ids a line names: kebab-case tokens of three words or more, the shape
// every task and decision id has.
export function idsIn(line) {
  return [...new Set(String(line || '').toLowerCase().match(/\b[a-z0-9]+(?:-[a-z0-9]+){2,}\b/g) || [])];
}

const DATE = /\b20\d\d-\d\d-\d\d\b/;
// A rule the user approved and the repo keeps: "UX-PATTERNS §7".
const WRITTEN_RULE = /\bUX-PATTERNS(\.md)?\s*(§|section\s*)\s*([0-9A-Z][0-9.]*)/i;
const USER_WORD = /\b(you|your|the user|the user's)\b/i;
const ASKED_ON = /\basked (for )?on 20\d\d-\d\d-\d\d\b/i;
// "because you asked", "at the user's ask", "as this task asked": only an
// answer when the task being finished is the user's own ask.
const THIS_ASK = /\b(you|the user) (asked|wanted|chose)\b|\b(your|the user's) ask\b|\bat the user's ask\b|\b(the|this) task('s)? (asked|asks|own checklist|checklist asks)\b|\bas (the|this) task asked\b/i;

// What settles a difference line, in words, or null when it names nothing.
//   ctx.card(id)  -> true for an open or answered decision card
//   ctx.task(id)  -> true for a task in the queue, any status
//   ctx.ownId     -> the task being finished, which cannot settle itself...
//   ctx.userAsked -> ...unless the user filed it, and the line says the
//                    difference is what they asked for
export function settlementOf(line, ctx = {}) {
  const s = String(line || '');
  for (const id of idsIn(s)) {
    if (ctx.card && ctx.card(id)) return `card ${id}`;
  }
  for (const id of idsIn(s)) {
    if (id !== ctx.ownId && ctx.task && ctx.task(id)) return `task ${id}`;
  }
  if ((USER_WORD.test(s) && DATE.test(s)) || ASKED_ON.test(s)) return `the user's answer on ${s.match(DATE)[0]}`;
  const rule = s.match(WRITTEN_RULE);
  if (rule) return `the rule in UX-PATTERNS §${rule[3]}`;
  if (ctx.userAsked && THIS_ASK.test(s)) return 'this task, which the user asked for';
  return null;
}

// Every difference line in an audit's `rough`, with what settles each.
//   [{ index, line, settledBy }]   settledBy is null when nothing does
export function mockDifferences(audit, ctx = {}) {
  const rough = Array.isArray(audit && audit.rough) ? audit.rough : [];
  return rough
    .map((line, index) => ({ index, line: String(line), settledBy: null }))
    .filter((r) => isMockDifference(r.line))
    .map((r) => ({ ...r, settledBy: settlementOf(r.line, ctx) }));
}

// The audit file names a task's words point at: queue/audits/<name>.json or a
// bare dated <YYYY-MM-DD>-<slug>.json.
export function auditNamesIn(text) {
  const out = new Set();
  for (const m of String(text || '').matchAll(/\b(20\d\d-\d\d-\d\d-[a-z0-9-]+\.json)\b/gi)) out.add(m[1]);
  return [...out];
}
