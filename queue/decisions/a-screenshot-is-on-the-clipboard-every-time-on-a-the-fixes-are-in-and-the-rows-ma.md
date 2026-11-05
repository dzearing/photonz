# How should the last clipboard check be done?

## What this is about

You said screenshots did not always reach the clipboard on your other Mac, which
runs one released Photonz. That fault has never been seen on this Mac, so its
cause is still not known. You asked for everything fixable from here to be
fixed, with the report from the other Mac only as confirmation.

## What is fixed, on main

- **Keys macOS keeps.** ⇧⌘3 and ⇧⌘4 belong to macOS on a new Mac. They save to
  the Desktop and never touch the clipboard, which looks exactly like Photonz
  failing to copy. Photonz now says so once, with a button to Keyboard Settings,
  and Settings lists every capture key (the rows boxed in the picture). This is
  the likeliest cause, and it is not confirmed.
- **Several displays.** The clipboard now holds the display under the pointer,
  and every display is kept in History.
- **A copy that fails.** It now says so and offers Copy Again.
- **The loop's own copies.** Walks no longer touch your clipboard, so they cannot
  reach your other Mac through Universal Clipboard.

## What was not reached

The task asks for 20 of 20 pastes in every app, with one released Photonz
running. Real Chrome pasted 20 of 20. Preview, Notes, Safari, Messages, Mail and
Claude could not be tested, because this terminal may not press keys in other
apps. Slack and Teams are not installed here. Photonz Dev was running throughout.

## The options

**Release it, then check on the other Mac (recommended).** The fixes reach the
Mac that fails. Copy `Scripts/clipboard-timing/other-mac-report.sh` over, run
`zsh other-mac-report.sh 10`, and use screenshots as usual for ten minutes.

**Let the loop paste into real apps here.** You allow the terminal to press keys
in other apps. This gives the numbers, on a Mac that has never shown the fault.

**Stop here.** The fixes go out with whichever release comes next, and nothing
confirms the other Mac.

The audit has the pictures: `queue/audits/2026-11-05-screenshot-clipboard-suspects-fixed.json`.
