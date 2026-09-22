<!--
**The page no control opens** (2026-09-22, owner). The other eight hang off a row, a menu entry or
an (i), which is why each answers that control's question. This one opens from the question mark
over the Overview tab, which asks nothing, so it may hold several small things and the title has to
say when to read it rather than which control it explains.

**That is also what lets it carry section headings.** `writing-a-help-page.md` says a page wanting
one holds two topics, and the reason behind that rule is what opened it: a page opened from a
control answers that control. Nothing here was asked, so the headings are what a reader scans
instead. **The parser already has them and nothing needed adding** (2026-09-22): the first `# ` in
the file is the page title and every later one is a heading block, drawn in
`GameFontHighlightMedium` (`DebindMessageFrame.lua`). The title itself is never drawn in the body,
so a heading competes with nothing.

**A new action lands in the open layer** (`AddNewAction` in `DebindUI.lua`), so the first section
names that before `Move to...`. Naming only the move reads as though making one somewhere else and
carrying it over were the only way in.

**Right-clicking a picker row is the third way in** (2026-09-22, owner), and it is the one nothing
on screen announces: the row looks like a button that does one thing. `Add to...` shows the same
destination list `Move to...` does (`SetupSpellPickerDropdownMenu`).

**The narrower tab is named as a class or a specialization, never as a character** (2026-09-22,
owner). Written as "one character or one specialization" the sentence reads as advice to work in
the character tabs, and the two tabs the reader wants are the class and the specialization ones.

**No line saying which tabs hold most keys** (2026-09-22, owner, dropped on review). Naming the
specialization tabs there costs the reader work later, since a key put in one has to be put in every
other specialization of that class, where the class tab holds it once with a narrower action over
it. It also pushed against the sentence above it, which is the rule that avoids exactly that.

**The word is layer** (2026-09-22, owner). The page said tab, and this window has three kinds: the
row at the top (*Overview*, *Switches*, *Storage*), the side row an action lives in, and the
picker's own. Only the middle one was meant. The side row carries no name of its own on screen, so
there is nothing to borrow, and `ordering.md` already says layer.

**It is stated rather than left to a spatial word** (review, 2026-09-22). "Put a narrower one over
it" was the only statement of the rule, and the recipe below uses above and below for position on a
key, so one spatial word carried two senses a page apart.

**The mount is that rule's example and sits in the same paragraph** (2026-09-22, owner). Standing on
its own it read as a rule about mounts and druids, and the paragraph on `Add an Action` had come
between the rule and the thing illustrating it. Declarative for the same reason: three imperatives
were three more instructions rather than one worked case.

**Not "the action above already took that case, so leave it off the one below"** (2026-09-22,
owner). It contradicts the sentence before it, which asks for the conditions each action needs, and
it is the half to drop: conditions trimmed against what stands above them have to be redone the
moment the order changes.

**The second heading is the rule itself** (review, 2026-09-22). `Conditions` repeated the submenu's
own name and `Two cases, two actions` leaned on a word nothing on screen gives the reader, so the
word case is off the page entirely.

**`Enemy` is ticked, not set** (2026-09-22). The reactions are boxes and there are three of them
(`REACTION_ITEMS`), so a value being set reads as a radio the reader will look for and not find.

**`Add to...` lists every layer, the open one included** (`AddDestinationTabs`), which is why the
sentence does not say another layer. That list is the same one move and copy show, deliberately.

**The reassurance closes the first section** (review, 2026-09-22). Reading as part of the layer rule
is what it is for: the anxiety it answers, that every layer has to be decided before anything works,
is the one the layer rule creates and nothing else on the page does. Standing at the end of the page
it read as being about the recipe, and standing before the first heading it spent the page's first
line on something that is not the answer to the title.

**The recipe names `Conditions` as well as `Resolved Unit`** (review, 2026-09-22). Headings invite a
reader to enter at the section matching what they want, and entering here they were told to tick a
box with no path to it.

**Selecting several is here and not left to the window** (2026-09-22, owner). Shift and control
clicking are the ordinary shortcuts, but nothing on screen says the right-click menu writes to the
whole selection or that `SetKeyForActions` takes a set, and that is what turns it from a shortcut
into the way this window is worked. **The shortcuts get one clause and the news gets the sentence**,
since the first half is what every list in the client already does.

**The heading names the key** (review, 2026-09-22). It has gone `Several actions at once`, which
collided with the page's other meaning of those words, then `Editing actions`, under which the step
the title promises could only be found by guessing. A reader scanning five headings for how to give
something a key now meets one that says so, and `and everything else` is what keeps the second
paragraph honest under it.

**The first step lives here** (2026-09-22, owner). Four rounds of review kept naming the same hole:
the page said how one key reaches many actions and never how a key reaches one. It is the same
right-click menu as everything else, which is why the section opens with the menu rather than with
`Assign a key`, and why selecting is the paragraph under it rather than a section of its own.

**The key group is the *Overview* tab's, and it crosses the layers** (2026-09-22, owner). Clicking
its heading selects what is under it (`KEY_HEADER_TOOLTIP_SELECT`), which is the way in to editing a
whole key at once. What that heading's own menu holds is left out: the reader has the actions
selected by then and the row menu is the one they want.

**The macro section carries the link** (review, 2026-09-22). Without it the section turned every
reader around, including the ones it had just told to go and write one.

**The macro section stands last, after the recipe has earned it** (2026-09-22, owner). Told first it
is a claim; told after a key that attacks and heals without one, it is a conclusion the reader has
just watched. It says what a macro is not needed for rather than what it is, because the page that
answers the second is the one a reader reaches once they want one.

**The talent condition is not on this page** (2026-09-22, owner). A talent condition passes in a
specialization it was not written for, as though the action carried none, which is the one thing
about it nothing on screen said. It was drafted here as a paragraph and went to
`CONDITION_TALENT_DESC` instead: the reader who needs it is standing in that menu picking a talent,
and a page about where actions go is not where they will look.

**The recipe names `Resolved Unit` on both actions** (review, 2026-09-22). It stood only in the
negative clause, on the action that does not carry it, so the condition doing the work was the one
left unnamed and a reader could put the hostile condition on some other unit. It also says the two
share a key, which only the heading said, and it sends them to the run order rather than restating
it.

**No macro beside it** (2026-09-22, owner). Showing the same thing as one macro line reads as
recommending a Custom Macro, and this page is for the people who do not need one.
-->

# How do I set my keys up?

# Where an action goes

Put an action in the layer that covers the most characters, and use a narrower layer only where a class or a specialization should run something else. A key in a narrower layer beats the same key in a broader one.

A mount every character uses sits in *Account* / *General*. Travel form sits in the druid layer, and a character who rides something else keeps that in its own.

Picking an entry in *Add an Action* puts the new action in the layer you have open, and right-clicking the entry instead offers *Add to...*, which lists every layer. *Move to...* in an action's right-click menu moves one you already have.

You do not have to bind everything at once.

# Assigning a key, and everything else

Right-clicking an action sets everything about it, its key included, in either list on the *Overview* tab. *Assign a key* is the item that gives it one.

Left-click picks an action, and shift-click or control-click picks more than one, after which the menu writes to all of them. The *Overview* tab also gathers each key's actions from every layer into one group, and clicking a key's heading picks everything under it, ready for that same menu.

# Conditions all have to be true

Give each action only the conditions it needs. Everything you pick under *Conditions* has to be true at once, so an action that should run in two different situations is two actions.

# One key for a friend and an enemy

Both actions go on the same key. Which one is reached first is in [](ordering.md). The harmful one goes above, carrying *Resolved Unit* under *Conditions* with *Enemy* ticked, and the helpful one below it with no *Resolved Unit* condition at all. The press then attacks an enemy and heals a friend. With nothing targeted the game places the cast, which is how Auto Self Cast puts a helpful spell on you.

# You may not need a Custom Macro

Conditions and a few actions on one key cover most of what a macro would, and the one above is an example. Writing one for what they leave out is in [](custom-macro.md).
