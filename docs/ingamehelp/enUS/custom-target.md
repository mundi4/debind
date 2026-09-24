<!--
**Why this page exists.** Nothing on screen says what the two slots hold or how they are filled, and the
one thing that does, the tooltip on the picker row (`TYPE_SETCUSTOM_DESC`), is only read by someone who
already found the row.

**The title asks what one is, and not how to set one** (2026-09-22, owner). Setting it is the first
paragraph and using it is the second, and a title naming only the first contradicted the page and
told the reader there was a second page for the rest. This is also the shape the pages beside it
take, and the title stands in four places, so the four read alike.

**Written as what the reader does.** Labels are named where they have to go: the picker's Special tab,
the action's Target menu, the two slot names under Units.

**The unit list is the one from `CUSTOM_TARGET_UNSUPPORTED_UNIT`**, which is the line the reader gets
when a press is refused, so the two say the same thing. What decides it is
`CUSTOM_TARGET_VALID_UNIT_TOKENS` in `Constants.lua`.

**The frame rule and the unit rule are separate because they fail apart.** A key press out of combat
reaches any unit frame through `mouseover` (`_onattributechanged` in `UnitWatch.lua`); the unit behind
it still has to be one of those six.

**Combat is the only axis the page splits on.** Which press reaches us over an unwired frame is the
bare left and right click's own rule, which holds no key (`IsBareWorldClick` in `ActionBindings.lua`,
`which-action-a-key-runs.md` §7) and is the same for every action, so saying it here would teach it
twice. The CHANGELOG for 3.6 names the keyboard and the mouse button, which is that rule under the
names of its two usual cases.

**The combat line is not the same rule said twice.** Out of combat `ResolveUnitToken` turns the frame's
own `unit` into a stable token, and in combat it returns at the lockdown check, so what the frame
carries has to be one of the six already. **Written as the frames that do work**, in the wording of the
line the reader gets when one does not (`CUSTOM_TARGET_UNSUPPORTED_UNIT_IN_COMBAT`). Naming the ones
that fail would be naming a few of them: a target frame, its own target frame, a nameplate, a group
member's pet frame and whatever else carries a token outside that table.

**The group slot case is here rather than left to its chat line** (`CUSTOM_TARGET_SET_VOLATILE`,
`CUSTOM_TARGET_INVALIDATED`). A target that clears itself later is the one surprise the reader cannot
work out from the screen.

**The ordinary case is stated with no timing on it** (review, 2026-09-22). Written as "set it before
the pull, or during a fight before your group changes", it put the exception's own conditions on the
rule, so the paragraph after it read as the same warning twice and a custom target read as
conditional in general. It also ended "stays on them through the fight", which promises less than
the code does: a name-tracked one survives the fight and the logout.

**And with no "until you set it on somebody else"** (review, 2026-09-22). That is an absolute the
first paragraph already qualifies, since a press over nothing clears it.

**The exception names the kind it applies to** (review, 2026-09-22). Opening "The exception is one
you set ...", it stood against the boss and arena sentence, which is the nearest thing an exception
could attach to and the one kind it is not about.

**The chat line for the clearing is not on the page.** `CUSTOM_TARGET_INVALIDATED` says what
happened and what to do next, so a reader who sees it needs nothing from here.

**"the way you keep your focus", not "set"** (review, 2026-09-22). A focus is set on the unit you
have targeted, and the clause right after this one says a custom target is set over a frame, so the
comparison was wrong about the one thing the sentence beside it explains. What carries over is
keeping a unit, not how it is filled.

**What makes a pin hold the spot is `grouproster_uptodate` and nothing else.** `UpdateGroupRoster`
leaves at the lockdown check, so the flag goes false at the first roster change of a fight and the
pins made from then on have no name behind them. That is why the page can say the fight ends it:
`PLAYER_REGEN_ENABLED` runs the roster again, and `OnGroupRosterChanged(true)` writes the name back
onto the ones still standing.
-->

# What is a Custom Target?

Two extra targets you keep the way you keep your focus. Put *Set Custom Target 1* or *Set Custom Target 2* on a key, from the *Special* tab of *Add an Action*, then press that key with your cursor over a unit frame. Press it with your cursor over nothing to clear it.

Then use one like any other unit: pick *Custom Target 1* or *Custom Target 2* in an action's *Target* menu, ask about it under *Units*, or write **@custom1** or **@custom2** in a *Custom Macro*, as in [](custom-macro.md).

You can set yourself, your pet, somebody in your party or raid, an encounter boss, or an arena opponent. On anything else the press does nothing and a line in chat says why. Each character has its own two, and they are still there at the next login.

Out of combat this works over any unit frame. In combat it works over the Player, Pet, Party, Raid, Boss and Arena frames Debind works on.

A custom target on somebody in your party or raid follows that person, even when the group changes. A boss or an arena opponent is the position rather than the person, so next time it is whoever stands there.

The exception is a party or raid custom target you set during a fight your group has already changed in. That one clears if the group changes again before the fight ends, and the line you get when you set it says so.