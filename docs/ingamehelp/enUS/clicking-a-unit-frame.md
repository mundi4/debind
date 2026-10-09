<!--
**The rule is here and not in a warning** (2026-09-17, owner; the row is locked instead, 2026-09-18). Nothing stored reaches that key, so a warning would ask the reader to change values it ignores. `devdocs/which-action-a-key-runs.md` §7.

**Split out of `cast-options.md`** (2026-09-22, owner). Three paragraphs answering "why does my mouse button behave unlike my keyboard binds" were the longest stretch of a page about what the Cast Options rows do.
-->

# What happens when you click a unit frame?

<!--
**Every other mouse button stands on a unit frame click too** (2026-10-04, owner; `which-action-a-key-runs.md` §7). The hidden [no unit frame] those keys used to carry is gone, so a click on a frame tries the same actions in the same order as a click anywhere else, and each goes where its *Hover Cast* value sends it. *Skip this action* is named as the way to leave the click to the frame because that is what a reader who lost a frame's own click is looking for; **it says "if nothing else on the key runs there"** (review, 2026-10-10), since it takes out one action and another on the same button still wins the click. **The default is named** (review, 2026-10-10): a click-casting player takes the clicked unit for granted, and a new action sends it to the usual target.

**The held-key paragraph names the rows, not where the cast lands** (review, 2026-10-10). What §7 settles is that no self or focus twin takes part in a frame click. Whether the game itself reads a held key when it places a cast on the usual target was not looked at, so "does not send the action to you" was a promise nobody had checked, and a cold reader found it at odds with "as from an action bar".

**What a winning *Give Key Back*, *Nothing* or *WoW Binding* does there is said** (2026-10-04, 2026-10-05, owner; §7). On a frame there is no game binding to hand the click to, so *Give Key Back* lets it through to the frame, and the other two stop it rather than let the frame run something the reader never picked.
-->

An action on the left or right mouse button with no modifier runs only when you click a unit frame, so a click anywhere else still reaches the game. On a frame it goes to the unit you click, and nothing set under *Cast Options* is read.

An action on any other mouse button, or on a left or right click with a modifier, runs on a unit frame click as well as anywhere else. On a frame it goes where its *Hover Cast* row sends it: on *Cast on the usual target* (the default), to the usual target, as from an action bar; on *Cast on the unit you point at*, to the unit you click. *Skip this action* keeps it out of a frame click, and if nothing else on the key runs there, the click goes to the frame.

If the action that runs on a unit frame click is *Give Key Back*, the click goes to the frame. With *Nothing* or *WoW Binding*, nothing happens: *WoW Binding*'s command does not run and the frame gets no click. If no action runs, the click goes to the frame.

The *Self Cast Key* and *Focus Cast Key* rows are not read on a unit frame click. Holding either key there makes an ordinary modified click, which runs whatever you bound to that combination, under that action's own *Cast Options*.

What each row of *Cast Options* does is in [](cast-options.md).
