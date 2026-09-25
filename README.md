# Debind

**Supports Retail and World of Warcraft: Forever.**

**Set a key once, for every character you have. Override it on one class, one spec, or a single alt — and only that key changes.**

A key in Debind goes straight to a spell, an item, or a macro — no action bar slot involved — and the layers decide which characters it covers. Whatever you already bound in WoW's own keybinding window stays exactly where it is, and stays there if you ever remove Debind.

## The problem

Roll an alt of a class you already play and you lay its bars out like the others. Some of those spells are on the bar because you want to watch the cooldown. The rest are on the bar because that's where the keybind is. `3` doesn't mean Judgment. `3` means *the third button on the first bar*, and Judgment happens to be standing there.

Addons have been putting spells on keys without a bar slot for years. None of them answer the next question:

**Which characters is this key for?**

Most of your binds are the same on every character. Some belong to one class. A few to one spec, one or two to a single character. WoW's own switch is all-or-nothing — the whole set shared, or the whole set per-character — and all-or-nothing has no way to say that. Go character-specific and every key that was the same everywhere now has to be set everywhere — the chore you were trying to avoid, times your alt count.

**And "which character" isn't the only question a key has.** The same key can want one thing in combat and another out of it, one thing on the frame under your mouse and another anywhere else. That part you already know — it's why you ran out of modifier keys, and why the macro got too long.

So the binds have to be layered, and one key has to be able to mean more than one thing.

## What you get

- **Layers, not profiles.** account → class → spec → this character → that character's spec. The narrowest layer holding that key wins; the rest keep every other key. Nothing to switch by hand — the layers follow your character and spec.
- **`@healer` and `@tank` that actually work.** WoW has no idea what a healer is; Debind does. Pick **Healer** as an action's target and you're done — no macro. And where you do want one, `/cast [@healer,exists][] Innervate` is one line.
- **Conditions on any key.** In combat, in a form, in a party or a raid, while some unit exists — re-checked as they change.
- **Click casting built in.** A key can go to the unit you point at, so one key heals off the raid frames and stays a normal key everywhere else. Unit frame addons work with it whether or not they support Clique, and Clique itself can run alongside.
- **Flip what a key does mid-fight.** Switches of your own, usable in combat, without spending a real modifier.

**Debind is for the keys where the answer isn't "all of them."** Put in the ones you want now — every other key goes on working exactly as it did.

![The Debind window. The overview column on the left shows every key in the order it fires; the right side is the layer being edited.](https://raw.githubusercontent.com/mundi4/debind/main/docs/screenshots/main-window.png)

## Layers

| Where a key can come from | Who it applies to |
|---|---|
| Character / Specialization | this character, in this spec |
| Character / General | this character |
| Account / Specialization | every Druid you own, while Balance |
| Account / Class | every Druid you own |
| Account / General | every character on the account |

**A layer holds only the keys you put in it — never a whole keyboard.** So the question is asked one key at a time: for *this* key, which rows have something to say?

The narrowest row that **fits** wins. A row whose conditions don't hold has nothing to say this time, so the key carries on to the next row that does, and does nothing if none of them do. Nothing is switched off on the way: the rows below are still answering for every other key.

Say `R` is Rebirth, in Account / Class. Every druid you have presses `R` for a battle rez, and so does the next one you roll. Then Balance wants `R` for Starfall — put Starfall in Account / Specialization and you're done. **The narrow layer takes over there, the broad one keeps everything else.** Balance gets Starfall, every other druid still gets Rebirth. You didn't copy Rebirth anywhere, you didn't delete it, and it's still in one place when you want to change it.

No profiles to pick. The layers follow your character and spec, and change when they do.

![Two layer tabs and their tooltips: Account / Balance covers every Druid you own while Balance; Oreo / Balance covers this character in this spec.](https://raw.githubusercontent.com/mundi4/debind/main/docs/screenshots/layer-tabs.png)

WoW's keybinding window has an *account-wide* / *character-specific* switch. It makes no difference to Debind either way — leave yours where it is.

## What a key can hold

A key can hold your spells, items, macros, mounts and toys, your flyouts and your pet's commands. And a few of Debind's own:

- **Custom Macro** — a macro kept in the addon instead of taking one of WoW's macro slots. Every WoW macro conditional works in one, and so do a few things WoW has no word for, like `@healer`.
- **Action Button** — for a key that already presses a bar button. Give that key a Debind action for one situation and put an Action Button under it, and every other press still goes to the bar, whatever a vehicle or a form has put there.
- **Set Custom Target** and **Switch** — the next two sections.

![The Add an Action window on its Spells tab, listing the character's spells with tabs for Macros, Mounts, Toys, Commands and Special.](https://raw.githubusercontent.com/mundi4/debind/main/docs/screenshots/add-an-action.png)

![A Custom Macro named "Innervate the healer" open in the editor — kept in the addon, costing none of WoW's macro slots.](https://raw.githubusercontent.com/mundi4/debind/main/docs/screenshots/custom-macro.png)

There are a few more for world markers, targeting, focus and the unit popup menu. Nobody installs an addon for those. They're there for when a key needs one.

## Conditions

Right-click an action to attach conditions. It only runs when all of them apply. In combat or out of it, which form you're in, what your mouse is over, whether you're in a party or a raid, whether some particular unit is there at all — and a dozen more in the menu.

These get re-checked as things change around you, in combat as much as out of it.

![An action's right-click menu: target, special conditions, importance, moving and copying — with the Target submenu open on No Target.](https://raw.githubusercontent.com/mundi4/debind/main/docs/screenshots/action-menu.png)

## Role targets

Beyond WoW's units, you get `tank`, `healer`, `maintank`, `mainassist`, `custom1`, `custom2`, and `unitframe`, the unit on the unit frame under your pointer.

Take Innervate. Balance druid, keystones, and it wants to go out to the healer over and over. Without `@healer` the choices are: retype the healer's name into a macro before every key, hunt for their frame with the mouse mid-pull, or park your focus on them — the focus you wanted for something else. WoW's macro conditionals have no idea what a healer is, so there is no fourth option.

Debind is the one working out who that is, so `@healer` only means something inside Debind. Most of the time that means the action's right-click menu — pick the unit and you're done:

![An action's tooltip: Innervate on F, target Healer, held back unless a healer exists — all of it picked from the menu, no macro involved.](https://raw.githubusercontent.com/mundi4/debind/main/docs/screenshots/role-target.png)

The other place is a **Custom Macro**, where one line can try the healer first and fall back to your normal target:

```
/cast [@healer,exists][] Innervate
```

**A role only works when exactly one person in the group has it.** With two tanks, `@tank` points at nobody rather than guessing.

### Custom targets

Two more slots that behave like extra focus targets, and don't cost you the real one. Bind **Set Custom Target**, then press it while hovering a frame.

A custom target follows the person, not their spot in the raid frames — shuffle the group and it goes with them.

## Switches

On/off switches of your own, as many as you want. You name each one, and the name is what you write: an action can require `$fishing` to be on, or off, and a Custom Macro reads it as `[$fishing]` / `[no$fishing]`.

A switch has one name and one meaning everywhere, but what it comes up as can be **overridden** for one class, one spec or one character.

They can be flipped **in combat**, which is the point of them — it's how you change what a key does in the middle of a fight. G Shift or Hypershift, without spending a real modifier key.

A switch can also drive itself from a macro conditional: hand it `[@tank,exists]` and it's on exactly while there's a tank.

## When a key holds several actions

Debind checks them in order and runs the first one that fits. If none of them fit, the key does nothing, even where WoW has something bound to it.

Two things decide that order before you do, and they're the same idea — the narrower case is checked first:

- **Having conditions at all.** An action with conditions is checked before one without: an action with no conditions always fits, so nothing under it would ever run.
- **Then the layer.** The narrower one goes first.

Everything else is yours to reorder.

![Four actions on the F key in the overview, each row saying why it beats the one below: unit frame rule, has conditions, spec over class — and one marked Never runs.](https://raw.githubusercontent.com/mundi4/debind/main/docs/screenshots/run-order.png)

The overview column shows the order you'll actually get, and each row says why it beats the one under it.

When an action can't be reached at all, the overview marks it **Never runs**. Sometimes that's a mistake worth catching. Sometimes it's the layer above doing exactly what you told it to — give Balance Starfall on `R` and Rebirth is dead on `R` for Balance, which was the whole point.

## Unit frames

Each action can go to the unit you point at, on a unit frame or, if you'd rather, on a nameplate or out in the world too. Put conditions on that unit and one key can heal off raid frames, do something else on the boss frames, and go back to being a normal key everywhere else.

![The Hovering Over Unit Frame submenu: hovered or not, which reactions, and which frame types count.](https://raw.githubusercontent.com/mundi4/debind/main/docs/screenshots/click-casting.png)

Debind works on unit frames whoever draws them. An addon that supports Clique registers with Debind the same way it registers with Clique; one that keeps its frames for its own hover casting is found anyway, and Debind works there without stopping anything that addon does. Clique itself can be installed and running at the same time, and both engines work on the frame — where you have bound the same key in both, Debind's is what fires. Debind can also stay off any of those frames, if you'd rather.

## Getting started

`/deb` opens the window. So does the addon compartment button by the minimap. Its tabs are the five layers, and **Overview** lists every key you have bound, in the order Debind tries them, for the character and spec you're on. The portrait button opens the help pages.

## A few things worth knowing

**It writes nowhere but its own settings file.** Not your keybindings, not a CVar. Pull it out and there's nothing to undo and nothing to hunt down in the console afterwards.

**You don't have to move everything into it.** Movement, the UI toggles, screenshot, bags — none of that has ever needed to differ by character, and mine are still in WoW's own window. The keys worth moving are the ones you'd otherwise keep in sync across characters by hand, or the ones you want behaving differently depending on what's going on. And if one character really does want a different bag key, that one key goes in that character's layer and no other character changes.

**These don't go on your action bars.** A Debind action is a binding, not a bar button — there's nothing to drag out. If you want to keep watching something, leave it on the bar where it already is and let Debind take the key; the button carries on doing everything it always did. And if one really needs a slot of its own, that one's a WoW macro — see below.

**Macros are still good.** If one macro solves your problem, write the macro — it's less machinery and it doesn't depend on me. This is for when the list stops being one macro.

**English, 한국어, Русский.** The Russian translation is ZamestoTV's.

**Not for Classic.** One client is enough to keep up with.

## Coming from Debounce

Debind was called Debounce until 3.0. Same addon, same author, same settings — `/deb` and `/debounce` both still work. In 3.1 the addon folder was renamed to match, which is where WoW keeps your settings file, so a small companion addon named **Debind Migration** ships alongside and carries them over. Leave it enabled — if it isn't, Debind says so when you log in rather than starting you off empty.

## Links

- [CurseForge](https://www.curseforge.com/wow/addons/debind)
- [GitHub issues](https://github.com/mundi4/debind/issues) — bugs and requests
- Oreo-Durotan (KR), Alliance · mundi4@gmail.com

## License

MIT. See [LICENSE](LICENSE).

The libraries under `Debind/Libs` and `DebindStorage/Libs` are not mine and keep the licenses they came with: LibStub is public domain, CallbackHandler-1.0 is Ace3's, LibDeflate is zlib, LibSerialize is MIT.
