<!--
**The page the settings tab sends a reader to.** That row sets one thing, which units count as
pointed at, and a reader meeting the name there needs to know what it is before the two modes mean
anything. The explanation used to be the row's own tooltip and outgrew it.

**What it does not carry**: the three Cast Options rows and their values. That is `cast-options.md`,
and saying it twice is saying it two ways by next month.
-->

# What is Hover Cast?

While you point at a unit, a key sends its action to that unit instead of where it would normally go. Point at nothing and the action goes where it normally would, and an action with a target picked under *Target* keeps going there.

**It is off on each action until you turn it on**, in the action's right-click menu under *Cast Options*. You can turn it on for several actions at once. The same menu lets one action use a mode of its own.

Which units count as pointed at is the mode in Debind's settings:

- *Unit Frames*, the unit of the unit frame under your cursor. Away from a unit frame nothing is pointed at.
- *Mouseover*, a unit frame, a nameplate, or the unit itself in the world.

The unit is handed to the action, and what the action can do with it is the action's own business: a macro or a mount takes no unit and runs the way it always does. It is used as it is, too. Debind does not ask whether the spell is friendly or harmful, so an attack aimed at a party member goes nowhere. Put a condition on the action when that matters.

What each row of *Cast Options* does, and how to keep an action from running while you point at a unit, is in [](cast-options.md). Which of a picked target, a held key and a pointed unit comes first is in [](targeting.md).
