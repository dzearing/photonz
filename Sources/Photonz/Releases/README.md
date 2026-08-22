# Releases

Photonz ships more than one experience in one binary. This folder is where a
release's own code lives.

```
Releases/
  ReleaseExperience.swift   the ONE switch over Release; the app asks here
  Current/                  the Photonz everyone gets (the default)
  Next/                     the next generation, built in the open
  Legacy/                   reserved: fills when Current is demoted
```

Everything outside this folder is **shared** by every release. That is the
normal state: a file only moves in here when a release genuinely needs it
different.

## Forking a file

1. Copy the shared file into your release's folder.
2. Rename its type with the release prefix (`NextEditorView`). One module, so
   names have to stay unique.
3. Point that release's `…Experience` factory at the copy.

Everything the release has not forked keeps coming from the shared code, so
Current's fixes keep reaching Next for free until Next has its own copy.

## The porting rule, one way only

- **Every change to Current must reach Next.** While the file is shared that
  happens by itself. Once Next has forked that file, carrying the change across
  is yours to do by hand, and the Current change is not finished until you have.
- **Nothing in `Next/` is ever back-ported to Current.** Next reaches people by
  being promoted, not by leaking.

Promotion is the endgame: Next becomes Current, today's Current becomes Legacy,
and nobody is yanked out from under the app they know.

## Adding a surface releases can differ on

Add a factory to `ReleaseExperience`, give every release folder its version, and
call it from the app. Never branch on `Release` anywhere else: one switch, in
one file, is what keeps this honest.

Full design: `docs/design/experiments.md`.
