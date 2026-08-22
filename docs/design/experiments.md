# Experiments — releases in one binary

Photonz ships **two experiences in the same app**: `current`, what everyone gets,
and `next`, where the next-generation experience is built. No separate install,
no separate build variant, no second branch. The user picks a release in
**Experiments** (app menu, or the menu-bar menu) and can tune per-release
feature flags there. `legacy` is reserved for the day Next is promoted.

## Why it exists

The next-gen Photonz has to be buildable without putting today's Photonz at
risk. A separate git branch rots: it drifts, it gets merge-conflicted, and it
never actually ships. So both releases live in one tree, one binary, and the
user picks which one runs.

## The model (PhotonzCore, `Release.swift` / `FeatureFlag.swift` / `FeatureCatalog.swift` / `ExperimentsStore.swift`)

| Type | Role |
| --- | --- |
| `Release` | `current` (default) and `next`. Every trait (title, tagline, storage namespace) is a property on the case, so a third case drops in without touching call sites. |
| `FeatureParameterValue` | A flag's typed knob: number, string, boolean, enumeration (fixed string cases plus the current selection). |
| `FeatureParameter` | Name, label, optional number bounds, value. Refuses a value of the wrong kind, clamps numbers, and only accepts enum cases it declares. |
| `FeatureFlag` | Stable name, title, description, enabled bit, parameters. |
| `FeatureFlagSettings` | One release's flags. `reconciled(with:)` folds stored state onto the current catalog. |
| `FeatureCatalog` | The flags the code has today, which releases each appears in, and where each starts on. |
| `ExperimentsStore` | Reads/writes the selected release and every release's settings, each under its own key. |

Storage is namespaced per release: `experiments.<release>.flags`, plus
`experiments.release` for the choice. Editing Next never touches Current, and
switching back and forth loses nothing.

Only enabled bits and parameter values are persisted. Copy, parameter lists and
limits always come from the catalog, so renaming a description or retiring a
flag can't corrupt anyone's settings: unknown flags are dropped, new ones arrive
with defaults, a value whose type changed falls back, and numbers are clamped.

## How the releases diverge: folders, then flags

A release's own code lives in its own folder:

```
Sources/Photonz/Releases/
  ReleaseExperience.swift   the ONE switch over Release; the app asks here
  Current/                  the Photonz everyone gets (the default)
  Next/                     the next generation, built in the open
  Legacy/                   reserved: fills when Current is demoted
```

`ReleaseExperience` is the seam. The app asks it for a surface, it asks the
running release, and that release's `…Experience` builds it:

```swift
// PhotonzApp, in an editor window
ReleaseExperience.imageEditor(windowID: windowID)
```

Everything outside `Releases/` is **shared**, and that is the normal state. A
file moves into a release folder only when that release genuinely needs it
different:

1. Copy the shared file into the release's folder.
2. Rename its type with the release prefix (`NextEditorView`). One module, so
   names have to stay unique. (If the app is ever split into per-release
   modules, this convention is what that change would replace.)
3. Point that release's `…Experience` factory at the copy.

Whatever a release has not forked keeps coming from the shared code, which is
how Current's fixes keep reaching Next for free.

Smaller differences don't deserve a forked file. Put those behind a feature
flag:

```swift
if Experiments.shared.isEnabled(FeatureCatalog.someFlag) { … }
```

What is not fine:

- branching on `Release` anywhere except `ReleaseExperience`;
- a second build target, scheme, or bundle id for Next;
- forking a whole screen when the actual difference is one behavior a flag
  could carry.

Current stays stable because it is the default, because Next's code sits in
Next's folder, and because each release has its own settings namespace.

## Drift discipline (the one-way rule)

- **Every change to Current must reach Next.** While the file is shared, that
  happens by itself. Once Next has forked that file, carrying the change across
  by hand is part of the work: **a Current change is not finished until Next has
  it.** Next must never fall behind the app people actually use.
- **Nothing in Next is ever back-ported to Current.** Next reaches users by
  being **promoted**, not by leaking.

Promotion is the endgame: when Next is good enough, `next` becomes `current` and
today's `current` becomes `legacy`, so nobody is yanked out from under the app
they know. That is why `Release` is written to absorb a third case, and why the
`Legacy/` folder already exists.

## The app is named after its release

`AppNaming` (PhotonzCore) composes the user-facing name from three parts: the
product name, the release's word, and the dev suffix. So a dev build running
Next calls itself **Photonz Next (Dev)**, and plain Current is just **Photonz**.
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
