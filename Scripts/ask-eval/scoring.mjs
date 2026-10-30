// A case's score from its three readings (Scripts/ask-eval/README.md, "The
// score, 0 to 100").

/// Below this didWhatWasAsked, the whole score shrinks in proportion: a stock
/// drawing that ignored "curled up sleeping" must not ride to 85 on clean
/// lines, alignment and a blind look that says "cat" (2026-10-20).
export const ASKED_FLOOR = 7;

/// A case's score, 0 to 100. A drawing: 30% rules, 40% judge, 30% named blind
/// (a drawing with no names to check, one saved from a vote, is scored like
/// anything else). Anything else: 40% rules, 60% judge. Then scaled by
/// didWhatWasAsked / 7 when that is under 7. Nothing made is 0.
export function combine(testCase, rules, judge, named) {
  if (!rules || rules.score === 0) return 0;
  const j = judge?.score ?? 0;
  // A photo is named blind like a drawing: a dog on a beach should read as a dog.
  const named3 = ["drawing", "photo"].includes(testCase.group) && (testCase.names ?? []).length > 0;
  let value = named3 ? 3 * rules.score + 4 * j + 3 * (named?.score ?? 0) : 4 * rules.score + 6 * j;
  const asked = judge?.lines?.didWhatWasAsked;
  if (typeof asked === "number" && asked < ASKED_FLOOR) value *= asked / ASKED_FLOOR;
  return Math.round(value * 10) / 10;
}
