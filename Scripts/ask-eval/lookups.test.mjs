// node --test Scripts/ask-eval/lookups.test.mjs
import { test } from "node:test";
import assert from "node:assert/strict";
import { sourceOf, tally, describe, sourcesFromTranscript } from "./lookups.mjs";
import { combine } from "./scoring.mjs";

test("a built-in is stored, an illustration a template, the model's own svg drawn", () => {
  assert.equal(sourceOf("add_drawing", '{"from":"built-in: cat face"}'), "stored");
  assert.equal(sourceOf("add_drawing", '{"from": "illustration: Layered (picked)"}'), "template");
  assert.equal(sourceOf("add_drawing", '{"from":"your svg","parts":3}'), "drawn");
  assert.equal(sourceOf("add_drawing", '{"from":"painted: z-image-turbo, 40 paths in 25 s"}'), "drawn");
  assert.equal(sourceOf("add_shape", "{}"), "drawn");
  assert.equal(sourceOf("add_text", "{}"), null);
  assert.equal(sourceOf("add_drawing", "no answer"), null);
});

test("the tally counts drawings and the cases answered only by lookup", () => {
  const t = tally({
    cat: { sources: ["stored"] },
    piano: { sources: ["stored", "stored"] },
    fox: { sources: ["template"] },
    robot: { sources: ["drawn", "stored"] },
    form: { sources: [] },
  });
  assert.deepEqual(t, { stored: 4, template: 1, drawn: 1, lookupShare: 83, casesByLookupOnly: 3, casesWithDrawings: 4 });
  assert.match(describe(t), /83% looked up/);
  assert.equal(describe(tally({})), "drawings: none made");
});

test("a skill transcript's add_drawing answers are read the same way", () => {
  const lines = [
    JSON.stringify({ type: "assistant", message: { content: [{ type: "tool_use", id: "a", name: "mcp__photonz__add_drawing" }] } }),
    JSON.stringify({ type: "user", message: { content: [{ type: "tool_result", tool_use_id: "a", content: [{ type: "text", text: '{"from":"your svg"}' }] }] } }),
    JSON.stringify({ type: "assistant", message: { content: [{ type: "tool_use", id: "b", name: "mcp__photonz__add_drawing" }] } }),
    JSON.stringify({ type: "user", message: { content: [{ type: "tool_result", tool_use_id: "b", content: '{"from":"built-in: dog"}' }] } }),
  ];
  assert.deepEqual(sourcesFromTranscript(lines), ["drawn", "stored"]);
});

test("a drawing that ignores what was asked cannot score high however clean it is", () => {
  const drawing = { group: "drawing", names: ["cat"] };
  const clean = { score: 10 };
  const ignored = { score: 6.3, lines: { didWhatWasAsked: 2 } };
  const named = { score: 10 };
  // The stock cat for "a cat curled up sleeping": rules 10, judge 6.3, named.
  assert.ok(combine(drawing, clean, ignored, named) < 30);
  // The same picture where the request was met keeps its full score.
  const met = { score: 8, lines: { didWhatWasAsked: 8 } };
  assert.equal(combine(drawing, clean, met, named), 30 + 32 + 30);
});

test("a drawing case with no names to check is scored on rules and the judge", () => {
  const fromUse = { group: "drawing" };
  assert.equal(combine(fromUse, { score: 10 }, { score: 8, lines: { didWhatWasAsked: 8 } }, null), 40 + 48);
});

test("nothing made scores 0", () => {
  assert.equal(combine({ group: "drawing" }, null, null, null), 0);
  assert.equal(combine({ group: "layout" }, { score: 0 }, null, null), 0);
});
