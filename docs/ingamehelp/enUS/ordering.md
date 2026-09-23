<!--
**The answer comes first.** Whoever opens this was stopped moving a row, so the order is the first thing on the page and the presses come after it (2026-09-17, owner: a help page answers at once).

**The constraint on Importance is in the lead-in, because that is the whole skim path** (2026-09-22). Four rounds of review said it still read as the handle to reach for, and each round moved it further up inside the item: below the list, then into the item, then to the item's first sentence. All three were body text, which the reader who stops at the bolds never sees.

**The other lead-ins were going to name their controls for the same reason**, since Importance was the only one of them with an on-screen name on it and so the only thing on that path that looked like something to press. A name carries `*` and a lead-in carries `**`, and one inside the other is unbalanced to the parser, so the names sit at the front of each body instead.

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

**The list is the answer, not a third place the order shows up** (2026-09-22, owner). All four sort it, so what the reader sees under a key already is the run order, and the four are what puts a row where it is rather than a calculation to run. That is why the items say "stands higher" and not "goes first", and why the last is named by the list rather than by the field behind it, which has no name on screen at all.

**The second item carries its own reason.** An action with no conditions matches every press, and that is the whole case for the step; without it the item reads as an arbitrary rule to memorise.
-->

The *Overview* tab lists actions grouped by key, and under one key they stand in the order they are tried. Four things put them in that order, and the first of the four where two actions differ settles which stands higher.

1. **Importance, where the other three cannot do it.** A higher *Importance* stands above the rest, however they compare on the other three. It is set on the action, and an Account action is the same action on every character, so the order you give it here is the order it has on characters you are not playing and cannot see.
2. **Whether it has conditions.** An action with conditions stands above one without. One with no conditions runs on every press, so nothing under it would ever be reached.
3. **The layer it is in.** The narrower layer stands higher: this character in this specialization, then this character, then the class in this specialization, then the class, then Account. *Move to...* moves an action to another layer.
4. **Where you put it in that layer.** *Run Sooner* and *Run Later* move the action one place. They are greyed out when one of the three above already settles the order, and the tooltip says which one.

<!--
**These two paragraphs are the one place conditions and layers meet, and the one a reader gets wrong.** They read "the narrower layer stands higher" and expect a character's action to beat any Account action. The first says why the step is there, with the case it exists for (`putting-conditions-back-in-the-order.md` §1).

**The two after it open with the reader's own question, one for each direction** (2026-09-23, owner), because that is what they arrive with, and each answer is a way that keeps them off Importance until nothing else works. Neither answer opens on Importance, since a skimmer takes the first words of an answer as the answer. Each still says what a different Importance does to it, at the end: left out, the fix silently does nothing in that case, and the Importance behind it may have been set while playing another character (second review, 2026-09-23).

The first falls back on a *Class/Specialization* condition on the narrower action rather than on the Account one: it touches nothing shared, and it holds on every character the narrower action runs on, so it changes nothing but the order.

**The second is a symptom, not an order** (2026-09-23, owner). Its main fix leaves the narrower action on top and lets the presses it no longer takes go on to the broader one; only the case with no conditions on either moves a row. Promising "runs before" there would send the reader to the list to see a move that does not happen. Importance comes last, the same last resort item 1 says it is.
-->

So an Account action with conditions stands above a character's action without them on the same key, unless their *Importance* differs. That is how an action for one situation on every character, such as one set to *While skyriding*, stays in front of each character's everyday action on that key.

**An Account action runs before this character's action on the same key.** That happens when the action in the broader layer (Account here) has conditions and the one in the narrower layer (this character's) does not. Give the narrower one a condition too and it stands above again, because the layer then decides. If no condition fits, give it *Class/Specialization* and tick its class: that always holds where the action runs, and it still counts as a condition. If the Account action has the higher *Importance*, that decides first; lower it to match.

**This character's action takes the presses an Account action on the same key should get.** If neither has conditions, give the one in the broader layer (Account here) a condition: it then stands above and takes the press whenever that condition holds, unless this character's action has the higher *Importance*. If the one in the narrower layer (this character's) has conditions, add more to it so that it holds in fewer cases, and every press it does not take goes on to the broader one. Only when neither can be done, raise the broader one's *Importance*.

<!--
**The fallback is named by where it is picked, not by its type name** (2026-09-22, owner). `Action Button` reads as the bar button itself, not as something to choose, and the sentence names an action bar slot one clause earlier. `Use WoW's Own Binding` and every other `Binding Command` become a block on the binding (`Misc.lua`, `dropping-the-game-fallback.md` §3), so the type whose name invites the guess is the one that does not reach the slot.
-->

Leave one action on a key without conditions and it runs whenever nothing above it did. If the key used to press an action bar slot, that action can press the slot: pick it from the *Commands* tab of *Add an Action*, where the action bar buttons are listed.

<!--
**Kept to one paragraph.** Which press an action is set to use, and where it goes, is the targeting page; here it is only what moves an action in or out of the list above.

**Nothing here says what the cursor is over** (2026-09-22, owner). In Unit Frames mode it is over a frame, not over a unit, so "point at a unit" is true of one mode only; and which of the two counts is the account mode or the action's own, which this page does not own. `Hover Cast has a unit for this press` holds either way, and the two hover pages answer the rest.

**The hover clause says the others are still tried and the key clause does not**, because that is the difference: a held key ends in its own tier and a pointed press reads on past it (`which-action-a-key-runs.md` §3). Written as one shape, Hover Cast's Off would read as taking the action out of the press.
-->

Some of the *Cast Options* change which of a key's actions are tried, and in what order. While you hold the Self Cast Key or the Focus Cast Key, only the actions set to use that key are tried, and if none of their conditions are met the key does nothing. While *Hover Cast* has a unit under your cursor, the actions set to use it are tried first and the rest after them. You set these per action, and [](targeting.md) explains them.

> Debind gives a key back when nothing on it is in play: every action either turned off in its own menu, or sitting in a specialization tab you are not in. WoW's own binding works there again, and the key's header is grey in the *Overview* tab.
