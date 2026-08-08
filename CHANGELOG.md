# 3.0

**Debounce is now Debind.** The addon folder was renamed too, so this update ships a small extra addon called **Debind (legacy data)** that holds the settings you saved under the old name. Debind reads it once per character and moves everything across — bindings, options, window positions. Keep it installed and enabled: characters you have not logged into since the update still need it. `/deb` and `/debounce` both still work.

- Editing moved out of popups and onto the window itself, in a panel with **Key & Order** and **Macro** as its tabs.
- **Key & Order** shows the order a key's actions will actually be tried in, and lets you drag them into a different one. When an action can't move, it names the rule holding it and what you'd change.
- Actions no longer have to be dragged in from elsewhere. A picker lists what you already own — spells, macros, mounts, toys, commands — and flyouts open at your cursor, in combat, instead of borrowing Blizzard's.
- Fixes: macros with more than one bracket group parse in full, conditions Clique has taken over are greyed out instead of failing quietly, and four cases where a key ran something other than what it showed.
