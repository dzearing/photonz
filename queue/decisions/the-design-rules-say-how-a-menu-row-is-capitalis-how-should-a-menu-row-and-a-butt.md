# How should a menu row and a button be capitalised?

## What this is about

Every menu in Photonz has rows: the menu bar at the top of the screen, the
menu you get when you right-click a clip, a layer or the canvas, and the small
menus behind the "..." on a panel. Buttons in the right hand panel carry short
labels too. This question is only about how those words are capitalised.

There are two ways to write the same row:

| Mac title case | Sentence case |
| --- | --- |
| Apply to Every Cut | Apply to every cut |
| Reset to Defaults | Reset to defaults |
| Copy Look | Copy properties |
| Draw a Curve... | Draw a curve... |

## Where the two disagree today

- **The mocks** write every row in sentence case. For example the right-click
  menus in [the video mock](http://127.0.0.1:8791/index.html#video) and the
  panel menus in [the app shell mock](http://127.0.0.1:8791/index.html#app-shell)
  ("Copy properties", "Reset to style", "Group selection").
- **The app** writes every menu row in Mac title case. A count of the rows it
  shows found 127 in title case and none in sentence case. Buttons inside the
  panel are mixed ("Draw a curve...", "Use this curve" are sentence case).
- **macOS itself** puts title case rows into our menus that we cannot reword:
  Select All, Enter Full Screen, Hide Others, Show Tab Bar.
- **Photoshop, Premiere and Final Cut** all use title case in their menus:
  Merge Down, Ripple Delete, Add Cross Dissolve.

Nothing in the design rules says which wins, so each new menu row picks one and
its audit explains the choice. Four audits did that in three days.

## What you would see

**a. The Mac way (recommended).** Nothing on screen changes for menus: they
already read this way. Panel buttons like "Draw a curve..." become
"Draw a Curve...". The mocks are left as drawn, and the rule says once that
rows are written the Mac way.

**b. The mock way.** Every row the app writes is rewritten: "Apply to every
cut", "Reset to defaults". Rows macOS supplies stay title case, so the Edit
menu would read "Undo", "Select All", "Copy look" side by side.

**c. Menus the Mac way, buttons the mock way.** Menus stay as they are today.
Buttons in the panel keep sentence case, matching the labels around them. Two
rules instead of one.

## What happens after you answer

The rule goes into the design rules, and a test reads every menu row the app
registers and fails the build on a row that breaks it, so the question never
comes back in an audit.
