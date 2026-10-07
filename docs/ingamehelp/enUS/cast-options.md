<!--
**One item per row, in menu order, each ending on its default** (2026-09-30). The rows were a list for the two key rows, three paragraphs for *Hover Cast* and a line after an aside for *Normal Cast*, and a reader skimming for one row could not find where it started. The 2026-09-22 rule still holds: the key rows' *Skip this action* and *Hover Cast*'s *Off* never share a list of values, because on a held key the action is out of that press and on a pointed one it only comes later (`which-action-a-key-runs.md` §6).

**The usual target is defined once, above the list** (review, 2026-09-30). Read inside the *Hover Cast* row, "where it would go with no key held" was taken to include the pointed unit.

**"whose *Hover Cast* is not *Off*", never "has *Hover Cast* set"** (review, 2026-09-30). *Off* is a value too, and "set" read as any value.

**The *Off* against *Cast on the usual target* difference lives here, with an example.** `hover-cast.md` carries the modes and deliberately not the three values. The two differ only in when they are tried because what an unticked *Normal Cast* does to *Off* is said in its own item (§6 table).

**Skip names the empty case** (review, 2026-09-30): a held press with nothing left does nothing and does not fall back to the unheld actions (§3).

**The bare mouse button rule is stated here and not only as a locked row** (2026-09-18, owner; §7). Only *Hover Cast* comes up disabled there; nothing set in any row is read, so that is what the item says.

**A greyed-out row is not explained here** (review, 2026-09-30, not taken): each one shows its reason in its own tooltip.
-->

# What do Cast Options do?

<!--
**STALE for the next release (2026-10-07, not yet rewritten).**
- *Self Cast Key* item: "with none left the press does nothing" is wrong under the give-back default. A held press where nothing set for that key runs goes as the plain press does: given back if the plain press is, nothing if an action would run there. Whether that rule itself stays is being discussed in another session (chords with no twin).
- *Hover Cast* item: *Off* is gone. Values are *Skip this action* / *Cast on the unit you point at* / *Cast on the usual target* (new default). "tried first / keeps its place" is wrong: a pointed press uses the same order as any other press (`taking-off-out-of-hover-cast.md` §2).
- *Normal Cast* item: "tried after the actions whose Hover Cast is not Off" is wrong for the same reason.
- To add: *Skip this action* on *Hover Cast* together with *Normal Cast* unticked is an error.
- The A/B example below and the *Off* in "With a unit picked" need rewriting.
- The header comment above (2-10) talks about *Off*.
-->

In *Cast Options* in an action's right-click menu, each row covers one way of pressing a key: whether this action takes part, and where it goes. On every row, *Cast on the usual target* means the unit an action bar button would be used on.

- *Self Cast Key*: a press with that key held. *Skip this action* takes the action out of that press. The next action on the key that is not skipped runs instead, and with none left the press does nothing. *Cast on yourself* sends the action to you. *Cast on the usual target* sends it to its usual target. A new action starts on *Cast on yourself*.
- *Focus Cast Key*: the same, with *Cast on your focus*. A new action starts on *Cast on your focus*.
- *Hover Cast*: a press with no key held, while you point at a unit. *Cast on the unit you point at* sends the action there. *Off* and *Cast on the usual target* both leave it on its usual target and differ only in when they are tried. With *Off*, it comes after every action on the key whose *Hover Cast* is not *Off*. With *Cast on the usual target*, it keeps its place among them. A new action starts on *Off*.
- *Normal Cast*: a press with no key held, tried after the actions whose *Hover Cast* is not *Off*. Untick it and the action runs on such a press only while you point at a unit, and only if its *Hover Cast* is not *Off*. Otherwise the press goes to the next action on the key. A new action starts ticked.

Say a key holds A and then B, and B is set to *Cast on the unit you point at*. While you point at a unit, B comes first if A is on *Off*. If A is on *Cast on the usual target*, A comes first, on its usual target.

Whether nameplates and units in the world count as pointed at, or only unit frames, is set under the same *Hover Cast* row: [](hover-cast.md).

<!--
**The automatics get one paragraph, not a list** (2026-09-30). Each row's tooltip already says what it does; what the page adds is that they apply to this action alone and where a new action starts. Two labels are the client's (`AUTO_SELF_CAST_TEXT`, `AUTO_DISMOUNT_FLYING_TEXT`) and two ours, and all four are rows of our menu, so all four are blue (`writing-a-help-page.md`).
-->

The four rows below them, *Auto Self Cast*, *Auto Cancel Form*, *Auto Dismount* and *Auto Dismount in Flight*, turn that behaviour of the game on or off for this action alone. A new action starts on *Use the game's setting*, which follows the game's own Options.

<!--
**The rest is one list after the answer, not grey asides** (2026-09-30, owner). Four grey paragraphs in a row read as one block to skip, and the last is the fix a player with a broken key came for. A plain lead-in line and not a heading, because this page opens from a menu row (`writing-a-help-page.md`).

**Each item leads with what the reader is looking at**, since the lead-ins are what a skimmer reads. They carry no blue name because a bold lead-in cannot hold one; the name opens the sentence after it.

**The picked-*Target* item says the casts come out the same, not that a value locks.** A picked target disables nothing under *Cast Options*; `withPickedNote` in `ActionMenuItems.lua` only adds a line.

**The key names go plain in the last two items** (review, 2026-09-22). They point at the game's own keys and settings, where blue would send the reader looking for a row of ours.

**The conflict item names the symptom** (review, 2026-09-22): the player it is for is looking at one key that does not answer the cast key. A held press reaches Debind only because the client drops an unbound ALT-X onto X (`which-action-a-key-runs.md` §3), and Debind's own keys go out through `SetBindingClick` on that same combination, so ours take it the same way (measured 2026-09-22). `Keybindings` is the client's name for that screen (`SETTINGS_KEYBINDINGS_LABEL`). It stays on this page because the reader it is for opens this page from the row that is not answering.
-->

Good to know:

- **With a unit picked.** When a unit is picked under *Target* in the same menu, every value that sends the action somewhere sends it to that unit instead. *Skip this action*, *Off* and an unticked *Normal Cast* still work as above. Which of a picked target, a held key and a pointed unit comes first is in [](targeting.md).
- **On a plain left or right click.** Nothing set in these rows is read, because that action runs only on a unit frame: [](clicking-a-unit-frame.md).
- **Where the two keys are set.** The Self Cast Key and the Focus Cast Key are the game's own keys, under Options > Gameplay > Combat.
- **One key ignores the cast key.** If a self cast or focus cast works on every key but one, look for a binding on the two keys together, in the game's Keybindings or in Debind. With ALT as your Self Cast Key, anything bound to ALT-X runs when you press X with ALT held.
