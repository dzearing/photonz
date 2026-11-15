// node --test Scripts/ask-eval/reading.test.mjs
import { test } from "node:test";
import assert from "node:assert/strict";
import { roundsFor, slots, baseID, readingTotal, groupTotals, spread, chance } from "./reading.mjs";

test("the sealed motion set is read in two rounds, every other set in one, unless asked", () => {
  assert.equal(roundsFor("held-out-motion"), 2);
  assert.equal(roundsFor("climb"), 1);
  assert.equal(roundsFor("held-out"), 1);
  assert.equal(roundsFor("held-out-motion", 1), 1);
  assert.equal(roundsFor("climb", 3), 3);
  assert.throws(() => roundsFor("climb", 0));
});

test("rounds go round the whole set before any case runs again", () => {
  assert.deepEqual(slots(["a", "b"], 3).map((s) => s.key), ["a", "b", "a~2", "b~2", "a~3", "b~3"]);
  assert.deepEqual(slots(["a"], 2), [{ key: "a", id: "a", round: 1 }, { key: "a~2", id: "a", round: 2 }]);
  assert.equal(baseID("bell-ringing~2"), "bell-ringing");
  assert.equal(baseID("bell-ringing"), "bell-ringing");
});

test("a reading is the mean of each case's own mean, so a case run more often weighs no more", () => {
  const cases = { a: { group: "animated", score: 10 }, "a~2": { group: "animated", score: 30 }, b: { group: "animated", score: 60 } };
  assert.equal(readingTotal(cases), 40);
  assert.deepEqual(groupTotals(cases), { animated: 40 });
  assert.equal(readingTotal({}), null);
});

test("a case not run yet counts 0 in the total, as before, but tells nothing about the spread", () => {
  const cases = { a: { score: 40 }, "a~2": { score: 0, unrun: "deferred" }, b: { score: 50 }, "b~2": { score: 54 } };
  assert.equal(readingTotal(cases), 36);
  // Only b has two runs: its spread stands for every case.
  assert.equal(spread(cases).casesWithRounds, 1);
});

test("the spread of a reading comes from how far each case moved between its own rounds", () => {
  // Every case moved 8 between its two runs: a variance of 32 a run, so a
  // reading of 2 cases x 2 rounds has a standard error of sqrt(32 / 4) = 2.83.
  const cases = { a: { score: 30 }, "a~2": { score: 38 }, b: { score: 70 }, "b~2": { score: 62 } };
  const s = spread(cases);
  assert.equal(s.standardError, 2.8);
  assert.equal(s.perRun, 5.7);
  assert.equal(s.casesWithRounds, 2);
  assert.equal(spread({ a: { score: 30 }, b: { score: 40 } }), null, "one round says nothing about the spread");
});

test("two readings differ for real only past twice the standard error of the difference", () => {
  const before = { total: 35, rounds: 2, caseCount: 16, spread: { standardError: 1.2, perRun: 9.6 } };
  const small = chance({ total: 37, rounds: 2, caseCount: 16, spread: { standardError: 1.2, perRun: 9.6 } }, before);
  assert.equal(small.difference, 2);
  assert.equal(small.standardError, 1.7);
  assert.equal(small.real, false);
  const big = chance({ total: 39, rounds: 2, caseCount: 16, spread: { standardError: 1.2, perRun: 9.6 } }, before);
  assert.equal(big.real, true);
  // A one-round reading has no spread of its own: it borrows the other's per-run
  // spread at its own number of runs (9.6 / sqrt(16) = 2.4).
  const old = chance({ total: 37, rounds: 2, caseCount: 16, spread: { standardError: 1.2, perRun: 9.6 } }, { total: 35, rounds: 1, caseCount: 16 });
  assert.equal(old.standardError, 2.7);
  assert.equal(chance({ total: 37, rounds: 1, caseCount: 16 }, { total: 35, rounds: 1, caseCount: 16 }), null);
});
