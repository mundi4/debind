<!--
**The answer comes first.** Whoever opens this was stopped moving a row, so the order is the first thing on the page and the presses come after it (2026-09-17, owner: a help page answers at once).

**The constraint on Importance is in the lead-in, because that is the whole skim path** (2026-09-22). Four rounds of review said it still read as the handle to reach for, and each round moved it further up inside the item: below the list, then into the item, then to the item's first sentence. All three were body text, which the reader who stops at the bolds never sees.

**The other two lead-ins were going to name their controls for the same reason**, since Importance was the only one of the three with an on-screen name on it and so the only thing on that path that looked like something to press. A name carries `*` and a lead-in carries `**`, and one inside the other is unbalanced to the parser, so the names sit at the front of each body instead.

**Reversing the list, weakest first, was put up and dropped** (2026-09-22). It leaves an unqualified name on the skim path either way, and it spends the one convention the page cannot afford: higher in this list means tried first. The numbers would then run against the precedence, and the two cross-references inside the items would have to argue with them rather than confirm them.

**The number of levels is left out.** It is the weakest of the reasons and the trap is the same at any count.
-->

# When a key holds more than one action

<!--
**"The key does nothing" is the line that matters to someone upgrading.** Up to the previous release a key with nothing to run was handed back to the game and its own keybinding ran; that path is gone (`dropping-the-game-fallback.md`). It also covers a held key nothing on it is set to use, so the paragraph at the end needs no sentence of its own for that. Pet battles handing keys back are left out: there the key does what the battle bar shows.

**Getting the key back is an aside and not a third opening paragraph** (2026-09-22). It answers when Debind stops holding a key, which is a different question from which action runs, and it was pushing the page's own subject down to the eighth line.

**The specialization half is named by its tab, never as a condition** (2026-09-22, owner). A layer for another specialization is not walked at all, so the key goes; a *specialization* condition that cannot hold on this character keeps the key, deliberately (2026-09-19, owner, `BuildKeyMap` in `Debind.lua`). One word covering two opposite outcomes is why this sentence names the tab.

**The grey header carries the cases this sentence does not count** (`IsKeyHandled`, `DebindUI.lua`). The reader does not have to match their key against a list; the list on screen already says which side it is on.
-->

Press a key that holds more than one action and Debind runs the first one whose conditions are met. If no action's conditions are met, the key does nothing: Debind keeps the key, and what WoW has bound to it does not run.

<!--
**"Grouped by key" is what points at the left list.** The Overview tab has two, and the one on the right is a layer's actions; the shape tells them apart where "left" alone would not survive a layout change.

**The list is the answer, not a third place the order shows up** (2026-09-22, owner). All three sort it, so what the reader sees under a key already is the run order, and the three are what puts a row where it is rather than a calculation to run. That is why the items say "stands higher" and not "goes first", and why the third is named by the list rather than by the field behind it, which has no name on screen at all.

**Conditions came out of the axis** (`taking-conditions-out-of-the-order.md`, implemented 2026-09-22). The sentence after the list is there because a reader who knew the old rule looks for the step and finds nothing, and a list that is silent about it cannot tell them it is gone on purpose.

**The one-time move on upgrade is not on this page.** It needs a key used in two layers with the broader one conditional and the narrower one not (§3-2), the action it covers is marked Never runs on screen, and the fix is a condition on the narrower one. That is a changelog line, not a rule of how the order works.
-->

The *Overview* tab lists actions grouped by key, and under one key they stand in the order they are tried. Three things put them in that order, and the first of the three where two actions differ settles which stands higher.

1. **Importance, where the other two cannot do it.** A higher *Importance* stands above the rest whatever they say. It is set on the action, and an Account action is the same action on every character, so the order you give it here is the order it has on characters you are not playing and cannot see.
2. **The layer it is in.** *Move to...* moves it between them, and the narrower layer stands higher, from this character and specialization down to Account.
3. **Where you put it in that layer.** *Run Sooner* and *Run Later* move the action one place. They are greyed out when one of the two above already settles the order, and the tooltip says which one.

Putting a condition on an action does not move it.

> *Use the old run order* in Debind's settings adds a fourth test above the layer, for the whole account: an action with conditions is tried before one without. It is there for keys you set up under an earlier version, and it will be removed in a later version.

<!--
**The two halves of one fact are one paragraph** (2026-09-22). An action with no conditions taking everything below it, and a last action put there on purpose to catch what nothing else took, were a paragraph apart with the whole list between them.

**The fallback is named by where it is picked, not by its type name** (2026-09-22, owner). `Action Button` reads as the bar button itself, not as something to choose, and the sentence names an action bar slot one clause earlier. `Use WoW's Own Binding` and every other `Binding Command` become a block on the binding (`Misc.lua`, `dropping-the-game-fallback.md` §3), so the type whose name invites the guess is the one that does not reach the slot.
-->

An action with no conditions is tried on every press, so nothing below it is ever reached. Give each one the conditions for the case it is meant for, and a press that meets none of them moves on to the next action down.

The last action on a key is the one to leave without conditions, so that it is tried when nothing above it ran. To reach the action bar slot that key used to press, pick that last one from the *Commands* tab of *Add an Action*, where the action bar buttons are listed.

<!--
**Kept to one paragraph.** Which press an action is set to use, and where it goes, is the targeting page; here it is only what moves an action in or out of the list above.

**It opens by saying it is not a fourth thing.** The list says three decide the order, and this paragraph adds two more influences; without the opening clause the reader's count breaks.

**The cast key clause names the Debind setting because the sentence is false without it**: a key unticked there counts as not held. A key the game has no binding for needs no clause, since there is nothing to hold.

**Nothing here says what the cursor is over** (2026-09-22, owner). In Unit Frames mode it is over a frame, not over a unit, so "point at a unit" is true of one mode only; and which of the two counts is the account mode or the action's own, which this page does not own. `Hover Cast has a unit for this press` holds either way, and the two hover pages answer the rest.

**The hover clause says the others are still tried and the key clause does not**, because that is the difference: a held key ends in its own tier and a pointed press reads on past it (`which-action-a-key-runs.md` §3). Written as one shape, Hover Cast's Off would read as taking the action out of the press.
-->

Some of the *Cast Options* change which of a key's actions are tried, and in what order. While you hold the Self Cast Key or the Focus Cast Key, only the actions set to use that key are tried, and if none of their conditions are met the key does nothing. While *Hover Cast* has a unit under your cursor, the actions set to use it are tried first and the rest after them. You set these per action, and [](targeting.md) explains them.

> Debind gives a key back when nothing on it is in play: every action either turned off in its own menu, or sitting in a specialization tab you are not in. WoW's own binding works there again, and the key's header is grey in the *Overview* tab.
