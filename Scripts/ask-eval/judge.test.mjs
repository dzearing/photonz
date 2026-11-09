// node --test Scripts/ask-eval/judge.test.mjs
// A picture the judge reads between two whole numbers must get one steady
// reading, not a coin flip between them (2026-11-09: the same balloon read
// 85.6 and 69.9 within the hour, because each line was the median of three
// looks and the median snaps a 6.3 to 6 or 7).
import { test } from "node:test";
import assert from "node:assert/strict";
import { JUDGE_LOOKS, RUBRIC_ID, linesFrom } from "./judge.mjs";
import { combine } from "./scoring.mjs";

const look = (asked, rest = 6) => ({ clean: rest, typography: null, aligned: rest, designed: rest, didWhatWasAsked: asked, readsAsIcon: rest });
const iconCase = { group: "icon", names: ["balloon"] };
const scoreOf = (looks) => {
  const lines = linesFrom(looks, { icon: true });
  const counted = Object.values(lines).filter((v) => v !== null);
  const judge = Math.round(counted.reduce((s, v) => s + v, 0) / counted.length * 10) / 10;
  return combine(iconCase, { score: 10 }, { score: judge, lines }, { score: 10 });
};

test("a line is the mean of its looks, not the median", () => {
  const lines = linesFrom([look(7), look(6), look(6)], { icon: true });
  assert.equal(lines.didWhatWasAsked, 6.33);
  assert.equal(lines.clean, 6);
});

test("a line every look left empty stays out", () => {
  const lines = linesFrom([look(7), look(6)], { icon: true });
  assert.equal(lines.typography, null);
  assert.ok(!("flow" in lines), "a still picture is never judged on flow");
});

test("one look moving from 6 to 7 moves the score a little, never a seventh of it", () => {
  // Nine looks, three of them at 7: the balloon's own rate.
  const three = scoreOf([...Array(3)].map(() => look(7)).concat([...Array(6)].map(() => look(6))));
  const four = scoreOf([...Array(4)].map(() => look(7)).concat([...Array(5)].map(() => look(6))));
  assert.ok(Math.abs(four - three) < 2.5, `one look flipped moved the score ${(four - three).toFixed(1)}`);
});

test("enough looks are taken by default to steady a picture on the edge", () => {
  assert.ok(JUDGE_LOOKS >= 9);
});

test("the way looks are combined is part of the rubric id, so median runs are not compared", () => {
  // f5ae1562 was the id of every run whose lines were medians of three looks.
  assert.match(RUBRIC_ID, /^[0-9a-f]{8}$/);
  assert.notEqual(RUBRIC_ID, "f5ae1562");
});
