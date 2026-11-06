# How should you try out a page of components?

## What this is about

You asked how to preview a page of components: hover over things, click on things.
Today you cannot. The canvas is always for editing, so pointing at a copy only opens
its name tag, and clicking picks it. We checked this on the real app with a button
that has Hover, Pressed and Disabled looks: with the pointer on it, the only pixels
that changed were the name tag.

This is a prototype of the answer. It runs in the browser and every rule works:

**[Try the prototype](http://127.0.0.1:8791/index.html#component-preview)**. Press
**Show me** to watch it, or press **Preview** and use the page. The seven boxes above
the window tick themselves off as you go.

The page in the prototype is drawn in HTML, not by the app. The rules for which look
shows when are the ones a build would run.

## What you would do

1. Open a picture with component copies on it and press **Preview** in the title bar,
   or ⌘Return, or View ▸ Preview.
2. The tools, the panel and Ask go. The page shows at 100 percent, or fitted if it
   would not fit. A small pill says Preview, Esc to leave.
3. Use it. Point at a button and it shows Hover. Press and it shows Pressed. Slide off
   while holding and it lets go, with no click, as a real button does.
4. Click a switch or a checkbox and it stays flipped. Click a tab or a radio and one
   stays picked in its group. Press Tab to move focus, and Space or Return to click.
5. Press Esc. The page, your selection, your zoom and Undo are as you left them.

## Nothing to set up

The looks' own names say what they are for: Default, Hover, Pressed, Focused, Disabled,
On, Off, Checked and Selected. There is no setting to fill in.

## Things the prototype settled that you may want to look at

- **A state with no look keeps the look it has.** Point at the Selected tab: there is
  no Selected Hover look, so it stays Selected. Using the plain Hover look there would
  make a picked tab appear to un-pick itself. If you name a look **On Hover**, it is
  used, and the switch in the prototype shows that.
- **A segmented control is one component.** The sheets Ask makes name its looks after
  its own words (Day, Week, Month), so a click on a word shows that word's look.
- **Tab stops only where a Focused look can show.** Preview adds no focus ring of its
  own, because it uses only the looks you made, so a stop with nothing to show would
  look like the key had failed.
- **Which copies count as one group.** Copies of one component inside the same group
  keep one selected. Copies that are not in a group count as one group for the page,
  so two sets of radios need a group each.
- **The Preview button never moves.** Ask goes away in Preview but keeps its space, so
  the second click, the one that leaves, lands on the same button.

## The one rule this bends

The placement rules keep status pills off the canvas. Your task asked for a pill saying
how to leave, so this is one named exception. It sits where the tool bar was, and the
page is always fitted to leave it clear, so it never covers what you are trying. A
component whose looks are named some other way puts a short note in it when you point
at it. Try the Plan card: it says Plan: no state looks.

## What is not in this step

- Typing into a field. A click shows its Focused look, and that is all.
- Clicking a button to go to another page, as your
  [Prototyping mock](http://127.0.0.1:8791/index.html#ui-prototype) draws. That is the
  next step, when you ask for it.

## What each answer means

- **Build it as shown.** A Preview button, on pictures that hold component copies.
- **Use the View and Edit switch.** Use the switch above the prototype's window to see
  it. One control for pictures and videos, but View means a player on a video and a
  live page here.
- **Not yet.** Say what is wrong in your note. The prototype changes and a new card
  comes back. Nothing is built.
- **Do not build this.** The task is dropped, and the canvas stays for editing only.
