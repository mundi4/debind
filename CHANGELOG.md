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
