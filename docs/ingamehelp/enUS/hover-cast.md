<!--
**The page the settings tab sends a reader to.** That row sets one thing, which units count as
pointed at, and a reader meeting the name there needs to know what it is before the two modes mean
anything. The explanation used to be the row's own tooltip and outgrew it.

**What it does not carry**: the other rows of Cast Options, and what each Hover Cast value does next
to *Normal Cast*. That is `cast-options.md`, and saying it twice is saying it two ways by next month.

**Hover Cast is never something you turn on** (2026-09-22). Since 2026-10-04 it has no off value
either (`taking-off-out-of-hover-cast.md`): the row holds *Skip this action*, *Cast on the unit you
point at* and *Cast on the usual target*. The page names all three because each answers a question
this page is opened with: how to make an action go to the pointed unit, what a new action does, and
how to keep one out while pointing. What they do beyond that stays with `cast-options.md`.

**That a pointed press tries the actions in the order on screen is not said.** It is what a reader
assumes without being told (the blank-agent reading in `taking-off-out-of-hover-cast.md` §1), and
since 2026-10-04 the key does exactly that.

**What the action does with the unit is not on this page.** A macro and a mount carry no unit at all
(`TYPES_WITH_UNIT`), and that Debind does not check whether a spell suits the unit is the last
paragraph but one of `targeting.md`.
-->

# What is Hover Cast?

<!--
**"lets you send", not "sends"**: a new action does not go to the pointed unit, and the opening
sentence must not promise that before the next one says how to set it.

**The picked-`Target` aside says where the action goes, never whether it runs.** A picked target does
not lock the row (`withPickedNote` in `ActionMenuItems.lua`), so *Skip this action* still keeps that
action out of a pointed press; "goes to that unit whether you point at something or not" would be
false.

**It names neither value** (review, 2026-10-10). "*Cast on the unit you point at* sends the action to
that unit instead" sent a cold reader's focus-picked heal to the party frame under the cursor, and
"sends it to the one picked there, not the one you point at" put a sentence against its own label.
-->



*Hover Cast* lets you send an action to the unit you point at instead of the usual target. You set it on each action: open *Cast Options* in its right-click menu, then *Hover Cast*, and pick *Cast on the unit you point at*. A new action starts on *Cast on the usual target*.

> With a unit picked under *Target*, the action goes to that unit even while you point at another.

<!--
**The frames are named the way `targeting.md` names them for the *Unit Frame* target**: the ones
Debind works on, the game's own and a unit frame addon's. Given as "the unit of the unit frame under
your cursor" and nothing more, the half a reader cannot work out is which frames those are, and
answering it on one page only leaves the other half-answered.

**The aside says every frame counts to begin with** (review, 2026-09-22). Naming the setting and
stopping there read as a step to carry out before the mode works, and the bullet above names a
subset without saying the subset starts as everything. The default is every box ticked
(`SettingsTab.lua`), and a frame taken out is never registered, so *Unit Frames* does not see it.

**It sits directly under the *Unit Frames* bullet, which is why that bullet comes second** (review,
2026-10-10). Under *Mouseover* the list does not narrow anything: that mode asks the game's
`mouseover`, not the frames Debind registers. Standing below the *Mouseover* bullet, the aside was read
as a rule for that mode.

**Mouseover is not explained** (2026-09-22, owner, `targeting.md`): every player knows it, and it is
the yardstick the other mode is read against, so it comes first.
-->

Which units count as pointed at is a mode:

- *Mouseover*: a unit frame, a nameplate, or the unit itself in the world.
- *Unit Frames*: the unit on a unit frame Debind works on, the game's own or a unit frame addon's. Away from one, nothing is pointed at.

> *Unit Frame Support* in Debind's settings lists the frames Debind works on. Every one counts until you untick it.

<!--
**The per-action mode row is the reason `cast-options.md` links here.** It is the same two values
plus `Use the mode in Debind's settings`, under a divider on the same submenu (`ActionMenuItems.lua`),
and an action that names one is not asking the settings tab any more (`HoverCastMode` in
`ActionBindings.lua`).

**Which of the two wins is said and not left to be inferred** (review, 2026-09-22). "One action can
use a mode of its own" was read as a second place to set the same thing rather than as one
overriding the other.

**The reader picks, not the action.** Written as "an action that picks one there uses it", the
sentence gave the action the choice and left the next "it" with nothing to stand on.

**The settings control is named** (review, 2026-10-10). "One mode on the settings tab" left a reader
who wanted nameplates to count hunting for which row that was. It is the *Hover Cast* dropdown
(`POINTED_UNIT_CAST` in `SettingsTab.lua`), the same name as the action's row.

**The account's starting mode is said** because the list above puts *Mouseover* first, where a reader
takes the first entry for the default. It is *Unit Frames* (`AccountHoverCastMode`).
-->

The *Hover Cast* row on Debind's settings tab sets the mode for the whole account, *Unit Frames* to begin with. The same two are also on an action's own *Hover Cast* row. Pick one there and that action uses it instead of the account's; until you do, the row is set to *Use the mode in Debind's settings*.

<!--
**Skip follows the mode too.** It stands the action on [the mode's unit is not there]
(`skipsPointedUnit` in `ActionBindings.lua`), so under *Unit Frames* a skipped action still runs over
a nameplate. The sentence leans on "point at" as the mode paragraph above defined it rather than
saying this again.

**"as if its conditions did not match", not "the next action runs"** (review, 2026-10-10). That is
what it is, a condition on the original, and it carries the rest a reader needs from a rule they
already know: the actions below are tried in order, one whose conditions fail is passed over, and
each goes where its own value sends it.

**The picked-`Target` case is said here, not in the aside under the opening** (review, 2026-10-10).
That aside says the picked unit wins over the pointed one, and a cold reader took it to win over
*Skip this action* too. Said there, it would name a value the page has not reached yet.
-->

To keep an action from running while you point at a unit, pick *Skip this action* on its *Hover Cast* row. The press then goes down the key's list as if that action's conditions did not match. This holds with a unit picked under *Target* as well.

The other rows of *Cast Options* are in [](cast-options.md). Which of a picked target, a held Self Cast Key or Focus Cast Key, and the unit you point at comes first is in [](targeting.md).
