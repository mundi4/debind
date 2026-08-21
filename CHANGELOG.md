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
