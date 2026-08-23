# What should the fourth Library tab be?

## The surface

Every editor screen in the design study has one panel dock on the right. The bottom group in that dock is the **Library**: the one place for reusable content you browse and drag onto the canvas. Inside it, a row of four small tabs picks what you are browsing:

- **Media**: your captures, imported images, video clips
- **Comp**: components, reusable pieces like a card or a button
- **Styles**: named paints and text styles
- **Assets**: the fourth tab today, and the one this decision is about

You can see the row live on the [Build a design system walkthrough](http://127.0.0.1:8791/index.html#ds-build-wt) (open the Library group in the right dock), and the standard version on the [agent generate walkthrough](http://127.0.0.1:8791/index.html#agent-generate-wt).

## Why this came up

The walkthrough that teaches "build a design system" needed a place for the system you build. In that story you name a paint (it lands in Styles), promote a card to a component (it lands in Comp), and then publish the pair as **brand-system v1.0**. The page gave that final object its own fourth tab called **Systems**, replacing Assets.

That broke consistency: every other screen shows Assets. It also surfaced a real gap. **Assets is an empty tab on every page.** No screen defines what an asset is or puts anything in it. Meanwhile the product model document describes the system catalog as living in the Library, in a scope it calls "Styles/Systems", which reads either as a Systems tab or as systems sharing the Styles tab.

So the study currently disagrees with itself, and one answer has to be applied everywhere.

## What you would see under each option

**a. Systems replaces Assets (recommended).** The tab row reads Media, Comp, Styles, Systems on every screen. The Systems tab shows your document's system as a card (name, draft or published version, what it contains, a Publish button), and later a browsable catalog of systems you can apply to re-theme the document. The reuse story the product teaches becomes visible in the furniture itself: tokens become styles, styles dress components, and both roll up into a system. Nothing is orphaned by losing Assets, because imported files already live under Media.

**b. Systems live inside Assets.** The row stays Media, Comp, Styles, Assets everywhere, and the system card sits at the top of the Assets tab. Cheapest change, and it preserves a drawer for future odds and ends. The cost is the label: nothing about the word Assets says "publish and apply your design system here", so the walkthrough's step 6 would read "click Assets" at its biggest moment.

**c. Systems live with Styles.** The row stays as it is, and the Styles tab leads with the system card above the styles grid. This matches the product model's "Styles/Systems" wording most literally and keeps styles next to the system that owns them. The cost is a crowded tab doing two jobs in a narrow dock, and publishing loses its own addressable place.

## What happens after you pick

The winning shape gets applied to the walkthrough page and to the shared pattern doc, and the remaining screens are brought in line so the Library reads identically everywhere. The clipped tab labels are already fixed separately: the row now gives each label its natural width, so whichever names win, they render whole.
