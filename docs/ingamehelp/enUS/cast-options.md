<!--
**One item per row, in menu order, each ending on its default** (2026-09-30). A reader skimming for
one row has to find where it starts, and the lead-in name is what they find it by.

**The values are listed in the menu's order, *Skip this action* first** (`ActionMenuItems.lua`), and
the three rows say it in the same words. Since 2026-10-04 the three rows hold the same three values
(`taking-off-out-of-hover-cast.md`), so a reader who learned one row has learned the other two.

**The usual target is defined once, above the list** (review, 2026-09-30). Read inside the *Hover
Cast* row, "where it would go with no key held" was taken to include the pointed unit.

**"the actions below it are tried", never "the next action runs"** (review, 2026-10-10). The one
below may have its conditions unmet or be skipped too, and a reader testing with such a key reads the
page as wrong.

**Each row names its own empty case, because the two differ.** A held press with nothing left
follows the plain key (`which-action-a-key-runs.md` S4): nothing while one of the key's actions
would run on a plain press, the game while the key is given back. A pointed press is a plain press,
and its empty case is the key's own. Said only on the first row, a reader carried it over to *Hover
Cast* (review, 2026-10-10).

**The held row's condition is the plain press, spelled out.** Written as "unless the key is given
back at that moment", a cold reader sent a held press to the game on a key whose plain press would
have cast (review, 2026-10-10); "given back" read as the default it is on the next row, not as a state
of this key right now.

**A value whose label already says where it goes gets no sentence** (review, 2026-10-10): "*Cast on
yourself* sends the action to you" taught nothing, and the usual target is defined above the list.
*Hover Cast*'s *Cast on the usual target* keeps one for "as if nothing were pointed at". The held
rows' cannot borrow it as "as if the key were not held": with the key let go over a unit, an action on
*Cast on the unit you point at* goes to that unit, and the held press sends it to the usual target
all the same.

**The recipe says "with no key held"** (review, 2026-10-10). *Normal Cast* leaves the held presses
alone, so an action set this way still goes to you or your focus with a cast key held.

**The *Normal Cast* item carries the recipe for "only on the unit you point at"** (review,
2026-10-10). It is what the box is unticked for, and unticking it alone leaves *Hover Cast* on *Cast
on the usual target*, which casts at the target while anything is pointed at.

**Skip with an unticked *Normal Cast* is said in the *Normal Cast* item.** It is the one pairing that
leaves the action nowhere, not even on a held key (`NOTHING_RUNS`, §6), and the reader meets it by
unticking the box.

**The bare mouse button rule is stated here and not only as a locked row** (2026-09-18, owner; §7).
Only *Hover Cast* comes up disabled there; nothing set in any row is read, so that is what the item
says.

**A greyed-out row is not explained here** (review, 2026-09-30, not taken): each one shows its reason
in its own tooltip.

**What a Give Key Back or WoW Binding action does on these rows is not here.** It casts at nothing,
and the two values that run say what it does in their own tooltips (`CASTING_HOVER_TAIL_*`).
-->

# What do Cast Options do?

In *Cast Options* in an action's right-click menu, the first four rows each cover one way of pressing a key: whether this action takes part, and where it goes. Wherever it appears, *Cast on the usual target* means the unit an action bar button would be used on.

- *Self Cast Key*: a press with that key held. *Skip this action* takes the action out of that press, and the actions below it are tried instead. With none left, the press does nothing if pressing the key on its own would run one of its actions. When none would run either, the key is given back by default ([](keys-given-back.md)), and the held press goes to the game too. A new action starts on *Cast on yourself*.
- *Focus Cast Key*: the same, with *Cast on your focus*. A new action starts on *Cast on your focus*.
- *Hover Cast*: a press with no key held, while you point at a unit. *Skip this action* takes the action out of that press, and the actions below it are tried instead; with none left, it is a press where no action runs, and the key is given back by default. *Cast on the usual target* sends the action to its usual target, as if nothing were pointed at. A new action starts on *Cast on the usual target*. Which units count as pointed at is set on the same row: [](hover-cast.md).
- *Normal Cast*: a press with no key held. Untick it and the action runs on such a press only while you point at a unit, going where its *Hover Cast* row sends it; with nothing pointed at, the actions below it are tried instead. For an action that, with no key held, runs only on the unit you point at, untick this and set *Hover Cast* to *Cast on the unit you point at*. With *Hover Cast* on *Skip this action* as well, the action never runs, not even with a key held, and the *Overview* tab marks it *Needs checking*. A new action starts ticked.

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

**The settings box *Keep WoW's bindings on cast key combinations* is not named** (2026-10-10, owner). The reader here is after one key, and the fix the item points at, the binding on that combination, is per key; the box changes every key at once, and its own tooltip says so beside the cast keys on the settings tab.
-->

Good to know:

- **With a unit picked.** When a unit is picked under *Target* in the same menu, every value that sends the action somewhere sends it to that unit instead. *Skip this action* and an unticked *Normal Cast* still work as above. Which of a picked target, a held key and a pointed unit comes first is in [](targeting.md).
- **On a plain left or right click.** An action on the left or right mouse button with no modifier runs only on a unit frame, and nothing set in these rows is read for it: [](clicking-a-unit-frame.md).
- **Where the two keys are set.** The Self Cast Key and the Focus Cast Key are the game's own keys, under Options > Gameplay > Combat.
- **One key ignores the cast key.** If a self cast or focus cast works on every key but one, look for a binding on the cast key together with that key, such as ALT-X, in the game's Keybindings, in another addon or in Debind. With ALT as your Self Cast Key, anything bound to ALT-X runs when you press X with ALT held.
