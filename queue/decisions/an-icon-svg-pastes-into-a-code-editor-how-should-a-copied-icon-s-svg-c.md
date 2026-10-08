# How should a copied icon's SVG code reach a code editor?

## What changed already

When you copy a drawing in Photonz (an icon in a frame, shapes on a blank
canvas), the clipboard now holds two things:

- **the picture**, as it always has, so pasting into a chat, Mail or Keynote
  gives the picture;
- **the SVG file** Export writes for a web page, under the Mac's own SVG type.

A screenshot, a photo or a video copies exactly as before: a picture, nothing
else.

## Where the SVG file lands, and where it does not

Measured on this Mac with a real copy from the app, on a local test page
(nothing pasted into any real service):

| Where you paste | What arrives |
| --- | --- |
| A Chrome-based app (Chrome, Edge, Figma's desktop app is built the same way) | The page is handed the SVG and the picture; a rich box shows the picture |
| Safari and other WebKit pages | The picture only. The SVG type is not offered |
| TextEdit, rich document | The picture |
| TextEdit plain text, a code editor, a plain text box | **Nothing** |

Code editors and plain text boxes read only plain text. So the one way the SVG
code reaches them is to put the code on the clipboard as text.

## The catch

The clipboard holds one piece of plain text, and Copy already uses that slot:
when a drawing has measurements on it, the measurement list rides as text so a
redline pastes its numbers into a doc or a chat. Code and list cannot both be
the text.

## The options

**A. Copy Merged also pastes the code as text.** Shift Command C on a drawing
puts the code in the text slot whenever there is no measurement list. Paste
into VS Code and you get the code. The cost: every plain text box gets the
code too, a plain chat box or a terminal included, and a drawing that has
measurements on it never pastes its code.

**B. A Copy SVG row (recommended).** A new row, **Copy SVG**, under Copy Merged
in the Edit menu and in the right-click menu of a layer, a frame and the
canvas. It puts the code on as text. Copy and Copy Merged stay as they are.
This is what Photoshop does (right-click a layer, Copy SVG) and what Figma does
(Copy as, then Copy as SVG), so it is where a person who knows those tools
looks.

**C. Leave it.** Copy carries the SVG file type only; to get code into an
editor, export the SVG and open the file. Choosing this retires the task.

## Worked example

You draw a 24 unit circle icon in an Icon 24 frame and want it in your web
project:

- Under **A**: pick nothing, press Shift Command C, switch to VS Code, press
  Command V. The code lands.
- Under **B**: right-click the frame, choose Copy SVG, Command V in VS Code.
  The code lands. Shift Command C into Slack still gives the picture.
- Under **C**: Shift Command E (Export), choose SVG, save, open the file.
