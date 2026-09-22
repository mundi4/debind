<!--
**Two lists, not one** (2026-09-22, owner). The first setting leaves different things behind: on the two key rows the action is out of that press, on Hover Cast nothing about it changes. Written as one list, *Off* and *Cast on the usual target* read as the same setting.

**The paragraph on the two Hover Cast values says only how they differ** (review, 2026-09-22). It opened by repeating where both send the action, which the paragraph above it had just said, so the one thing it is there for arrived third.

**One thing a sentence** in the paragraph that hands off to the hover page (review, 2026-09-22). The condition and the mode row were carried by one sentence with the link inside it, and neither came out of a single read.

**The bare mouse button rule is stated here and not only as a locked row** (2026-09-18, owner; `which-action-a-key-runs.md` §7).

**One row locks there, not these rows** (review, 2026-09-22). Only *Hover Cast* comes up disabled on a bare click (`ActionMenuItems.lua`); the two key rows lock for a different reason, the key being off account wide, and *Normal Cast* is a tickbox that never locks. What is true of all four is that nothing set in them is read, so that is what the aside says.
-->

# What do Cast Options do?

*Cast Options* in an action's right-click menu sets what this action does on each kind of press.

The *Self Cast Key* and *Focus Cast Key* rows each take one of three settings:

- *Cast on yourself* or *Cast on your focus* sends the action to that unit while you hold the key. A new action is set to this.
- *Cast on the usual target* keeps the action in that press and sends it where it would go with no key held.
- *Skip this action* takes it out of that press, and the press goes to the next action on the key.

<!--
**The rule before the three settings** (`which-action-a-key-runs.md` §3, 2026-09-17 owner). A held
press reaches Debind at all because the client dropped an unbound ALT-X onto X; with anything bound
to the two keys together the press never arrives. Nothing in this window can show it, because the
other binding may be WoW's.

**It opens with the symptom** (review, 2026-09-22). Stated as the rule alone it was followable and
still useless: the player it is for is looking at one key that does not answer the cast key, and the
cause is not something they would think to look up. The sentence that sends them to their
keybindings is the one naming what they are seeing.

**Debind's own keys count too, and that is measured** (2026-09-22). §3 said only that another
binding takes the press, and Debind's own keys go out through `SetBindingClick` on that same
combination, so ours takes it the same way.

**Both places are named where the reader is sent, not where the rule is stated** (review,
2026-09-22). `Keybindings` is the client's own name for that screen (`SETTINGS_KEYBINDINGS_LABEL`)
and it goes in the clause that tells them to go looking; the example then needs no second list, and
one thing is no longer called `WoW` here and `the game's own` in the aside below.

**It stands above the Options aside** (review, 2026-09-22). It is what makes the first bullet false,
so it goes directly under the list; the other one says where the game keeps those keys and waits.

**The two names go plain in the aside below** (review, 2026-09-22). The tag follows what the word
points at, and that sentence points at the game's own settings, where blue would send the reader
looking for a row of ours (`writing-a-help-page.md`). Blue is right two blocks up, where the same
words name our rows.
-->

> If a self cast or focus cast works on every key but one, look for a binding on the two keys together, in the game's Keybindings or in Debind. Holding the key reaches an action only while that combination has nothing bound to it: with ALT as your Self Cast Key, anything bound to ALT-X runs when you press X with ALT held.

> The Self Cast Key and the Focus Cast Key are the game's own keys, under Options > Gameplay > Combat.

*Hover Cast* is a row of the same shape for the unit you point at, holding *Cast on the unit you point at*, *Cast on the usual target* and *Off*. A new action is set to *Off*, which does not stop the action from running: pointing at a unit simply does not change where it goes.

*Off* and *Cast on the usual target* differ only in the turn this action takes. With *Off*, it is tried after every action on the key whose *Hover Cast* is set to something else; with *Cast on the usual target*, it keeps its usual place among them. The order itself is in [](ordering.md).

To keep an action from running at all while you point at a unit, give it a condition under *Units*. Under the three *Hover Cast* settings is a mode row that says which units count as pointed at. Both are in [](hover-cast.md).

> When a unit is chosen under *Target* in the same menu, every press that runs this action sends it to that unit, so *Cast on yourself* and *Cast on the usual target* come to the same cast. Which of a picked target, a held key and a pointed unit comes first is in [](targeting.md).

*Normal Cast* covers the press with no key held, unless *Hover Cast* takes that press for this action. Untick it and that press goes to the next action on the key.

> On the left or right mouse button with no modifier nothing set in these rows is read, because that action runs only on a unit frame: [](clicking-a-unit-frame.md).
