<!--
**The answer comes first.** Whoever opens this was stopped moving a row, so the order is the first thing on the page and the presses come after it (2026-09-17, owner: a help page answers at once).

**The constraint on Importance is in the lead-in, because that is the whole skim path** (2026-09-22). Four rounds of review said it still read as the handle to reach for, and each round moved it further up inside the item: below the list, then into the item, then to the item's first sentence. All three were body text, which the reader who stops at the bolds never sees.

**The lead-in says both halves outright: it overrides, and it goes last** (2026-10-10, owner). Worded as "Importance, where the other three cannot do it", two readers took it for a tie-breaker, the opposite of its rank. Importance has to outrank everything and still never be the first value a player touches.

**The other lead-ins were going to name their controls for the same reason**, since Importance was the only one of them with an on-screen name on it and so the only thing on that path that looked like something to press. A name carries `*` and a lead-in carries `**`, and one inside the other is unbalanced to the parser, so the names sit at the front of each body instead.

**Reversing the list, weakest first, was put up and dropped** (2026-09-22). It leaves an unqualified name on the skim path either way, and it spends the one convention the page cannot afford: higher in this list means tried first. The numbers would then run against the precedence, and the two cross-references inside the items would have to argue with them rather than confirm them.

**The number of levels is left out.** It is the weakest of the reasons and the trap is the same at any count.
-->

# When a key holds more than one action

<!--
**What happens when nothing runs is one sentence and a link.** When a key is given back is its own page (`keys-given-back.md`); here it only closes the rule the paragraph opens. The held cast key's empty case differs from it and is said in the last paragraph, where the held key is; **the opening points there** (review, 2026-10-10), since a reader who stops here would otherwise take a held press to be given back too.
-->

Press a key that holds more than one action and Debind runs the first one whose conditions are met. If none of them runs, the key is given back by default, or the press does nothing, as set under *Keys Given Back* in Debind's settings; with the Self Cast Key or the Focus Cast Key held, see the end of this page. More is in [](keys-given-back.md).

<!--
**"Grouped by key" is what points at the left list.** The Overview tab has two, and the one on the right is a layer's actions; the shape tells them apart where "left" alone would not survive a layout change.

**The list is the answer, not a third place the order shows up** (2026-09-22, owner). All four sort it, so what the reader sees under a key already is the run order, and the four are what puts a row where it is rather than a calculation to run. That is why the items say "stands higher" and not "goes first", and why the last is named by the list rather than by the field behind it, which has no name on screen at all.

**The second item carries its own reason.** An action with no conditions matches every press, and that is the whole case for the step; without it the item reads as an arbitrary rule to memorise. **"every press it takes part in", not "every press"**: *Normal Cast* unticked or *Hover Cast* on *Skip this action* keeps an action with no conditions out of some presses, and those values are not conditions to the order (`which-action-a-key-runs.md` §2).
-->

The *Overview* tab lists actions grouped by key, and under one key they stand in the order they are tried. Four things put them in that order, and the first of the four where two actions differ settles which stands higher.

1. **Importance, which overrides the other three: change it last.** A higher *Importance* stands above the rest. Reach for it only where conditions and layers (below) cannot give the order you want: it is set on the action, and an Account action is the same action on every character, so the *Importance* you give it here applies on characters you are not playing and cannot see.
2. **Whether it has conditions.** An action with conditions stands above one without. One with no conditions runs on every press it takes part in, so nothing under it is reached on those presses.
3. **The layer it is in.** The narrower layer stands higher: this character in this specialization, then this character, then the class in this specialization, then the class, then Account. *Move to...* moves an action to another layer.
4. **Where you put it in that layer.** *Run Sooner* and *Run Later* move the action one place. They are greyed out when one of the three above already settles the order, and the tooltip says which one.

<!--
**These two paragraphs are the one place conditions and layers meet, and the one a reader gets wrong.** They read "the narrower layer stands higher" and expect a character's action to beat any Account action. The first says why the step is there, with the case it exists for (`putting-conditions-back-in-the-order.md` §1).

**The two after it open with the reader's own question, one for each direction** (2026-09-23, owner), because that is what they arrive with, and each answer is a way that keeps them off Importance until nothing else works. Neither answer opens on Importance, since a skimmer takes the first words of an answer as the answer. Each still says what a different Importance does to it, at the end: left out, the fix silently does nothing in that case, and the Importance behind it may have been set while playing another character (second review, 2026-09-23).

The first falls back on a *Classes/Specializations* condition on the narrower action rather than on the Account one: it touches nothing shared, and it holds on every character the narrower action runs on, so it changes nothing but the order.

**The second is a symptom, not an order** (2026-09-23, owner). Its main fix leaves the narrower action on top and lets the presses it no longer takes go on to the broader one; only the case with no conditions on either moves a row. Promising "runs before" there would send the reader to the list to see a move that does not happen. Importance comes last, the same last resort item 1 says it is.
-->

So an Account action with conditions stands above a character's action without them on the same key, unless their *Importance* differs. That is how an action for one situation on every character, such as one set to *While skyriding*, stays in front of each character's everyday action on that key.

**An Account action runs before this character's action on the same key.** That happens when the action in the broader layer (Account here) has conditions and the one in the narrower layer (this character's) does not. Give the narrower one a condition too and it stands above again, because the layer then decides. If no condition fits, give it *Classes/Specializations* and tick your class: that always holds where the action runs, and it still counts as a condition. If the Account action has the higher *Importance*, that decides first; lower it to match.

**This character's action takes the presses an Account action on the same key should get.** If neither has conditions, give the one in the broader layer (Account here) a condition: it then stands above and takes the press whenever that condition holds, unless this character's action has the higher *Importance*. If the one in the narrower layer (this character's) has conditions, add more to it so that it holds in fewer cases, and every press it does not take goes on to the broader one. Only when neither can be done, raise the broader one's *Importance*.

<!--
**No paragraph on pressing an action bar slot from the key.** It was for a key with nothing left to run, which by default now goes back to the game and to whatever the game has on it, the slot included (`keys-given-back.md`). Item 2 already says what an action with no conditions does at the bottom of a key.

**Kept to one paragraph.** Which press an action is set to use, and where it goes, is the targeting page; here it is only what moves an action in or out of the list above.

**Nothing here says what the cursor is over** (2026-09-22, owner). In Unit Frames mode it is over a frame, not over a unit, so "point at a unit" is true of one mode only; and which of the two counts is the account mode or the action's own, which this page does not own. `Hover Cast has a unit for this press` holds either way, and the two hover pages answer the rest.

**The held key gets its own empty case and the pointed press does not**, because that is the difference: a held key ends in its own tier and follows the plain key when nothing there runs, and a pointed press is a plain press, whose empty case is the first paragraph's (`which-action-a-key-runs.md` §3, S4). The wording matches the *Self Cast Key* item of `cast-options.md`, where a cold reader misread "unless the key is given back".

**Normal Cast is named** (review, 2026-10-10). Item 2 says "every press it takes part in", and without this sentence nothing on the page says which value takes an action with no conditions out of a plain press, so an unticked one read as standing in front of the actions under it.
-->

Some of the *Cast Options* change which of a key's actions take part in a press. While you hold the Self Cast Key or the Focus Cast Key, only the actions not set to *Skip this action* for that key are tried. If none of those runs, the press does nothing if pressing the key on its own would run one of its actions; when none would run either, the held press goes where that plain press does. While *Hover Cast* has a unit under your cursor, the actions are tried in the same order as on any other press, and *Hover Cast* sets whether each one takes part. With *Normal Cast* unticked, an action takes no part in a press without either key while *Hover Cast* has no unit under your cursor. What each row of *Cast Options* does is in [](cast-options.md).
