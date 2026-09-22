<!--
**The page answers the edit box and nothing else** (2026-09-18, owner), which is the one thing its
(i) stands next to (`DebindMacroFrameMixin:OnHelpClick`). The name, the icon and the character
count are on that window too and are not body, so they stay out.

**Only the units a game macro lacks** (2026-09-17, owner: tank, healer, maintank, mainassist,
custom1, custom2, unitframe and @@).

**The opening example falls back rather than only aiming** (2026-09-22, owner). Naming a unit is the
lesser half of what these names are for; the half worth showing first is what happens when nobody
holds the name, which is also what the paragraph on `@@` comes back to. `exists` is not spare beside
`nodead`: `dead` is false of a unit that is not there, so `nodead` alone lets the first part through
with no healer in the group.

**Not `[@@]` as the second part** (2026-09-22). It always puts a unit in, so with nothing aimed at
and no target that part goes through and casts at a unit that is not there, which is the one shape
this page tells the reader to avoid. `[]` hands the placement to the game and gets automatic self
cast with it.

**The example no longer matches `TYPE_MACROTEXT_DESC`'s**, which is a picker tooltip. Nothing can
drift, since neither is a claim about behaviour.

**A unit nobody holds is named as "counts as not existing"** because that is what the body sees: an unset alias goes out as `raid41` (`COMPOSE_MACROTEXT_SNIPPET` in `SecureBindings.lua`). What to do about it is left to the reader: `exists` is the game's own rule and this page is not the place that teaches it (2026-09-18, owner).

**`@@` with nothing to aim at is named as the target** (2026-09-18, owner), which is what it bakes to (`implementing-focus-and-self-cast.md` §4). It read "as if it were not written" while the value was a lone `@`.

**The empty part is written out because `@@` took the automatic self-cast with it** (2026-09-18, owner): the body now always names a unit, so a helpful spell with no target no longer falls back to the reader. `[@@,exists][]` is how they get that back, and it is the one thing the change costs them.

**The last sentence covers the switch name too** because it goes through the same parser, and a page about the body is not where `@@` in a switch expression belongs. The expression box says that itself (`CUSTOM_STATE_EDIT_VALUE_DESC`).

**Switches are here, and were once left to the switches' own text** (2026-09-18, owner). Nothing
else tells a reader in the edit box that `[$name]` is a thing the body can hold.

**The writing rule is one sentence** for the three ways a unit silently stays plain text: upper case, `target=`, and brackets that do not open a part of the line (`ParseMacroText` in `Misc.lua`). A switch name goes the same way through the same parser.

**`target=` is named in the body, not only here** (2026-09-22). The sentence carried two of the three and this comment claimed all three, so the one a reader is most likely to write was the one nowhere on the page: `parseOptions` reads an option only where it opens with `@`, and `[target=tank]` never reaches `SPECIAL_UNITS`. `[target=focus]` is the commoner spelling in the game's own macros, so this is the form they arrive with.

**It is shown as a pair rather than named in prose** (review, 2026-09-22). Stated as a clause inside the rule, it arrived last and negated and a reader did not recognise their own line in it. The page shows no other wrong form, and this is the one where a wrong line beside the right one earns its place.

**`@` belongs to the units and `$` to the Switches** (review, 2026-09-22). One sentence covering both put both behind `@`, so a reader looking for where the `@` goes in `[$fishing]` found nothing. **Lower case does cover both**: `CreateSwitch` folds the stored name and `ParseMacroText` does not fold what it reads, so `[$Fishing]` finds no definition (`Profile.lua`, and the comment there on why only the doors fold).

**The opening says `@` too, because the closing rule is a reminder and not the first news of it** (review, 2026-09-22). It read "Write them like any other unit", which the last paragraph then contradicts, since `target=` is one of the ordinary ways to write any other unit.

**It says "a unit" and not "them"** (review, 2026-09-22). The sentence before it names the units and the Switches, so "them" pointed `@` at a Switch name, which is what the closing rule had just been fixed to stop saying.

**"Put a conditional on that part", never "test that part"** (review, 2026-09-22). In English that reads first as trying it out and seeing, which is not what the reader has to do.

**"A Switch works as a conditional too"** (review, 2026-09-22). Written "is a conditional of its own", it reads as a bracket group of its own, which is the wrong idea the page has no room to show an example against.

**The `@@` fallback needs a test and not only an empty part** (review, 2026-09-22). `[@@]` on its own always matches, so the cast goes to a unit that is not there and no later part is reached. The example beside it has always carried the test; the sentence did not.

**The frames are named the way the two hover pages name them** (2026-09-22). Given as the frame you press the key over, it was a third wording for one thing, and somebody who took their unit frame addon out under *Unit Frame Support* had nowhere to find out why the name answers nothing.

**`@@` carries suffixes like every other name** since 2026-09-18, so the sentence no longer carves it out. Only `target` and `pet` chains are suffixes (`UNIT_SUFFIXES`), which is why the line names those two.
-->

# Writing a Custom Macro

Anything a macro in the game's own list holds, and two things it cannot: the units below, and your Switches.

Write a unit after @, where you would name any other unit.

**/cast [@healer,exists,nodead][] Innervate**

- **@tank, @healer, @maintank, @mainassist.** The member of your group who holds that role, only while exactly one member holds it. Debind's settings can leave you out of each.
- **@custom1, @custom2.** The unit you set with *Set Custom Target*.
- **@unitframe.** The unit on a unit frame Debind works on that your cursor is over as you press the key.
- **@@.** The unit this press aims at: you while the Self Cast Key is held, your focus while the Focus Cast Key is held, and the unit you point at with *Hover Cast*. With none of these it is your target.

A name with nobody behind it is a unit that does not exist, so exists is false for it. Target and pet can follow any of these names, as in **@tanktarget** or **@@target**.

@@ always puts a unit in, so with nothing aimed at and no target nothing happens. Put a conditional on that part and an empty part after it, and the cast goes where it normally would.

**/cast [@@,help][] Regrowth**

A Switch works as a conditional too: **[$fishing]** while it is on, **[no$fishing]** while it is off. Use the name from *Switches*.

Write these names in lower case and inside the brackets that open a part of a line, a unit straight after @ and a Switch straight after $. Written any other way they are left as plain text. Write **[@tank]** and not **[target=tank]**.
