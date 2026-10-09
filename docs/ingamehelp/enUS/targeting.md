<!--
**Why this page exists at all.** Whether the game's own redirection applies to a Debind key turns on one thing, did the reader choose a target, and nothing on screen says so. The people who built it spent a day getting it wrong from the code, so a reader has no chance.

**Written as what the reader did**, never as what the addon stores. Labels are named where the reader has to go: the Target menu, Units, Resolved Unit, Hover Cast and Cast Options. Renaming any of them moves this text with it.

**The title does not open with `Where`.** It is also a button on the settings tab, which is global, and there "where is an action" reads as which tab it is in. Asking for the unit leaves one reading.

**Only the answer stays here** (2026-09-17, owner: a help page answers at once). What each row under Cast Options does is `cast-options.md`.

**A picked unit that is not there swallows the press, and that is one rule for every unit** (`devdocs/which-action-a-key-runs.md` §5: no exception is made for the three). It stood as its own page for Unit Frame and Mouseover, which taught the reader they were special and left a focus or pet action with the same symptom no answer at all (2026-09-22, owner).

**Mouseover is not explained, only used as the yardstick** (2026-09-22, owner: every player knows it, and anyone who does not finds it outside the game). What no tooltip carries is what Unit Frame picks up, and it is said against a word the reader already has.
-->

# Which unit is an action used on?

<!--
**The order comes first, as one list.** The client's own order is named after it because a reader who knows the game expects the cursor to win over a held key (2026-09-15, owner).

**Steps 2 and 3 say which value puts the action on that step.** Step 3 only moves an action set to *Cast on the unit you point at*; since 2026-10-04 a new action is on *Cast on the usual target* (`taking-off-out-of-hover-cast.md`), so a bare "the unit you point at" promised a move the default does not make. Step 2 names the default and leaves the other values to `cast-options.md`.

**"With no focus set, the press does nothing" holds under the give-back default.** The beat keeps or lets go of the chord by the focus tier's records, and a record's box holds only the conditions it carries (`RecordConstraints` in `Judgment.lua`). The focus twin is aimed at `focus` and adds no condition on it (`ActionBindings.lua`, S2), so while the twin's own conditions hold the chord stays ours, even with the plain key given back, and the press is spent on an absent unit the way §5 says a picked `focus` is. When they fail, the press never reached this action, which is the general rule and not this sentence. **It says no other action is tried, and names no way past it** (review, 2026-10-10). "Such a press does nothing" read as covering an action set to the usual target too, and as leaving the next action free to run. "As in 1" was tried and dropped: it carried step 1's fix along, and *When the unit exists* on focus makes the plain press need a focus. *Resolved Unit*'s *When the unit exists* is the closer fix and still not a clean one, since on the plain press it asks the target (S3, `handing-the-rest-of-a-key-to-the-game.md` B12, B13): a heal loses the game's own placing with no target. Which cost an action can take is per spell, and step 2 is about the order.

**Step 1 says "unit", not "target"** (review, 2026-10-10). In the game "the target you picked" is your current target, the opposite of what the step means.

**Step 4 says Mouseover Cast is ignored** (review, 2026-10-10). "As it does on an action bar" alone read against step 3: on a bar with Mouseover Cast on, the hovered unit would get the cast.

**Step 2 names the value, not "its default"** (review, 2026-10-10): a cold reader could not tell the default of which row was meant.

**Step 3 says a new action is not on it** (review, 2026-10-10). A reader who set up *Unit Frame Support* took pointing to work on a new action.

**Auto Self Cast is named after the list, not on one step.** Debind leaves it to the client on every step of the order (`setting-the-clients-cast-automatics-per-action.md` §3, 2026-09-21), so naming it under step 4 alone would read as the other three suppressing it. What the game does with it is not ours to say (owner).

**Mouseover Cast is named even though the answer is "no".** It is on the same client panel as the two keys, so a reader who has it on and is not told otherwise concludes the key is broken.
-->

Where an action goes is settled in this order, and the first that applies decides:

1. **The unit you picked** under *Target*. Nothing you hold or point at moves it. While that unit is not there the press stops with this action, and no other action on the key is tried; to pass it on, add *When the unit exists* for that unit under *Units*.
2. **The key you hold.** The Self Cast Key sends the action to you and the Focus Cast Key to your focus, unless the action's *Cast Options* say otherwise. With no focus set, a Focus Cast Key press stops with an action whose *Focus Cast Key* row is on *Cast on your focus*, where a new action starts, and no other action on the key is tried. A key turned off in Debind's settings counts as not held.
3. **The unit you point at**, for an action set to *Cast on the unit you point at* under *Hover Cast* in its *Cast Options*. A new action is not, and pointing at a unit does not move it. Which units count is the *Hover Cast* mode, in Debind's settings or on the action. The game's own Mouseover Cast does not apply to Debind keys.
4. **None of these.** The game places the cast as it does on an action bar, ignoring Mouseover Cast.

*Unit Frame* under *Target* is narrower than *Mouseover*: only the unit on a unit frame Debind works on, whether that frame belongs to the game or to a unit frame addon, and never a nameplate or a unit in the world. Which frames those are is set under *Unit Frame Support* in Debind's settings.

Auto Self Cast is the game's own, and a Debind key goes out with it as an action bar button does. The *Auto Self Cast* row under *Cast Options* sets it for one action.

In the game's own settings the unit under your cursor comes before the key you hold. In Debind the key comes first.

The *Resolved Unit* condition under *Units* asks about the unit this order arrives at. Debind does not check whether a spell suits that unit, so when it matters, put a condition on it.

What each action does on a held key or a pointed unit is set under *Cast Options* in its right-click menu, explained in [](cast-options.md).
