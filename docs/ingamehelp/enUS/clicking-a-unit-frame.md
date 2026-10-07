<!--
**The rule is here and not in a warning** (2026-09-17, owner; the row is locked instead, 2026-09-18). Nothing stored reaches that key, so a warning would ask the reader to change values it ignores. `devdocs/which-action-a-key-runs.md` §7.

**Split out of `cast-options.md`** (2026-09-22, owner). Three paragraphs answering "why does my mouse button behave unlike my keyboard binds" were the longest stretch of a page about what the Cast Options rows do.
-->

# What happens when you click a unit frame?

<!--
**MISSING for the next release (2026-10-07, not yet written).** The two paragraphs below still hold. To add (`taking-off-out-of-hover-cast.md` §2-6, §2-8):
- An action on any other mouse button now runs on a unit frame click too, on its usual target. To leave that click to the frame, set its *Hover Cast* to *Skip this action*.
- On a unit frame click, a *Give Key Back* that runs sends the click to the frame; *Nothing* and *WoW Binding* stop it.
-->

An action on the left or right mouse button with no modifier runs only when you click a unit frame, so a click anywhere else still reaches the game. On a frame it goes to the unit you click, and nothing set under *Cast Options* is read.

The Self Cast Key and the Focus Cast Key are not used on a unit frame click. Holding one of them there is an ordinary modified click, which runs whatever you bound to that combination, under its own *Cast Options*.

What each row of *Cast Options* does is in [](cast-options.md).
