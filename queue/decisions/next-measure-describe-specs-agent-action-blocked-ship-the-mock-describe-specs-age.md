# What is the Describe specs button?

## The feature in one paragraph

In the design mock, after you have measured a screenshot (widths, gaps, font sizes), there is an **Export** section in the right dock. It has two actions. **Copy as spec list** copies your measurements as clean text you can paste anywhere. **Describe specs** is the ambitious one: one click hands the capture and all its measurements to the agent, and the agent writes the spec *for* you, in sentences, like a designer writing a redline handoff note: "The Save button is 128 by 36 with a 16 px gap to the field above it..."

## Where to see it

- The measure and redline reference mock: [Measure & redline](http://127.0.0.1:8791/index.html#redline) shows the Export section with both actions.
- The full workflow it belongs to: [Capture & redline clickthrough](http://127.0.0.1:8791/index.html#capture-wt), the end-to-end story of capturing a screenshot and redlining it.
- The written spec for the whole measure feature set: `docs/design/next-measure.md` in the repo, section 7 covers export.

## What the decision is really about

The button implies the app can talk to an agent. Nothing like that exists in the shipping app today, so the question is what to ship first:

- **Copy as text only** ships the dependable half now. You still get your measurements out in one click; a person or an agent can turn that text into prose later.
- **Copy as text plus a scriptable surface** additionally lets outside tools pull the measurement list without the app being open, which is a stepping stone toward the full feature.
- **Build the full button now** commits to agent plumbing before the basic measuring workflow has proven itself.

## Why the recommendation is Copy as text only

The primary use of Photonz is fast UX redlining. A reliable, instant text export serves that today. The magical write-it-for-me moment is genuinely wanted, but it is additive: nothing about shipping the text export first makes the button harder later, and the exported list is exactly the input the future agent feature would consume anyway.
