<!--
**The answer comes first.** Whoever opens this was stopped moving a row, so the order is the first thing on the page and the presses come after it (2026-09-17, owner: a help page answers at once). The advice on which handle to reach for first is left out for the same reason.
-->

# Which action does a key run?

<!--
**"The key does nothing" is the line that matters to someone upgrading.** Up to the previous release a key with nothing to run was handed back to the game and its own keybinding ran; that path is gone (`devdocs/legacy/dropping-the-game-fallback.md`). It also covers a held key no action answers, so the paragraph at the end needs no sentence of its own for that. Pet battles handing keys back are left out: there the key does what the battle bar shows.
-->

A key can hold more than one action. Press it and Debind runs the first one whose conditions are met. If none of them does, the key does nothing.

<!--
**"Grouped by key" is what points at the left list.** The Overview tab has two, and the one on the right is a layer's actions; the shape tells them apart where "left" alone would not survive a layout change.
-->

The order is the one under the key in the list on the left of the *Overview* tab, where actions are grouped by key. It is decided by these, from the top. The first one where two actions differ settles it.

1. *Importance*. The higher one goes first.
2. *Conditions*. An action with conditions goes before one without.
3. **Layer.** The narrower layer goes first, from this character and specialization down to Account. Set with *Move to...*.
4. **Position.** When all three are equal, *Run Sooner* and *Run Later* move the action one place. They are greyed out when one of the three above already decides, and the tooltip says which.

<!--
**Kept to one paragraph.** Which press an action answers, and where it goes, is the targeting page; here it is only what moves an action in or out of the list above.

**"Turned off in Debind's settings" is there because the sentence is false without it**: a key unticked there counts as not held. A key the game has no binding for needs no clause, since there is nothing to hold.
-->

While you hold the Self Cast Key or the Focus Cast Key, unless it is turned off in Debind's settings, only the actions that answer that key are tried. While you point at a unit, the actions that answer that are tried first, and the rest after them. What each action answers is set under *Cast Options*, explained in [](targeting.md).
