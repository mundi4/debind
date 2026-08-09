# 3.1

**The addon folder is now named Debind too.** If you missed it, this addon was called Debounce until 3.0 renamed it — and since `/deb` still worked, there was not much to notice. I stopped at the display name on purpose: the folder is where WoW keeps your settings file, so renaming it means putting everyone through a migration, and that seemed like a lot to ask over a name.

Then I kept opening my AddOns folder and finding `Debounce` still sitting in it. It is a bad name. I would rather do this once, right after 3.0 while hardly anyone has settled into the new one, than leave it there forever. Sorry for the extra step.

So this update ships a small companion addon, **Debind Migration**, holding what 3.0 and earlier saved. Debind opens it once per character, moves that character's settings across — bindings, options, window positions — and leaves it alone after that. Keep it enabled: characters you have not logged in on since updating still have their settings in there. If 3.1 is your first install, it never runs at all.

# 3.0

**Debounce is now Debind.** Only the name shown in-game changed — the folder, your saved bindings and `/deb` are all where they were.

- Editing moved out of popups and onto the window itself, in a panel with **Key & Order** and **Macro** as its tabs.
- **Key & Order** shows the order a key's actions will actually be tried in, and lets you drag them into a different one. When an action can't move, it names the rule holding it and what you'd change.
- Actions no longer have to be dragged in from elsewhere. A picker lists what you already own — spells, macros, mounts, toys, commands — and flyouts open at your cursor, in combat, instead of borrowing Blizzard's.
- Fixes: macros with more than one bracket group parse in full, conditions Clique has taken over are greyed out instead of failing quietly, and four cases where a key ran something other than what it showed.
