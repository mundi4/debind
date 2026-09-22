<!--
**The page the settings tab sends a reader to.** That row sets one thing, which units count as
pointed at, and a reader meeting the name there needs to know what it is before the two modes mean
anything. The explanation used to be the row's own tooltip and outgrew it.

**What it does not carry**: the three Cast Options rows and their values. That is `cast-options.md`,
and saying it twice is saying it two ways by next month.

**Hover Cast is never something you turn on** (2026-09-22). The row holds three values and `Cast on
the usual target` is neither on nor off, so a reader arriving here from `cast-options.md` would have
to unlearn a binary this page had invented.

**The opening names `Cast on the unit you point at` because nothing else on the page can** (review,
2026-09-22). Taking the binary out left no value named but `Off`, and a reader who went looking for
the switch had the two modes to pick from and picked one of those. The third value stays with
`cast-options.md`; this one is what the page is about.

**The picked-`Target` clause is its own aside.** It used to sit inside the "point at nothing"
sentence, which said a picked target holds only while nothing is pointed at; it holds on every press
that runs the action (`which-action-a-key-runs.md` §5, `TARGET_UNIT_FIXED`).
-->

# What is Hover Cast?

*Hover Cast* sends an action to the unit you point at instead of the usual target. You set it on each action: open *Cast Options* in its right-click menu, then *Hover Cast*, and pick *Cast on the unit you point at*. A new action is set to *Off*.

> An action with a unit picked under *Target* goes to that unit whether you point at something or not.

<!--
**The frames are named the way `targeting.md` names them for the *Unit Frame* target**: the ones
Debind works on, the game's own and a unit frame addon's. Given as "the unit of the unit frame under
your cursor" and nothing more, the half a reader cannot work out is which frames those are, and
answering it on one page only leaves the other half-answered.

**The aside says every frame counts to begin with** (review, 2026-09-22). Naming the setting and
stopping there read as a step to carry out before the mode works, in the same shape as the settings
tab sentence below, and the bullet above names a subset without saying the subset starts as
everything. The default is every box ticked (`SettingsTab.lua`), and a frame taken out is never
registered, so *Unit Frames* does not see it.

**It stays under the bullet it qualifies**, although it splits the two mode paragraphs (review,
2026-09-22, dropped). Which frames the first bullet means is what it answers.

**Mouseover is not explained** (2026-09-22, owner, `targeting.md`): every player knows it, and it is
the yardstick the other mode is read against.
-->

Which units count as pointed at is a mode:

- *Unit Frames*, the unit on a unit frame Debind works on, the game's own or a unit frame addon's. Away from one, nothing is pointed at.
- *Mouseover*, a unit frame, a nameplate, or the unit itself in the world.

> *Unit Frame Support* in Debind's settings lists the frames Debind works on. Every one counts until you take it out.

<!--
**The per-action mode row is the reason `cast-options.md` links here** and this page left it out
until 2026-09-22. It is the same two values plus `Use the mode in Debind's settings`, under a
divider on the same submenu (`ActionMenuItems.lua`), and an action that names one is not asking the
settings tab any more (`HoverCastMode` in `Misc.lua`).

**Which of the two wins is said and not left to be inferred** (review, 2026-09-22). "One action can
use a mode of its own" was read as a second place to set the same thing rather than as one
overriding the other.

**The reader picks, not the action.** Written as "an action that picks one there uses it", the
sentence gave the action the choice and left the next "it" with nothing to stand on.
-->

One mode on the settings tab covers the whole account. The same two are also on an action's own *Hover Cast* row. Pick one there and that action uses it instead of the account's; until you do, the row is set to *Use the mode in Debind's settings*.

<!--
**The menu entry is *Unit Frame*, singular** (`UNIT_HOVER`). The plural is the settings tab's mode
name, and this paragraph used it for the menu entry until 2026-09-22.

**What the action does with the unit is not on this page.** A macro and a mount carry no unit at all
(`TYPES_WITH_UNIT`), and that Debind does not check whether a spell suits the unit is the last
paragraph but one of `targeting.md`. The sentences that stood here said it a second way and invented
an outcome for the spell that does not cast.
-->

*Off* does not keep an action from running while you point at a unit: it runs with the target it would have anyway. To stop it there, put a condition on the unit you point at. Under *Units*, pick *Unit Frame* (or *Mouseover*) and choose *When the unit doesn't exist*.

The other rows of *Cast Options* are in [](cast-options.md). Which of a picked target, a held key and the unit you point at comes first is in [](targeting.md).
