<!--
**One list for three rows.** Off means the same on the Self Cast Key, Focus Cast Key and Hover Cast rows, a twin that is not made (`devdocs/which-action-a-key-runs.md` §6), so the answers are written once instead of once per row. What is left behind differs, and that difference is the second bullet.

**The unit frame click is here and not on the targeting page** because it is an exception to the two key rows: a click on a frame never reaches them (`devdocs/which-action-a-key-runs.md` §7).
-->

# What do the Cast Options do?

*Cast Options* in an action's right-click menu says what the action does on each kind of press. The Self Cast Key, Focus Cast Key and *Hover Cast* rows each take one of three answers:

- *Cast on yourself*, *Cast on your focus* or *Cast on the unit you point at* sends the action to that unit. The two key rows do this unless you change them; *Hover Cast* starts off, so pointing at a unit does nothing until you turn it on.
- *Cast as usual* keeps the action's place on the key and sends it where it would go with nothing held or pointed at.
- *Off* makes no binding for that press. On the two key rows the action is out of that press and the next action on the key takes it. On *Hover Cast* the action still runs, behind every action on the key that does answer a pointed press.

To keep an action from running while you point at a unit, put a condition on that unit instead: under *Units*, pick *Unit Frame* (or *Mouseover*) and choose *When the unit doesn't exist*.

When a unit is chosen under *Target*, the first answer on each row sends the action to that unit instead, and *Cast as usual* is locked. Which of the target, a held key and a pointed unit comes first is in [](targeting.md).

*Hover Cast* also says which units count as pointed at for this action: *Use the mode in Debind's settings*, or *Unit Frames* or *Mouseover* for this action alone.

*Normal Cast* is the press with nothing held and nothing pointed at. Untick it and the action runs only on a held key or a pointed unit, and that plain press goes to the next action on the key.

Clicking a unit frame does not use the Self Cast Key or the Focus Cast Key. A key held on the click picks the binding you made for that exact combination, so the click still goes to the frame's unit.

<!--
**The rule is here and not in a warning** (2026-09-17, owner; the row is locked instead, 2026-09-18). Nothing stored reaches that key, so a warning would ask the reader to change values it ignores. `devdocs/which-action-a-key-runs.md` §7.
-->
An action on the left or right mouse button with no modifier runs only when you click a unit frame. There it ignores *Normal Cast* and *Hover Cast*, using *Unit Frames* and the unit you click, so a click anywhere else still reaches the game.
