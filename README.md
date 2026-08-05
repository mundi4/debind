# Debind

A World of Warcraft keybinding addon. Set a key once for every character, then override it on one class, one spec, or one character.

*Debind was called Debounce until this release. Same addon, same author, same settings — `/deb` and `/debounce` both still work.*

## The problem

Roll an alt of a class you already play, and you lay its action bars out like the others. Some of those spells are on the bar because you want to watch the cooldown. The rest are on the bar because that's where the keybind is. `3` doesn't mean Judgment. `3` means *the third button on the first bar*, and Judgment happens to be standing there.

Getting a spell onto a key without a bar slot isn't new; addons have done that for years. The question that doesn't get answered is the one right behind it:

**Which characters is this key for?**

Most of your binds are the same on every character. Some belong to one class. A few to one spec, and one or two to a single character. WoW gives you a choice between *account-wide* and *character-specific*, and neither of those is the answer — pick character-specific and the keys that are the same everywhere now have to be changed everywhere, which is the same chore you were trying to get out of, multiplied.

So the binds have to be layered.

## Layers

| Where a key can come from | Who it applies to |
|---|---|
| Character / Specialization | this character, in this spec |
| Character / General | this character |
| Shared / Specialization | every Warlock you own, while Destruction |
| Shared / Class | every Warlock you own |
| Shared / General | every character on the account |
| *WoW's own keybindings* | *whatever you already had. Debind doesn't touch it.* |

It's an order, read from the top: the highest row with something for that key is the one that gets it, and the rows under it go on covering everything it didn't take. The bottom row is where a key ends up when none of the others want it.

When you add a binding, put it in the broadest layer that fits and leave it there. When one spec wants that key for something else, add it to a narrower layer — **the narrow one takes over there, the broad one keeps everything else.** You don't copy it, you don't delete it, and there's still one place to edit it later.

There is no profile to pick. The layers follow your character and spec, and change when they do.

**That last row stays out of it entirely.** Debind doesn't copy your keybindings in, doesn't change them, and doesn't try to run them on WoW's behalf either. When nothing you put on a key applies, Debind's binding comes off that key and the game handles the press itself, through the same keybinding system it always used. A key you never gave to Debind was never involved to begin with.

WoW's own keybinding window has a switch on it for *account-wide* or *character-specific*. It makes no difference to Debind's layers either way, so leave yours where it is.

Debind is for the keys where the answer isn't "all of them".

## Getting started

`/deb` opens the window, and so does the addon compartment button by the minimap.

Drag a spell, item, macro or mount onto the list. **Add...** has the rest. Left-click an action and press the key you want; mouse buttons and the wheel count. Right-click it for conditions, targets and the like. The tabs along the bottom and down the side decide which layer it lives in, and dragging an action onto another tab moves it there.

## What a key can hold

Spells, items, macros and mounts, dragged in from where they already are. Then:

- **Macro Text** — a macro kept in the addon instead of taking one of WoW's macro slots. Every WoW macro conditional works in one, and so do a few things WoW has no word for, like `@healer`.
- **Binding Command** — one of WoW's own binding commands (jump, open a bag, press a bar button), wrapped so it can carry conditions.
- **Use WoW's Own Binding** — gives the key back to WoW for the cases you pick, so one spec can go on using your normal binding.
- **Set Custom Target** and **Set Custom State** — the two things below.

The **Add...** menu has a few more: world markers, targeting, focus, the unit popup menu. Nobody installs an addon for those. They're there for when a key needs one.

## Conditions

Right-click an action to attach conditions; it only runs when all of them apply. In combat or out of it, which form you're in, what your mouse is over, whether you're in a party or a raid, whether some particular unit is there at all — and a dozen more in the menu.

These are re-checked as things change around you, in combat as much as out of it.

## Role targets

Beyond WoW's units, you get `tank`, `healer`, `maintank`, `mainassist`, `custom1`, `custom2`, and `hover` — the frame under your pointer.

Take Innervate. Balance druid, keystones, and it wants to go out to the healer over and over. Without `@healer` the choices are: retype the healer's name into a macro before every key, hunt for their frame with the mouse mid-pull, or park your focus on them — the focus you wanted for something else. WoW's macro conditionals have no idea what a healer is, so there is no fourth option.

Debind is the one working out who that is, so `@healer` only means anything in Debind's own places. Most of the time that place is the action's right-click menu — pick the unit and you're done.

The other is a **Macro Text**, where one line can try the healer first and fall back to your normal target:

```
/cast [@healer,exists][] Innervate
```

**A role only works when exactly one person in the group has it.** With two tanks, `@tank` points at nobody rather than guessing.

### Custom targets

Two more slots that behave like extra focus targets, and don't cost you the real one. Bind **Set Custom Target**, then press it while hovering a frame. Works from the player, pet, party, raid, boss and arena frames, and there's an entry on the unit right-click menu too.

A custom target follows the person, not their spot in the raid frames — shuffle the group and it goes with them.

One gap, and it's a narrow one: the group changes mid-fight, and *after that* you pin a party or raid member. Until combat ends that one is tied to their spot in the group rather than to them, and if the group shifts again first it's dropped rather than left pointing at whoever moved into the slot — Debind says so in chat. One pinned before the group changed keeps following them through it.

## Custom states

Five switches of your own. An action can require one to be on, or off, and a Macro Text can read it as `[$state1]` / `[no$state1]`.

They can be flipped **in combat**, which is the point of them — it's how you change what a key does in the middle of a fight. G Shift or Hypershift, without spending a real modifier key.

A state can also drive itself from a macro conditional: hand it `[@tank,exists]` and it's on exactly while there's a tank.

## When a key holds several actions

Debind checks them in order and runs the first one that fits. If none of them fit, the key does whatever your WoW keybinding says — the last row of that table.

Three things decide that order, and they're all the same idea — the narrower case is checked first:

- **Hovering a unit frame comes first.** Otherwise the action that runs anywhere would take the key, and the one meant for the frame under your mouse would never run.
- **Then having conditions at all.** An action with conditions is checked before one without, for the same reason: an action with no conditions always fits.
- **Then the layer.** The narrower one goes first.

If that ordering isn't what you want, set the action's **Importance** — what you set yourself wins over anything the addon worked out on its own. The **Key & Order** tab shows the order you'll actually get, and when an action can't be moved it says which rule is holding it and what you'd change.

## Unit frames

Hovering a unit frame is a condition like any other, so click casting is just a binding with that condition on it. Unit frame addons that support Clique register with Debind the same way they would with it.

You can run Clique itself alongside this. Debind leaves unit frames to Clique and everything else works as usual — what stops is the hover condition and any action aimed at `@hover`. Both are marked in the list, and Debind says so when you log in.

## A few things worth knowing

**It doesn't touch your existing keybindings.** Whatever you set up in WoW's own keybinding window stays exactly as it is, and any key Debind isn't using at that moment behaves normally.

**You don't have to move everything into it.** Movement, the UI toggles, screenshot, bags — none of that has ever needed to differ by character, and mine are still in WoW's own window. The keys worth moving are the ones you'd otherwise keep in sync across characters by hand, or the ones you want behaving differently depending on what's going on. And if one character really does want a different bag key, that one key goes in that character's layer and no other character changes.

**A few keys stop working in the house editor.** While it's open the editor claims some keys for its own shortcuts, and Debind leaves those alone — so an action bound to one of them does nothing until you close the editor. If you'd rather keep one of yours, there's a setting on the action for that.

**Macros are still good.** If one macro solves your problem, write the macro — it's less machinery and it doesn't depend on me. This is for when the list stops being one macro.

**Not for Classic.** One client is enough to keep up with.

## Links

- [CurseForge](https://www.curseforge.com/wow/addons/debounce)
- [GitHub issues](https://github.com/mundi4/Debounce/issues) — bugs and requests
- Oreo-Durotan (KR), Alliance · mundi4@gmail.com
