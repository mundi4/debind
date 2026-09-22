<!--
**Not a help page.** It sits beside `index.md` rather than in a locale folder, so `build-help.js`
does not read it and none of it becomes a locale key. It is the list of what this version has to
tell a reader who updated, kept until the changelog window is there to carry it.

**Outlines, not sentences.** Each entry says what has to be said and what the reader already knows
it by; the wording is written when the window is. Writing finished prose here would be writing it
twice, and the second one would be the one nobody updates.

**What earns an entry**: something the reader will meet on screen or in their own keys. A rename
they will see, a value that is not where it was, a key that behaves differently, a mark that is
new. Not what moved inside the addon.

**What opens the window** (2026-09-18, owner): a number in the code that goes up by one whenever we
want the window shown again, and the last number a reader saw, kept in the profile. Higher in the
code than in the profile means show it. It is not the addon version, so a release with nothing to
say leaves it alone. A fresh profile starts at the code's number, or a reader's first login brings
a list of changes they never had. Same ladder `dbver` is, and it is written when the window is.
-->

# Changelog: the version Cast Options landed in

## Hover Cast is set on each action, and starts off

- What it replaces: the Unit Frame condition, which is how these readers know it.
- What did not change: their existing actions do what they did. An action that ran over a unit
  frame still does.
- What is new to do: turn it on per action, in the action's right-click menu under Cast Options.
  Several actions can be changed at once.
- Where the mode lives now: the settings tab keeps only which units count as pointed at (Unit
  Frames or Mouseover); each action may name its own.

## Cast Options: what each press does

<!-- The value labels have moved since these two bullets were written. Read them off the menu. -->
- The three rows (Self Cast Key, Focus Cast Key, Hover Cast) each take Off, cast at that press's
  unit, or Cast as usual.
- Off is one word on all three rows now. There is no "Skip this action".
- To keep an action from running while pointing at a unit, use the condition on that unit instead
  ([when the unit doesn't exist]). Name where that lives.

## Turning an action off

- New: an action can be turned off without deleting it.
- What it keeps (conditions, importance, its place in the key) and what it gives back (its key,
  to the game).
- How it differs from Delete.

## Two new marks

- An action with every press turned off is now marked, and the way to clear it is turning the
  action off rather than turning a press back on.
- A left or right click with no modifier, with a condition that rules out the only click it can
  answer, is marked on the key and on that condition.

## A key with nothing to run no longer falls back to the game

- What changed: a key whose actions all fail their conditions used to be handed back, and WoW's own
  binding for it ran. Now the key is held and the press does nothing.
- Who this reaches: anybody with a conditional action on a key WoW also binds. An action bar key is
  the common one, and the symptom reads as a broken keybinding rather than as a setting.
- What to do instead: put an action with no conditions last on the key to catch the press. For the
  action bar slot that is Action Button. Say plainly that Use WoW's Own Binding is not it, since the
  name invites exactly that guess.
- The other direction: turning every action on a key off does hand the key back, which is the
  entry above.

## The order on a key

- An action with a Unit Frame condition no longer runs ahead of other conditioned actions on the
  same key. Layers and the place in the key decide, as they do everywhere else.
- Say who this reaches: only a key that holds both a unit-frame action and another conditioned
  action, in different layers.
