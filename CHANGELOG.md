# 4.2

**On World of Warcraft: Forever, a party member set as a custom target now takes.** Until now chat said it was set, but it was not.

**On World of Warcraft: Forever, Dispel is now two actions.** A Dispel action now shows as Dispel: Curse, Disease, and Dispel: Magic, Poison is new. Both work on a Druid, Priest, Shaman or Paladin; a Mage has only Dispel: Curse, Disease. Where a class has two spells for one dispel, the higher-level one is cast once you know it.

**A key where no action runs can go back to WoW, if you want it to.** Set When no action runs under Keys Given Back in Debind's settings to Key is given back, and the key then does what WoW or another addon has on it, as it did before 4.0. It starts on Press does nothing, which is what every key has done since 4.0.

**Keys given back can follow a change sooner.** A key that is given back, or runs a WoW Binding, only in some situations can still do what it did before a change for up to 0.2 seconds after it. This can happen with When no action runs set to Key is given back, or on a key with a Give Key Back or WoW Binding action. Lowering State Driver Interval, under Miscellaneous in Debind's settings, shortens that delay, down to one frame at 0. The value belongs to Blizzard's state driver, which other addons use too, so a lower value makes theirs update more often as well and costs more CPU. With no such key, the slider changes nothing.

**Hover Cast has no Off, and a press while you point at a unit follows the order on screen.** It tries a key's actions in the order the Overview tab shows. An action that was on Off is now on Cast on the usual target, so one standing above an action set to Cast on the unit you point at now takes that press; set it to Skip this action to pass it on. One that was on Off with Normal Cast unticked is now on Skip this action. As set it never runs, so it is marked Needs checking.

**Mouse buttons other than left and right click run on unit frames.** An action on one of them now runs when you click a unit frame with that button, and goes where its Hover Cast row sends it. To leave that click to the frame as before, set it to Skip this action.

**During a pet battle, an Action Button action does what WoW's own keybinding for that button does.** Action Button 1 to 5 press the battle's buttons, and 6 to 12 do nothing. Until now it pressed that slot of your main action bar.

**An Action Button action whose slot holds a flyout opens it at the cursor**, as a Flyout action does. It used to open on that slot's button on WoW's action bar, so with a bar addon that hides WoW's bars it showed nothing and left that addon's button raising an error.

**Two new actions: Give Key Back and WoW Binding.** Give Key Back, in the Special tab of Add an action, gives the key back when it runs. WoW Binding, in the WoW Bindings tab, runs one of WoW's own keybindings. A Use WoW's Own Binding or Binding Command left over from before 4.0 is now a Nothing action, which is what it has done since 4.0.

**The Commands tab of Add an action is now WoW Bindings**, and holds only WoW's own keybindings. Targeting, focus, the unit menu, world markers and the Action Button rows moved to the Special tab.

**A share code made by 4.2 cannot be pasted into 4.1.2 or earlier**, which answer that it was made by a newer version of Debind. Share codes made by earlier versions still paste into 4.2.

# 4.1.2

**On World of Warcraft: Forever, spells you have not learned yet can be given a key now.** Talking to a class trainer adds the spells that trainer can teach to an Unlearned group in the spell list. With Unavailable checked in the trainer window's filters, the spells you cannot learn yet are added as well. The group's tooltip says the same.

# 4.1.1

**Entering an arena with Clique or another click casting addon installed no longer raises a Lua error from Debind.**

# 4.1

**Debind now runs on World of Warcraft: Forever as well as the current game.** Some of it has not been tried there yet. The Dispel, Raid Buff and Resurrect actions, which cast whichever spell your class has rather than one you picked, may not work as they should. Dual specialization is not handled, because the author's characters are still too low level to reach it.

**Your bindings from the current game can come along.** A share code made in the current game can be pasted on Forever, through New Payload and From Share Code in the Storage tab. Many of the spells and items in it do not exist on Forever.

**Clique bindings can be brought in.** New Payload in the Storage tab takes a Clique share code under From Share Code, and From Clique... reads the profiles of the Clique you have installed. Either way Add to My Bindings puts them into the layer you pick.

# 4.0.2

**The libraries Debind carries now ship exactly as their authors published them.** Since 3.2 every release had written Debind's own version and commit into the header comment of LibDeflate, which read as that library's version. Only the comment was touched; how the library loads and runs was never affected.

# 4.0.1

**Party/Raid Frames in a unit condition no longer carries a New mark.** The mark was for the role checkboxes under it, which came in with 3.5, and should have come off in 4.0.

# 4.0

**Each action now says what it does on each kind of press, under Cast Options in its right-click menu.** The Self Cast Key and Focus Cast Key rows each take Cast on yourself, or on your focus, Cast on the usual target, or Skip this action, which hands that press to the next action on the key. Hover Cast is a row of the same shape for the unit you point at, and Normal Cast covers a press with no key held. So one key can carry one action for a held key and a different one for a plain press. Several actions can be set at once.

**Hover casting is set on each action now, and it starts off.** It takes the place of the Unit Frame condition, and everything you set up under that condition does what it did before. The one exception is an action whose Unit Frame condition had more conditions with it, placed below one on the same key that had the Unit Frame condition alone: it never ran before, and now it runs when its conditions are met. Debind's settings now hold only which units count as pointed at, Unit Frames or Mouseover; an action can name a mode of its own instead.

**A target picked under Target is where the action goes, on every press that runs it.** Holding the Self Cast Key or the Focus Cast Key does not move it: the action takes that press and still goes to its own unit. Neither does the unit you are pointing at. And Auto Self Cast does not send a friendly spell back to you when the unit you picked cannot take it; the action simply does not go out. That last one used to depend on the unit: a friendly spell aimed at your target came back to you while you had a target and did nothing at all while you had none. Disable under Target hands the decision back to the game, and the menu says so on every entry.

**The game's own Mouseover Cast does not apply to Debind keys.** Pointing at a unit is Hover Cast, which each action turns on for itself.

**With no target picked, a held key comes before the unit you are pointing at.** The game's own settings do it the other way round, and that goes wrong exactly when it matters: your cursor rests on the enemy you last clicked, so the interrupt you meant for your focus lands on that enemy. On a Debind key the key you are holding decides.

**A click on a unit frame does not use the two cast keys**, whether or not the action takes the frame's unit. That is what the game does with its own click casting.

**The Self Cast Key and the Focus Cast Key can each be turned off for Debind keys**, in Debind's settings. Holding a key turned off there is the same as not holding it. One action can sit out a held key instead, with Skip this action on that row under Cast Options, and the press goes to the next action on the key.

**Four things the game does for you are now set on each action**: Auto Self Cast, Auto Cancel Form, Auto Dismount and Auto Dismount while flying. Each one is On, Off, or whatever the game's own settings say, which is what every action does until you change it. A spell you hold to empower answers these as well.

**An action can be turned off without deleting it.** It keeps its key, its conditions, its Importance and its place on the key, and it stops running. When every action on a key is turned off, the key goes back to whatever WoW has bound to it.

**A key whose actions all fail their conditions no longer goes to the game.** The press does nothing and the key stays Debind's. Before this, a key you also had bound in WoW ran WoW's binding whenever none of your actions could fire, which reads as a broken keybinding rather than as something you set. To catch those presses yourself, leave the last action on a key without conditions. To reach the action bar slot that key used to press, pick that last action from the Commands tab of Add an Action, where the action bar buttons are listed.

**Use WoW's Own Binding no longer does anything.** All it ever did was hand the key to WoW, and that is the path this version closes, so there is nothing for it to become. One left on a key is marked in the Overview, and where a slash command does the same job a Custom Macro is the replacement.

**A Binding Command that pressed an action bar button is now an Action Button action** and presses that button as it did. Every other Binding Command is left where it is and marked the same way.

**A new action called Nothing.** The press does nothing and takes the key for itself, so no action below it on the same key runs either. Put conditions on it and it stops those actions in those cases only.

**Three new actions pick the spell for you: Dispel, Raid Buff and Resurrect.** They are in the Spells tab of Add an Action, under Everything Else. Dispel casts your specialization's friendly dispel, Raid Buff your class's raid-wide buff, such as Power Word: Fortitude or Arcane Intellect, and Resurrect the resurrection that fits the press: your battle resurrection in combat, your mass resurrection on a dead group member or with no target, and your single one on any other dead friend. One of them on the Account tab does that job on every character. Where a character has no such spell, or has not learned it yet, the key is still taken and the press does nothing. The Spell to Cast condition hands that press to the next action on the key instead. Resurrect Options, next to Cast Options, allows a mass resurrection with no target, which starts on, and a battle resurrection out of combat when you have no other resurrection for that friend, which starts off.

**Debind now steps off the keys a replaced action bar uses.** While a vehicle or a possession has replaced your action bar, the keys bound to that bar's buttons go to the game and come back when the bar does. During a pet battle, the keys on action buttons 1 to 5 do the same, which is the only way to reach a pet battle ability from a key. Those two, and the House Editor keys Debind already gave up, are three ticks under Keys Given Back in Debind's settings.

**The window has help pages.** The portrait button opens the help at the page on setting your keys up, and the dropdown there holds the rest: the run order, which unit an action goes to, Hover Cast, Cast Options, clicking a unit frame, custom targets, Switches and Custom Macros.

**A key can now be limited to certain specializations.** The new Class/Specialization condition lists every class, and you tick the specializations the action fires in. Every class is there because an action in the Account tab runs on characters of another one. The specialization a character has before choosing one counts as its own.

**A new Talents condition.** It asks about the specialization you are playing, and only what you set there: in any other specialization the action runs as though it carried no talent condition at all. Both hero talent trees are offered, and a talent in the tree you did not choose counts as not taken.

**Known Spell now names the spell it asks about.** It used to ask only about the action's own spell. You pick the spell, so a key can be held back until you know a particular one.

**The Pet condition now lives on the Pet row under Units.** It was the same question in two places. What you had set moved across with the rest of your settings.

**Replace an Action.** You pick something else for the action to do and everything around it stays: the key, the conditions, the Importance and the place in the run order. Anything set on it that the new one cannot use is listed before anything changes.

**Debind works on unit frames whatever addon draws them, including the ones that run hover casting of their own.** Earlier versions left those frames alone, because taking one could stop that addon's own hover casting working there. Debind now takes the frame without taking anything away: whatever the addon had on it still runs, and Debind's keys run beside it. Where you have both of them on one key over a unit frame, Debind's is what fires.

**Debind now works alongside Clique instead of leaving unit frames to it.** Both run on the same frame: Clique keeps doing what you have set up there, and Debind's keys work there too. Where you have bound the same key in both, Debind's is what fires. If you had been running the two together, this changes what your unit frames do the first time you log in on this version.

**One list says which unit frames to leave alone.** Unit Frame Support in Debind's settings lists the game's own seven windows and every unit frame addon Debind knows by name, and unticking one keeps Debind off those frames entirely; that addon's own click handling is unaffected. Everything is ticked to begin with, which is Debind working everywhere. A change takes effect at the next login.

**When another addon takes over click casting for everyone, Debind no longer takes it back.** It used to, which lost the frames that addon had already collected and left it writing where nobody was reading. Debind now stands behind it: the addon keeps the name and keeps every frame it decided to keep, and Debind works on those frames as well.

Nearly everything Clique or an addon's own hover cast can do, Debind can do as well, usually as a condition rather than a macro. If you find something it cannot, or cannot work out how to set it up, leave a comment on CurseForge or at github.com/mundi4/debind/issues.
