/* check-easing · ONE set of easing curves, named the same way everywhere.
   Run:  node shared/check-easing.mjs          (from docs/design/mocks)
         node shared/check-easing.mjs --list   (print the canonical list)

   THE DRIFT THIS EXISTS TO STOP. On 2026-09-14 four different lists of
   easing options were on screen at once across the study: Linear /
   Ease in-out / Spring on two icon pages, Linear / Ease out / Spring on a
   third, Linear / Ease out / Ease in-out on a fourth, and two or three
   names of its own on each video page. The same control offered you
   Spring on one screen and not the next, for no reason a person could see.

   The list now lives in ONE file, shared/components/curve.js, and a page
   asks for it with data-curve-menu. This script reads the list out of that
   file — it is never retyped here — and then fails a page that:

     1. writes curve rows by hand (a .cvth thumbnail in page markup), or
     2. offers a control named Easing or Curve whose choices are its own.

   Rule 2 is the one that matters, and it is deliberately narrow: it looks
   for a group of sibling buttons where two or more are easing words. That
   is what every one of the four drifted vocabularies looked like, and it
   does not fire on prose, on a speed ramp's Ramp/Hold, or on a page that
   merely says the word easing. */
import { readFileSync, readdirSync } from "node:fs";
import { join } from "node:path";

const PAGES = "pages";
const COMPONENT = "shared/components/curve.js";

/* the canonical list, read out of the component rather than restated */
const src = readFileSync(COMPONENT, "utf8");
const LIST = [...src.matchAll(/^\s*\{ id: "([\w-]+)",[\s\S]*?label: "([^"]+)"/gm)]
  .map(([, id, label]) => ({ id, label }));
if (LIST.length < 5) {
  console.error(`could not read the curve list out of ${COMPONENT} — has its shape changed?`);
  process.exit(2);
}

if (process.argv.includes("--list")) {
  console.log(`The one easing vocabulary (${COMPONENT}):\n`);
  LIST.forEach((c, i) => console.log(`  ${i + 1}. ${c.label.padEnd(20)} ${c.id}`));
  console.log(`  ${LIST.length + 1}. Draw a curve…       custom`);
  process.exit(0);
}

/* An easing WORD, for rule 2. Deliberately includes the names that drifted
   in (Spring, S-curve, Ease in-out with the hyphen) as well as the ones
   that survived, because a page offering "Spring" is exactly the bug. */
const EASING_WORD = /^(linear|ease|ease[ -]?in|ease[ -]?out|ease[ -]?in[ -]?out|ease[ -]?in[ -]?out[ -]?sine|ease[ -]?out[ -]?back|ease[ -]?out[ -]?elastic|spring|s-?curve|bounce|steps(,? ?\d+)?|custom)$/i;

const failures = [];

/* rule 3 · the app and the study say the same words in the same order.
   The mocks propose what the app builds, so a proposal that has quietly
   renamed a curve is worse than no proposal. This reads the app's own
   enum rather than a copy of it. */
const SWIFT = "../../../Sources/PhotonzCore/LayerMotion.swift";
try {
  const whole = readFileSync(SWIFT, "utf8");
  /* the enum, not the file: MotionProperty has a `title` switch too */
  const swift = whole.slice(whole.indexOf("public enum EasingCurve"));
  const order = /public static let named: \[EasingCurve\] = \[([\s\S]*?)\]/.exec(swift);
  const titles = /public var title: String \{\s*switch self \{([\s\S]*?)\n    \}/.exec(swift);
  if (order && titles) {
    const label = new Map(
      [...titles[1].matchAll(/case (?:let )?\.(\w+)[^:]*: "([^"]*)"/g)].map(([, c, t]) => [c, t]));
    const appList = [...order[1].matchAll(/\.(\w+)(?:\((\d+)\))?/g)]
      .map(([, c, arg]) => (label.get(c) || c).replace("\\(count)", arg || ""));
    const mockList = LIST.map((c) => c.label);
    if (appList.join(" | ") !== mockList.join(" | ")) {
      failures.push({
        page: COMPONENT,
        why: `the list does not match the app's EasingCurve.named\n      app:  ${appList.join(" / ")}\n      mock: ${mockList.join(" / ")}`,
        fix: `make the two agree — ${SWIFT} is the one the app ships`,
      });
    }
  }
} catch (_) { /* the app is not beside the mocks; the page rules still apply */ }

for (const file of readdirSync(PAGES).filter((f) => f.endsWith(".html")).sort()) {
  const html = readFileSync(join(PAGES, file), "utf8");
  const page = join(PAGES, file);

  /* rule 1 · curve rows written out by hand */
  if (/class="cvth[" ]/.test(html) && !html.includes("data-curve-menu")) {
    failures.push({
      page,
      why: "draws its own curve rows (.cvth) instead of asking for the shared list",
      fix: 'replace the rows with an empty <div class="popover menu pop" id="curveMenu" data-curve-menu>',
    });
  }

  /* rule 2 · a group of buttons that is its own easing vocabulary */
  for (const m of html.matchAll(/<(span|div)\b[^>]*class="[^"]*\bseg\b[^"]*"[^>]*>([\s\S]*?)<\/\1>/g)) {
    const labels = [...m[2].matchAll(/<button\b[^>]*>([^<]*)<\/button>/g)]
      .map((b) => b[1].replace(/&[^;]+;/g, " ").trim())
      .filter(Boolean);
    const easing = labels.filter((l) => EASING_WORD.test(l));
    if (easing.length >= 2) {
      failures.push({
        page,
        why: `a segmented group offers its own easing list: ${labels.join(" / ")}`,
        fix: "use the shared curve control (data-curve-menu) so every page offers the same eight names",
      });
    }
  }
}

if (failures.length) {
  console.error(`check-easing: ${failures.length} page${failures.length > 1 ? "s" : ""} with an easing list of its own\n`);
  for (const f of failures) console.error(`  ${f.page}\n    ${f.why}\n    fix: ${f.fix}\n`);
  console.error(`The one list (node shared/check-easing.mjs --list):`);
  console.error(`  ${LIST.map((c) => c.label).join(" · ")} · Draw a curve…`);
  process.exit(1);
}

console.log(`check-easing: OK. ${LIST.length} named curves in ${COMPONENT}, and every page that offers a curve offers those.`);
