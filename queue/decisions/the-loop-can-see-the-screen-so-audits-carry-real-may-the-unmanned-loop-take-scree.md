# May the unmanned loop take screenshots of its own copy of the app?

## What this is about

The go loop builds features in the Next release without anyone watching, and
finishes each one with an audit: a short report with pictures, so you can judge
the feature before you try it. Every audit written on 2026-09-02, sixteen of
them, carries the same caveat: the loop's copy of the app has no Screen
Recording permission, so nothing was checked live and every picture is an
offscreen render of the same view.

That matters most for the capture work. Clicking a window to capture it with its
shadow, the loupe beside the pointer, the toast after a capture: all of it was
verified with scripted events and renders, never by looking at the screen.

## Which app this is

Photonz keeps three copies apart on purpose:

- `Photonz Dev.app` is the one you work in. This card does not touch it.
- `Photonz Probe.app` belongs to the loop. It has its own bundle id
  (`com.dzearing.photonz.probe`), its own settings and its own permissions.
- `Photonz.app` is the shipping build.

The probe is signed with the same stable local identity as the dev app, so a
permission granted once stays granted through every rebuild.

## What you would do under each option

### Grant it

In System Settings, Privacy & Security:

1. Screen Recording: add `dist/Photonz Probe.app` and turn it on.
2. Accessibility: add the terminal that runs the go loop and turn it on, so a
   runner can press a hotkey or open a menu in the probe.

After that, the launch script reports the grant state on every run, runners
save a real screenshot of the probe window with each audit, and live checks
(focus, menus, hotkeys, the real frozen frame during a capture) become part of
the routine. The grants can be turned off again in the same place.

### Keep verification offscreen

Nothing changes. Audits keep rendering through the real pipeline and keep
listing the exact steps for you to check by hand.

## Why this is a card

Only a person can make a permission grant, and letting an unattended process
read the screen is your decision, not the loop's. The task behind this card
does the plumbing (grant reporting in the launch script, screenshot guidance in
the runner prompt) once you have chosen.
