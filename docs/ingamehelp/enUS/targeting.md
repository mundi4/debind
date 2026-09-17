<!--
**Why this page exists at all.** Whether the game's own redirection applies to a Debind key turns on one thing, did the reader choose a target, and nothing on screen says so. The people who built it spent a day getting it wrong from the code, so a reader has no chance.

**Written as what the reader did**, never as what the addon stores. Labels are named where the reader has to go: the Target menu, Units, Resolved Unit, Hover Cast and Cast Options. Renaming any of them moves this text with it.

**The title does not open with `Where`.** It is also a button on the settings tab, which is global, and there "where is an action" reads as which tab it is in. Asking for the unit leaves one reading.

**Only the answer stays here** (2026-09-17, owner: a help page answers at once). What each row under Cast Options does is `cast-options.md`, and a picked Unit Frame or Mouseover is `picking-a-pointed-unit.md`.
-->

# Which unit is an action used on?

<!--
**The order comes first, as one list.** The client's own order is named after it because a reader who knows the game expects the cursor to win over a held key (2026-09-15, owner).

**Auto Self Cast is named once, on the step it belongs to.** A held key or a picked target goes out with it off (`SELFCAST_OFF_SNIPPET` in `SecureBindings.lua`), and a reader expects it to bring a friendly spell back to them. What the game does after that is not ours to say (owner).

**Mouseover Cast is named even though the answer is "no".** It is on the same client panel as the two keys, so a reader who has it on and is not told otherwise concludes the key is broken.
-->

Where an action goes is settled in this order, and the first that applies decides:

1. **The target you picked** under *Target*. Nothing you hold or point at moves it. If it is *Unit Frame* or *Mouseover*, read [](picking-a-pointed-unit.md).
2. **The key you hold.** The Self Cast Key sends the action to you and the Focus Cast Key to your focus. With no focus set, the press does nothing. A key turned off in Debind's settings counts as not held.
3. **The unit you point at.** Which units count is the *Hover Cast* mode in Debind's settings. The game's own Mouseover Cast does not apply to Debind keys.
4. **None of these.** The game places the cast as it does on an action bar. This is the only case Auto Self Cast applies.

The game's own settings look at the unit under your cursor before the key you hold. Debind does it the other way round.

The *Resolved Unit* condition under *Units* asks about the unit this order arrives at. Debind does not check whether a spell suits that unit, so when it matters, put a condition there.

How each action answers a held key or a pointed unit is set under *Cast Options* in its right-click menu, explained in [](cast-options.md).
