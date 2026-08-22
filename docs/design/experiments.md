# Experiments — two releases in one binary

Photonz ships **two experiences in the same app**: `public`, what everyone gets,
and `next`, where the next-generation experience is built. No separate install,
no separate build variant, no forked source tree. The user picks a release in
**Experiments** (app menu, or the menu-bar menu) and can tune per-release
feature flags there.

## Why it exists

The next-gen Photonz has to be buildable without putting today's Photonz at
risk. A separate branch or a duplicated view hierarchy rots: it drifts, it gets
merge-conflicted, and it never actually ships. So the divergence lives in the
running code, gated at the few call sites that need it.

## The model (PhotonzCore, `Release.swift` / `FeatureFlag.swift` / `FeatureCatalog.swift` / `ExperimentsStore.swift`)

| Type | Role |
| --- | --- |
| `Release` | `public` (default) and `next`. Every trait (title, tagline, storage namespace) is a property on the case, so a third case drops in without touching call sites. |
| `FeatureParameterValue` | A flag's typed knob: number, string, boolean, enumeration (fixed string cases plus the current selection). |
| `FeatureParameter` | Name, label, optional number bounds, value. Refuses a value of the wrong kind, clamps numbers, and only accepts enum cases it declares. |
| `FeatureFlag` | Stable name, title, description, enabled bit, parameters. |
| `FeatureFlagSettings` | One release's flags. `reconciled(with:)` folds stored state onto the current catalog. |
| `FeatureCatalog` | The flags the code has today, which releases each appears in, and where each starts on. |
| `ExperimentsStore` | Reads/writes the selected release and every release's settings, each under its own key. |

Storage is namespaced per release: `experiments.<release>.flags`, plus
`experiments.release` for the choice. Editing Next never touches Public, and
switching back and forth loses nothing.

Only enabled bits and parameter values are persisted. Copy, parameter lists and
limits always come from the catalog, so renaming a description or retiring a
flag can't corrupt anyone's settings: unknown flags are dropped, new ones arrive
with defaults, a value whose type changed falls back, and numbers are clamped.

## How next-gen behavior diverges (decided; do not re-litigate)

**Runtime-gated inside shared code.** Two tools, in order of preference:

1. **A feature flag** when the behavior is worth configuring or worth turning
   off independently:
   ```swift
   if Experiments.shared.isEnabled(FeatureCatalog.someFlag) { … }
   ```
2. **A release branch** at the specific call site when it's simply "Next does
   this differently":
   ```swift
   if Experiments.shared.release == .next { … } else { … }
   ```

One-offs sprinkled through the existing views are FINE. What is not fine:

- a parallel `Next/` view hierarchy, or a duplicated editor;
- a second build target, scheme, or bundle id for Next;
- a global "if next" wrapper around a whole screen instead of the specific
  behavior that actually differs.

Public stays stable because it is the default, it is untouched by Next-only
branches, and it has its own settings namespace.

## Drift discipline (the one-way rule)

- Features added to **Public** are **ported forward to Next**. Next must never
  fall behind the app people actually use.
- Features in **Next** are **NEVER back-ported to Public**. Next reaches users
  by being **promoted**, not by leaking.

Promotion is the endgame: when Next is good enough, `next` becomes `public` and
today's `public` becomes `legacy`, so nobody is yanked out from under the app
they know. That is why `Release` is written to absorb a third case.

## Switching releases takes a relaunch

Deliberate. The release choice reaches AppKit surfaces built outside SwiftUI's
environment (the menu-bar agent, the capture overlay, the floating panels), and
windows opened under one release should not half-morph into the other. So:

- `Experiments.shared.release` is the release this process is running, fixed at
  launch.
- `selectedRelease` is what the next launch will run. It persists immediately.
- The dialog says so out loud and offers a one-click relaunch.

**Flag edits inside the running release apply live** — `Experiments` is
`@Observable`, and call sites read it when they draw.

## The app is named after its release

`AppNaming` (PhotonzCore) composes the user-facing name from three parts: the
product name, the release's word, and the dev suffix. So a dev build running
Next calls itself **Photonz Next (Dev)**, and plain Public is just **Photonz**.
`AppInfo.name` is the single source for that string, so About, Quit, the Welcome
window and the menu-bar accessibility label all follow.

The macOS app menu is the exception: its title comes from the bundle, which is
fixed at build time. `AppCoordinator.applyAppMenuTitle()` renames menu item 0 at
launch and again on every activation, because SwiftUI rebuilds the menu bar as
scenes come and go.

## The dialog

`Sources/Photonz/ExperimentsDialog.swift`, in a plain window owned by
`ExperimentsWindowController` (app-level, so it opens with no editor window on
screen). Selecting a release row only changes which flags you are looking at;
switching is a separate, explicit button.

The flag list is a word wheel: a search field narrows it as you type
(`FeatureFlagSettings.flags(matching:)`, every term has to match). A flag is an
on/off switch first, so its parameters stay collapsed behind a disclosure until
you go looking for them. Opened, each parameter gets the control its type asks
for: stepper + field for numbers, text field for strings, switch for booleans,
pop-up for enumerations.

## Adding a flag

1. Add a `Definition` to `FeatureCatalog`, with its releases and where it starts
   on, plus name constants.
2. Read it at the call site through `Experiments.shared` (add a small reader in
   the "Flag readers" extension so the call site stays one line, with a fallback
   that behaves exactly like stock Photonz).
3. Cover the model side in `Tests/PhotonzCoreTests/ExperimentsTests.swift`.

Two flags ship today and prove the plumbing end to end:
`release-tag-in-window-title` (string, enum and boolean parameters; tags editor
window titles) and `capture-toast-timing` (number parameters; how long a
post-capture toast holds and fades).
