# Debind

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
- **Click casting built in.** Hovering a unit frame is a condition like any other, so one key can heal off the raid frames and stay a normal key everywhere else. Unit frame addons that support Clique already work with it.
- **Flip what a key does mid-fight.** Five switches of your own, usable in combat, without spending a real modifier.

**Debind is for the keys where the answer isn't "all of them."** Put in the ones you want now — every other key goes on working exactly as it did.

![The Debind window. The overview column on the left shows every key in the order it fires; the right side is the layer being edited.](https://raw.githubusercontent.com/mundi4/debind/main/docs/screenshots/main-window.png)

## Layers

| Where a key can come from | Who it applies to |
|---|---|
| Character / Specialization | this character, in this spec |
| Character / General | this character |
| Shared / Specialization | every Druid you own, while Balance |
| Shared / Class | every Druid you own |
| Shared / General | every character on the account |
| *WoW's own keybindings* | *whatever you already had. Debind doesn't touch it.* |

**A layer holds only the keys you put in it — never a whole keyboard.** So the question is asked one key at a time: for *this* key, which rows have something to say?

The narrowest row that **fits** wins. A row whose conditions don't hold has nothing to say this time, so the key carries on to the next row that does — and to your WoW keybinding if none of them do. Nothing is switched off on the way: the rows below are still answering for every other key. (Put two actions on the same key and a couple of other things get checked before the layer does — *When a key holds several actions*, further down.)

Say `R` is Rebirth, in Shared / Class. Every druid you have presses `R` for a battle rez, and so does the next one you roll. Then Balance wants `R` for Starfall — put Starfall in Shared / Specialization and you're done. **The narrow layer takes over there, the broad one keeps everything else.** Balance gets Starfall, every other druid still gets Rebirth. You didn't copy Rebirth anywhere, you didn't delete it, and it's still in one place when you want to change it.

No profiles to pick. The layers follow your character and spec, and change when they do.

![Two layer tabs and their tooltips: Shared / Balance covers every Druid you own while Balance; Oreo / Balance covers this character in this spec.](https://raw.githubusercontent.com/mundi4/debind/main/docs/screenshots/layer-tabs.png)

**That last row stays out of it.** When nothing you put on a key applies, Debind's binding comes off and the game handles the press itself — Debind never runs your binding for you. A key you never gave to Debind was never involved at all.

WoW's keybinding window has an *account-wide* / *character-specific* switch. It makes no difference to Debind either way — leave yours where it is.

## Getting started

`/deb` opens the window. So does the addon compartment button by the minimap.

The list you land on is the layer you're editing. The tabs along the bottom pick **Shared** or **this character**; the tabs down the side pick **General**, **Class**, or one specialization. Those two together are the five layers in that table — hover a tab and it says which one it is and who it covers. The number on a tab is how many actions are in it. Dragging an action onto another tab moves it there.

**Overview**, the tab at the bottom left, opens a second column beside it: every key you have bound, grouped by key, in the order Debind tries them, for the character and spec you're on. Read this one when you want to know what a key actually does — it covers every tab at once, not just the one you have open. Click a row and you land on that action in whichever layer it lives in.

The **+** at the top opens **Add an Action**, with a search box over everything in it. It stays open while you work, and every click adds to whichever layer tab you have open. Dragging a spell, item, macro or mount onto the list works too.

![The Add an Action window on its Spells tab, listing the character's spells with tabs for Macros, Mounts, Toys, Commands and Special.](https://raw.githubusercontent.com/mundi4/debind/main/docs/screenshots/add-an-action.png)

To give something a key, turn on **Bind Mode** — the keycap button at the top of the window, next to the **+** — then point at the action and press the key. Mouse buttons and the wheel count. While that mode is on:

- **Escape, pointing at an action** — clears that action's key.
- **Escape, pointing at nothing** — puts back every key you've changed since you turned the mode on.
- **Done** — keeps them.

Everything else about an action — conditions, targets, importance, moving and copying — is on its right-click menu. Ctrl-click and shift-click pick out more than one at a time, and the menu then applies to the lot, which is how you move a tab's worth of bindings somewhere else or empty one out.

## What a key can hold

**Add an Action** has six tabs: **Spells**, **Macros**, **Mounts**, **Toys**, **Commands** and **Special**. The first four are what you already own — **Spells** has your flyouts and your pet's commands in it too. Items come in by dragging. The rest are Debind's own:

- **Custom Macro** — a macro kept in the addon instead of taking one of WoW's macro slots. Every WoW macro conditional works in one, and so do a few things WoW has no word for, like `@healer`. **New Custom Macro**, above the picker's list, starts an empty one.
- **Binding Command**, on **Commands** — one of WoW's own binding commands (jump, open a bag, press a bar button), wrapped so it can carry conditions.
- **Use WoW's Own Binding**, on **Special** — gives the key back to WoW for the cases you pick, so one spec can go on using your normal binding.
- **Set Custom Target** and **Set Switch**, on **Special** — the next two sections.

![A Custom Macro named "Innervate the healer" open in the editor — kept in the addon, costing none of WoW's macro slots.](https://raw.githubusercontent.com/mundi4/debind/main/docs/screenshots/custom-macro.png)

The **Commands** tab has a few more of ours, above WoW's own list: world markers, targeting, focus, the unit popup menu. Nobody installs an addon for those. They're there for when a key needs one.

## Conditions

Right-click an action to attach conditions. It only runs when all of them apply. In combat or out of it, which form you're in, what your mouse is over, whether you're in a party or a raid, whether some particular unit is there at all — and a dozen more in the menu.

These get re-checked as things change around you, in combat as much as out of it.

![An action's right-click menu: target, special conditions, importance, moving and copying — with the Target submenu open on No Target.](https://raw.githubusercontent.com/mundi4/debind/main/docs/screenshots/action-menu.png)

## Role targets

Beyond WoW's units, you get `tank`, `healer`, `maintank`, `mainassist`, `custom1`, `custom2`, and `hover` — the frame under your pointer.

Take Innervate. Balance druid, keystones, and it wants to go out to the healer over and over. Without `@healer` the choices are: retype the healer's name into a macro before every key, hunt for their frame with the mouse mid-pull, or park your focus on them — the focus you wanted for something else. WoW's macro conditionals have no idea what a healer is, so there is no fourth option.

Debind is the one working out who that is, so `@healer` only means something inside Debind. Most of the time that means the action's right-click menu — pick the unit and you're done:

![An action's tooltip: Innervate on F, target Healer, held back unless a healer exists — all of it picked from the menu, no macro involved.](https://raw.githubusercontent.com/mundi4/debind/main/docs/screenshots/role-target.png)

The other place is a **Custom Macro**, where one line can try the healer first and fall back to your normal target:

```
/cast [@healer,exists][] Innervate
```

The same **Target** submenu also has **No Target**, which is none of the above: it lets the key pick up a new target even when you already have one, and it ignores auto self cast. And **Only if unit exists** holds the action back unless somebody is actually there — anyone, friendly only, or enemy only.

**A role only works when exactly one person in the group has it.** With two tanks, `@tank` points at nobody rather than guessing.

### Custom targets

Two more slots that behave like extra focus targets, and don't cost you the real one. Bind **Set Custom Target**, then press it while hovering a frame. Works from the player, pet, party, raid, boss and arena frames, and there's an entry on the unit right-click menu too.

A custom target follows the person, not their spot in the raid frames — shuffle the group and it goes with them.

## Switches

Five switches of your own. An action can require one to be on, or off, and a Custom Macro can read it as `[$state1]` / `[no$state1]`.

They can be flipped **in combat**, which is the point of them — it's how you change what a key does in the middle of a fight. G Shift or Hypershift, without spending a real modifier key.

A switch can also drive itself from a macro conditional: hand it `[@tank,exists]` and it's on exactly while there's a tank.

## When a key holds several actions

Debind checks them in order and runs the first one that fits. If none of them fit, the key does whatever your WoW keybinding says — the last row of that table.

Three things decide that order, and they're all the same idea — the narrower case is checked first:

- **Hovering a unit frame comes first.** Otherwise the action that runs anywhere would take the key, and the one meant for the frame under your mouse would never run.
- **Then having conditions at all.** An action with conditions is checked before one without, for the same reason: an action with no conditions always fits.
- **Then the layer.** The narrower one goes first.

![Four actions on the F key in the overview, each row saying why it beats the one below: unit frame rule, has conditions, spec over class — and one marked Never runs.](https://raw.githubusercontent.com/mundi4/debind/main/docs/screenshots/run-order.png)

If that ordering isn't what you want, set the action's **Importance** — what you set yourself wins over anything the addon worked out on its own. The overview column shows the order you'll actually get, and each row says why it beats the one under it. Select a row and you get **Run Sooner** and **Run Later**. When an action can't move, the button says which rule is holding it instead of doing nothing.

When an action can't be reached at all, the overview marks it **Never runs**. Sometimes that's a mistake worth catching. Sometimes it's the layer above doing exactly what you told it to — give Balance Starfall on `R` and Rebirth is dead on `R` for Balance, which was the whole point.

## Unit frames

Hovering a unit frame is a condition like any other, so click casting is just a binding with that condition on it.

**`[@mouseover]` is whoever your cursor happens to be over** — a raid frame, a boss frame, or a character standing out in the world, all the same to it, and the game never says which. Debind's hover is unit frames only — and when the one out in the world is what you meant, **mouseover** is a target you pick off the menu like any other.

It's not one switch, either. You pick which frames count — player, pet, party and raid, target and focus, boss, arena — and which reactions, friendly, enemy or neither. So one key can heal off raid frames, do something else on the boss frames, and go back to being a normal key everywhere else.

![The Hovering Over Unit Frame submenu: hovered or not, which reactions, and which frame types count.](https://raw.githubusercontent.com/mundi4/debind/main/docs/screenshots/click-casting.png)

Unit frame addons that support Clique register with Debind the same way they register with Clique. And you can run Clique itself alongside this. Debind leaves unit frames to Clique and everything else works as usual — what stops is the hover condition and any action aimed at `@hover`. Both are marked in the list, and Debind says so when you log in.

## A few things worth knowing

**It writes nowhere but its own settings file.** Not your keybindings, not a CVar. Pull it out and there's nothing to undo and nothing to hunt down in the console afterwards.

**You don't have to move everything into it.** Movement, the UI toggles, screenshot, bags — none of that has ever needed to differ by character, and mine are still in WoW's own window. The keys worth moving are the ones you'd otherwise keep in sync across characters by hand, or the ones you want behaving differently depending on what's going on. And if one character really does want a different bag key, that one key goes in that character's layer and no other character changes.

**These don't go on your action bars.** A Debind action is a binding, not a bar button — there's nothing to drag out. If you want to keep watching something, leave it on the bar where it already is and let Debind take the key; the button carries on doing everything it always did. And if one really needs a slot of its own, that one's a WoW macro — see below.

**Custom targets have one gap, and it's a narrow one.** The group changes mid-fight, and *after that* you pin a party or raid member. Until combat ends that one is tied to their spot in the group rather than to them, and if the group shifts again first it's dropped rather than left pointing at whoever moved into the slot — Debind says so in chat. One pinned before the group changed keeps following them through it.

**A few keys stop working in the house editor.** While it's open the editor claims some keys for its own shortcuts, and Debind leaves those alone — so an action bound to one of them does nothing until you close the editor. If you'd rather keep one of yours, there's a setting on the action for that.

**Macros are still good.** If one macro solves your problem, write the macro — it's less machinery and it doesn't depend on me. This is for when the list stops being one macro.

**English, 한국어, Русский.** The Russian translation is ZamestoTV's.

**Not for Classic.** One client is enough to keep up with.

## Coming from Debounce

Debind was called Debounce until 3.0. Same addon, same author, same settings — `/deb` and `/debounce` both still work. In 3.1 the addon folder was renamed to match, which is where WoW keeps your settings file, so a small companion addon named **Debind Migration** ships alongside and carries them over. Leave it enabled — if it isn't, Debind says so when you log in rather than starting you off empty.

## Links

- [CurseForge](https://www.curseforge.com/wow/addons/debind)
- [GitHub issues](https://github.com/mundi4/debind/issues) — bugs and requests
- Oreo-Durotan (KR), Alliance · mundi4@gmail.com
