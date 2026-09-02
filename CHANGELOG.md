# 3.5.2

**A key bound to hovering over a unit frame no longer keeps firing on a frame you have already left.** Some addons hook the same unit frames Debind does, and when one of them gets there after us, the game tells only that addon that the cursor has left. Debind never heard it, so the frame the cursor moved off stayed the answer, and the action kept landing on that frame's unit. Only the frames that addon had hooked were affected, and only bindings that hover.

On those frames Debind now asks the game where the cursor is instead, and lets the frame go as soon as the cursor is over nothing. The one case it cannot see is the cursor going straight from such a frame onto another unit, and even that clears the moment the cursor is over nothing again.

**A line at login says when this is happening to you.** It only goes out when another addon has got there after us and your bindings hover at all.

Nothing else changed in this one.

# 3.5.1

**EllesmereUI's unit frames answer again.** Its latest update builds them on an engine of its own rather than on the frame library it used before, and that library was how Debind found them: from that update, a key you had bound over its player, target, focus, pet, target of target, focus target or boss frame did nothing there. Its party and raid frames were never affected, which is why only some of your frames went quiet.

Nothing else changed in this one.

# 3.5

**Four new conditions, and a key on a unit frame can ask what the person does.**

**A mount key can hold more than one mount now.** **Flying Allowed** and **Skyriding Allowed** ask what the place you are standing in permits, which is the question a mount key asks before it picks. Put a ground mount, a flying mount and a skyriding mount on one key, each with the condition that suits it, and the key picks. Reaching for that used to mean dropping to a custom macro.

**Airborne** is the other half of it, and it asks about you rather than about the ground: whether you are off it right now. Both have to exist, or a key cannot tell "I could fly here" from "I am flying".

The two about the place lag the world a little, the way every mount macro ever written has. Stepping outdoors does not make mounting legal on the same frame, and crossing the other way leaves you mounted for some distance.

**Role.** A binding that runs while you are hovering a unit frame can ask whether that person is a tank, a healer or damage, the way it can already ask about their reaction or whether they are dead. One key can hold a save for the tank and a dispel for the healer and pick by who you are pointing at. **No Role** is the fourth, for a unit that has none assigned.

Only party and raid frames can answer at all, so over any other frame the condition does not hold the action back.

**Converting an action to a Custom Macro no longer changes what the key does.** It rewrote the action in place and quietly took things with it on the way. Five of those:

- An equipment slot can be converted now. It could not be before, though `/use` with the slot number is exactly what its binding already sends.
- An action keeps its aim. One aiming at a unit Debind worked out for you, rather than one you picked yourself, came out as a body with no target in it at all.
- A world marker is no longer offered. The key both places a marker and takes it back, `/wm` only places, and nothing in a macro tells the two apart.
- A macro name whose macro you have since deleted is no longer offered.
- An action with **Only When Spell Known** is no longer offered. That condition asks about the action's own spell, and a macro body takes that spell's place, so the converted action would have read as carrying no conditions at all and the next action on that key would never have fired.

Also in this one:

- Some unit frames drawn by other addons were never reached, EllesmereUI's among them. The slot in its party frames that holds you is one, and so are the frames it puts beside your raid frames: the friendly units an encounter wants kept alive, and the copies it makes of raid members you pick out. Every other slot in the same party block worked, which made it look like the one frame was broken rather than never registered. Debind now catches these as the addon wires them up, and treats all of them as party and raid frames, which is where they are drawn and what a binding scoped to those should reach.

**A share code made here still opens in 3.4, and nothing in it is turned away.** One that uses **Flying Allowed**, **Skyriding Allowed** or **Airborne** opens there with that condition missing, and so does one that asks about **Role**. Nothing on that end says it went, so the action ends up running in places you had ruled out, or on whoever you are pointing at rather than the role you picked. It stops the moment the other side updates. The other direction is unchanged: a code from 3.4, 3.3 or 3.2 opens here exactly as before.

# 3.4

**Two new tabs in the picker, and three new conditions.**

**Items.** A key can now follow an equipment slot rather than an item. Bind your trinket slot and swapping the trinket changes what the key fires, with the icon following it. The other group is whatever you are carrying that has a use effect. A slot binding takes a target the same way an item bound by its own name does.

**Collections** holds mounts and toys together, favourites first and named by kind so the two halves of the list cannot be read as one. It used to be two tabs, and the Mounts one hid itself when you had no mounts, taking the tab space with it while your toys were still in reach elsewhere.

**While Mounted, While Indoors and While Skyriding** join the condition list, and the conditions too small to hold a row each now sit in one **Miscellaneous** submenu. A switch expression can read `[mounted]` and `[indoors]` as well.

**Group headings in the picker fold**, and they wear the bar the overview's key groups already wear.

Also in this one:

- The Commands tab could come up dead. Another addon putting a table into the global namespace under its own name was enough to do it. An addon's bindings are now listed under its folder name, which is what the game's own keybinding panel shows.
- A binding that only runs while you are alone and aims at a role unit is now marked. Those units are empty when you are alone, so it could never have fired.
- A unit condition this build cannot read no longer counts as "when there is none". A higher binding reading it that way was enough for Debind to drop the binding underneath it without saying so.
- The throttle slider in the state driver options reached nothing on a rebuild, which always used the default instead.
- An **Unused** action carrying conditions could release its key for good, leaving whatever was under it on that key dead with nothing on screen to say why.
- A nameplate keeps targeting on a click while Debind is watching it.
- A toy arriving no longer sends the mount list off to be built again.

**A share code made here still opens in 3.3, with two exceptions.** One that binds an equipment slot is turned away whole rather than read in part, which is the answer this addon gives to anything it could not have made itself. One that uses **While Mounted**, **While Indoors** or **While Skyriding** opens there with that condition missing, and nothing on that end says it went, so the action ends up running in places you had ruled out. Both stop the moment the other side updates. The other direction is unchanged: a code from 3.3 or 3.2 opens here exactly as before.

# 3.3

**Custom states are switches now, and there is no longer a fixed five of them.**

They used to be five numbered slots, sitting in the list whether you used them or not. Now you make one when you want one and give it a name, and that name is what everything else reads: a condition on `$burst`, a macro conditional `[$burst]`. Renaming rewrites every action that names it, on every character of the account, including the macro bodies it appears in. The five you already have keep working under the names `$state1` to `$state5`, so nothing you set up before this moves.

**Switches have a tab of their own.** It lists the ones you have, what each comes up as, which actions read it, and whether anything reads it at all. Settings, renaming and deleting are on the right-click menu there, and out of combat you can turn one on or off from the list. You can also make one from the condition menu, or from the action you are editing, at the moment you find you need it. Deleting one leaves the actions that name it red rather than quietly dropping the condition, so you can see where to go.

**What a switch comes up as can differ per class, specialization or character.** The account wide answer is **Starts on**, **Starts off** or **As you left it**, and any of the tabs on the left can carry an override that replaces it there. **As you left it is remembered per character now**; it used to be one answer everybody on the account shared.

**A key that works a switch says which way it works it**: turns it on, turns it off, or turns it over.

**Export and Import are one tab now, Storage.**

What is kept there is a payload, and there are two ways to get one: **New Payload** makes one out of everything the character has right now, **Paste Share Code** takes one from somebody else. Pick a payload on the left and its actions stand on the right, where you can tick the part you want and delete outright what you never want in it. Putting it into your bindings is two answers, **Add as Pending**, which changes nothing your keys do until you accept them, and **Add and Accept**, which starts them straight away and asks first about any key of yours they land on. **Create Share Code** turns the ticked part back into a string.

**What arrives keeps the key it was sent on.** It used to be parked on a key of its own with a number where the key goes, and that number was the only thing telling one arrival from another. An arrival now sits on its real key and stays a set of its own, so you can see what it would do before accepting it, and your set on that key is not touched. Accepting a whole key at once asks which side wins: **Keep Existing**, **Take Incoming** or **Merge**.

**A switch itself does not travel with the code.** The actions do, and each one reads whichever switch of yours carries that name, so a payload built around `$burst` starts working the moment you have a `$burst` of your own. Until then those actions sit red and say which name they are missing. Nothing that arrives writes a switch, because a switch is shared by everything in your profile and writing one would change what your existing actions do before you had accepted anything.

**Share codes made here cannot be read by 3.2.** What an action looks like on the wire changed, and an older build says so rather than guessing. Codes and pending payloads from 3.2 are read here exactly as before.

**Your unit frame bindings now reach the frames other addons draw.**

Clicking a unit frame to cast is meant to work on whatever frames you use, and for a lot of setups it quietly did not. Debind hears about a frame through a list every click casting addon shares, and any addon that runs click casting of its own can take that list over: from that moment the frames being drawn go somewhere Debind never sees them. Frames built from a group of players are worse still, because those connect once, at the moment they are built, and a connection missed then is missed for the session.

Debind now goes and finds them instead of waiting to be told. It asks the frame library its frames came from, it takes the members of a group frame set off the set itself as they appear, and it takes the shared list back when another addon has claimed it. If another addon then narrows what a frame will deliver, Debind puts it back rather than going silent.

**A frame drawn by another addon is now recognised for what it is.** Every one of them used to arrive as "other", so a binding you scoped to party frames did nothing on the party frames you were actually looking at. Debind now reads the frame, which matters most for the slot in a party frame set that holds you: it reports itself as the player, and it is a party frame.

**A new setting decides when a click on a unit frame casts** (in **Unit frame options**). Mouse up is what Blizzard's own frames do and what you get if you leave it alone, mouse down fires the moment the button goes down, and the third answer follows **Cast action keybinds on key down** in the game's own settings, which is the one your keys already follow.

Also in this one:

- A click on a mouse button you have no binding for is left alone on the way down as well as the way up. It used to be taken on the press even when Debind had nothing to run, which quietly ate that click from the frame underneath.
- Mouse wheel bindings on a unit frame survive another addon turning the wheel off on that frame.
- **Add custom target menus on the unit popup** is gone, and with it the entries it added to the right-click menu on a unit. That menu is one the game protects, and adding to it put Debind's name in error reports for breakage that started elsewhere. Setting a custom target from a binding is unchanged.

- **Remove Duplicate Actions**, on the overview row and in the options menu. It looks for actions that are exact copies of one another inside one layer and takes the copies out, keeping the one that fires first. The same action on two layers is left alone: that is what the layers are for.
- Taking the key off a set of actions asks first, because unbinding scatters them and nothing records that they went together.
- An older Debind now stands down from settings a newer one wrote, instead of reading what it can and dropping the rest. None of your keys work and it says why, and putting the newer version back returns everything.

# 3.2.2

**A fix for the unit frame menu going missing under one option.**

With **Use mouse down for click casting** on, right-clicking a unit frame did nothing at all: the menu the game opens there never came up. Left-clicking still picked the unit up as your target, so the option looked like it was doing its job.

That setting asked the frames to report the press of a click and not the release, and the release is the only moment the game opens that menu. They report both now, and click casting still fires on the press.

Nothing changes with the option off, which is how it comes.

# 3.2.1

**A fix for party frame health bars standing still in Edit Mode.**

Opening the name and icon window for a custom macro left the game's shared icon list marked as this addon's. Edit Mode reads that list on the way in, to pick the icons for the sample auras it shows you, and reading it there was enough for the game to refuse the party frame health bar updates that came right after. Every entry into Edit Mode did it again, and with an error display installed the errors arrived once per frame. Reloading cleared it, until the next time that window was opened.

Debind keeps its own icon list now, so the game's is neither built nor dropped by this addon. The window itself is unchanged.

This has been here since 3.1. It only became visible on 12.1, where the game seals the health values that the refused update was comparing.

# 3.2

**You can hand your setup to somebody else now, as a string.**

The **Export** tab turns any part of it into one line of text, the specializations you are not playing included, so you do not have to switch characters to put them in. It works just as well as a backup of your own.

The **Import** tab is the other end. Paste a string and it stays there until you decide what to do with it, so you can come back and finish later. **Bring it in** asks which parts to take and adds those to your bindings **switched off**: nothing you press behaves any differently until you accept them, one at a time or all at once. What arrives lands on a key of its own rather than joining a key you already use, so a set you receive never quietly merges into a set you built.

**Macro names travel, macro bodies do not.** A received action calls your macro of that name, or says in red that you have no such macro. Nothing about you rides along either: no character name, no realm.

**A new piece appears in your addon list, Debind Storage.** It builds those strings and holds the ones you receive. Leave it enabled: it is loaded on demand, so until you open one of the two tabs it is never read at all. Deleting it loses whatever is still being held there, though anything you already accepted stays in your bindings.

**The overview column got a lot bigger.** A key group folds, and folded it still says what is inside. There is a search box, and a filter for the parts of the list you want out of the way. A key group nothing currently runs from is greyed, and a problem with a binding is now coloured by how much it actually breaks.

**Actions on a specialization you are not in are listed too**, in the place they would take if that specialization were active. They used to be reachable only by opening their tab on the right and looking.

**Assigning a key happens in a dialog now.** It says which key the action is on and what the new one is about to apply to, and it will do a whole key group in one go. If the key is already taken it asks before taking it. Bind Mode is still there for setting a lot of keys quickly.

**A unit condition can ask whether the unit is alive or dead**, and the frame you are hovering now takes the same conditions every other unit does, so you can ask two things about one unit at once. Turning a condition off keeps what you had picked under it.

Also in this one:

- A custom state name with a typo in it now stops the binding and says so, instead of letting it through with that condition simply gone.
- Spells you have not learned yet are back in the spell picker.
- Actions sharing a key keep the order you gave them after an edit that could shuffle them.
- With Clique installed, Debind now says so on login: your unit frame bindings here do not fire while it is there.

# 3.1.6

**12.1 readiness: sealed answers about arena enemies no longer break custom targets.**

Patch 12.1 answers some questions about arena enemies with sealed values — asking for a class, a name or an identity gives back something that exists but cannot be read. Debind asked those questions in a few places: to color the name in the "custom target set" message, to resolve which unit a custom target points at, and to tell Grid2 which frame carries the target indicator. Reading a sealed answer errored, and the error also cut short whatever update pass it happened in. Seen live on the 12.1 PTR by setting a custom target on an arena enemy.

Sealed answers now degrade instead of erroring: a name that cannot be read shows the unit token instead, a class color falls back to gray, and an identity that cannot be confirmed counts as "not the same unit" — including what the Grid2 indicator is told, since a sealed value passed onward would error inside Grid2 instead.

If your region is already on 12.1, this one is for you. Nothing changes on 12.0 servers.

# 3.1.5

**A follow-up to the 3.1.4 fix — the question it relied on turned out to have wrong answers.**

3.1.4 taught Debind to leave sealed pieces of a unit frame alone by asking each piece "are you sealed?" before touching it. Testing on the 12.1 PTR showed that question can come back *no* for a piece that refuses to be touched anyway: the private-aura icons WoW hangs under unit frames deny being sealed and still error on contact. It reproduced in an arena, where those icons sit under every frame — which lines up with the original report saying "specifically in arena".

So Debind no longer trusts the answer alone. It still asks — a piece that admits to being sealed is skipped cheaply — but any piece that errors when touched is now treated exactly like a sealed one: that piece and everything inside it are left alone, and the walk carries on with the rest of the frame. One untouchable piece no longer takes the login setup down with it. Whatever else Midnight decides to seal should land in the same net, since this shape of fix does not need to know the list in advance.

Hopefully this is the last of this error. If 3.1.4 did not stop it for you, this one should — and I would still like to hear either way.

# 3.1.4

**Debind could throw an error at login and leave some unit frames without click-casting.**

This one comes from a single report, and I could not reproduce it or pin down which frame caused it. What follows is a fix for the cause the error points at, not for something anyone has watched happen — so if you were seeing this, I would like to know whether it stops.

When Debind takes on a unit frame it walks the pieces inside it — bars, icons, borders — and asks each one to pass mouse movement through to the frame, so that moving the cursor onto an icon still counts as hovering the frame rather than leaving it. WoW seals some of its own pieces off from addons completely, and asking a sealed piece anything at all is an error rather than a refusal.

Debind already stepped around a sealed unit frame, but it only looked at the frame itself and not at the pieces hanging underneath it. The error stopped that walk partway, and with it the rest of the login setup: whichever frames had not been taken on yet were skipped, so click-casting and hover conditions were simply missing on them until the next reload — with nothing on screen to say so.

Sealed pieces are now recognised wherever they turn up, and left alone along with anything inside them.

# 3.1.3

**3.1.2 could freeze the game with raid frames from another addon.**

Changing groups — anyone joining or leaving, or switching raid layouts — could send the game into an endless loop and stop it dead. It needed a unit frame addon that builds its frames with WoW's own group header, which is most of them, so if 3.1.2 gave you trouble this was almost certainly it.

Debind was writing a setting onto that header, and a header rebuilds all of its frames whenever any of its settings change — including while it is already in the middle of building them, which is exactly when Debind was writing. Each frame it built asked Debind to set up click-casting, which wrote again, which started another rebuild. The write is now made the same way Blizzard makes its own, which the header knows to ignore.

**Sorry.** 3.1.2 was out for a short time and this was in it.

# 3.1.2

**Click-casting a custom macro, a macro, or a pet command did nothing at all.**

Put one of those on a unit frame click and it never fired. The same action on a keyboard key worked, and everything else on unit frames — spells, items, targeting, focus — worked too, so the key you had set looked fine everywhere you could check it. There was no error and nothing in the chat.

Mounts were caught by it as well, but only the ones Debind has to summon through a macro rather than a spell.

The cause was one hop too many. A click on a unit frame went through a macro to reach the action, and WoW will not run a macro that a macro started — so anything macro-shaped at the end of that chain was dropped on the floor, and only those. Debind no longer routes the click through a macro, so the action is now the first and only one in the chain.

**Hover bindings limited to the *Other* reaction went dead a moment after you hovered.**

If you restricted an action to *Other* under **Reactions** — the setting that covers everything you can neither help nor harm, like merchants, guards, corpses and friendly totems — it worked the instant your cursor arrived and then stopped. Two parts of Debind disagreed on what *Other* meant, and the one that ran a fraction of a second later won.

# 3.1.1

**A key could stop working because of a condition on a different key.**

Under an action's **Units** menu, if one action was set to *When the unit exists* for, say, your focus, and any other action anywhere used that same unit with *When the unit is friendly* or *When the unit is an enemy* instead, the first one quietly stopped matching whenever the focus actually was friendly or an enemy. One such action on its own worked fine, so the fault never looked like it belonged to the condition you had set.

It went further than that one action. Debind marks an action unreachable when a higher-priority one already covers every case it could run in, and it was right that *exists* covers *friendly* — so it removed the lower action as redundant, while the higher one was the one failing to fire. Nothing ran, and nothing said why.

**If you built around this, look at that key again.** An action you put under an *exists* one to catch the friendly case is now genuinely redundant, and the *exists* action will run in its place.

# 3.1

**The addon folder is now named Debind too.** If you missed it, this addon was called Debounce until 3.0 renamed it — and since `/deb` still worked, there was not much to notice. I stopped at the display name on purpose: the folder is where WoW keeps your settings file, so renaming it means putting everyone through a migration, and that seemed like a lot to ask over a name.

Then I kept opening my AddOns folder and finding `Debounce` still sitting in it. It is a bad name. I would rather do this once, right after 3.0 while hardly anyone has settled into the new one, than leave it there forever. Sorry for the extra step.

So this update ships a small companion addon, **Debind Migration**, holding what 3.0 and earlier saved. Debind opens it once per character, moves that character's settings across — bindings, options, window positions — and leaves it alone after that. Keep it enabled: characters you have not logged in on since updating still have their settings in there. If 3.1 is your first install, it never runs at all.

**The window has a left half now.** The panel 3.0 put beside the list did not last the week. What stands in its place is an overview of every key you have bound — grouped by key, in the order Debind tries them, for the character and specialization you are on. It is what pressing the key would actually do, rather than what happens to be in the tab you have open, and it is drawn the moment the window opens instead of waiting for you to pick something.

- **Setting a key is a mode.** Turn on *Set Keys*, point at an action, press. Each press lands as you make it — mouse buttons and the wheel count. Escape while pointing at an action clears its key, and Escape while pointing at nothing puts back every key you changed since you turned the mode on.
- Where several actions share a key, each row says why it beats the one under it, and the row you select gets **Run Sooner** and **Run Later**.
- Everything else about an action — conditions, targets, importance, moving and copying — is on its right-click menu, where it already was. The macro editor is a window of its own again.

**Actions can be picked several at a time.** Ctrl-click adds one to what you have selected, shift-click takes everything between, and the right-click menu then works on the whole selection — move it, copy it, delete it. Clearing a tab out and copying a tab's worth somewhere else were each asked for as their own command; they are the same command, and it was already in the menu waiting for something to point it at.

Also in this one:

- **Korean (koKR)** is now translated, in full.
- **The layer tabs say which layer they are.** The ones down the side were an icon and a number, and their tooltip carried the specialization name on its own, which does not tell you whether you are looking at the shared branch or this character's — the same icon stands in both. Each tab now titles itself with the whole layer name and adds a line under it: who uses that layer, what it beats, and when that is not true.
- A move button that cannot move now says what is holding the action in place, rather than only that something is.
- The companion addon above is normally silent, but if it has been switched off or has gone missing, Debind says so on login and waits for an answer instead of quietly starting you off empty.
- Fixes: a `$state` token no longer rides out of an unclosed bracket group in a custom macro, and Debind waits for the game to report your specialization rather than building a half-finished set of bindings from what it knows at that moment.

# 3.0

**Debounce is now Debind.** Only the name shown in-game changed — the folder, your saved bindings and `/deb` are all where they were.

- Editing moved out of popups and onto the window itself, in a panel with **Key & Order** and **Macro** as its tabs.
- **Key & Order** shows the order a key's actions will actually be tried in, and lets you drag them into a different one. When an action can't move, it names the rule holding it and what you'd change.
- Actions no longer have to be dragged in from elsewhere. A picker lists what you already own — spells, macros, mounts, toys, commands — and flyouts open at your cursor, in combat, instead of borrowing Blizzard's.
- Fixes: macros with more than one bracket group parse in full, conditions Clique has taken over are greyed out instead of failing quietly, and four cases where a key ran something other than what it showed.
