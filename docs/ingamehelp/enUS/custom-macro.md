<!--
**The page answers the edit box and nothing else** (2026-09-18, owner), which is the one thing its
(i) stands next to (`DebindMacroFrameMixin:OnHelpClick`). The name, the icon and the character
count are on that window too and are not body, so they stay out.

**Only the units a game macro lacks** (2026-09-17, owner: tank, healer, maintank, mainassist,
custom1, custom2, unitframe and @@).

**A unit nobody holds is named as "counts as not existing"** because that is what the body sees: an unset alias goes out as `raid41` (`COMPOSE_MACROTEXT_SNIPPET` in `SecureBindings.lua`). What to do about it is left to the reader: `exists` is the game's own rule and this page is not the place that teaches it (2026-09-18, owner).

**`@@` with nothing to aim at is named as the target** (2026-09-18, owner), which is what it bakes to (`devdocs/implementing-focus-and-self-cast.md` §4). It read "as if it were not written" while the value was a lone `@`.

**The empty part is written out because `@@` took the automatic self-cast with it** (2026-09-18, owner): the body now always names a unit, so a helpful spell with no target no longer falls back to the reader. `[@@,exists][]` is how they get that back, and it is the one thing the change costs them.

**The last sentence covers the switch name too** because it goes through the same parser, and a page about the body is not where `@@` in a switch expression belongs. The expression box says that itself (`CUSTOM_STATE_EDIT_VALUE_DESC`).

**Switches are here, and were once left to the switches' own text** (2026-09-18, owner). Nothing
else tells a reader in the edit box that `[$name]` is a thing the body can hold.

**The writing rule is one sentence** for the three ways a unit silently stays plain text: upper case, `target=`, and brackets that do not open a part of the line (`ParseMacroText` in `Misc.lua`). A switch name goes the same way through the same parser.

**`@@` carries suffixes like every other name** since 2026-09-18, so the sentence no longer carves it out. Only `target` and `pet` chains are suffixes (`UNIT_SUFFIXES`), which is why the line names those two.
-->

# Writing a Custom Macro

Anything a macro in the game's own list holds, and two things it cannot: the units below, and your switches.

These units can be aimed at. Write them like any other unit.

**/cast [@tank,exists] Rejuvenation; Regrowth**

- **@tank, @healer, @maintank, @mainassist.** The member of your group who holds that role, only while exactly one member holds it. Debind's settings can leave you out of each.
- **@custom1, @custom2.** The unit you pinned with *Set Custom Target*.
- **@unitframe.** The unit on the unit frame you press the key over.
- **@@.** The unit this press aims at: you while the Self Cast Key is held, your focus while the Focus Cast Key is held, and the unit you point at with *Hover Cast*. With none of these it is your target.

A unit nobody holds counts as not existing. Target and pet can follow any of these names, as in @tanktarget or @@target.

@@ always puts a unit in, so with nothing aimed at and no target the action goes nowhere. Write an empty part after it to send it where it would normally go.

**/cast [@@,exists][] Regrowth**

A switch is a condition of its own: [$fishing] while it is on, [no$fishing] while it is off. The name is the one it has under *Switches*.

Write units and switches in lower case, in the brackets that open each part of a line. Anywhere else they are left as plain text.
