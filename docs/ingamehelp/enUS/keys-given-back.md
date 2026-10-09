<!--
**Why this page exists** (2026-10-07, owner). A key is given back four ways now, and the answers were spread over an aside in `ordering.md`, the rows of the settings section and an action's tooltip. Which action runs and when Debind stops holding a key are two questions, and this is the second.

**What receives the key is never named as one thing** (owner). Debind only clears its own binding; what runs then can be WoW's own keybindings, another addon, or nothing. The verb is "give back" throughout, the same as the settings section.
-->

# When is a key given back?

A key given back works as if Debind had nothing on it: whatever else is bound to it runs, from WoW's own keybindings or another addon, and nothing if nothing is.

<!--
**Item 3 says the setting does not reach it** (review, 2026-10-07). No action runs there either, so without it a reader who chose *Press Does Nothing* expects those keys to do nothing too.

**Item 4's lead-in names the situations** (2026-10-07, owner). "While the game uses the keys for itself" said nothing, since the game has a use for almost every key. A replaced bar is explained in the item because the term is ours; the bar types (override, vehicle) were too hard for the settings tooltip (`0-DIARY.md`, 2026-10-07), and forms, stealth and skyriding are the cases a reader wrongly counts in, in the words of `GIVE_BACK_REPLACED_BAR_DESC`. Which keys each situation covers is left to the rows' tooltips.

**The bar is "a replaced action bar" in plain words, and *Replaced Action Bar* only where the value is picked** (review, 2026-10-10). One name for it (2026-10-08, owner) is kept; blue on the bar itself read as a control standing in for the game's bar.

**Item 4 says which row sets which situation, and what is on to begin with.** Without it the item reads as all three happening on their own, and a replaced bar is off until picked (`GiveBackOnReplacedBar`). **Both values that cover a replaced bar are named** (review, 2026-10-10): "once you pick it" sent a reader to *Replaced Action Bar* alone, which turns pet battles off without a word.

**Give Key Back is in the body, not the lead-in**, because a lead-in cannot hold a blue name (`writing-a-help-page.md`).
-->

1. **At a press where none of its actions runs.** No action's conditions are met, or none is set to run on that kind of press. *When no action runs* under *Keys Given Back* in Debind's settings sets this, and starts on *Key Is Given Back*; set it to *Press Does Nothing* and those presses do nothing instead.
2. **When an action set to give the key back runs.** *Give Key Back* stands on the key like any other action and runs when its conditions are met and nothing above it ran. No action under it is tried.
3. **When nothing on the key is in play.** Each action is either turned off or in a specialization tab you are not in. This happens whatever *When no action runs* is set to, and the key's header is grey in the *Overview* tab.
4. **During a pet battle, on a replaced action bar, or in the House Editor.** A replaced action bar is the one you get when a vehicle, a possession or a quest replaces your whole action bar; forms, stealth and skyriding do not count. Under *Keys Given Back* in Debind's settings, *Action Button keys* sets the first two: a pet battle to begin with, and a replaced action bar once you pick *Replaced Action Bar* or *Replaced Action Bar and Pet Battles*. *House Editor keys* sets the third, and is ticked to begin with.

<!--
**The press-and-release trap is written here, with nothing on screen to warn of it** (2026-10-07, owner). Adding a Give Key Back or WoW Binding action shows a notice; the default give-back shows none. WoW Binding is left out of this paragraph (owner): this page is about giving keys back. The stuck direction is a key given back at the press and taken again before the release. Nothing says how to get out of it, because no way out has been seen in the game.

**The lead-in is the symptom** (review, 2026-10-07). The reader who meets this did not know a movement or ping keybinding was on the key, and arrives with nothing but "I keep moving"; a skimmer reads only the bold.

**A recommendation, not an order, and the way to do it is the next paragraph** (owner). Nobody puts Debind actions on a key they move with, so the reader here does not use that keybinding on the key, and Nothing is the right fix for them. It sits right before the Nothing paragraph so the two read as why and how without the method written twice.
-->

**If you keep moving after releasing a key, or the ping wheel stays open.** Some WoW keybindings do one thing when the key is pressed and another when it is released. If a key given back is still held when Debind takes it again, the release never reaches that keybinding. That is what keeps you moving or leaves the ping wheel open. For keys bound to these, it is safer not to let them be given back.

<!--
**Very Low, not only "no conditions"** (2026-10-07, owner). A Nothing at Normal stands above any Low action on the key and stops it, so the conditions rule alone does not put it last. It also spares unbinding the key in WoW for a reader who does not use that keybinding on it.
-->

If one key should do nothing when none of its actions runs, while your other keys are given back, add a *Nothing* action to that key, with no conditions, and set its *Importance* to *Very Low*. You find it in the *Special* tab of *Add an Action*. Check that it is the last action under the key in the *Overview* tab, so it runs only when none of the others does.

A click on a unit frame where no action runs goes to the frame.
