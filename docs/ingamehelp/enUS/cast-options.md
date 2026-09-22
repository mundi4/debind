<!--
**Two lists, not one** (2026-09-22, owner). The first setting leaves different things behind: on the two key rows the action is out of that press, on Hover Cast nothing about it changes. Written as one list, *Off* and *Cast on the usual target* read as the same setting.

**The bare mouse button rule is stated here and not only as a locked row** (2026-09-18, owner; `devdocs/which-action-a-key-runs.md` §7).
-->

# What do Cast Options do?

*Cast Options* in an action's right-click menu sets what this action does on each kind of press.

The *Self Cast Key* and *Focus Cast Key* rows each take one of three settings:

- *Cast on yourself* or *Cast on your focus* sends the action to that unit while you hold the key. A new action is set to this.
- *Cast on the usual target* keeps the action in that press and sends it where it would go with no key held.
- *Skip this action* takes it out of that press, and the press goes to the next action on the key.

> The *Self Cast Key* and the *Focus Cast Key* are the game's own keys, under Options > Gameplay > Combat.

*Hover Cast* is a row of the same shape for the unit you point at, holding *Cast on the unit you point at*, *Cast on the usual target* and *Off*. A new action is set to *Off*, which does not stop the action from running: pointing at a unit simply does not change where it goes.

*Off* and *Cast on the usual target* both send it where it would go with nothing pointed at. What differs is the turn it takes. With *Off*, this action is tried after every action on the key whose *Hover Cast* is set to something else; with *Cast on the usual target*, it keeps its usual place among them. The order itself is in [](ordering.md).

To keep an action from running at all while you point at a unit, give it a condition under *Units*. That, and the mode row under the three *Hover Cast* settings that says which units count as pointed at, are in [](hover-cast.md).

> When a unit is chosen under *Target* in the same menu, every press that runs this action sends it to that unit, so *Cast on yourself* and *Cast on the usual target* come to the same cast. Which of a picked target, a held key and a pointed unit comes first is in [](targeting.md).

*Normal Cast* covers the press with no key held, unless *Hover Cast* takes that press for this action. Untick it and that press goes to the next action on the key.

> On the left or right mouse button with no modifier these rows are locked and nothing set here is read, because that action runs only on a unit frame: [](clicking-a-unit-frame.md).
