<!--
**Only the units a game macro lacks** (2026-09-17, owner: tank, healer, maintank, mainassist, custom1, custom2, unitframe and @@). Switches are left to the switches' own text.

**A unit nobody holds is named as "counts as not existing"** because that is what the body sees: an unset alias goes out as `raid41` (`COMPOSE_MACROTEXT_SNIPPET` in `SecureBindings.lua`), so `exists` is the way to fall through.

**`@@` with nothing to aim at is "as if not written"**: it goes out as a lone `@`, which the client ignores (`devdocs/implementing-focus-and-self-cast.md` §2-3).

**The writing rule is one sentence** for the three ways a unit silently stays plain text: upper case, `target=`, and brackets that do not open a part of the line (`ParseMacroText` in `Misc.lua`).
-->

# Which extra units can a Custom Macro aim at?

A *Custom Macro* can aim at these units, which a macro in the game's own list cannot. Write them like any other unit, as in /cast [@tank,exists] Rejuvenation; Regrowth.

- **@tank, @healer, @maintank, @mainassist.** The member of your group who holds that role, only while exactly one member holds it. Debind's settings can leave you out of each.
- **@custom1, @custom2.** The unit you pinned with *Set Custom Target*.
- **@unitframe.** The unit on the unit frame you press the key over.
- **@@.** The unit this press aims at: you while the Self Cast Key is held, your focus while the Focus Cast Key is held, and the unit you point at with *Hover Cast*. With none of these it is as if it were not written.

A unit nobody holds counts as not existing, so add exists to go on to the next part of the line. Target and pet can follow a name, as in @tanktarget, except after @@.

Write them in lower case, with @, in the brackets that open each part of a line. Anywhere else they are left as plain text.
