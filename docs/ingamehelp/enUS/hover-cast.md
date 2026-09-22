<!--
**The page the settings tab sends a reader to.** That row sets one thing, which units count as
pointed at, and a reader meeting the name there needs to know what it is before the two modes mean
anything. The explanation used to be the row's own tooltip and outgrew it.

**What it does not carry**: the three Cast Options rows and their values. That is `cast-options.md`,
and saying it twice is saying it two ways by next month.

**Not yet fixed, raised 2026-09-22 and left for a pass of its own.** Every one of these is in text
older than that day.

- The opening puts the picked-`Target` clause inside the "point at nothing" sentence, which says a
  picked target holds only while nothing is pointed at. It holds on every press that runs the
  action, and `cast-options.md` already says so.
- This page calls Hover Cast a thing you turn on, while `cast-options.md` has it as three settings
  in which `Cast on the usual target` is neither on nor off. A reader arriving from here has to
  unlearn the binary.
- `cast-options.md` sends the reader here for the mode row under the three Hover Cast settings, and
  this page documents only the two account modes. `Use the mode in Debind's settings` is never
  named, and neither is what picking a mode for one action does against the account one.
- The bold on "It is off on each action until you turn it on" is neither a list lead-in nor an
  example line, which are the only two things `**` means (`writing-a-help-page.md`).
- "what the action can do with it is the action's own business" and "Debind does not ask whether the
  spell is friendly or harmful" are the anthropomorphism `writing-user-facing-text.md` rules out.
  "an attack aimed at a party member goes nowhere" invents an outcome where the client's own word is
  that the spell does not cast.
- "It is used as it is, too" says what the sentence after it already says.
- The *Unit Frames* mode is given as "the unit of the unit frame under your cursor" and stops there.
  Which frames those are is the half a reader cannot work out, and `targeting.md` now carries it for
  the *Unit Frame* target: the frames Debind works on, the game's own and a unit frame addon's, with
  the settings deciding which of the game's own count. The same holds for this mode, and saying it
  in one place only leaves the other half-answered.
-->

# What is Hover Cast?

While you point at a unit, a key sends its action to that unit instead of where it would normally go. Point at nothing and the action goes where it normally would, and an action with a target picked under *Target* keeps going there.

**It is off on each action until you turn it on**, in the action's right-click menu under *Cast Options*. You can turn it on for several actions at once. The same menu lets one action use a mode of its own.

Which units count as pointed at is the mode in Debind's settings:

- *Unit Frames*, the unit of the unit frame under your cursor. Away from a unit frame nothing is pointed at.
- *Mouseover*, a unit frame, a nameplate, or the unit itself in the world.

The unit is handed to the action, and what the action can do with it is the action's own business: a macro or a mount takes no unit and runs the way it always does. It is used as it is, too. Debind does not ask whether the spell is friendly or harmful, so an attack aimed at a party member goes nowhere. Put a condition on the action when that matters.

To keep an action from running at all while you point at a unit, put a condition on that unit: under *Units*, pick *Unit Frames* (or *Mouseover*) and choose *When the unit doesn't exist*. Turning *Hover Cast* off does not do this, since the action still runs with the target it would have anyway.

What each row of *Cast Options* does is in [](cast-options.md). Which of a picked target, a held key and a pointed unit comes first is in [](targeting.md).